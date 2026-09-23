package com.taplens.app

import android.app.Activity
import android.os.Bundle
import android.widget.ScrollView
import android.widget.TextView

/** Debug-only native test screen for the three fixed day-one inputs. */
class LocalSafetyTestActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val output = NativeBridge.dayOneSamples.joinToString("\n\n") { input ->
            val parsed = runCatching { DeepLinkAnalyzer.analyze(input).toMap() }
                .getOrElse { mapOf("error" to (it.message ?: "unknown")) }
            "$input\n$parsed"
        }
        setContentView(ScrollView(this).apply {
            addView(TextView(context).apply {
                text = output
                setPadding(32, 32, 32, 32)
                setTextIsSelectable(true)
            })
        })
    }
}
