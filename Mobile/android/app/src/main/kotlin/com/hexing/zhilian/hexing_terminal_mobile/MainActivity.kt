package com.hexing.zhilian.hexing_terminal_mobile

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    private var eventNamespace: String? = null
    private var initialTargetRoute: String? = null
    private var startupStartedAt = 0L
    private var firstFlutterUiReported = false

    override fun onCreate(savedInstanceState: Bundle?) {
        startupStartedAt = SystemClock.elapsedRealtime()
        startupStage("onCreateEnter")
        initialTargetRoute = targetRoute(intent)
        activeActivity = WeakReference(this)
        super.onCreate(savedInstanceState)
        startupStage("onCreateReturn")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        startupStage("configureEngineEnter")
        super.configureFlutterEngine(flutterEngine)
        startupStage("pluginsRegistered")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getToken" -> {
                        val namespace = call.argument<String>("storageNamespace")
                        pushStorageExecutor.execute {
                            val value = try {
                                val store = SecurePushTokenStore(applicationContext)
                                store.quarantineLegacy()
                                namespace?.let { store.read(it) }
                            } catch (_: Exception) { null }
                            runOnUiThread { result.success(value) }
                        }
                    }
                    "getInitialNotification" -> {
                        result.success(initialTargetRoute)
                        initialTargetRoute = null
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(this)
        startupStage("configureEngineReturn")
    }

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        if (!firstFlutterUiReported) {
            firstFlutterUiReported = true
            startupStage("firstFlutterUiDisplayed")
        }
    }

    private fun startupStage(stage: String) {
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
        Log.i("MOBILE_STARTUP_NATIVE", "{\"stage\":\"$stage\",\"elapsedMs\":${SystemClock.elapsedRealtime() - startupStartedAt}}")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        targetRoute(intent)?.let { route ->
            val sink = eventSink
            if (sink == null) {
                initialTargetRoute = route
            } else {
                sink.success(
                    mapOf(
                        "type" to "notification",
                        "targetRoute" to route,
                    ),
                )
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        eventNamespace = (arguments as? Map<*, *>)?.get("storageNamespace") as? String
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        eventNamespace = null
    }

    override fun onDestroy() {
        if (activeActivity.get() === this) {
            activeActivity.clear()
        }
        eventSink = null
        super.onDestroy()
    }

    private fun emitToken(namespace: String, provider: String, token: String) {
        if (namespace != eventNamespace) return
        eventSink?.success(
            mapOf(
                "type" to "token",
                "platform" to "android",
                "provider" to provider,
                "token" to token,
                "storageNamespace" to namespace,
            ),
        )
    }

    companion object {
        private const val METHOD_CHANNEL = "com.hexing.zhilian/push"
        private const val EVENT_CHANNEL = "com.hexing.zhilian/push/events"
        const val TARGET_ROUTE_EXTRA = "im_target_route"

        private var activeActivity = WeakReference<MainActivity>(null)
        private val pushStorageExecutor = Executors.newSingleThreadExecutor()

        @JvmStatic
        fun publishPushToken(context: Context, storageNamespace: String, provider: String, token: String) {
            val normalizedProvider = provider.trim()
            val normalizedToken = token.trim()
            if (normalizedProvider.isEmpty() || normalizedToken.isEmpty()) return
            val applicationContext = context.applicationContext
            pushStorageExecutor.execute {
                try {
                    val store = SecurePushTokenStore(applicationContext)
                    store.quarantineLegacy()
                    store.write(storageNamespace, normalizedProvider, normalizedToken)
                    activeActivity.get()?.runOnUiThread {
                        activeActivity.get()?.emitToken(storageNamespace, normalizedProvider, normalizedToken)
                    }
                } catch (_: Exception) {
                    // No insecure fallback or credential-bearing error output.
                }
            }
        }

        @JvmStatic
        fun notificationIntent(context: Context, targetRoute: String): Intent =
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(TARGET_ROUTE_EXTRA, targetRoute)

        private fun targetRoute(intent: Intent?): String? {
            val route = intent?.getStringExtra(TARGET_ROUTE_EXTRA)?.trim()
                ?: intent?.data?.takeIf {
                    it.scheme == "hexing-zhilian" && it.host == "im"
                }?.path
            return normalizeTargetRoute(route)
        }

        private fun normalizeTargetRoute(value: String?): String? {
            val route = value?.trim().orEmpty()
            if (
                route == "/messages" ||
                route == "/todos" ||
                route == "/notifications" ||
                route == "/contacts" ||
                route == "/contacts?mode=requests"
            ) {
                return route
            }
            return route.takeIf {
                CHAT_ROUTE.matches(it) || APPROVAL_ROUTE.matches(it)
            }
        }

        private val CHAT_ROUTE = Regex(
            "^/chat/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-" +
                "[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
        )
        private val APPROVAL_ROUTE = Regex(
            "^/approval/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-" +
                "[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
        )
    }
}
