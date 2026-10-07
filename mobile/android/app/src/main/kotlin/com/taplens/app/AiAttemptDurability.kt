package com.taplens.app

/**
 * Enforces the write-ahead boundary for school AI requests. The caller must
 * not return success to Dart unless the synchronous storage commit and the
 * decrypted read-back both match the record that will guard the POST.
 */
internal object AiAttemptDurability {
    fun commitAndVerify(
        expected: String,
        commit: () -> Boolean,
        readBack: () -> String?,
    ) {
        check(commit()) { "AI attempt metadata was not durably committed" }
        check(readBack() == expected) { "AI attempt metadata read-back failed" }
    }
}
