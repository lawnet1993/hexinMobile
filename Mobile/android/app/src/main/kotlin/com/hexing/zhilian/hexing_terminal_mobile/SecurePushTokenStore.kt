package com.hexing.zhilian.hexing_terminal_mobile

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Device push credentials only. Call off the UI thread; never log values. */
internal class SecurePushTokenStore(
    context: Context,
    private val storageName: String = "mobile-push-v2",
    private val legacyPreferencesName: String = "mobile_push",
) {
    private val context = context.applicationContext
    private val directory = File(context.noBackupFilesDir, storageName)

    init { require(VALID_NAME.matches(storageName)) }

    fun read(namespace: String): Map<String, String>? = synchronized(LOCK) {
        validateNamespace(namespace)
        if (namespace == LEGACY_QUARANTINE) return@synchronized null
        readUnlocked(namespace)
    }

    fun write(namespace: String, provider: String, token: String) = synchronized(LOCK) {
        validateNamespace(namespace)
        require(namespace != LEGACY_QUARANTINE)
        writeUnlocked(namespace, provider, token)
    }

    /** Legacy values have no environment identity: encrypt but never bind them. */
    fun quarantineLegacy() = synchronized(LOCK) {
        val legacy = context.getSharedPreferences(legacyPreferencesName, Context.MODE_PRIVATE)
        if (!legacy.contains("provider") && !legacy.contains("token")) return@synchronized
        val provider = legacy.getString("provider", "").orEmpty()
        val token = legacy.getString("token", "").orEmpty()
        if (token.isNotEmpty()) {
            writeUnlocked(LEGACY_QUARANTINE, provider.ifEmpty { "legacy" }, token)
            val stored = readUnlocked(LEGACY_QUARANTINE)
            check(stored?.get("token") == token) { "Legacy push migration failed" }
        }
        // Remove only the obsolete credential keys, after verified encryption.
        check(legacy.edit().remove("provider").remove("token").commit()) {
            "Legacy push cleanup failed"
        }
    }

    private fun writeUnlocked(namespace: String, provider: String, token: String) {
        require(provider.isNotBlank() && provider.length <= 128)
        require(token.isNotBlank() && token.length <= 8192)
        val key = key(namespace) ?: KeyGenerator.getInstance("AES", "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(alias(namespace), KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build())
            generateKey()
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(namespace.toByteArray(Charsets.UTF_8))
        val clear = JSONObject().put("provider", provider).put("token", token).toString().toByteArray(Charsets.UTF_8)
        val encrypted = try { cipher.doFinal(clear) } finally { clear.fill(0) }
        val record = JSONObject().put("version", 1)
            .put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .put("ciphertext", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .toString().toByteArray(Charsets.UTF_8)
        check(directory.isDirectory || directory.mkdirs()) { "Push storage unavailable" }
        val file = atomicFile(namespace)
        val output = file.startWrite()
        try {
            output.write(record)
            file.finishWrite(output)
        } catch (error: Exception) {
            file.failWrite(output)
            throw error
        }
    }

    private fun readUnlocked(namespace: String): Map<String, String>? {
        return try {
            val file = atomicFile(namespace)
            if (!file.baseFile.isFile || file.baseFile.length() > 65536) return null
            val key = key(namespace) ?: return null // Never recreate a lost key on read.
            val record = JSONObject(String(file.readFully(), Charsets.UTF_8))
            if (record.optInt("version") != 1) return null
            val iv = Base64.decode(record.getString("iv"), Base64.NO_WRAP)
            if (iv.size != 12) return null
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
            cipher.updateAAD(namespace.toByteArray(Charsets.UTF_8))
            val clear = cipher.doFinal(Base64.decode(record.getString("ciphertext"), Base64.NO_WRAP))
            try {
                val payload = JSONObject(String(clear, Charsets.UTF_8))
                val provider = payload.getString("provider")
                val token = payload.getString("token")
                if (provider.isBlank() || provider.length > 128 || token.isBlank() || token.length > 8192) return null
                mapOf("platform" to "android", "provider" to provider, "token" to token, "storageNamespace" to namespace)
            } finally { clear.fill(0) }
        } catch (_: Exception) {
            // Corrupt or restored-without-key data cannot fall back to plaintext.
            null
        }
    }

    private fun key(namespace: String): SecretKey? = KeyStore.getInstance("AndroidKeyStore").run {
        load(null)
        getKey(alias(namespace), null) as? SecretKey
    }

    private fun alias(namespace: String) = "$storageName.$namespace"
    private fun atomicFile(namespace: String) = AtomicFile(File(directory, "$namespace.json"))
    private fun validateNamespace(namespace: String) { require(VALID_NAME.matches(namespace)) }

    companion object {
        private val LOCK = Any()
        private val VALID_NAME = Regex("^[a-zA-Z0-9_-]{1,96}$")
        private const val LEGACY_QUARANTINE = "legacy-unscoped"
    }
}
