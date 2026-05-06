package com.cotor.model

/**
 * Defaults for local OpenAI-compatible and Ollama model servers.
 */
object LocalModelDefaults {
    const val GEMMA4_MODEL = "gemma4:e2b"
    const val OLLAMA_BASE_URL = "http://127.0.0.1:11434"
    const val LM_STUDIO_BASE_URL = "http://127.0.0.1:1234/v1"

    private val gemma4ModelPattern = Regex("""(^|[/_.:-])gemma[-_]?4($|[/_.:-])""", RegexOption.IGNORE_CASE)
    private val gemmaFamilyModelPattern = Regex("""(^|[/_.:-])gemma[0-9]*($|[/_.:-])""", RegexOption.IGNORE_CASE)

    fun normalizeModel(model: String?): String? =
        model?.trim()?.takeIf { it.isNotEmpty() }

    fun normalizeBaseUrl(baseUrl: String?, defaultBaseUrl: String): String =
        baseUrl?.trim()?.trimEnd('/')?.takeIf { it.isNotEmpty() } ?: defaultBaseUrl

    fun isGemma4Model(model: String): Boolean =
        gemma4ModelPattern.containsMatchIn(model.trim())

    fun isGemmaFamilyModel(model: String): Boolean =
        gemmaFamilyModelPattern.containsMatchIn(model.trim())

    fun installedGemma4Models(models: List<String>): List<String> =
        models.mapNotNull(::normalizeModel)
            .filter(::isGemma4Model)
            .distinct()

    fun preferredInstalledGemmaModels(models: List<String>): List<String> {
        val normalized = models.mapNotNull(::normalizeModel).distinct()
        val gemma4Models = normalized.filter(::isGemma4Model)
        val otherGemmaModels = normalized.filter { isGemmaFamilyModel(it) && !isGemma4Model(it) }
        return gemma4Models + otherGemmaModels
    }
}
