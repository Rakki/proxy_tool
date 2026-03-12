package org.roboratory.proxy_tool

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URLEncoder
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class ProxyVpnService : VpnService() {
    private var tunInterface: ParcelFileDescriptor? = null
    private var detachedTunFd: Int? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val monitorExecutor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor()
    private val cleanupLock = Any()
    private var activeSessionToken: Long = 0
    private var pendingRecoveryTask: ScheduledFuture<*>? = null
    private var pendingHealthTask: ScheduledFuture<*>? = null
    private var networkCallbackRegistered = false
    private var lastRecoveryAtMs: Long = 0
    @Volatile
    private var currentConfig: ProxyServiceConfig? = null
    @Volatile
    private var nativeRunning = false
    @Volatile
    private var stopRequested = false
    @Volatile
    private var sessionActive = false
    @Volatile
    private var networkAvailable = true

    private val connectivityManager by lazy {
        getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    }

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            networkAvailable = true
            RuntimeEventDispatcher.emit(
                type = "vpn_network_available",
                message = "Upstream network became available",
            )
            scheduleHealthCheck(1500L)
        }

        override fun onLost(network: Network) {
            networkAvailable = false
            RuntimeEventDispatcher.emit(
                type = "vpn_network_lost",
                message = "Upstream network lost, waiting for recovery",
            )
            scheduleRecovery("network_lost", 2000L)
        }

        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
            networkAvailable =
                networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            RuntimeEventDispatcher.emit(
                type = "vpn_network_changed",
                message = "Network capabilities changed",
                data = mapOf(
                    "validated" to networkCapabilities.hasCapability(
                        NetworkCapabilities.NET_CAPABILITY_VALIDATED,
                    ),
                    "transportWifi" to networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
                    "transportCellular" to networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
                ),
            )
            scheduleHealthCheck(1500L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        return super.onBind(intent)
    }

    override fun onCreate() {
        super.onCreate()
        RuntimeEventDispatcher.initialize(applicationContext)
        registerNetworkCallbackIfNeeded()
        schedulePeriodicHealthCheck()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            Log.i(logTag, "Received stop action")
            RuntimeEventDispatcher.emit(
                type = "vpn_stop_requested",
                message = "Stop requested for active VPN session",
            )
            currentConfig = null
            stopRequested = true
            cancelMonitorTasks()
            requestShutdownByClosingTun()
            return START_NOT_STICKY
        }

        val config = intent?.let { ProxyServiceConfig.fromIntent(it) }
            ?: return START_NOT_STICKY

        requestShutdownByClosingTun()
        val sessionToken = synchronized(cleanupLock) {
            activeSessionToken += 1
            activeSessionToken
        }
        currentConfig = config
        stopRequested = false
        sessionActive = true
        scheduleHealthCheck(2500L)
        WidgetStateStore.setActiveProfileId(applicationContext, config.id)
        ProxyWidgetProvider.refreshAll(applicationContext)
        createNotificationChannel()
        RuntimeEventDispatcher.emit(
            type = "vpn_starting",
            message = "Starting VPN profile ${config.name}",
            data = mapOf(
                "profileId" to config.id,
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
            WidgetStateStore.setActiveProfileId(applicationContext, null)
            ProxyWidgetProvider.refreshAll(applicationContext)
            stopSelf()
            return START_NOT_STICKY
        }

        tunInterface = vpnInterface
        RuntimeEventDispatcher.emit(
            type = "vpn_established",
            message = "VPN interface established",
            data = mapOf(
                "profileId" to config.id,
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
            WidgetStateStore.setActiveProfileId(applicationContext, null)
            ProxyWidgetProvider.refreshAll(applicationContext)
            stopSelf()
            return START_NOT_STICKY
        }
        val tunFd = vpnInterface.detachFd()
        synchronized(cleanupLock) {
            if (activeSessionToken != sessionToken) {
                tunInterface = null
                ParcelFileDescriptor.adoptFd(tunFd).close()
                vpnInterface.close()
                return START_NOT_STICKY
            }
            detachedTunFd = tunFd
        }
        executor.execute {
            try {
                nativeRunning = true
                val result = NativeTun2ProxyBridge.startTun2Proxy(
                    config.proxyUrl(),
                    tunFd,
                    config.mtu,
                )
                nativeRunning = false
                Log.i(logTag, "tun2proxy exited with code $result")
                RuntimeEventDispatcher.emit(
                    type = "tun2proxy_exit",
                    message = "tun2proxy exited with code $result",
                    data = mapOf("exitCode" to result),
                )
            } catch (error: Throwable) {
                nativeRunning = false
                Log.e(logTag, "tun2proxy crashed", error)
                RuntimeEventDispatcher.emit(
                    type = "vpn_error",
                    message = "tun2proxy crashed: ${error.message ?: error::class.java.simpleName}",
                )
            } finally {
                val shouldFinalizeCurrentSession = synchronized(cleanupLock) {
                    activeSessionToken == sessionToken
                }
                if (shouldFinalizeCurrentSession) {
                    sessionActive = false
                    WidgetStateStore.setActiveProfileId(applicationContext, null)
                    ProxyWidgetProvider.refreshAll(applicationContext)
                    cancelMonitorTasks()
                    closeSessionResources()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        WidgetStateStore.setActiveProfileId(applicationContext, null)
        ProxyWidgetProvider.refreshAll(applicationContext)
        RuntimeEventDispatcher.emit(
            type = "vpn_destroyed",
            message = "VPN service destroyed",
        )
        cancelMonitorTasks()
        unregisterNetworkCallbackIfNeeded()
        requestShutdownByClosingTun()
        executor.shutdown()
        monitorExecutor.shutdownNow()
        super.onDestroy()
    }

    override fun onRevoke() {
        Log.i(logTag, "VPN revoked by system")
        WidgetStateStore.setActiveProfileId(applicationContext, null)
        ProxyWidgetProvider.refreshAll(applicationContext)
        RuntimeEventDispatcher.emit(
            type = "vpn_revoked",
            message = "VPN permission revoked by system",
        )
        currentConfig = null
        stopRequested = true
        cancelMonitorTasks()
        requestShutdownByClosingTun()
        super.onRevoke()
    }

    private fun registerNetworkCallbackIfNeeded() {
        if (networkCallbackRegistered) {
            return
        }

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        connectivityManager.registerNetworkCallback(request, networkCallback)
        networkCallbackRegistered = true
    }

    private fun unregisterNetworkCallbackIfNeeded() {
        if (!networkCallbackRegistered) {
            return
        }

        runCatching {
            connectivityManager.unregisterNetworkCallback(networkCallback)
        }
        networkCallbackRegistered = false
    }

    private fun cancelMonitorTasks() {
        pendingRecoveryTask?.cancel(false)
        pendingRecoveryTask = null
        pendingHealthTask?.cancel(false)
        pendingHealthTask = null
    }

    private fun schedulePeriodicHealthCheck() {
        monitorExecutor.scheduleWithFixedDelay(
            {
                performHealthCheck("periodic")
            },
            20L,
            20L,
            TimeUnit.SECONDS,
        )
    }

    private fun scheduleHealthCheck(delayMs: Long) {
        pendingHealthTask?.cancel(false)
        pendingHealthTask = monitorExecutor.schedule(
            {
                performHealthCheck("network_change")
            },
            delayMs,
            TimeUnit.MILLISECONDS,
        )
    }

    private fun performHealthCheck(reason: String) {
        val config = currentConfig ?: return
        if (stopRequested || !sessionActive) {
            return
        }
        if (!networkAvailable) {
            scheduleRecovery("no_network", 2500L)
            return
        }

        val reachable = isProxyReachable(config)
        if (!reachable) {
            RuntimeEventDispatcher.emit(
                type = "vpn_degraded",
                message = "Proxy health check failed",
                data = mapOf(
                    "profileId" to config.id,
                    "reason" to reason,
                    "endpoint" to "${config.host}:${config.port}",
                ),
            )
            scheduleRecovery("health_check_failed", 2500L)
        } else {
            RuntimeEventDispatcher.emit(
                type = "vpn_healthy",
                message = "Proxy health check succeeded",
                data = mapOf(
                    "profileId" to config.id,
                    "endpoint" to "${config.host}:${config.port}",
                ),
            )
        }
    }

    private fun isProxyReachable(config: ProxyServiceConfig): Boolean {
        return runCatching {
            Socket().use { socket ->
                protect(socket)
                socket.connect(InetSocketAddress(config.host, config.port), 3000)
            }
            true
        }.getOrDefault(false)
    }

    private fun scheduleRecovery(trigger: String, delayMs: Long) {
        if (stopRequested) {
            return
        }

        pendingRecoveryTask?.cancel(false)
        pendingRecoveryTask = monitorExecutor.schedule(
            {
                recoverActiveProfile(trigger)
            },
            delayMs,
            TimeUnit.MILLISECONDS,
        )
    }

    private fun recoverActiveProfile(trigger: String) {
        val config = currentConfig ?: return
        if (stopRequested) {
            return
        }
        if (!networkAvailable) {
            scheduleRecovery("awaiting_network", 3000L)
            return
        }

        val now = System.currentTimeMillis()
        if (now - lastRecoveryAtMs < 8000L) {
            return
        }
        lastRecoveryAtMs = now

        RuntimeEventDispatcher.emit(
            type = "vpn_reconnecting",
            message = "Reconnecting active proxy after network change",
            data = mapOf(
                "profileId" to config.id,
                "trigger" to trigger,
                "endpoint" to "${config.host}:${config.port}",
            ),
        )

        val restartIntent = createStartIntent(applicationContext, config.toWidgetMap())
        ContextCompat.startForegroundService(this, restartIntent)
    }

    private fun requestShutdownByClosingTun() {
        RuntimeEventDispatcher.emit(
            type = "tun2proxy_stop",
            message = "Stopping tun2proxy by closing TUN resources",
        )
        synchronized(cleanupLock) {
            nativeRunning = false
            sessionActive = false
        }
        closeSessionResources()
    }

    private fun closeSessionResources() {
        var tunFdToClose: Int? = null
        var tunInterfaceToClose: ParcelFileDescriptor? = null

        synchronized(cleanupLock) {
            sessionActive = false
            tunFdToClose = detachedTunFd
            detachedTunFd = null
            tunInterfaceToClose = tunInterface
            tunInterface = null
        }

        try {
            tunFdToClose?.let { fd ->
                ParcelFileDescriptor.adoptFd(fd).close()
            }
        } catch (error: Throwable) {
            Log.w(logTag, "Failed to close detached tun fd", error)
            RuntimeEventDispatcher.emit(
                type = "vpn_error",
                message = "Failed to close detached tun fd: ${error.message ?: error::class.java.simpleName}",
            )
        }

        try {
            tunInterfaceToClose?.close()
        } catch (error: Exception) {
            Log.w(logTag, "Failed to close VPN interface", error)
            RuntimeEventDispatcher.emit(
                type = "vpn_error",
                message = "Failed to close VPN interface: ${error.message ?: error::class.java.simpleName}",
            )
        }
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
            intent.putExtra("id", configuration["id"] as? String)
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
    val id: String?,
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

    fun toWidgetMap(): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "name" to name,
            "type" to type,
            "host" to host,
            "port" to port,
            "username" to username,
            "password" to password,
            "routingMode" to when (routingMode) {
                RoutingModeValue.ALL_TRAFFIC -> "allTraffic"
                RoutingModeValue.SELECTED_APPS -> "selectedApps"
            },
            "selectedApps" to selectedPackages.map { packageName ->
                mapOf(
                    "name" to packageName,
                    "packageName" to packageName,
                )
            },
        )
    }

    companion object {
        fun fromIntent(intent: Intent): ProxyServiceConfig {
            return ProxyServiceConfig(
                id = intent.getStringExtra("id"),
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
