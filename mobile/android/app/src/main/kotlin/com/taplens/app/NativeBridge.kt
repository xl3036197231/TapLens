package com.taplens.app

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object NativeBridge : MethodChannel.MethodCallHandler {
    const val CHANNEL_NAME = "com.taplens.app/local_safety"
    private const val SECURE_STORAGE_CHANNEL = "com.taplens.app/secure_storage"
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
                else -> result.notImplemented()
            }
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
