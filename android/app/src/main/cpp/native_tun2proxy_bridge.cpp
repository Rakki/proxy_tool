#include <android/log.h>
#include <dlfcn.h>
#include <jni.h>

#include <atomic>
#include <mutex>
#include <string>

#include "tun2proxy.h"

namespace {
constexpr const char* kLogTag = "Tun2Proxy";

JavaVM* g_vm = nullptr;
jclass g_bridge_class = nullptr;
void* g_tun2proxy_handle = nullptr;
std::mutex g_library_mutex;

using SetLogCallbackFn = void (*)(void (*)(enum Tun2proxyVerbosity, const char*, void*), void*);
using WithFdRunFn = int (*)(const char*, int, bool, bool, unsigned short, enum Tun2proxyDns, enum Tun2proxyVerbosity);
using StopFn = int (*)();
using SetTrafficCallbackFn = void (*)(uint32_t, void (*)(const struct Tun2proxyTrafficStatus*, void*), void*);

SetLogCallbackFn g_set_log_callback = nullptr;
WithFdRunFn g_with_fd_run = nullptr;
StopFn g_stop = nullptr;
SetTrafficCallbackFn g_set_traffic_callback = nullptr;
std::atomic<bool> g_callbacks_enabled{false};

std::string verbosity_to_string(enum Tun2proxyVerbosity verbosity) {
    switch (verbosity) {
        case Tun2proxyVerbosity_Error:
            return "error";
        case Tun2proxyVerbosity_Warn:
            return "warn";
        case Tun2proxyVerbosity_Debug:
            return "debug";
        case Tun2proxyVerbosity_Trace:
            return "trace";
        case Tun2proxyVerbosity_Info:
            return "info";
        case Tun2proxyVerbosity_Off:
        default:
            return "info";
    }
}

JNIEnv* get_jni_env() {
    if (g_vm == nullptr) {
        return nullptr;
    }

    JNIEnv* env = nullptr;
    const jint status = g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (status == JNI_OK) {
        return env;
    }

    if (status == JNI_EDETACHED) {
        if (g_vm->AttachCurrentThread(&env, nullptr) == JNI_OK) {
            return env;
        }
    }

    return nullptr;
}

bool ensure_tun2proxy_loaded() {
    std::lock_guard<std::mutex> lock(g_library_mutex);
    if (g_tun2proxy_handle != nullptr) {
        return true;
    }

    g_tun2proxy_handle = dlopen("libtun2proxy.so", RTLD_NOW);
    if (g_tun2proxy_handle == nullptr) {
        __android_log_print(ANDROID_LOG_ERROR, kLogTag, "dlopen failed: %s", dlerror());
        return false;
    }

    g_set_log_callback = reinterpret_cast<SetLogCallbackFn>(
        dlsym(g_tun2proxy_handle, "tun2proxy_set_log_callback"));
    g_with_fd_run = reinterpret_cast<WithFdRunFn>(
        dlsym(g_tun2proxy_handle, "tun2proxy_with_fd_run"));
    g_stop = reinterpret_cast<StopFn>(
        dlsym(g_tun2proxy_handle, "tun2proxy_stop"));
    g_set_traffic_callback = reinterpret_cast<SetTrafficCallbackFn>(
        dlsym(g_tun2proxy_handle, "tun2proxy_set_traffic_status_callback"));

    if (g_set_log_callback == nullptr ||
        g_with_fd_run == nullptr ||
        g_stop == nullptr ||
        g_set_traffic_callback == nullptr) {
        __android_log_print(ANDROID_LOG_ERROR, kLogTag, "Failed to resolve tun2proxy symbols");
        return false;
    }

    return true;
}

void emit_log_to_java(const char* level, const char* message) {
    if (!g_callbacks_enabled.load() || g_bridge_class == nullptr || message == nullptr) {
        return;
    }

    JNIEnv* env = get_jni_env();
    if (env == nullptr) {
        return;
    }

    const jmethodID method = env->GetStaticMethodID(
        g_bridge_class,
        "onNativeLog",
        "(Ljava/lang/String;Ljava/lang/String;)V");
    if (method == nullptr) {
        return;
    }

    jstring j_level = env->NewStringUTF(level);
    jstring j_message = env->NewStringUTF(message);
    env->CallStaticVoidMethod(g_bridge_class, method, j_level, j_message);
    env->DeleteLocalRef(j_level);
    env->DeleteLocalRef(j_message);
}

void emit_traffic_to_java(const struct Tun2proxyTrafficStatus* status) {
    if (!g_callbacks_enabled.load() || g_bridge_class == nullptr || status == nullptr) {
        return;
    }

    JNIEnv* env = get_jni_env();
    if (env == nullptr) {
        return;
    }

    const jmethodID method = env->GetStaticMethodID(
        g_bridge_class,
        "onNativeTraffic",
        "(JJ)V");
    if (method == nullptr) {
        return;
    }

    env->CallStaticVoidMethod(
        g_bridge_class,
        method,
        static_cast<jlong>(status->tx),
        static_cast<jlong>(status->rx));
}

void log_callback(enum Tun2proxyVerbosity verbosity, const char* message, void* /*ctx*/) {
    if (!g_callbacks_enabled.load()) {
        return;
    }

    int priority = ANDROID_LOG_INFO;
    switch (verbosity) {
        case Tun2proxyVerbosity_Error:
            priority = ANDROID_LOG_ERROR;
            break;
        case Tun2proxyVerbosity_Warn:
            priority = ANDROID_LOG_WARN;
            break;
        case Tun2proxyVerbosity_Debug:
        case Tun2proxyVerbosity_Trace:
            priority = ANDROID_LOG_DEBUG;
            break;
        case Tun2proxyVerbosity_Info:
        case Tun2proxyVerbosity_Off:
        default:
            priority = ANDROID_LOG_INFO;
            break;
    }

    if (message != nullptr) {
      __android_log_print(priority, kLogTag, "%s", message);
      emit_log_to_java(verbosity_to_string(verbosity).c_str(), message);
    }
}

void traffic_callback(const struct Tun2proxyTrafficStatus* status, void* /*ctx*/) {
    if (!g_callbacks_enabled.load()) {
        return;
    }
    emit_traffic_to_java(status);
}

void disable_callbacks() {
    g_callbacks_enabled.store(false);
    if (g_set_log_callback != nullptr) {
        g_set_log_callback(nullptr, nullptr);
    }
    if (g_set_traffic_callback != nullptr) {
        g_set_traffic_callback(0, nullptr, nullptr);
    }
}
}  // namespace

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* /*reserved*/) {
    g_vm = vm;
    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
        return JNI_ERR;
    }

    jclass local_class = env->FindClass("org/roboratory/proxy_tool/NativeTun2ProxyBridge");
    if (local_class == nullptr) {
        return JNI_ERR;
    }
    g_bridge_class = static_cast<jclass>(env->NewGlobalRef(local_class));
    env->DeleteLocalRef(local_class);
    return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT jint JNICALL
Java_org_roboratory_proxy_1tool_NativeTun2ProxyBridge_startTun2Proxy(
    JNIEnv* env,
    jobject /*thiz*/,
    jstring proxy_url,
    jint tun_fd,
    jint tun_mtu
) {
    if (!ensure_tun2proxy_loaded()) {
        return -1;
    }

    const char* proxy = env->GetStringUTFChars(proxy_url, nullptr);
    g_callbacks_enabled.store(true);
    g_set_log_callback(log_callback, nullptr);
    g_set_traffic_callback(2, traffic_callback, nullptr);
    const int result = g_with_fd_run(
        proxy,
        tun_fd,
        false,
        false,
        static_cast<unsigned short>(tun_mtu),
        Tun2proxyDns_Virtual,
        Tun2proxyVerbosity_Info);
    env->ReleaseStringUTFChars(proxy_url, proxy);
    disable_callbacks();
    return result;
}

extern "C" JNIEXPORT jint JNICALL
Java_org_roboratory_proxy_1tool_NativeTun2ProxyBridge_stopTun2Proxy(
    JNIEnv* /*env*/,
    jobject /*thiz*/
) {
    if (!ensure_tun2proxy_loaded()) {
        return -1;
    }
    disable_callbacks();
    return g_stop();
}
