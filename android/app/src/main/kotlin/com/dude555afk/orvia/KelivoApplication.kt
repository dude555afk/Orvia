package com.dude555afk.orvia

import android.app.Application
import com.dude555afk.orvia.background.BackgroundRuntime
import com.dude555afk.orvia.scheduled.ScheduledTasks
import com.dude555afk.orvia.workspace.WorkspacePlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/** One Dart isolate and database owner per process, independent of its UI. */
class OrviaApplication : Application() {
    val backgroundRuntime by lazy { BackgroundRuntime(this) }
    val scheduledTasks by lazy { ScheduledTasks(this) }
    val workspace by lazy { WorkspacePlugin(this) }
    val deviceTools by lazy { DeviceLocalToolsHandler(this) }

    private val engineHolder = lazy {
        FlutterEngine(this).also { engine ->
            val messenger = engine.dartExecutor.binaryMessenger
            backgroundRuntime.configure(messenger)
            scheduledTasks.configure(messenger)
            workspace.configure(messenger)
            deviceTools.configure(messenger)
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        }
    }

    val hasEngine get() = engineHolder.isInitialized()
    val engine: FlutterEngine get() = engineHolder.value
}