package com.taplens.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class DeepLinkAnalyzerTest {
    @Test
    fun parsesIntentPackageFallbackAndExtra() {
        val result = DeepLinkAnalyzer.analyze(
            "intent://open/course?id=42#Intent;scheme=taplens-campus;" +
                "package=com.example.fakecampus;" +
                "S.browser_fallback_url=https%3A%2F%2Fsafe.example.test%2Ffallback;" +
                "S.student_id=REDACTED;end",
        )

        assertEquals("intent", result.inputType)
        assertEquals("taplens-campus", result.scheme)
        assertEquals("com.example.fakecampus", result.packageName)
        assertEquals("https://safe.example.test/fallback", result.fallbackUrl)
        assertEquals("REDACTED", result.extras["student_id"])
        assertTrue(result.parameters["id"]!!.contains("42"))
    }

    @Test
    fun parsesHttpsWithoutSideEffects() {
        val result = DeepLinkAnalyzer.analyze(
            "https://example.test/apply?source=poster&source=qr",
        )

        assertEquals("url", result.inputType)
        assertEquals("example.test", result.host)
        assertEquals("/apply", result.path)
        assertEquals(listOf("poster", "qr"), result.parameters["source"])
        assertNull(result.packageName)
    }

    @Test
    fun parsesCustomScheme() {
        val result = DeepLinkAnalyzer.analyze(
            "taplens-campus://lecture/register?student_id=REDACTED",
        )

        assertEquals("deep_link", result.inputType)
        assertEquals("taplens-campus", result.scheme)
        assertEquals("lecture", result.host)
        assertEquals("/register", result.path)
        assertEquals(listOf("REDACTED"), result.parameters["student_id"])
    }

    @Test
    fun rejectsMissingScheme() {
        assertThrows(IllegalArgumentException::class.java) {
            DeepLinkAnalyzer.analyze("example.test/no-scheme")
        }
    }

    @Test
    fun rejectsControlCharacters() {
        assertThrows(IllegalArgumentException::class.java) {
            DeepLinkAnalyzer.analyze("https://example.test/\u0000hidden")
        }
    }

    @Test
    fun rejectsQrPayloadsThatWouldTriggerSystemActions() {
        val unsupportedPayloads = listOf(
            "WIFI:T:WPA;S:TapLens-Test;P:not-a-real-password;;",
            "SMSTO:+10000000000:TapLens test message",
            "tel:+10000000000",
            "mailto:test@example.test?subject=TapLens",
            "BEGIN:VCARD",
            "MECARD:N:Example;TEL:+10000000000;;",
            "market://details?id=com.example.fakecampus",
            "intent://call#Intent;scheme=tel;end",
        )

        unsupportedPayloads.forEach { payload ->
            assertThrows("Expected rejection for $payload", IllegalArgumentException::class.java) {
                DeepLinkAnalyzer.analyze(payload)
            }
        }
    }
}
