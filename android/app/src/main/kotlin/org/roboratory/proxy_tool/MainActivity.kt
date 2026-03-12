package org.roboratory.proxy_tool

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingStartConfiguration: Map<*, *>? = null
    private var pendingStartResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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

    companion object {
        private const val requestPrepareVpn = 7001
    }
}
