package com.taplens.app

import android.app.Activity
import android.os.Bundle

/**
 * Reserved entry point for the isolated :preflight process.
 * Day one intentionally performs no WebView navigation; day three will add the
 * controlled WebView after its blocking policy is implemented.
 */
class PreflightActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        finish()
    }
}
