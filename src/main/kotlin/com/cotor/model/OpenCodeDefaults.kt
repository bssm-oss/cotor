package com.cotor.model

/**
 * Shared OpenCode CLI defaults and compatibility helpers.
 *
 * Keep this aligned with the model the user wants as the default for
 * company-created agents so execution costs stay predictable.
 */
object OpenCodeDefaults {
    const val DEFAULT_MODEL = "opencode-go/deepseek-v4-flash"

    private val selectableModelPrefixes = listOf(
        "opencode/",
        "opencode-go/",
        "deepseek/"
    )

    fun normalizeModel(model: String?): String? {
        val trimmed = model?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return trimmed
    }

    fun isSelectableModel(model: String): Boolean = selectableModelPrefixes.any { prefix ->
        model.startsWith(prefix)
    }
}
