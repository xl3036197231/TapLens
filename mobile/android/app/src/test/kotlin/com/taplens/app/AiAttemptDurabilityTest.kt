package com.taplens.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test

class AiAttemptDurabilityTest {
    @Test
    fun commitsBeforeReadBackAndAcceptsOnlyMatchingValue() {
        val operations = mutableListOf<String>()
        var stored: String? = null

        AiAttemptDurability.commitAndVerify(
            expected = "encrypted-ledger-value",
            commit = {
                operations += "commit"
                stored = "encrypted-ledger-value"
                true
            },
            readBack = {
                operations += "read-back"
                stored
            },
        )

        assertEquals(listOf("commit", "read-back"), operations)
    }

    @Test
    fun failedCommitStopsBeforeReadBack() {
        var readBackCalled = false

        assertThrows(IllegalStateException::class.java) {
            AiAttemptDurability.commitAndVerify(
                expected = "encrypted-ledger-value",
                commit = { false },
                readBack = {
                    readBackCalled = true
                    "encrypted-ledger-value"
                },
            )
        }

        assertFalse(readBackCalled)
    }

    @Test
    fun mismatchedReadBackFailsClosed() {
        assertThrows(IllegalStateException::class.java) {
            AiAttemptDurability.commitAndVerify(
                expected = "expected-ledger-value",
                commit = { true },
                readBack = { "different-ledger-value" },
            )
        }
    }
}
