package com.taplens.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

object NativeBridge : MethodChannel.MethodCallHandler {
    const val CHANNEL_NAME = "com.taplens.app/local_safety"
    private const val SECURE_STORAGE_CHANNEL = "com.taplens.app/secure_storage"
    private val secureStorageExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "taplens-secure-storage")
    }
    private val mainThreadHandler = Handler(Looper.getMainLooper())
    private lateinit var applicationContext: Context

    val dayOneSamples = listOf(
        "https://scholarship.example.test/apply?source=poster",
        "taplens-campus://lecture/register?student_id=REDACTED",
        "intent://open/course?id=42#Intent;scheme=taplens-campus;package=com.example.fakecampus;S.browser_fallback_url=https%3A%2F%2Fsafe.example.test%2Ffallback;S.student_id=REDACTED;end",
    )
    val dayTwoSamples = dayOneSamples + listOf(
        "intent://broken#Intent;package=com.example.fakecampus;end",
        "example.test/no-scheme",
    )
    val dayThreeSamples = dayTwoSamples + listOf(
        "https://info.example.test/notice",
    )

    fun register(messenger: BinaryMessenger, context: Context) {
        applicationContext = context.applicationContext
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler(this)
        MethodChannel(messenger, SECURE_STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveKey" -> {
                    val value = call.argument<String>("key")
                    if (value.isNullOrBlank()) {
                        result.error("KEY_INVALID", "Key cannot be empty", null)
                    } else {
                        runCatching { SecureKeyStore.save(applicationContext, value) }
                            .onSuccess { result.success(null) }
                            .onFailure { result.error("KEY_STORAGE_ERROR", "Unable to save key", null) }
                    }
                }
                "readKey" -> result.success(SecureKeyStore.read(applicationContext))
                "clearKey" -> {
                    SecureKeyStore.clear(applicationContext)
                    result.success(null)
                }
                "saveSession" -> {
                    val value = call.argument<String>("session")
                    if (value.isNullOrBlank()) {
                        result.error("SESSION_INVALID", "Session cannot be empty", null)
                    } else {
                        runCatching { SecureKeyStore.saveSession(applicationContext, value) }
                            .onSuccess { result.success(null) }
                            .onFailure { result.error("SESSION_STORAGE_ERROR", "Unable to save session", null) }
                    }
                }
                "readSession" -> result.success(SecureKeyStore.readSession(applicationContext))
                "clearSession" -> {
                    SecureKeyStore.clearSession(applicationContext)
                    result.success(null)
                }
                "saveAiAttempts" -> {
                    val value = call.argument<String>("attempts")
                    if (value == null || value.length > 65536) {
                        result.error("AI_ATTEMPTS_INVALID", "AI attempt metadata is invalid", null)
                    } else {
                        saveAiAttempts(value, result)
                    }
                }
                "readAiAttempts" -> {
                    runCatching { SecureKeyStore.readAiAttempts(applicationContext) }
                        .onSuccess(result::success)
                        .onFailure { result.error("AI_ATTEMPTS_STORAGE_ERROR", "Unable to read AI attempt metadata", null) }
                }
                "clearAiAttempts" -> {
                    SecureKeyStore.clearAiAttempts(applicationContext)
                    result.success(null)
                }
                "saveQrAnalysisAttempts" -> {
                    val value = call.argument<String>("attempts")
                    if (value == null || value.length > 65536) {
                        result.error("QR_ATTEMPTS_INVALID", "QR attempt metadata is invalid", null)
                    } else {
                        saveQrAnalysisAttempts(value, result)
                    }
                }
                "readQrAnalysisAttempts" -> {
                    runCatching { SecureKeyStore.readQrAnalysisAttempts(applicationContext) }
                        .onSuccess(result::success)
                        .onFailure { result.error("QR_ATTEMPTS_STORAGE_ERROR", "Unable to read QR attempt metadata", null) }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveAiAttempts(value: String, result: MethodChannel.Result) {
        try {
            secureStorageExecutor.execute {
                val failure = runCatching {
                    SecureKeyStore.saveAiAttempts(applicationContext, value)
                }.exceptionOrNull()
                mainThreadHandler.post {
                    if (failure == null) {
                        result.success(null)
                    } else {
                        result.error(
                            "AI_ATTEMPTS_STORAGE_ERROR",
                            "Unable to durably save AI attempt metadata",
                            null,
                        )
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error(
                "AI_ATTEMPTS_STORAGE_ERROR",
                "Unable to durably save AI attempt metadata",
                null,
            )
        }
    }

    private fun saveQrAnalysisAttempts(value: String, result: MethodChannel.Result) {
        try {
            secureStorageExecutor.execute {
                val failure = runCatching {
                    SecureKeyStore.saveQrAnalysisAttempts(applicationContext, value)
                }.exceptionOrNull()
                mainThreadHandler.post {
                    if (failure == null) {
                        result.success(null)
                    } else {
                        result.error(
                            "QR_ATTEMPTS_STORAGE_ERROR",
                            "Unable to durably save QR attempt metadata",
                            null,
                        )
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error(
                "QR_ATTEMPTS_STORAGE_ERROR",
                "Unable to durably save QR attempt metadata",
                null,
            )
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "analyzeLink" -> analyzeLink(call, result)
            "analyzeLocalEvidence" -> analyzeLocalEvidence(call, result)
            "getDayOneSamples" -> result.success(dayOneSamples)
            "getDayTwoSamples" -> result.success(dayTwoSamples)
            "getDayThreeSamples" -> result.success(dayThreeSamples)
            else -> result.notImplemented()
        }
    }

    private fun analyzeLink(call: MethodCall, result: MethodChannel.Result) {
        val value = call.argument<String>("value")
        if (value.isNullOrBlank()) {
            result.error("DEEPLINK_UNSUPPORTED", "链接为空或缺少 value 字段", null)
            return
        }

        runCatching { DeepLinkAnalyzer.analyze(value).toMap() }
            .onSuccess(result::success)
            .onFailure {
                result.error(
                    "DEEPLINK_UNSUPPORTED",
                    it.message ?: "不支持或无法解析该链接",
                    null,
                )
            }
    }

    private fun analyzeLocalEvidence(call: MethodCall, result: MethodChannel.Result) {
        val analysisId = call.argument<String>("analysis_id")
        val value = call.argument<String>("value")
        val expectedPackageName = call.argument<String>("expected_package_name")
        if (analysisId.isNullOrBlank()) {
            result.error("APP_INPUT_INVALID", "缺少 analysis_id", null)
            return
        }

        val response = runCatching {
            if (value.isNullOrBlank()) {
                LocalEvidenceBuilder.buildFailure(analysisId)
            } else {
                runCatching {
                    LocalEvidenceBuilder.build(analysisId, value, expectedPackageName)
                }.getOrElse {
                    LocalEvidenceBuilder.buildFailure(analysisId)
                }
            }
        }.getOrElse {
            result.error("APP_INPUT_INVALID", "analysis_id 必须是 UUID", null)
            return
        }
        result.success(response)
    }
}
