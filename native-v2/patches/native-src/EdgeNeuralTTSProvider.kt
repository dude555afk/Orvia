package me.rerere.tts.provider.android

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import me.rerere.tts.model.AudioChunk
import me.rerere.tts.model.AudioFormat
import me.rerere.tts.model.TTSRequest
import me.rerere.tts.provider.TTSProvider
import me.rerere.tts.provider.TTSProviderSetting
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * Keyless Microsoft Edge Read Aloud provider. Uses the current Sec-MS-GEC v2
 * handshake and the same MP3 protocol used by Edge Read Aloud clients.
 *
 * No provider fallback is attempted: a failed Edge request is surfaced to the
 * caller instead of silently switching voices/services.
 */
internal class EdgeNeuralTTSProvider(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .callTimeout(35, TimeUnit.SECONDS)
        .readTimeout(35, TimeUnit.SECONDS)
        .build(),
) : TTSProvider<TTSProviderSetting.EdgeNeural> {

    override fun generateSpeech(
        providerSetting: TTSProviderSetting.EdgeNeural,
        request: TTSRequest,
    ): Flow<AudioChunk> = flow {
        val spoken = request.text.trim()
        require(spoken.isNotEmpty()) { "Nothing to speak" }
        val bytes = withContext(Dispatchers.IO) {
            synthesize(spoken, providerSetting.voice)
        }
        emit(
            AudioChunk(
                data = bytes,
                format = AudioFormat.MP3,
                isLast = true,
                metadata = mapOf(
                    "provider" to "microsoft-edge",
                    "voice" to providerSetting.voice,
                    "protocol" to "Sec-MS-GEC v2",
                ),
            ),
        )
    }

    private suspend fun synthesize(text: String, voice: String): ByteArray {
        val locale = Regex("[A-Za-z]{2}-[A-Za-z]{2}").find(voice)?.value
            ?: throw IllegalArgumentException("Edge TTS voice must include a locale, such as en-US-AriaNeural")
        val connectionId = UUID.randomUUID().toString().replace("-", "")
        val requestId = UUID.randomUUID().toString().replace("-", "")
        val url = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1" +
            "?TrustedClientToken=${EdgeSecMsGecV2.TRUSTED_CLIENT_TOKEN}" +
            "&Sec-MS-GEC=${EdgeSecMsGecV2.generate()}" +
            "&Sec-MS-GEC-Version=2-143.0.3650.75" +
            "&ConnectionId=$connectionId"
        val timestamp = SimpleDateFormat(
            "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'",
            Locale.US,
        ).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date())
        val escaped = text
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
        val ssml = """
            <speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xmlns:mstts="https://www.w3.org/2001/mstts" xml:lang="$locale">
              <voice name="$voice">
                <prosody pitch="+0Hz" rate="+0%" volume="+0%">
                  $escaped
                </prosody>
              </voice>
            </speak>
        """.trimIndent()
        val speechConfig = """{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-96kbitrate-mono-mp3"}}}}"""
        val socketResult = CompletableDeferred<ByteArray>()
        val audio = ByteArrayOutputStream()
        val audioMarker = "Path:audio\r\n".toByteArray(Charsets.US_ASCII)
        val separator = "\r\n\r\n".toByteArray(Charsets.US_ASCII)
        var socket: WebSocket? = null

        fun finishOrFail(error: Throwable?) {
            if (socketResult.isCompleted) return
            if (error != null) {
                socketResult.completeExceptionally(error)
            } else if (audio.size() == 0) {
                socketResult.completeExceptionally(IOException("Edge TTS returned no audio"))
            } else {
                socketResult.complete(audio.toByteArray())
            }
        }

        fun processFrame(bytes: ByteArray) {
            // The protocol's binary audio frames begin with a two-byte header length.
            // Search for its ASCII path marker rather than assuming a fixed header size.
            val message = bytes.toString(Charsets.ISO_8859_1)
            if (message.contains("Path:turn.end")) {
                finishOrFail(null)
                socket?.close(1000, "turn complete")
                return
            }
            if (message.contains("Path:response") && (
                    message.contains("Forbidden", ignoreCase = true) ||
                    message.contains("Invalid", ignoreCase = true) ||
                    message.contains("statusCode") && !message.contains("\"statusCode\":200")
                )) {
                finishOrFail(IOException("Edge TTS rejected the request. Check the service protocol and device clock."))
                return
            }
            val index = indexOf(bytes, audioMarker)
            if (index >= 0) {
                val start = index + audioMarker.size
                if (start < bytes.size) audio.write(bytes, start, bytes.size - start)
            }
        }

        val request = Request.Builder()
            .url(url)
            .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0")
            .header("Origin", "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold")
            .header("Pragma", "no-cache")
            .header("Cache-Control", "no-cache")
            .build()
        val listener = object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                val configFrame = "X-Timestamp:$timestamp\r\n" +
                    "Content-Type:application/json; charset=utf-8\r\n" +
                    "Path:speech.config\r\n\r\n$speechConfig\r\n"
                val ssmlFrame = "X-RequestId:$requestId\r\n" +
                    "Content-Type:application/ssml+xml\r\n" +
                    "X-Timestamp:${timestamp}Z\r\n" +
                    "Path:ssml\r\n\r\n$ssml"
                if (!webSocket.send(configFrame) || !webSocket.send(ssmlFrame)) {
                    finishOrFail(IOException("Unable to send Edge TTS request"))
                    webSocket.cancel()
                }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                processFrame(text.toByteArray(Charsets.UTF_8))
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                processFrame(bytes.toByteArray())
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                val status = response?.code?.let { " (HTTP $it)" }.orEmpty()
                finishOrFail(IOException("Edge TTS connection failed$status: ${t.message ?: "unknown error"}", t))
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                finishOrFail(null)
            }
        }
        socket = client.newWebSocket(request, listener)
        return try {
            withTimeout(30_000L) { socketResult.await() }
        } finally {
            if (!socketResult.isCompleted) socket?.cancel()
            else socket?.close(1000, "complete")
        }
    }

    private fun indexOf(source: ByteArray, target: ByteArray): Int {
        if (target.isEmpty()) return 0
        if (source.size < target.size) return -1
        for (i in 0..source.size - target.size) {
            var matches = true
            for (j in target.indices) {
                if (source[i + j] != target[j]) {
                    matches = false
                    break
                }
            }
            if (matches) return i
        }
        return -1
    }
}
