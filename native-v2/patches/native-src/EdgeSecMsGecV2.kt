package me.rerere.tts.provider.android

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets.UTF_8

/**
 * Sec-MS-GEC v2 token implementation for Microsoft's Edge Read Aloud endpoint.
 *
 * Algorithm port based on rany2/edge-tts 7.3.1 (LGPL-3.0-or-later).
 * The customized SHA-256 midstate below is part of the v2 token format; replacing
 * it with MessageDigest SHA-256 produces an invalid token and HTTP 403.
 */
internal object EdgeSecMsGecV2 {
    const val TRUSTED_CLIENT_TOKEN = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private const val WINDOWS_EPOCH_SECONDS = 11644473600L
    private const val MASK = -1

    private val initial = intArrayOf(
        0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
        0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
    )
    private val seededState = intArrayOf(
        0xFD9FBEA2.toInt(), 0x91243CE7.toInt(), 0xBE499094.toInt(), 0xCD2E1E0A.toInt(),
        0x6C006F49, 0x04BD35AB, 0xFEB0A7E4.toInt(), 0x03EFFBD2,
    )
    private val seededSchedule = intArrayOf(
        0xEB24BF9E.toInt(), 0x1558691F, 0xA0C09EE2.toInt(), 0x0CFA32BA,
        0xA622EE8C.toInt(), 0xD1DD9491.toInt(), 0xC0DD25A0.toInt(), 0xF9E70AB6.toInt(),
        0xF0C31573.toInt(), 0x7058CE4E, 0x7188E606, 0x00E5AB33,
        0xD258B060.toInt(), 0x72766564,
    )
    private val roundConstants = intArrayOf(
        0x428A2F98, 0x71374491, 0xB5C0FBCF.toInt(), 0xE9B5DBA5.toInt(),
        0x3956C25B, 0x59F111F1.toInt(), 0x923F82A4.toInt(), 0xAB1C5ED5.toInt(),
        0xD807AA98.toInt(), 0x12835B01, 0x243185BE, 0x550C7DC3,
        0x72BE5D74, 0x80DEB1FE.toInt(), 0x9BDC06A7.toInt(), 0xC19BF174.toInt(),
        0xE49B69C1.toInt(), 0xEFBE4786.toInt(), 0x0FC19DC6, 0x240CA1CC,
        0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152.toInt(), 0xA831C66D.toInt(), 0xB00327C8.toInt(), 0xBF597FC7.toInt(),
        0xC6E00BF3.toInt(), 0xD5A79147.toInt(), 0x06CA6351, 0x14292967,
        0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
        0x650A7354, 0x766A0ABB.toInt(), 0x81C2C92E.toInt(), 0x92722C85.toInt(),
        0xA2BFE8A1.toInt(), 0xA81A664B.toInt(), 0xC24B8B70, 0xC76C51A3.toInt(),
        0xD192E819.toInt(), 0xD6990624.toInt(), 0xF40E3585.toInt(), 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5,
        0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
        0x748F82EE, 0x78A5636F, 0x84C87814.toInt(), 0x8CC70208.toInt(),
        0x90BEFFFA.toInt(), 0xA4506CEB.toInt(), 0xBEF9A3F7.toInt(), 0xC67178F2.toInt(),
    )
    private val coefficients = arrayOf(
        intArrayOf(0xE82E91B1.toInt(), 0xB32700D0.toInt()),
        intArrayOf(0x44DE24C6, 0x88DFF51D.toInt()),
        intArrayOf(0x3BEB65BC, 0x29514038),
        intArrayOf(0xC89C5933.toInt(), 0xB328CBDF.toInt()),
        intArrayOf(0x8D1EC211.toInt(), 0xD405B4D5.toInt()),
        intArrayOf(0x314EF5D5, 0x26E55F3C),
        intArrayOf(0xE92491B1.toInt(), 0x607801C6),
        intArrayOf(0xF0A5B9D5.toInt(), 0x82B2C1FB.toInt()),
        intArrayOf(0x06064CF3, 0xFA51A3DA.toInt()),
        intArrayOf(0xDA79FA60.toInt(), 0x207CC464),
        intArrayOf(0xBED20560.toInt(), 0x3C3C74F3),
        intArrayOf(0x89F9C9F8.toInt(), 0xD2D14B61.toInt()),
        intArrayOf(0x35FA38C6, 0xBB04A2C1.toInt()),
        intArrayOf(0xCB49E3C6.toInt(), 0xC5626167.toInt()),
    )
    private val blockConstants = roundConstants.copyOf().apply { this[14] = 0xC9DC06A7.toInt() }

    fun generate(unixTimestampSeconds: Long = System.currentTimeMillis() / 1000L): String {
        var ticks = unixTimestampSeconds + WINDOWS_EPOCH_SECONDS
        ticks -= ticks % 300L
        val value = "${ticks * 10_000_000L}$TRUSTED_CLIENT_TOKEN".toByteArray(UTF_8)
        val digest = sha256Digest(value)
        val pair = cs64Digest(value, digest)
        val csBytes = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
            .putInt(pair.first).putInt(pair.second).array()
        return csBytes.toHexUpper() + "-" + digest.toHexUpper()
    }

    private fun ByteArray.toHexUpper(): String =
        joinToString("") { "%02X".format(it.toInt() and 0xff) }

    private fun bigEndianWord(bytes: ByteArray, start: Int, count: Int): Int {
        var out = 0
        for (i in 0 until count) out = (out shl 8) or (bytes[start + i].toInt() and 0xff)
        return out
    }

    private fun sigma0(x: Int): Int =
        (x ushr 7) xor (x shl 25) xor (x ushr 18) xor (x shl 14) xor (x ushr 3)

    private fun sigma1(x: Int): Int =
        (x ushr 17) xor (x shl 15) xor (x ushr 19) xor (x shl 13) xor (x ushr 10)

    private fun upperSigma0(x: Int): Int =
        Integer.rotateRight(x, 2) xor Integer.rotateRight(x, 13) xor Integer.rotateRight(x, 22)

    private fun upperSigma1(x: Int): Int =
        Integer.rotateRight(x, 6) xor Integer.rotateRight(x, 11) xor Integer.rotateRight(x, 25)

    private fun expandSchedule(words: MutableList<Int>, firstWord: Int = 16) {
        for (i in firstWord until 64) {
            val x = words[i - 2]
            val y = words[i - 15]
            words.add(sigma1(x) + words[i - 7] + sigma0(y) + words[i - 16])
        }
    }

    private fun sha256Rounds(start: IntArray, words: List<Int>, firstRound: Int = 0): IntArray {
        var a = start[0]; var b = start[1]; var c = start[2]; var d = start[3]
        var e = start[4]; var f = start[5]; var g = start[6]; var h = start[7]
        val constants = if (firstRound == 14) blockConstants else roundConstants
        for (i in firstRound until 64) {
            val t1 = h + upperSigma1(e) + ((e and f) xor (e.inv() and g)) + constants[i] + words[i]
            val t2 = upperSigma0(a) + ((a and b) xor (a and c) xor (b and c))
            h = g; g = f; f = e; e = d + t1
            d = c; c = b; b = a; a = t1 + t2
        }
        return intArrayOf(a, b, c, d, e, f, g, h)
    }

    private fun initialState(prefix: ByteArray): IntArray {
        val words = MutableList(14) { 0 }
        words.add(bigEndianWord(prefix, 0, 3))
        words.add(bigEndianWord(prefix, 3, 4))
        for (i in 16 until 30) {
            var value = seededSchedule[i - 16]
            if (i - 2 >= 14) value += if (i == 16) sigma1(words[i - 2]) xor 0x000B92C0 else sigma1(words[i - 2])
            if (i - 7 >= 14) value += words[i - 7]
            if (i - 15 >= 14) value += if (i == 29) sigma0(words[i - 15]) xor 0x059C0B80 else sigma0(words[i - 15])
            words.add(value)
        }
        words.add(sigma1(words[28]) + words[23] + sigma0(words[15]) + words[14] + 0xC9DC06A7.toInt() - roundConstants[14])
        expandSchedule(words, 31)
        val working = sha256Rounds(seededState, words, 14)
        return IntArray(8) { initial[it] + working[it] }
    }

    private fun sha256Digest(data: ByteArray): ByteArray {
        require(data.size >= 7) { "Edge TTS token input must contain at least seven bytes" }
        val length = 57 + data.size
        val padded = ByteArrayOutputStream()
        padded.write(data, 7, data.size - 7)
        padded.write(0x80)
        repeat(((55 - length) % 64 + 64) % 64) { padded.write(0) }
        padded.write(ByteBuffer.allocate(8).order(ByteOrder.BIG_ENDIAN).putLong(length.toLong() * 8L).array())
        val all = padded.toByteArray()
        var state = initialState(data.copyOfRange(0, 7))
        var offset = 0
        while (offset < all.size) {
            val words = MutableList(16) { i ->
                bigEndianWord(all, offset + i * 4, 4)
            }
            expandSchedule(words)
            val working = sha256Rounds(state, words)
            state = IntArray(8) { state[it] + working[it] }
            offset += 64
        }
        val out = ByteBuffer.allocate(32).order(ByteOrder.BIG_ENDIAN)
        state.forEach(out::putInt)
        return out.array()
    }

    private fun rol16(value: Int): Int = Integer.rotateLeft(value, 16)

    private fun littleEndianWordsPaddedEven(data: ByteArray): List<Int> {
        val length = (data.size + 3) / 4 * 4
        val padded = data.copyOf(length)
        val result = ArrayList<Int>(length / 4 + 1)
        val bb = ByteBuffer.wrap(padded).order(ByteOrder.LITTLE_ENDIAN)
        while (bb.remaining() >= 4) result.add(bb.int)
        if (result.size % 2 != 0) result.add(0)
        return result
    }

    private fun cs64Digest(data: ByteArray, digest: ByteArray): Pair<Int, Int> {
        val keyBuffer = ByteBuffer.wrap(digest).order(ByteOrder.LITTLE_ENDIAN)
        val keyA = keyBuffer.int or 1
        val keyB = keyBuffer.int or 1
        val factors = intArrayOf(keyA * 0x82893933.toInt(), keyB * 0x82893933.toInt())
        val terms = ArrayList<Int>()
        val offsets = ArrayList<Int>()
        coefficients.forEachIndexed { index, pair ->
            terms.add(pair[0] * factors[index % 2])
            offsets.add(pair[1])
        }
        val prefix = ByteArray(data.size + 1).also { it[0] = 0; data.copyInto(it, 1) }
        littleEndianWordsPaddedEven(prefix).forEachIndexed { i, word ->
            var term = word * (if (i % 2 == 0) keyA else keyB)
            var offset = rol16(word) * (if (i % 2 == 0) 0xEF0569FB.toInt() else 0xC31713DB.toInt())
            if (i == 0) {
                term += 0xF2F90B1A.toInt() * factors[0]
                offset += 0x0B1A0000
            }
            terms.add(term)
            offsets.add(offset)
        }
        var swapAcc = 0; var swapLast = 0; var state = 0; var acc = 0
        for (i in terms.indices step 2) {
            val x = terms[i]; val y = terms[i + 1]
            var t = rol16(offsets[i] + x)
            var q = t * 0x76F50F34
            swapAcc += rol16(q) * 0xC3EFEA97.toInt() + q
            t = rol16(offsets[i + 1] + y)
            q = t * 0x1881CE3C
            swapLast = rol16(q) * 0x35BD1EC9 + q
            swapAcc += swapLast
            state = state * keyA + x
            state = rol16(state) * 0xCF98B111.toInt()
            state = rol16(state) * 0x87085B9F.toInt()
            state = rol16(state) * 0x12CEB96D
            state = rol16(state) * 0x257E1D83
            acc += state
            t = state * keyB + y
            t = rol16(t) * 0xA27416F5.toInt()
            t = rol16(t) * 0xD38396FF.toInt()
            state = rol16(rol16(t) * 0x7C932B89) * 0xBFA49F69.toInt()
            acc += state
        }
        return Pair(swapLast xor state, swapAcc xor acc)
    }
}
