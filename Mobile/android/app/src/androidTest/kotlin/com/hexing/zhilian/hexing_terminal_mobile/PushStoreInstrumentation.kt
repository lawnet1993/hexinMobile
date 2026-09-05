package com.hexing.zhilian.hexing_terminal_mobile

import android.app.Activity
import android.app.Instrumentation
import android.content.Context
import android.os.Bundle
import android.util.Base64
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.SecretKey

/** Isolated on-device Keystore test. Never reads application credentials. */
class PushStoreInstrumentation : Instrumentation() {
    private lateinit var arguments: Bundle
    private val passed = mutableListOf<String>()

    override fun onCreate(arguments: Bundle?) {
        this.arguments = arguments ?: Bundle()
        start()
    }

    private fun verify(name: String, condition: Boolean) {
        check(condition) { name }
        passed.add(name)
    }

    override fun onStart() {
        val report = Bundle()
        try {
            val runId = arguments.getString("runId").orEmpty()
            require(Regex("^[a-f0-9]{32}$").matches(runId))
            val name = "ai-uat-push-$runId"
            val legacyName = "$name-legacy"
            val context = targetContext
            val store = SecurePushTokenStore(context, name, legacyName)
            val directory = File(context.noBackupFilesDir, name)
            fun file(scope: String) = File(directory, "$scope.json")
            val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            val scopes = listOf("uat-test", "uat-production", "tamper", "key-loss", "copy-other", "legacy-unscoped")
            when (arguments.getString("phase")) {
                "seed" -> {
                    verify("isolated_empty_fixture", !directory.exists())
                    store.write("uat-test", "fixture-provider", "fixture-token-test")
                    store.write("uat-production", "fixture-provider", "fixture-token-production")
                    verify("roundtrip", store.read("uat-test")?.get("token") == "fixture-token-test")
                    verify("environment_isolation", store.read("uat-production")?.get("token") == "fixture-token-production")
                    verify("ciphertext_only", !file("uat-test").readText().contains("fixture-token") && !file("uat-test").readText().contains("fixture-provider"))
                    val key = keys.getKey("$name.uat-test", null) as SecretKey
                    verify("key_non_exportable", key.encoded == null)
                    verify("no_backup_directory", directory.canonicalFile.parentFile == context.noBackupFilesDir.canonicalFile)
                    val firstCipher = file("uat-test").readText()
                    store.write("uat-test", "fixture-provider", "fixture-token-test")
                    verify("fresh_iv_per_write", firstCipher != file("uat-test").readText())
                    verify("fresh_instance_reads", SecurePushTokenStore(context, name, legacyName).read("uat-test")?.get("token") == "fixture-token-test")
                    verify("path_traversal_rejected", runCatching { store.write("../unsafe", "fixture", "fixture") }.isFailure)
                    verify("oversized_write_rejected", runCatching { store.write("uat-test", "fixture", "x".repeat(8193)) }.isFailure && store.read("uat-test")?.get("token") == "fixture-token-test")
                    store.write("tamper", "fixture-provider", "fixture-token-tamper")
                    val record = JSONObject(file("tamper").readText())
                    val encrypted = Base64.decode(record.getString("ciphertext"), Base64.NO_WRAP)
                    encrypted[0] = (encrypted[0].toInt() xor 1).toByte()
                    record.put("ciphertext", Base64.encodeToString(encrypted, Base64.NO_WRAP))
                    file("tamper").writeText(record.toString())
                    verify("tamper_fails_closed", store.read("tamper") == null)
                    store.write("copy-other", "fixture-provider", "fixture-token-other")
                    file("uat-test").copyTo(file("copy-other"), overwrite = true)
                    verify("cross_scope_cipher_rejected", store.read("copy-other") == null)
                    store.write("key-loss", "fixture-provider", "fixture-token-lost")
                    keys.deleteEntry("$name.key-loss")
                    verify("missing_key_fails_closed", store.read("key-loss") == null && !keys.containsAlias("$name.key-loss"))
                    store.write("key-loss", "fixture-provider", "fixture-token-reissued")
                    verify("fresh_token_recovers_key_loss", store.read("key-loss")?.get("token") == "fixture-token-reissued")
                    val legacy = context.getSharedPreferences(legacyName, Context.MODE_PRIVATE)
                    check(legacy.edit().putString("provider", "fixture-provider").putString("token", "fixture-token-legacy").putBoolean("keep", true).commit())
                    store.quarantineLegacy()
                    verify("legacy_plaintext_removed", !legacy.contains("provider") && !legacy.contains("token") && legacy.getBoolean("keep", false))
                    verify("legacy_encrypted_not_auto_bound", file("legacy-unscoped").isFile && !file("legacy-unscoped").readText().contains("fixture-token-legacy") && store.read("legacy-unscoped") == null && store.read("uat-test")?.get("token") == "fixture-token-test")
                    val quarantine = file("legacy-unscoped").readText()
                    store.quarantineLegacy()
                    verify("legacy_migration_idempotent", file("legacy-unscoped").readText() == quarantine)
                }
                "verify" -> {
                    verify("new_process_test_token_preserved", store.read("uat-test")?.get("token") == "fixture-token-test")
                    verify("new_process_production_isolated", store.read("uat-production")?.get("token") == "fixture-token-production")
                    verify("new_process_legacy_still_quarantined", store.read("legacy-unscoped") == null)
                    verify("new_process_tamper_still_rejected", store.read("tamper") == null)
                    // Only this run's dedicated fixture aliases/files/preferences.
                    scopes.forEach { keys.deleteEntry("$name.$it") }
                    directory.listFiles().orEmpty().forEach {
                        check(it.isFile && it.canonicalFile.parentFile == directory.canonicalFile)
                        check(it.delete())
                    }
                    check(directory.delete())
                    check(context.getSharedPreferences(legacyName, Context.MODE_PRIVATE).edit().clear().commit())
                    verify("fixture_cleanup", !directory.exists() && scopes.none { keys.containsAlias("$name.$it") })
                }
                else -> error("Unsupported test phase")
            }
            report.putString("result", "passed")
            report.putInt("passed_count", passed.size)
            report.putString("passed_checks", passed.joinToString(","))
            report.putInt("process_id", android.os.Process.myPid())
            finish(Activity.RESULT_OK, report)
        } catch (_: Throwable) {
            report.putString("result", "failed")
            report.putInt("passed_count", passed.size)
            report.putString("passed_checks", passed.joinToString(","))
            finish(Activity.RESULT_CANCELED, report)
        }
    }
}
