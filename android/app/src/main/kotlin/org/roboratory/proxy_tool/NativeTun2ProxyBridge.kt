package org.roboratory.proxy_tool

object NativeTun2ProxyBridge {
    init {
        System.loadLibrary("proxybridge")
    }

    external fun startTun2Proxy(
        proxyUrl: String,
        tunFd: Int,
        tunMtu: Int,
    ): Int

    external fun stopTun2Proxy(): Int

    @JvmStatic
    fun onNativeLog(level: String, message: String) {
        RuntimeEventDispatcher.emit(
            type = "native_log",
            message = message,
            data = mapOf("level" to level),
        )
    }

    @JvmStatic
    fun onNativeTraffic(tx: Long, rx: Long) {
        RuntimeEventDispatcher.emit(
            type = "traffic",
            message = "Traffic update",
            data = mapOf("tx" to tx, "rx" to rx),
        )
    }
}
