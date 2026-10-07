package com.dude555afk.orvia.workspace

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.util.ArrayDeque

class WorkspaceEvents : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()
    private var sink: EventChannel.EventSink? = null
    private val pending = ArrayDeque<Map<String, Any?>>()

    fun emit(event: Map<String, Any?>) {
        mainHandler.post {
            synchronized(lock) {
                val current = sink
                if (current != null) {
                    current.success(event)
                } else {
                    pending.addLast(event)
                }
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        synchronized(lock) {
            sink = events
            while (pending.isNotEmpty()) {
                events?.success(pending.removeFirst())
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        synchronized(lock) {
            sink = null
        }
    }
}
