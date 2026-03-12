package org.roboratory.proxy_tool

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object RuntimeEventDispatcher {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var appContext: Context? = null

    fun initialize(context: Context) {
        appContext = context.applicationContext
    }

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
        appContext?.sendBroadcast(
            Intent(actionRuntimeEvent).apply {
                `package` = appContext?.packageName
                putExtra(extraType, type)
                putExtra(extraMessage, message)
                putExtra(extraTimestamp, payload["timestamp"] as Long)
                putExtra(extraData, HashMap(data))
            },
        )
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    fun emitPayload(payload: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(HashMap(payload))
        }
    }

    const val actionRuntimeEvent = "org.roboratory.proxy_tool.RUNTIME_EVENT"
    const val extraType = "type"
    const val extraMessage = "message"
    const val extraTimestamp = "timestamp"
    const val extraData = "data"
}
