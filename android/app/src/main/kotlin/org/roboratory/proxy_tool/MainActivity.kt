package org.roboratory.proxy_tool

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingStartConfiguration: Map<*, *>? = null
    private var pendingStartResult: MethodChannel.Result? = null
    private var runtimeEventReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RuntimeEventDispatcher.initialize(applicationContext)
        registerRuntimeEventReceiver()

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "proxy_tool/runtime_events",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                RuntimeEventDispatcher.attachSink(events)
            }

            override fun onCancel(arguments: Any?) {
                RuntimeEventDispatcher.attachSink(null)
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "proxy_tool/runtime",
        ).setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "startProxy" -> {
                    val arguments = call.arguments as? Map<*, *>
                    if (arguments == null) {
                        result.error("invalid_args", "Missing proxy configuration", null)
                        return@setMethodCallHandler
                    }

                    val prepareIntent = VpnService.prepare(this)
                    if (prepareIntent != null) {
                        pendingStartConfiguration = arguments
                        pendingStartResult = result
                        @Suppress("DEPRECATION")
                        startActivityForResult(prepareIntent, requestPrepareVpn)
                    } else {
                        startProxyVpn(arguments)
                        result.success(null)
                    }
                }

                "stopProxy" -> {
                    startService(ProxyVpnService.createStopIntent(this))
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        runtimeEventReceiver?.let { receiver ->
            unregisterReceiver(receiver)
        }
        runtimeEventReceiver = null
        RuntimeEventDispatcher.attachSink(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != requestPrepareVpn) {
            return
        }

        val result = pendingStartResult
        val configuration = pendingStartConfiguration
        pendingStartResult = null
        pendingStartConfiguration = null

        if (resultCode != Activity.RESULT_OK || configuration == null) {
            result?.error("vpn_denied", "VPN permission denied", null)
            return
        }

        startProxyVpn(configuration)
        result?.success(null)
    }

    private fun startProxyVpn(configuration: Map<*, *>) {
        val intent = ProxyVpnService.createStartIntent(this, configuration)
        ContextCompat.startForegroundService(this, intent)
    }

    private fun registerRuntimeEventReceiver() {
        if (runtimeEventReceiver != null) {
            return
        }

        runtimeEventReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != RuntimeEventDispatcher.actionRuntimeEvent) {
                    return
                }

                val payload = hashMapOf<String, Any?>(
                    "type" to intent.getStringExtra(RuntimeEventDispatcher.extraType),
                    "message" to intent.getStringExtra(RuntimeEventDispatcher.extraMessage),
                    "timestamp" to intent.getLongExtra(
                        RuntimeEventDispatcher.extraTimestamp,
                        System.currentTimeMillis(),
                    ),
                    "data" to HashMap(readRuntimeData(intent)),
                )
                RuntimeEventDispatcher.emitPayload(payload)
            }
        }

        val filter = IntentFilter(RuntimeEventDispatcher.actionRuntimeEvent)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(runtimeEventReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(runtimeEventReceiver, filter)
        }
    }

    private fun readRuntimeData(intent: Intent): Map<String, Any?> {
        val rawData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getSerializableExtra(
                RuntimeEventDispatcher.extraData,
                HashMap::class.java,
            )
        } else {
            @Suppress("DEPRECATION")
            intent.getSerializableExtra(RuntimeEventDispatcher.extraData) as? HashMap<*, *>
        }
        val typedData = hashMapOf<String, Any?>()
        rawData?.forEach { (key, value) ->
            if (key is String) {
                typedData[key] = value
            }
        }
        return typedData
    }

    companion object {
        private const val requestPrepareVpn = 7001
    }
}
