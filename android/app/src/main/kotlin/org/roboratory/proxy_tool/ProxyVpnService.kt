package org.roboratory.proxy_tool

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import java.net.URLEncoder
import java.util.concurrent.Executors

class ProxyVpnService : VpnService() {
    private var tunInterface: ParcelFileDescriptor? = null
    private var detachedTunFd: Int? = null
    private val executor = Executors.newSingleThreadExecutor()
    @Volatile
    private var currentConfig: ProxyServiceConfig? = null

    override fun onBind(intent: Intent?): IBinder? {
        return super.onBind(intent)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            Log.i(logTag, "Received stop action")
            RuntimeEventDispatcher.emit(
                type = "vpn_stop_requested",
                message = "Stop requested for active VPN session",
            )
            currentConfig = null
            stopCurrentSession()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        val config = intent?.let { ProxyServiceConfig.fromIntent(it) }
            ?: return START_NOT_STICKY

        currentConfig = config
        stopCurrentSession()
        createNotificationChannel()
        RuntimeEventDispatcher.emit(
            type = "vpn_starting",
            message = "Starting VPN profile ${config.name}",
            data = mapOf(
                "endpoint" to "${config.host}:${config.port}",
                "proxyType" to config.type,
                "routingMode" to config.routingMode.name,
                "selectedApps" to config.selectedPackages,
            ),
        )
        ServiceCompat.startForeground(
            this,
            notificationId,
            buildNotification(config),
            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
        )

        val builder = Builder()
            .setSession(config.name)
            .setMtu(config.mtu)
            .addAddress("10.7.0.2", 32)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("198.18.0.1")

        if (config.routingMode == RoutingModeValue.SELECTED_APPS) {
            val selectedPackages = config.selectedPackages
                .filter { it.isNotBlank() && it != packageName }
                .distinct()
            for (pkg in selectedPackages) {
                try {
                    builder.addAllowedApplication(pkg)
                } catch (error: Exception) {
                    Log.w(logTag, "Failed to allow package $pkg", error)
                }
            }
        } else {
            try {
                builder.addDisallowedApplication(packageName)
            } catch (error: Exception) {
                Log.w(logTag, "Failed to disallow own package", error)
            }
        }

        val vpnInterface = builder.establish()
        if (vpnInterface == null) {
            Log.e(logTag, "Failed to establish VPN interface")
            RuntimeEventDispatcher.emit(
                type = "vpn_error",
                message = "Failed to establish VPN interface",
                data = mapOf("endpoint" to "${config.host}:${config.port}"),
            )
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        tunInterface = vpnInterface
        RuntimeEventDispatcher.emit(
            type = "vpn_established",
            message = "VPN interface established",
            data = mapOf(
                "endpoint" to "${config.host}:${config.port}",
                "proxyType" to config.type,
                "routingMode" to config.routingMode.name,
                "selectedAppsCount" to config.selectedPackages.size,
            ),
        )
        try {
            val fileDescriptor = vpnInterface.fileDescriptor
            val currentFlags = Os.fcntlInt(fileDescriptor, OsConstants.F_GETFL, 0)
            Os.fcntlInt(
                fileDescriptor,
                OsConstants.F_SETFL,
                currentFlags and OsConstants.O_NONBLOCK.inv(),
            )
            RuntimeEventDispatcher.emit(
                type = "vpn_fd_ready",
                message = "TUN file descriptor switched to blocking mode",
            )
        } catch (error: Throwable) {
            Log.e(logTag, "Failed to switch TUN fd to blocking mode", error)
            RuntimeEventDispatcher.emit(
                type = "vpn_error",
                message = "Failed to switch TUN fd to blocking mode: ${error.message ?: error::class.java.simpleName}",
            )
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val tunFd = vpnInterface.detachFd()
        detachedTunFd = tunFd
        executor.execute {
            try {
                val result = NativeTun2ProxyBridge.startTun2Proxy(
                    config.proxyUrl(),
                    tunFd,
                    config.mtu,
                )
                Log.i(logTag, "tun2proxy exited with code $result")
                RuntimeEventDispatcher.emit(
                    type = "tun2proxy_exit",
                    message = "tun2proxy exited with code $result",
                    data = mapOf("exitCode" to result),
                )
            } catch (error: Throwable) {
                Log.e(logTag, "tun2proxy crashed", error)
                RuntimeEventDispatcher.emit(
                    type = "vpn_error",
                    message = "tun2proxy crashed: ${error.message ?: error::class.java.simpleName}",
                )
            } finally {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        RuntimeEventDispatcher.emit(
            type = "vpn_destroyed",
            message = "VPN service destroyed",
        )
        stopCurrentSession()
        executor.shutdownNow()
        super.onDestroy()
    }

    override fun onRevoke() {
        Log.i(logTag, "VPN revoked by system")
        RuntimeEventDispatcher.emit(
            type = "vpn_revoked",
            message = "VPN permission revoked by system",
        )
        currentConfig = null
        stopCurrentSession()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        super.onRevoke()
    }

    private fun stopCurrentSession() {
        try {
            val result = NativeTun2ProxyBridge.stopTun2Proxy()
            RuntimeEventDispatcher.emit(
                type = "tun2proxy_stop",
                message = "tun2proxy stop requested",
                data = mapOf("result" to result),
            )
        } catch (error: Throwable) {
            Log.w(logTag, "Failed to stop tun2proxy cleanly", error)
            RuntimeEventDispatcher.emit(
                type = "vpn_error",
                message = "Failed to stop tun2proxy cleanly: ${error.message ?: error::class.java.simpleName}",
            )
        }

        try {
            detachedTunFd?.let { fd ->
                ParcelFileDescriptor.adoptFd(fd).close()
            }
        } catch (error: Throwable) {
            Log.w(logTag, "Failed to close detached tun fd", error)
            RuntimeEventDispatcher.emit(
                type = "vpn_error",
                message = "Failed to close detached tun fd: ${error.message ?: error::class.java.simpleName}",
            )
        }
        detachedTunFd = null

        try {
            tunInterface?.close()
        } catch (error: Exception) {
            Log.w(logTag, "Failed to close VPN interface", error)
            RuntimeEventDispatcher.emit(
                type = "vpn_error",
                message = "Failed to close VPN interface: ${error.message ?: error::class.java.simpleName}",
            )
        }
        tunInterface = null
    }

    private fun buildNotification(config: ProxyServiceConfig): Notification {
        val openAppIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val routingLine = when (config.routingMode) {
            RoutingModeValue.ALL_TRAFFIC -> "Routing: all traffic"
            RoutingModeValue.SELECTED_APPS -> "Routing: ${config.selectedPackages.size} selected apps"
        }

        val proxyLine = "${config.type.uppercase()} ${config.host}:${config.port}"

        return NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(config.name)
            .setContentText(proxyLine)
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "$proxyLine\n$routingLine\nVPN tunnel is active.",
                ),
            )
            .setOngoing(true)
            .setContentIntent(openAppIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            channelId,
            "Proxy VPN",
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val channelId = "proxy_vpn"
        private const val notificationId = 1001
        private const val logTag = "ProxyVpnService"

        fun createStartIntent(
            context: Context,
            configuration: Map<*, *>,
        ): Intent {
            val intent = Intent(context, ProxyVpnService::class.java)
            intent.putExtra("name", configuration["name"] as? String)
            intent.putExtra("type", configuration["type"] as? String)
            intent.putExtra("host", configuration["host"] as? String)
            intent.putExtra("port", (configuration["port"] as? Number)?.toInt() ?: 0)
            intent.putExtra("username", configuration["username"] as? String)
            intent.putExtra("password", configuration["password"] as? String)
            intent.putExtra("routingMode", configuration["routingMode"] as? String)

            val rawSelectedApps = configuration["selectedApps"] as? List<*>
            val selectedPackages = ArrayList<String>()
            rawSelectedApps?.forEach { item ->
                val appMap = item as? Map<*, *>
                val packageName = appMap?.get("packageName") as? String
                if (!packageName.isNullOrBlank()) {
                    selectedPackages.add(packageName)
                }
            }
            intent.putStringArrayListExtra("selectedPackages", selectedPackages)
            return intent
        }

        fun createStopIntent(context: Context): Intent {
            return Intent(context, ProxyVpnService::class.java).apply {
                action = ACTION_STOP
            }
        }

        private const val ACTION_STOP = "org.roboratory.proxy_tool.STOP_PROXY"
    }
}

private data class ProxyServiceConfig(
    val name: String,
    val type: String,
    val host: String,
    val port: Int,
    val username: String?,
    val password: String?,
    val routingMode: RoutingModeValue,
    val selectedPackages: List<String>,
    val mtu: Int = 1500,
) {
    fun proxyUrl(): String {
        val scheme = when (type.lowercase()) {
            "http" -> "http"
            "https" -> "http"
            else -> "socks5"
        }

        val credentials = if (!username.isNullOrBlank()) {
            val encodedUser = URLEncoder.encode(username, Charsets.UTF_8.name())
            val encodedPassword = URLEncoder.encode(password ?: "", Charsets.UTF_8.name())
            "$encodedUser:$encodedPassword@"
        } else {
            ""
        }

        return "$scheme://$credentials$host:$port"
    }

    companion object {
        fun fromIntent(intent: Intent): ProxyServiceConfig {
            return ProxyServiceConfig(
                name = intent.getStringExtra("name") ?: "Proxy profile",
                type = intent.getStringExtra("type") ?: "socks5",
                host = intent.getStringExtra("host") ?: "",
                port = intent.getIntExtra("port", 0),
                username = intent.getStringExtra("username"),
                password = intent.getStringExtra("password"),
                routingMode = RoutingModeValue.fromRaw(
                    intent.getStringExtra("routingMode"),
                ),
                selectedPackages = intent.getStringArrayListExtra("selectedPackages")
                    ?: emptyList(),
            )
        }
    }
}

private enum class RoutingModeValue {
    ALL_TRAFFIC,
    SELECTED_APPS;

    companion object {
        fun fromRaw(raw: String?): RoutingModeValue {
            return when (raw) {
                "selectedApps" -> SELECTED_APPS
                else -> ALL_TRAFFIC
            }
        }
    }
}
