package com.taplens.app

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Stores the optional user supplied AI key encrypted with an AES key held by
 * Android Keystore. The raw key never enters the backend or logcat.
 */
object SecureKeyStore {
    private const val aiKeyAlias = "taplens.ai.key"
    private const val sessionKeyAlias = "taplens.auth.session"
    private const val aiAttemptsKeyAlias = "taplens.ai.attempts"
    private const val preferencesName = "taplens_secure_storage"
    private const val encryptedValue = "deepseek_api_key"
    private const val encryptedSession = "auth_session"
    private const val encryptedAiAttempts = "ai_attempt_metadata"
    private const val transformation = "AES/GCM/NoPadding"
    private const val keystoreName = "AndroidKeyStore"

    fun save(context: Context, value: String) {
        require(value.isNotBlank()) { "Key cannot be empty" }
        preferences(context).edit()
            .putString(encryptedValue, encrypt(value, aiKeyAlias))
            .apply()
    }

    fun read(context: Context): String? {
        val stored = preferences(context).getString(encryptedValue, null) ?: return null
        return decrypt(stored, aiKeyAlias)
    }

    fun clear(context: Context) {
        preferences(context).edit().remove(encryptedValue).apply()
    }

    fun saveSession(context: Context, value: String) {
        require(value.isNotBlank()) { "Session cannot be empty" }
        preferences(context).edit()
            .putString(encryptedSession, encrypt(value, sessionKeyAlias))
            .apply()
    }

    fun readSession(context: Context): String? {
        val stored = preferences(context).getString(encryptedSession, null) ?: return null
        return decrypt(stored, sessionKeyAlias)
    }

    fun clearSession(context: Context) {
        preferences(context).edit().remove(encryptedSession).apply()
    }

    fun saveAiAttempts(context: Context, value: String) {
        require(value.length <= 65536) { "AI attempt metadata is too large" }
        preferences(context).edit()
            .putString(encryptedAiAttempts, encrypt(value, aiAttemptsKeyAlias))
            .apply()
    }

    fun readAiAttempts(context: Context): String? {
        val stored = preferences(context).getString(encryptedAiAttempts, null) ?: return null
        return decrypt(stored, aiAttemptsKeyAlias)
            ?: throw IllegalStateException("AI attempt metadata cannot be decrypted")
    }

    fun clearAiAttempts(context: Context) {
        preferences(context).edit().remove(encryptedAiAttempts).apply()
    }

    private fun encrypt(value: String, alias: String): String {
        val cipher = Cipher.getInstance(transformation)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey(alias))
        val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
        val ciphertext = Base64.encodeToString(
            cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8)),
            Base64.NO_WRAP,
        )
        return "$iv.$ciphertext"
    }

    private fun decrypt(stored: String, alias: String): String? {
        val parts = stored.split('.', limit = 2)
        if (parts.size != 2) return null
        return runCatching {
            val cipher = Cipher.getInstance(transformation)
            val iv = Base64.decode(parts[0], Base64.NO_WRAP)
            val ciphertext = Base64.decode(parts[1], Base64.NO_WRAP)
            cipher.init(
                Cipher.DECRYPT_MODE,
                getOrCreateKey(alias),
                GCMParameterSpec(128, iv),
            )
            String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8)
        }.getOrNull()
    }

    private fun preferences(context: Context): SharedPreferences =
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)

    private fun getOrCreateKey(alias: String): SecretKey {
        val keyStore = KeyStore.getInstance(keystoreName).apply { load(null) }
        val existing = keyStore.getKey(alias, null)
        if (existing is SecretKey) return existing

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            keystoreName,
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }
}
