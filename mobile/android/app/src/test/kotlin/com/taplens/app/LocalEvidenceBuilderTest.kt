package com.taplens.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalEvidenceBuilderTest {
    private val analysisId = "6b368c4b-4d97-4a87-bd62-b3d8c2d50010"
    private val processedAt = "2026-09-22T04:00:00Z"

    @Test
    fun buildsHttpsEvidenceWithoutSideEffects() {
        val result = LocalEvidenceBuilder.build(
            analysisId = analysisId,
            rawValue = "https://short.example.test/a1b2",
            processedAt = processedAt,
        )

        assertEquals("succeeded", result["processing_status"])
        val target = result.map("target")
        assertEquals("https", target["scheme"])
        assertEquals("short.example.test", target["host"])
        assertEquals("https://short.example.test/a1b2", target["display_value"])
        val observations = result.map("observations")
        assertEquals(false, observations["launched_external_app"])
        assertEquals(false, observations["network_accessed"])
        assertTrue(result.list("evidence").all { (it as Map<*, *>)["id"].toString().startsWith("L") })
    }

    @Test
    fun reportsPackageMismatchFallbackAndSensitiveParameter() {
        val studentId = "2026123456"
        val fallbackToken = "fallback-secret"
        val result = LocalEvidenceBuilder.build(
            analysisId = analysisId,
            rawValue = "intent://open/course?token=query-secret#Intent;scheme=taplens-campus;" +
                "package=com.example.fakecampus;" +
                "S.browser_fallback_url=https%3A%2F%2Fsafe.example.test%2Ffallback%3Ftoken%3D$fallbackToken;" +
                "S.student_id=$studentId;end",
            expectedPackageName = "com.example.officialcampus",
            processedAt = processedAt,
        )

        val hints = result.list("risk_hints").map { it as Map<*, *> }
        val codes = hints.map { it["code"] }
        assertTrue("LOCAL_PACKAGE_MISMATCH" in codes)
        assertTrue("LOCAL_FALLBACK_PRESENT" in codes)
        assertTrue("LOCAL_SENSITIVE_PARAMETER" in codes)
        assertTrue(hints.any { it["risk_level"] == "high" })
        val target = result.map("target")
        assertEquals("com.example.fakecampus", target["package_name"])
        assertEquals("[REDACTED]", (target["extras"] as Map<*, *>)["student_id"])
        assertEquals(listOf("[REDACTED]"), (target["parameters"] as Map<*, *>)["token"])
        assertEquals(
            "https://safe.example.test/fallback?token=[REDACTED]",
            target["fallback_url"],
        )
        val serialized = result.toString()
        assertFalse(serialized.contains(studentId))
        assertFalse(serialized.contains(fallbackToken))
        assertFalse(serialized.contains("query-secret"))
    }

    @Test
    fun keepsSuccessfulStaticResultExplicitlyInsufficient() {
        val result = LocalEvidenceBuilder.build(
            analysisId = analysisId,
            rawValue = "https://info.example.test/notice",
            processedAt = processedAt,
        )

        assertEquals("succeeded", result["processing_status"])
        val hints = result.list("risk_hints").map { it as Map<*, *> }
        assertTrue(hints.any {
            it["code"] == "LOCAL_STATIC_ONLY" && it["risk_level"] == "insufficient_evidence"
        })
        assertEquals("not_started", result.map("preflight")["status"])
        assertEquals(false, result.map("observations")["network_accessed"])
    }

    @Test
    fun buildsSchemaShapedFailure() {
        val result = LocalEvidenceBuilder.buildFailure(
            analysisId = analysisId,
            processedAt = processedAt,
        )

        assertEquals("failed", result["processing_status"])
        assertNull(result["target"])
        assertTrue(result.list("evidence").isEmpty())
        assertFalse(result.list("errors").isEmpty())
        assertEquals("DEEPLINK_UNSUPPORTED", (result.list("errors").first() as Map<*, *>)["code"])
    }

    @Test
    fun rejectsInvalidAnalysisId() {
        assertThrows(IllegalArgumentException::class.java) {
            LocalEvidenceBuilder.build(
                analysisId = "not-a-uuid",
                rawValue = "https://example.test",
                processedAt = processedAt,
            )
        }
    }

    @Test
    fun parsesApkDownloadAsStaticUrlWithoutExecutingIt() {
        val result = LocalEvidenceBuilder.build(
            analysisId = analysisId,
            rawValue = "https://download.example.test/apps/fake-campus.apk",
            processedAt = processedAt,
        )

        assertEquals("succeeded", result["processing_status"])
        assertEquals("url", result.map("target")["input_type"])
        assertEquals(false, result.map("observations")["launched_external_app"])
        assertEquals(false, result.map("observations")["network_accessed"])
        assertEquals("not_started", result.map("preflight")["status"])
    }

    @Suppress("UNCHECKED_CAST")
    private fun Map<String, Any?>.map(key: String): Map<String, Any?> =
        get(key) as Map<String, Any?>

    @Suppress("UNCHECKED_CAST")
    private fun Map<String, Any?>.list(key: String): List<Any?> =
        get(key) as List<Any?>
}
