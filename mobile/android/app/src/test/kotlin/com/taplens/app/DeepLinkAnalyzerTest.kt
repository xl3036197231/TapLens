package com.taplens.app

import org.junit.Assert.assertEquals
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
        val result = DeepLinkAnalyzer.analyze("https://example.test/apply?source=poster")

        assertEquals("url", result.inputType)
        assertEquals("example.test", result.host)
        assertEquals("/apply", result.path)
        assertEquals(listOf("poster"), result.parameters["source"])
    }
}
