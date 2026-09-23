package com.taplens.app

import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets

/**
 * Day-one, side-effect-free parser for web URLs, custom schemes and intent:// URIs.
 * It never launches the parsed target and does not access app secrets or history.
 */
object DeepLinkAnalyzer {
    private const val INTENT_MARKER = "#Intent;"
    private const val INTENT_END = ";end"
    private const val MAX_INPUT_LENGTH = 4096

    fun analyze(rawValue: String): ParsedTarget {
        val value = rawValue.trim()
        require(value.isNotEmpty()) { "The target must not be blank" }
        require(value.length <= MAX_INPUT_LENGTH) { "The target is too long" }
        require(value.none { it.isISOControl() }) { "The target contains control characters" }
        return if (value.startsWith("intent://", ignoreCase = true)) {
            parseIntentUri(value)
        } else {
            parseUri(value)
        }
    }

    private fun parseUri(value: String): ParsedTarget {
        val uri = runCatching { URI(value) }
            .getOrElse { throw IllegalArgumentException("Malformed URI", it) }
        val scheme = uri.scheme?.lowercase()
            ?: throw IllegalArgumentException("URI scheme is required")
        val kind = if (scheme == "http" || scheme == "https") "url" else "deep_link"

        return ParsedTarget(
            inputType = kind,
            scheme = scheme,
            host = uri.host,
            path = uri.rawPath.orEmpty().ifEmpty { "/" },
            packageName = null,
            fallbackUrl = null,
            parameters = parseQuery(uri.rawQuery),
            extras = emptyMap(),
        )
    }

    private fun parseIntentUri(value: String): ParsedTarget {
        val markerIndex = value.indexOf(INTENT_MARKER, ignoreCase = true)
        require(markerIndex > 0 && value.endsWith(INTENT_END, ignoreCase = true)) {
            "Malformed intent URI"
        }

        val base = value.substring(0, markerIndex)
        val directiveText = value.substring(markerIndex + INTENT_MARKER.length, value.length - INTENT_END.length)
        val directives = directiveText.split(';').filter { it.isNotBlank() }
        var scheme: String? = null
        var packageName: String? = null
        var fallbackUrl: String? = null
        val extras = linkedMapOf<String, String>()

        directives.forEach { directive ->
            when {
                directive.startsWith("scheme=") -> scheme = decode(directive.substringAfter('=').lowercase())
                directive.startsWith("package=") -> packageName = decode(directive.substringAfter('='))
                directive.startsWith("S.browser_fallback_url=") -> {
                    fallbackUrl = decode(directive.substringAfter('='))
                }
                directive.startsWith("S.fallback_url=") -> {
                    fallbackUrl = decode(directive.substringAfter('='))
                }
                directive.length > 2 && directive[1] == '.' && directive.contains('=') -> {
                    val key = directive.substring(2).substringBefore('=')
                    extras[key] = decode(directive.substringAfter('='))
                }
            }
        }

        val resolvedScheme = scheme ?: throw IllegalArgumentException("Intent URI scheme is required")
        require(resolvedScheme.matches(Regex("^[a-z][a-z0-9+.-]*$"))) {
            "Intent URI scheme is invalid"
        }
        val syntheticUri = runCatching {
            URI(resolvedScheme + base.removePrefix("intent"))
        }.getOrElse { throw IllegalArgumentException("Malformed intent target", it) }

        return ParsedTarget(
            inputType = "intent",
            scheme = resolvedScheme,
            host = syntheticUri.host,
            path = syntheticUri.rawPath.orEmpty().ifEmpty { "/" },
            packageName = packageName,
            fallbackUrl = fallbackUrl,
            parameters = parseQuery(syntheticUri.rawQuery),
            extras = extras,
        )
    }

    private fun parseQuery(rawQuery: String?): Map<String, List<String>> {
        if (rawQuery.isNullOrBlank()) return emptyMap()
        val result = linkedMapOf<String, MutableList<String>>()
        rawQuery.split('&').filter { it.isNotEmpty() }.forEach { pair ->
            val key = decode(pair.substringBefore('='))
            val value = if (pair.contains('=')) decode(pair.substringAfter('=')) else ""
            result.getOrPut(key) { mutableListOf() }.add(value)
        }
        return result
    }

    private fun decode(value: String): String =
        URLDecoder.decode(value, StandardCharsets.UTF_8.name())
}

data class ParsedTarget(
    val inputType: String,
    val scheme: String,
    val host: String?,
    val path: String,
    val packageName: String?,
    val fallbackUrl: String?,
    val parameters: Map<String, List<String>>,
    val extras: Map<String, String>,
) {
    fun toMap(expectedPackageName: String? = null): Map<String, Any?> = mapOf(
        "input_type" to inputType,
        "scheme" to scheme,
        "host" to host,
        "path" to path,
        "package_name" to packageName,
        "fallback_url" to fallbackUrl,
        "parameters" to parameters,
        "extras" to extras,
        "candidate_apps" to emptyList<Map<String, Any?>>(),
        "expected_package_name" to expectedPackageName,
    )
}
