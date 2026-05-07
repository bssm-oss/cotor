package com.cotor.model

/**
 * Shared OpenCode CLI defaults and compatibility helpers.
 *
 * Keep this aligned with the model the user wants as the default for
 * company-created agents so execution costs stay predictable.
 */
object OpenCodeDefaults {
    const val DEFAULT_MODEL = "opencode/nemotron-3-super-free"
    const val DEEPSEEK_FLASH_MODEL = "opencode-go/deepseek-v4-flash"
    const val LOCAL_OLLAMA_GEMMA_MODEL = "ollama/gemma3:4b"
    const val LOCAL_OLLAMA_EXECUTION_MODE = "local-ollama-opencode"
    const val LOCAL_OLLAMA_BASE_URL = "http://127.0.0.1:11434/v1"

    private val selectableModelPrefixes = listOf(
        "ollama/",
        "opencode/",
        "opencode-go/",
        "deepseek/"
    )

    fun normalizeModel(model: String?): String? {
        val trimmed = model?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return trimmed
    }

    fun isSelectableModel(model: String): Boolean = selectableModelPrefixes.any { prefix ->
        model.startsWith(prefix) && !isForbiddenCloudModel(model)
    }

    fun isLocalOllamaModel(model: String?): Boolean {
        val normalized = normalizeModel(model) ?: return false
        return normalized.startsWith("ollama/") && !isForbiddenCloudModel(normalized)
    }

    fun ollamaTagForOpenCodeModel(model: String): String? =
        normalizeModel(model)
            ?.takeIf(::isLocalOllamaModel)
            ?.removePrefix("ollama/")
            ?.takeIf { it.isNotBlank() }

    fun localOllamaEnvironment(environment: Map<String, String>): Map<String, String> =
        environment + mapOf(
            "OLLAMA_HOST" to "127.0.0.1:11434",
            "OLLAMA_NO_CLOUD" to "1",
            "OLLAMA_API_KEY" to ""
        )

    fun isForbiddenCloudModel(model: String): Boolean {
        val normalized = model.trim().lowercase()
        return normalized.endsWith(":cloud") ||
            normalized.contains("ollama.com") ||
            normalized.contains("remote_host=")
    }
}
