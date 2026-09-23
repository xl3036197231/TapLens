package com.taplens.app

import android.app.Activity
import android.os.Bundle
import android.widget.ScrollView
import android.widget.TextView

/** Debug-only native test screen for the three fixed day-one inputs. */
class LocalSafetyTestActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val output = NativeBridge.dayTwoSamples.joinToString("\n\n") { input ->
            val parsed = runCatching {
                LocalEvidenceBuilder.build(
                    analysisId = "6b368c4b-4d97-4a87-bd62-b3d8c2d50001",
                    rawValue = input,
                    processedAt = "2026-09-22T02:00:00Z",
                )
            }.getOrElse {
                LocalEvidenceBuilder.buildFailure(
                    analysisId = "6b368c4b-4d97-4a87-bd62-b3d8c2d50001",
                    processedAt = "2026-09-22T02:00:00Z",
                )
            }
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
