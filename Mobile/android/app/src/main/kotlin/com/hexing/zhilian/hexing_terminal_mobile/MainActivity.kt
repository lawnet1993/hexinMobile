package com.hexing.zhilian.hexing_terminal_mobile

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    private var initialTargetRoute: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        initialTargetRoute = targetRoute(intent)
        activeActivity = WeakReference(this)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getToken" -> result.success(readToken(this))
                    "getInitialNotification" -> {
                        result.success(initialTargetRoute)
                        initialTargetRoute = null
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(this)
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
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onDestroy() {
        if (activeActivity.get() === this) {
            activeActivity.clear()
        }
        eventSink = null
        super.onDestroy()
    }

    private fun emitToken(provider: String, token: String) {
        eventSink?.success(
            mapOf(
                "type" to "token",
                "platform" to "android",
                "provider" to provider,
                "token" to token,
            ),
        )
    }

    companion object {
        private const val METHOD_CHANNEL = "com.hexing.zhilian/push"
        private const val EVENT_CHANNEL = "com.hexing.zhilian/push/events"
        private const val PREFERENCES = "mobile_push"
        private const val PROVIDER_KEY = "provider"
        private const val TOKEN_KEY = "token"
        const val TARGET_ROUTE_EXTRA = "im_target_route"

        private var activeActivity = WeakReference<MainActivity>(null)

        @JvmStatic
        fun publishPushToken(context: Context, provider: String, token: String) {
            val normalizedProvider = provider.trim()
            val normalizedToken = token.trim()
            if (normalizedProvider.isEmpty() || normalizedToken.isEmpty()) return
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit()
                .putString(PROVIDER_KEY, normalizedProvider)
                .putString(TOKEN_KEY, normalizedToken)
                .apply()
            activeActivity.get()?.runOnUiThread {
                activeActivity.get()?.emitToken(normalizedProvider, normalizedToken)
            }
        }

        @JvmStatic
        fun notificationIntent(context: Context, targetRoute: String): Intent =
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(TARGET_ROUTE_EXTRA, targetRoute)

        private fun readToken(context: Context): Map<String, String>? {
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            val provider = preferences.getString(PROVIDER_KEY, "")?.trim().orEmpty()
            val token = preferences.getString(TOKEN_KEY, "")?.trim().orEmpty()
            if (provider.isEmpty() || token.isEmpty()) return null
            return mapOf(
                "platform" to "android",
                "provider" to provider,
                "token" to token,
            )
        }

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
