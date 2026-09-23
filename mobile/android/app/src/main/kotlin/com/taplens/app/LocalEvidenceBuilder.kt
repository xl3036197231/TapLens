package com.taplens.app

import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.util.UUID

/** Builds schema-compatible day-two local evidence without network or app launches. */
object LocalEvidenceBuilder {
    private const val SCHEMA_VERSION = "1.0"
    private const val PARSER_VERSION = "android-static-v1"
    private val sensitiveParameterMarkers = setOf(
        "password",
        "passwd",
        "phone",
        "mobile",
        "email",
        "token",
        "student_id",
        "national_id",
        "identity",
        "身份证",
        "手机号",
        "学号",
    )

    fun build(
        analysisId: String,
        rawValue: String,
        expectedPackageName: String? = null,
        processedAt: String = Instant.now().toString(),
    ): Map<String, Any?> {
        validateAnalysisId(analysisId)
        val parsed = DeepLinkAnalyzer.analyze(rawValue)
        val redactedParameters = parsed.parameters.mapValues { (name, values) ->
            if (isSensitiveParameter(name.lowercase())) values.map { REDACTED_VALUE } else values
        }
        val redactedExtras = parsed.extras.mapValues { (name, value) ->
            if (isSensitiveParameter(name.lowercase())) REDACTED_VALUE else value
        }
        val redactedFallbackUrl = parsed.fallbackUrl?.let(::redactSensitivePairs)
        val redactedDisplayValue = redactDisplayValue(
            rawValue = rawValue,
            fallbackUrl = parsed.fallbackUrl,
            redactedFallbackUrl = redactedFallbackUrl,
        )
        val evidence = mutableListOf<Map<String, Any?>>()

        fun addEvidence(kind: String, title: String, detail: String): String {
            val id = "L%02d".format(evidence.size + 1)
            evidence += mapOf(
                "id" to id,
                "kind" to kind,
                "title" to title,
                "detail" to detail,
            )
            return id
        }

        val targetId = addEvidence(
            kind = if (parsed.inputType == "url") "url" else "deep_link",
            title = "静态目标",
            detail = listOfNotNull(parsed.scheme, parsed.host, parsed.path).joinToString(" "),
        )
        val packageId = parsed.packageName?.let {
            addEvidence("package", "Intent 指定包名", it)
        }
        val fallbackId = redactedFallbackUrl?.let {
            addEvidence("fallback", "失败回退地址", it)
        }
        val parameterId = if (parsed.parameters.isNotEmpty() || parsed.extras.isNotEmpty()) {
            val names = (parsed.parameters.keys + parsed.extras.keys).distinct().sorted()
            addEvidence("parameter", "参数名称", names.joinToString(", "))
        } else {
            null
        }

        val riskHints = mutableListOf<Map<String, Any?>>()
        riskHints += riskHint(
            code = "LOCAL_STATIC_ONLY",
            riskLevel = "insufficient_evidence",
            message = "当前仅完成静态解析，尚未访问网页或执行目标应用。",
            evidenceIds = listOf(targetId),
        )

        if (fallbackId != null) {
            riskHints += riskHint(
                code = "LOCAL_FALLBACK_PRESENT",
                riskLevel = "medium",
                message = "Deep Link 包含失败回退地址，执行目标可能发生变化。",
                evidenceIds = listOf(fallbackId),
            )
        }

        if (expectedPackageName != null) {
            if (parsed.packageName == null) {
                riskHints += riskHint(
                    code = "LOCAL_PACKAGE_UNVERIFIED",
                    riskLevel = "insufficient_evidence",
                    message = "链接没有指定包名，无法确认是否进入预期应用。",
                    evidenceIds = listOf(targetId),
                )
            } else if (parsed.packageName != expectedPackageName) {
                riskHints += riskHint(
                    code = "LOCAL_PACKAGE_MISMATCH",
                    riskLevel = "high",
                    message = "链接指定包名与预期官方包名不一致。",
                    evidenceIds = listOfNotNull(packageId),
                )
            }
        }

        val parameterNames = (parsed.parameters.keys + parsed.extras.keys).map { it.lowercase() }
        if (parameterId != null && parameterNames.any(::isSensitiveParameter)) {
            riskHints += riskHint(
                code = "LOCAL_SENSITIVE_PARAMETER",
                riskLevel = "medium",
                message = "链接参数包含可能的敏感字段。",
                evidenceIds = listOf(parameterId),
            )
        }

        return baseResult(
            analysisId = analysisId,
            processedAt = processedAt,
            processingStatus = "succeeded",
            target = parsed.toMap(expectedPackageName).toMutableMap().apply {
                put("display_value", redactedDisplayValue)
                put("parameters", redactedParameters)
                put("fallback_url", redactedFallbackUrl)
                put("extras", redactedExtras)
            },
            riskHints = riskHints,
            evidence = evidence,
            errors = emptyList(),
        )
    }

    fun buildFailure(
        analysisId: String,
        processedAt: String = Instant.now().toString(),
    ): Map<String, Any?> {
        validateAnalysisId(analysisId)
        val error = mapOf(
            "code" to "DEEPLINK_UNSUPPORTED",
            "message" to "链接为空、缺少协议或格式不受支持",
            "retryable" to false,
            "details" to null,
        )
        return baseResult(
            analysisId = analysisId,
            processedAt = processedAt,
            processingStatus = "failed",
            target = null,
            riskHints = listOf(
                riskHint(
                    code = "LOCAL_PARSE_FAILED",
                    riskLevel = "insufficient_evidence",
                    message = "未获得可用的静态解析证据，不能判断目标是否安全。",
                    evidenceIds = emptyList(),
                ),
            ),
            evidence = emptyList(),
            errors = listOf(error),
        )
    }

    private fun baseResult(
        analysisId: String,
        processedAt: String,
        processingStatus: String,
        target: Map<String, Any?>?,
        riskHints: List<Map<String, Any?>>,
        evidence: List<Map<String, Any?>>,
        errors: List<Map<String, Any?>>,
    ): Map<String, Any?> = mapOf(
        "schema_version" to SCHEMA_VERSION,
        "analysis_id" to analysisId,
        "processed_at" to processedAt,
        "processing_status" to processingStatus,
        "target" to target,
        "observations" to mapOf(
            "launched_external_app" to false,
            "network_accessed" to false,
            "parser_version" to PARSER_VERSION,
        ),
        "preflight" to mapOf(
            "attempted" to false,
            "status" to "not_started",
            "initial_url" to null,
            "final_url" to null,
            "title" to null,
            "forms" to emptyList<Map<String, Any?>>(),
            "external_protocols" to emptyList<String>(),
            "blocked_actions" to emptyList<String>(),
            "screenshot_path" to null,
            "error" to null,
        ),
        "risk_hints" to riskHints,
        "evidence" to evidence,
        "errors" to errors,
    )

    private fun riskHint(
        code: String,
        riskLevel: String,
        message: String,
        evidenceIds: List<String>,
    ): Map<String, Any?> = mapOf(
        "code" to code,
        "risk_level" to riskLevel,
        "message" to message,
        "evidence_ids" to evidenceIds,
    )

    private fun isSensitiveParameter(name: String): Boolean =
        sensitiveParameterMarkers.any { marker -> name.contains(marker) }

    private fun redactDisplayValue(
        rawValue: String,
        fallbackUrl: String?,
        redactedFallbackUrl: String?,
    ): String {
        var result = redactSensitivePairs(rawValue)
        if (fallbackUrl != null && redactedFallbackUrl != null && fallbackUrl != redactedFallbackUrl) {
            result = result.replace(fallbackUrl, redactedFallbackUrl)
            result = result.replace(urlEncode(fallbackUrl), urlEncode(redactedFallbackUrl))
        }
        return result
    }

    private fun redactSensitivePairs(value: String): String =
        SENSITIVE_PAIR.replace(value) { match ->
            val key = runCatching { URLDecoder.decode(match.groupValues[3], StandardCharsets.UTF_8.name()) }
                .getOrDefault(match.groupValues[3])
                .lowercase()
            if (!isSensitiveParameter(key)) {
                match.value
            } else {
                match.groupValues[1] + match.groupValues[2] + match.groupValues[3] + "=" + REDACTED_VALUE
            }
        }

    private fun urlEncode(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8.name())

    private fun validateAnalysisId(analysisId: String) {
        runCatching { UUID.fromString(analysisId) }
            .getOrElse { throw IllegalArgumentException("analysis_id must be a UUID", it) }
    }

    private const val REDACTED_VALUE = "[REDACTED]"
    private val SENSITIVE_PAIR = Regex("""([?&;])([A-Za-z]\.)?([^=&#;]+)=([^&#;]*)""")
}
