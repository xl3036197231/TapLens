package com.taplens.app

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object NativeBridge : MethodChannel.MethodCallHandler {
    const val CHANNEL_NAME = "com.taplens.app/local_safety"

    val dayOneSamples = listOf(
        "https://scholarship.example.test/apply?source=poster",
        "taplens-campus://lecture/register?student_id=REDACTED",
        "intent://open/course?id=42#Intent;scheme=taplens-campus;package=com.example.fakecampus;S.browser_fallback_url=https%3A%2F%2Fsafe.example.test%2Ffallback;S.student_id=REDACTED;end",
    )

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "analyzeLink" -> analyzeLink(call, result)
            "getDayOneSamples" -> result.success(dayOneSamples)
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
}
