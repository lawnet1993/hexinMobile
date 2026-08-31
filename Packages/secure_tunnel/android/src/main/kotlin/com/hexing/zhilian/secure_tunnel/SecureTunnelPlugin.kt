package com.hexing.zhilian.secure_tunnel

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.security.MessageDigest

class SecureTunnelPlugin : FlutterPlugin, ActivityAware,
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler,
    PluginRegistry.ActivityResultListener {
    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var activity: Activity? = null
    private var permissionResult: MethodChannel.Result? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        events = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)
    override fun onDetachedFromActivity() { activity = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getRuntimeIdentity" -> result.success(runtimeIdentity())
            "getStatus" -> result.success(currentStatus())
            "requestPermission" -> requestPermission(result)
            "installProfile" -> installProfile(call, result)
            "start" -> start(result)
            "stop" -> {
                savePhase("disconnected", "安全连接已断开")
                result.success(null)
            }
            "rollback" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    private fun runtimeIdentity(): Map<String, Any> {
        val core = File(context.applicationInfo.nativeLibraryDir, "libmihomo.so")
        val exists = core.isFile
        val version = context.applicationInfo.metaData
            ?.getString("com.hexing.zhilian.secure_tunnel.CORE_VERSION")
            .orEmpty()
        return mapOf(
            "platform" to "android",
            "architecture" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
            "corePath" to if (exists) core.absolutePath else "",
            "coreVersion" to if (exists) version else "",
            "coreSha256" to if (exists) sha256(core) else "",
        )
    }

    private fun requestPermission(result: MethodChannel.Result) {
        val intent = VpnService.prepare(context)
        if (intent == null) {
            result.success(true)
            return
        }
        val host = activity
        if (host == null || permissionResult != null) {
            result.success(false)
            return
        }
        permissionResult = result
        host.startActivityForResult(intent, VPN_PERMISSION_REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != VPN_PERMISSION_REQUEST) return false
        permissionResult?.success(resultCode == Activity.RESULT_OK)
        permissionResult = null
        return true
    }

    private fun installProfile(call: MethodCall, result: MethodChannel.Result) {
        val corePath = call.argument<String>("corePath").orEmpty()
        val coreSha = call.argument<String>("coreSha256").orEmpty().lowercase()
        val configPath = call.argument<String>("configPath").orEmpty()
        val configSha = call.argument<String>("configSha256").orEmpty().lowercase()
        val core = File(corePath)
        val config = File(configPath)
        if (!core.isFile || sha256(core) != coreSha) {
            result.error("core_invalid", "安全隧道内核校验失败", null)
            return
        }
        if (!config.isFile || sha256(config) != configSha) {
            result.error("config_invalid", "安全策略校验失败", null)
            return
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("profileId", call.argument<String>("profileId").orEmpty())
            .putString("profileVersion", call.argument<String>("profileVersion").orEmpty())
            .putString("coreVersion", call.argument<String>("coreVersion").orEmpty())
            .apply()
        savePhase("disconnected", "安全策略已安装")
        result.success(null)
    }

    private fun start(result: MethodChannel.Result) {
        val identity = runtimeIdentity()
        if ((identity["corePath"] as String).isEmpty()) {
            savePhase("unavailable", "当前安装包未包含受信任的 mihomo 内核")
            result.error("core_missing", "当前安装包未包含受信任的 mihomo 内核", null)
            return
        }
        result.error("core_bridge_missing", "mihomo Android TUN 桥接尚未接入", null)
    }

    private fun currentStatus(): Map<String, Any> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val identity = runtimeIdentity()
        val coreAvailable = (identity["corePath"] as String).isNotEmpty()
        return mapOf(
            "phase" to if (coreAvailable) prefs.getString("phase", "disconnected")!! else "unavailable",
            "message" to if (coreAvailable) prefs.getString("message", "安全连接未启用")!!
                else "当前安装包未包含受信任的 mihomo 内核",
            "profileId" to prefs.getString("profileId", "")!!,
            "profileVersion" to prefs.getString("profileVersion", "")!!,
            "coreVersion" to prefs.getString("coreVersion", "")!!,
            "uploadBytes" to 0L,
            "downloadBytes" to 0L,
        )
    }

    private fun savePhase(phase: String, message: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("phase", phase).putString("message", message).apply()
        eventSink?.success(currentStatus())
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count <= 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
        sink?.success(currentStatus())
    }
    override fun onCancel(arguments: Any?) { eventSink = null }

    companion object {
        private const val METHOD_CHANNEL = "com.hexing.zhilian/secure_tunnel"
        private const val EVENT_CHANNEL = "com.hexing.zhilian/secure_tunnel/status"
        private const val VPN_PERMISSION_REQUEST = 41731
        private const val PREFS = "secure_tunnel"
    }
}
