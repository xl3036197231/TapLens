package com.taplens.app

import androidx.test.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4

/**
 * Run writeProbe and readProbe in separate connected-test invocations, with an
 * app force-stop between them, to verify the encrypted ledger survives process
 * death. The test uses its own preference file and Keystore alias.
 */
@RunWith(JUnit4::class)
class AiAttemptDurabilityRestartTest {
    @Test
    fun writeProbe() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        SecureKeyStore.clearAiAttemptsIn(context, storageName)
        SecureKeyStore.saveAiAttemptsIn(context, ledgerJson, storageName, keyAlias)

        assertEquals(
            ledgerJson,
            SecureKeyStore.readAiAttemptsIn(context, storageName, keyAlias),
        )
    }

    @Test
    fun readProbeAfterProcessRestart() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals(
            ledgerJson,
            SecureKeyStore.readAiAttemptsIn(context, storageName, keyAlias),
        )
        SecureKeyStore.clearAiAttemptsIn(context, storageName)
    }

    private companion object {
        const val storageName = "taplens_day9_durability_test"
        const val keyAlias = "taplens.day9.test.attempts"
        const val ledgerJson =
            "[{\"analysis_id\":\"d52e9205-50bf-4e52-8c8d-3a4a701be4bb\"," +
                "\"created_at\":\"2026-10-07T00:00:00.000000Z\"," +
                "\"owner_id\":\"day9-device-probe\",\"state\":\"requestStarted\"," +
                "\"updated_at\":\"2026-10-07T00:00:00.000000Z\"}]"
    }
}
