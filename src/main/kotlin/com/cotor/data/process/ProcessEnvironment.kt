package com.cotor.data.process

/**
 * Builds child-process environments without inheriting ambient developer secrets.
 *
 * Parent process variables are allowlisted because they are implicit. Explicit
 * per-run variables are preserved unless their names look like secrets, with a
 * narrow exception for the scoped A2A token that Cotor intentionally injects
 * into company run subprocesses.
 */
internal fun sanitizeProcessEnvironment(
    environment: Map<String, String>,
    parentEnvironment: Map<String, String> = System.getenv()
): MutableMap<String, String> {
    val sanitized = linkedMapOf<String, String>()

    parentEnvironment.forEach { (key, value) ->
        if (isValidEnvironmentKey(key) && isAllowedParentEnvironmentKey(key) && !isBlockedProcessEnvironmentKey(key)) {
            sanitized[key] = value
        }
    }

    environment.forEach { (key, value) ->
        if (isValidEnvironmentKey(key) && isAllowedExplicitEnvironmentKey(key)) {
            sanitized[key] = value
        }
    }

    return sanitized
}

internal fun isBlockedProcessEnvironmentKey(key: String): Boolean {
    val normalized = key.trim().uppercase()
    if (normalized in allowedScopedSecretEnvironmentKeys) {
        return false
    }
    if (normalized in blockedProcessEnvironmentKeys) {
        return true
    }
    return blockedProcessEnvironmentFragments.any { normalized.contains(it) }
}

private fun isAllowedExplicitEnvironmentKey(key: String): Boolean =
    !isBlockedProcessEnvironmentKey(key)

private fun isAllowedParentEnvironmentKey(key: String): Boolean {
    val normalized = key.trim().uppercase()
    return normalized in allowedParentEnvironmentKeys ||
        allowedParentEnvironmentPrefixes.any { normalized.startsWith(it) }
}

private fun isValidEnvironmentKey(key: String): Boolean =
    key.isNotBlank() && key.none { it == '=' || it == '\u0000' }

private val allowedParentEnvironmentKeys = setOf(
    "HOME",
    "USER",
    "LOGNAME",
    "SHELL",
    "TMPDIR",
    "TMP",
    "TEMP",
    "LANG",
    "TERM",
    "COLORTERM",
    "NO_COLOR",
    "PATH",
    "JAVA_HOME",
    "CODEX_HOME",
    "COTOR_CODEX_OAUTH_HOME",
    "XDG_CONFIG_HOME",
    "XDG_CACHE_HOME",
    "XDG_DATA_HOME"
)

private val allowedParentEnvironmentPrefixes = setOf(
    "LC_"
)

private val allowedScopedSecretEnvironmentKeys = setOf(
    "COTOR_A2A_TOKEN"
)

private val blockedProcessEnvironmentKeys = setOf(
    "OPENAI_API_KEY",
    "GITHUB_TOKEN",
    "GH_TOKEN",
    "GIT_ASKPASS",
    "LINEAR_API_TOKEN",
    "ANTHROPIC_API_KEY",
    "CLAUDE_CODE_OAUTH_TOKEN",
    "GEMINI_API_KEY",
    "GOOGLE_API_KEY",
    "COTOR_APP_TOKEN",
    "COTOR_APP_CONTROL_TOKEN"
)

private val blockedProcessEnvironmentFragments = setOf(
    "TOKEN",
    "SECRET",
    "PASSWORD",
    "PASSWD",
    "API_KEY",
    "ACCESS_KEY",
    "PRIVATE_KEY",
    "CREDENTIAL"
)
