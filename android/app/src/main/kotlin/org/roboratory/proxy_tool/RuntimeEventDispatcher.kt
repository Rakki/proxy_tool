package org.roboratory.proxy_tool

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object RuntimeEventDispatcher {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    fun attachSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun emit(
        type: String,
        message: String,
        data: Map<String, Any?> = emptyMap(),
    ) {
        val payload = HashMap<String, Any?>()
        payload["type"] = type
        payload["message"] = message
        payload["timestamp"] = System.currentTimeMillis()
        payload["data"] = HashMap(data)
        mainHandler.post {
            eventSink?.success(payload)
        }
    }
}
