package com.taplens.app

import android.app.Activity
import android.os.Bundle
import android.widget.ScrollView
import android.widget.TextView

/** Debug-only native test screen for the fixed, side-effect-free local inputs. */
class LocalSafetyTestActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val output = NativeBridge.dayThreeSamples.mapIndexed { index, input ->
            val parsed = runCatching {
                LocalEvidenceBuilder.build(
                    analysisId = "6b368c4b-4d97-4a87-bd62-b3d8c2d5${(index + 1).toString().padStart(4, '0')}",
                    rawValue = input,
                    expectedPackageName = "com.example.officialcampus",
                    processedAt = "2026-09-23T02:00:00Z",
                )
            }.getOrElse {
                LocalEvidenceBuilder.buildFailure(
                    analysisId = "6b368c4b-4d97-4a87-bd62-b3d8c2d5${(index + 1).toString().padStart(4, '0')}",
                    processedAt = "2026-09-23T02:00:00Z",
                )
            }
            "CASE ${index + 1}\n$parsed"
        }.joinToString("\n\n")
        setContentView(ScrollView(this).apply {
            addView(TextView(context).apply {
                text = output
                setPadding(32, 32, 32, 32)
                setTextIsSelectable(true)
            })
        })
    }
}
