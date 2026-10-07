package com.dude555afk.orvia

import android.app.Activity
import android.content.ActivityNotFoundException
import android.net.Uri
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.os.StatFs
import android.provider.DocumentsContract
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.engine.FlutterEngine
import com.dude555afk.orvia.workspace.WorkspacePlugin
import io.flutter.plugin.common.MethodChannel
import com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin
import java.io.File
import java.io.FileInputStream
import java.io.OutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val orvia get() = application as OrviaApplication
    private var reusedEngine = false
    private val highRefreshRate by lazy { HighRefreshRateController(window) }

    override fun provideFlutterEngine(context: android.content.Context): FlutterEngine {
        reusedEngine = orvia.hasEngine
        return orvia.engine
    }
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onStart() {
        super.onStart()
        orvia.backgroundRuntime.setForeground(true)
    }

    override fun onPostResume() {
        super.onPostResume()
        applyEdgeToEdgeSystemBars(window)
        highRefreshRate.resume()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) highRefreshRate.request(force = true)
    }

    override fun onStop() {
        highRefreshRate.stop()
        orvia.backgroundRuntime.setForeground(false)
        super.onStop()
    }

    private companion object {
        const val CREATE_DOCUMENT_REQUEST_CODE = 4107
        const val INSTALL_UNKNOWN_APPS_REQUEST_CODE = 4111
    }

    private enum class WritableFileState {
        IDLE, OPEN, COMMITTED, DISCARDED,
    }

    private val processTextChannelName = "app.process_text"
    private val fileSaveChannelName = "app.file_save"
    private val deviceStorageChannelName = "app.device_storage"
    private val updaterChannelName = "app.updater"
    private var processTextChannel: MethodChannel? = null
    private var fileSaveChannel: MethodChannel? = null
    private var deviceStorageChannel: MethodChannel? = null
    private var updaterChannel: MethodChannel? = null
    private var pendingUpdateInstallResult: MethodChannel.Result? = null
    private var pendingUpdateApkPath: String? = null
    private var pendingProcessText: String? = null
     private var pendingSaveResult: MethodChannel.Result? = null
     private var pendingSaveSourcePath: String? = null
     private var pendingDirectWrite = false
     private var pendingWritableStream: OutputStream? = null
     private var pendingWritableUri: Uri? = null
     @Volatile private var writableFileState = WritableFileState.IDLE
     private val writableFileExecutor = Executors.newSingleThreadExecutor()
     private var deviceLocalToolsHandler: DeviceLocalToolsHandler? = null
     private var workspacePlugin: WorkspacePlugin? = null
    private var incomingShareHandler: IncomingShareHandler? = null
    private var receivedShare = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        forwardCachedProcessTextLaunch(reusedEngine, savedInstanceState, intent, processTextChannel)
        (orvia.engine.plugins.get(FlutterLocalNotificationsPlugin::class.java) as? FlutterLocalNotificationsPlugin)?.let {
            forwardCachedNotificationLaunch(reusedEngine, savedInstanceState, intent, it)
        }
        orvia.backgroundRuntime.receiveConversation(intent)
        receivedShare = savedInstanceState?.getBoolean("orvia.receivedShare") == true
        if (!receivedShare) receivedShare = incomingShareHandler?.receive(intent) == true
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("orvia.receivedShare", receivedShare)
        super.onSaveInstanceState(outState)
    }

    override fun onFlutterSurfaceViewCreated(flutterSurfaceView: FlutterSurfaceView) {
        super.onFlutterSurfaceViewCreated(flutterSurfaceView)
        highRefreshRate.attach(flutterSurfaceView)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
         super.configureFlutterEngine(flutterEngine)
        incomingShareHandler = IncomingShareHandler(this, flutterEngine.dartExecutor.binaryMessenger)
         OAuthHandler.configure(this, flutterEngine.dartExecutor.binaryMessenger)
         orvia.backgroundRuntime.attachActivity(this)
         deviceLocalToolsHandler = orvia.deviceTools.also { it.attachActivity(this) }
         workspacePlugin = orvia.workspace.also { it.attachActivity(this) }
        processTextChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, processTextChannelName)
        processTextChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialText" -> {
                    val text = pendingProcessText ?: takeProcessText(intent)
                    pendingProcessText = null
                    result.success(text)
                }
                else -> result.notImplemented()
            }
        }
        fileSaveChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fileSaveChannelName)
        fileSaveChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "saveFileFromPath" -> handleSaveFileFromPath(call.arguments, result)
                "createWritableFile" -> handleCreateWritableFile(call.arguments, result)
                "writeWritableFileChunk" -> handleWriteWritableFileChunk(call.arguments, result)
                "completeWritableFile" -> handleCompleteWritableFile(result)
                "abortWritableFile" -> handleAbortWritableFile(result)
                else -> result.notImplemented()
            }
        }
        deviceStorageChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceStorageChannelName)
        deviceStorageChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "freeBytes" -> result.success(usableBytesForAppData())
                else -> result.notImplemented()
            }
        }
        updaterChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannelName)
        updaterChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPreferredAbi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull())
                "installApk" -> handleInstallApk(call.arguments, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun usableBytesForAppData(): Long? = try {
        val target = filesDir ?: dataDir
        StatFs(target.absolutePath).availableBytes.takeIf { it > 0 }
    } catch (_: Exception) {
        null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        orvia.backgroundRuntime.receiveConversation(intent)
        setIntent(intent)
        receivedShare = incomingShareHandler?.receive(intent) == true
        val text = takeProcessText(intent) ?: return
        val ch = processTextChannel
        if (ch != null) {
            ch.invokeMethod("onProcessText", text)
        } else {
            pendingProcessText = text
        }
    }

    override fun onDestroy() {
        deviceLocalToolsHandler?.detachActivity(this)
        orvia.backgroundRuntime.detachActivity(this)
        OAuthHandler.detachActivity(this)
        processTextChannel?.setMethodCallHandler(null)
        fileSaveChannel?.setMethodCallHandler(null)
        deviceStorageChannel?.setMethodCallHandler(null)
        updaterChannel?.setMethodCallHandler(null)
        pendingUpdateInstallResult?.error("cancelled", "Update installation was interrupted.", null)
        pendingUpdateInstallResult = null
        pendingUpdateApkPath = null
        highRefreshRate.dispose()
        pendingSaveResult?.error("cancelled", "The file picker was closed.", null)
        pendingSaveResult = null
        pendingSaveSourcePath = null
        val stream = pendingWritableStream
        val uri = pendingWritableUri
        if (stream != null && uri != null) {
            writableFileExecutor.execute {
                if (writableFileState == WritableFileState.OPEN) {
                    discardWritableDestination(stream, uri)
                }
            }
        }
        writableFileExecutor.shutdown()
        incomingShareHandler?.dispose()
        workspacePlugin?.detachActivity(this)
        super.onDestroy()
    }
 
     override fun onRequestPermissionsResult(
         requestCode: Int,
         permissions: Array<out String>,
         grantResults: IntArray,
     ) {
         if (workspacePlugin?.onRequestPermissionsResult(requestCode) == true) return
        if (orvia.backgroundRuntime.permissionResult(requestCode)) return
         if (deviceLocalToolsHandler?.onRequestPermissionsResult(requestCode, grantResults) == true) {
             return
         }
         super.onRequestPermissionsResult(requestCode, permissions, grantResults)
     }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == INSTALL_UNKNOWN_APPS_REQUEST_CODE) {
            super.onActivityResult(requestCode, resultCode, data)
            val result = pendingUpdateInstallResult
            val path = pendingUpdateApkPath
            pendingUpdateInstallResult = null
            pendingUpdateApkPath = null
            if (result == null || path.isNullOrBlank()) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()) {
                result.error("permission_denied", "Install unknown apps permission was not granted.", null)
                return
            }
            try {
                launchApkInstaller(File(path))
                result.success(true)
            } catch (e: Exception) {
                result.error("install_launch_failed", e.message, null)
            }
            return
        }
        if (workspacePlugin?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != CREATE_DOCUMENT_REQUEST_CODE) {
            return
        }

        val destUri = if (resultCode == Activity.RESULT_OK) data?.data else null
        handleSaveDestination(destUri)
    }

    private fun handleInstallApk(arguments: Any?, result: MethodChannel.Result) {
        if (pendingUpdateInstallResult != null) {
            result.error("busy", "Another update installation is already in progress.", null)
            return
        }
        val args = arguments as? Map<*, *>
        val rawPath = args?.get("path")?.toString()?.trim().orEmpty()
        if (rawPath.isEmpty()) {
            result.error("invalid_args", "Missing APK path.", null)
            return
        }
        val apk = File(rawPath)
        val cacheRoot = cacheDir.canonicalFile
        val candidate = try {
            apk.canonicalFile
        } catch (e: Exception) {
            result.error("invalid_path", e.message, null)
            return
        }
        if (!candidate.path.startsWith(cacheRoot.path + File.separator) ||
            !candidate.isFile ||
            !candidate.name.endsWith(".apk", ignoreCase = true)) {
            result.error("invalid_path", "APK must be an existing file inside Orvia's cache.", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()) {
            pendingUpdateInstallResult = result
            pendingUpdateApkPath = candidate.absolutePath
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            )
            startActivityForResult(intent, INSTALL_UNKNOWN_APPS_REQUEST_CODE)
            return
        }

        try {
            launchApkInstaller(candidate)
            result.success(true)
        } catch (e: Exception) {
            result.error("install_launch_failed", e.message, null)
        }
    }

    private fun launchApkInstaller(apk: File) {
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.update.fileprovider",
            apk,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun handleSaveFileFromPath(arguments: Any?, result: MethodChannel.Result) {
        if (pendingSaveResult != null || pendingWritableStream != null) {
            result.error("busy", "Another save operation is already in progress.", null)
            return
        }

        val args = arguments as? Map<*, *>
        val rawSourcePath = args?.get("sourcePath")?.toString()?.trim().orEmpty()
        if (rawSourcePath.isEmpty()) {
            result.error("invalid_args", "Missing sourcePath.", null)
            return
        }

        val sourceFile = File(rawSourcePath)
        if (!sourceFile.exists() || !sourceFile.isFile) {
            result.error("not_found", "Source file does not exist.", null)
            return
        }

        val suggestedFileName = args?.get("fileName")?.toString()?.trim().takeUnless { it.isNullOrEmpty() }
            ?: sourceFile.name

        pendingSaveResult = result
        pendingSaveSourcePath = sourceFile.absolutePath

        try {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/zip"
                putExtra(Intent.EXTRA_TITLE, suggestedFileName)
            }
            startActivityForResult(intent, CREATE_DOCUMENT_REQUEST_CODE)
        } catch (e: ActivityNotFoundException) {
            pendingSaveResult = null
            pendingSaveSourcePath = null
            result.error("launch_failed", e.message, null)
        }
    }

    private fun handleCreateWritableFile(arguments: Any?, result: MethodChannel.Result) {
        if (pendingSaveResult != null || pendingWritableStream != null) {
            result.error("busy", "Another save operation is already in progress.", null)
            return
        }

        val args = arguments as? Map<*, *>
        val fileName = args?.get("fileName")?.toString()?.trim().orEmpty()
        if (fileName.isEmpty()) {
            result.error("invalid_args", "Missing fileName.", null)
            return
        }

        pendingSaveResult = result
        pendingDirectWrite = true
        try {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/zip"
                putExtra(Intent.EXTRA_TITLE, fileName)
            }
            startActivityForResult(intent, CREATE_DOCUMENT_REQUEST_CODE)
        } catch (e: ActivityNotFoundException) {
            pendingSaveResult = null
            pendingDirectWrite = false
            result.error("launch_failed", e.message, null)
        }
    }

    private fun handleCompleteWritableFile(result: MethodChannel.Result) {
        val stream = pendingWritableStream
        if (stream == null) {
            result.error("not_open", "No writable file destination is open.", null)
            return
        }

        writableFileExecutor.execute {
            try {
                stream.flush()
                stream.close()
                writableFileState = WritableFileState.COMMITTED
                runOnUiThread {
                    if (pendingWritableStream === stream) {
                        pendingWritableStream = null
                        pendingWritableUri = null
                    }
                    result.success(true)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("close_failed", e.message, null)
                }
            }
        }
    }

    private fun handleWriteWritableFileChunk(arguments: Any?, result: MethodChannel.Result) {
        val stream = pendingWritableStream
        if (stream == null) {
            result.error("not_open", "No writable file destination is open.", null)
            return
        }
        val bytes = arguments as? ByteArray
        if (bytes == null) {
            result.error("invalid_args", "Missing writable file bytes.", null)
            return
        }
        if (bytes.isEmpty()) {
            result.success(true)
            return
        }

        writableFileExecutor.execute {
            try {
                stream.write(bytes)
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("write_failed", e.message, null)
                }
            }
        }
    }

    private fun handleAbortWritableFile(result: MethodChannel.Result) {
        val stream = pendingWritableStream
        val uri = pendingWritableUri
        if (stream == null || uri == null) {
            result.error("not_open", "No writable file destination is open.", null)
            return
        }

        writableFileExecutor.execute {
            try {
                stream.close()
            } catch (_: Exception) {
            }

            var deleted = false
            try {
                deleted = DocumentsContract.deleteDocument(contentResolver, uri)
                if (!deleted) {
                    result.error("discard_failed", "Unable to delete incomplete destination file.", null)
                }
            } catch (e: Exception) {
                result.error("discard_failed", e.message, null)
            }
            if (deleted) {
                writableFileState = WritableFileState.DISCARDED
            }
            runOnUiThread {
                if (pendingWritableStream === stream) {
                    pendingWritableStream = null
                    pendingWritableUri = null
                }
            }
        }
    }

    private fun discardWritableDestination(stream: OutputStream, uri: Uri): Exception? {
        var cleanupError: Exception? = null
        try {
            stream.close()
        } catch (e: Exception) {
            cleanupError = e
        }

        var deleted = false
        try {
            deleted = DocumentsContract.deleteDocument(contentResolver, uri)
            if (!deleted) {
                cleanupError = cleanupError
                    ?: IllegalStateException("Unable to delete incomplete destination file.")
            }
        } catch (e: Exception) {
            cleanupError = cleanupError ?: e
        }
        if (deleted) {
            writableFileState = WritableFileState.DISCARDED
        }
        return cleanupError
    }

    private fun handleSaveDestination(destUri: Uri?) {
        val result = pendingSaveResult ?: return
        if (pendingDirectWrite) {
            pendingSaveResult = null
            pendingDirectWrite = false
            if (destUri == null) {
                result.success(null)
                return
            }
            try {
                pendingWritableUri = destUri
                val descriptor = contentResolver.openFileDescriptor(destUri, "rwt")
                    ?: throw IllegalStateException("Unable to open destination file.")
                pendingWritableStream = ParcelFileDescriptor.AutoCloseOutputStream(descriptor)
                writableFileState = WritableFileState.OPEN
                result.success(true)
            } catch (e: Exception) {
                try {
                    DocumentsContract.deleteDocument(contentResolver, destUri)
                } catch (_: Exception) {
                }
                pendingWritableUri = null
                result.error("open_failed", e.message, null)
            }
            return
        }
        val sourcePath = pendingSaveSourcePath

        if (destUri == null || sourcePath.isNullOrBlank()) {
            pendingSaveResult = null
            pendingSaveSourcePath = null
            result.success(false)
            return
        }

        Thread {
            try {
                contentResolver.openOutputStream(destUri)?.use { outputStream ->
                    FileInputStream(File(sourcePath)).use { inputStream ->
                        inputStream.copyTo(outputStream, DEFAULT_BUFFER_SIZE)
                    }
                } ?: throw IllegalStateException("Unable to open destination stream.")

                runOnUiThread {
                    pendingSaveResult = null
                    pendingSaveSourcePath = null
                    result.success(true)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    pendingSaveResult = null
                    pendingSaveSourcePath = null
                    result.error("save_failed", e.message, null)
                }
            }
        }.start()
    }
}

internal fun forwardCachedProcessTextLaunch(
    reusedEngine: Boolean,
    savedState: Bundle?,
    intent: Intent,
    channel: MethodChannel?,
) {
    if (reusedEngine && savedState == null && channel != null &&
        intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0) {
        takeProcessText(intent)?.let { channel.invokeMethod("onProcessText", it) }
    }
}

internal fun takeProcessText(intent: Intent?): String? {
    if (intent?.action != Intent.ACTION_PROCESS_TEXT) return null
    val text = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
    intent.removeExtra(Intent.EXTRA_PROCESS_TEXT)
    return text?.trim()?.takeIf { it.isNotEmpty() }
}

internal fun forwardCachedNotificationLaunch(
    reusedEngine: Boolean,
    savedState: Bundle?,
    intent: Intent,
    plugin: FlutterLocalNotificationsPlugin,
) {
    if (reusedEngine && savedState == null &&
        intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0) {
        plugin.onNewIntent(intent)
    }
}
