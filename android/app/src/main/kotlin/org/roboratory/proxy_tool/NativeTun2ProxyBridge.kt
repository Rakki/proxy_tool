package org.roboratory.proxy_tool

object NativeTun2ProxyBridge {
    @Volatile
    private var lastTrafficAtMs: Long = 0L

    @Volatile
    private var lastConnectionAttemptAtMs: Long = 0L

    @Volatile
    private var lastTxBytes: Long = 0L

    @Volatile
    private var lastRxBytes: Long = 0L

    init {
        System.loadLibrary("proxybridge")
    }

    external fun startTun2Proxy(
        proxyUrl: String,
        tunFd: Int,
        tunMtu: Int,
    ): Int

    external fun stopTun2Proxy(): Int

    fun resetRuntimeStats() {
        lastTrafficAtMs = 0L
        lastConnectionAttemptAtMs = 0L
        lastTxBytes = 0L
        lastRxBytes = 0L
    }

    fun runtimeStats(): Map<String, Long> {
        return mapOf(
            "lastTrafficAtMs" to lastTrafficAtMs,
            "lastConnectionAttemptAtMs" to lastConnectionAttemptAtMs,
            "tx" to lastTxBytes,
            "rx" to lastRxBytes,
        )
    }

    @JvmStatic
    fun onNativeLog(level: String, message: String) {
        val isConnectionAttempt = message.startsWith("Beginning #")
        if (isConnectionAttempt) {
            lastConnectionAttemptAtMs = System.currentTimeMillis()
        }
        val shouldEmitToFlutter =
            isConnectionAttempt || level == "warn" || level == "error"
        if (!shouldEmitToFlutter) {
            return
        }
        RuntimeEventDispatcher.emit(
            type = "native_log",
            message = message,
            data = mapOf("level" to level),
        )
    }

    @JvmStatic
    fun onNativeTraffic(tx: Long, rx: Long) {
        lastTrafficAtMs = System.currentTimeMillis()
        lastTxBytes = tx
        lastRxBytes = rx
        RuntimeEventDispatcher.emit(
            type = "traffic",
            message = "Traffic update",
            data = mapOf("tx" to tx, "rx" to rx),
        )
    }
}
