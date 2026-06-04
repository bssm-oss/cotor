package com.cotor.app

import kotlinx.serialization.Serializable

@Serializable
data class ProviderCatalogEntry(
    val id: String,
    val displayName: String,
    val command: String,
    val capabilities: List<CapabilityKey> = emptyList(),
    val aliases: List<String> = emptyList(),
    val noNetworkScan: Boolean = true
)

@Serializable
data class ProviderScanResult(
    val provider: ProviderCatalogEntry,
    val available: Boolean,
    val message: String
)

@Serializable
data class DirectChatProviderCatalogEntry(
    val id: String,
    val providerId: String,
    val displayName: String,
    val iconSystemName: String,
    val defaultModel: String,
    val defaultBaseUrl: String = "",
    val allowsBaseUrl: Boolean = true,
    val supportsModelDiscovery: Boolean = false
)

fun providerCatalog(): List<ProviderCatalogEntry> = listOf(
    ProviderCatalogEntry(
        "codex-cli",
        "Codex CLI",
        "codex",
        listOf(CapabilityKey.SHELL_EXEC, CapabilityKey.EXTERNAL_API_CALL),
        aliases = listOf("codex", "codex-exec", "codex-oauth")
    ),
    ProviderCatalogEntry(
        "claude-code",
        "Claude Code",
        "claude",
        listOf(CapabilityKey.SHELL_EXEC, CapabilityKey.EXTERNAL_API_CALL),
        aliases = listOf("claude")
    ),
    ProviderCatalogEntry("gemini", "Gemini CLI", "gemini", listOf(CapabilityKey.SHELL_EXEC, CapabilityKey.EXTERNAL_API_CALL)),
    ProviderCatalogEntry("copilot", "GitHub Copilot CLI", "copilot", listOf(CapabilityKey.SHELL_EXEC, CapabilityKey.EXTERNAL_API_CALL)),
    ProviderCatalogEntry("cursor", "Cursor CLI", "cursor", listOf(CapabilityKey.SHELL_EXEC, CapabilityKey.EXTERNAL_API_CALL)),
    ProviderCatalogEntry("goose", "Goose", "goose", listOf(CapabilityKey.SHELL_EXEC, CapabilityKey.EXTERNAL_API_CALL)),
    ProviderCatalogEntry("opencode", "OpenCode", "opencode", listOf(CapabilityKey.SHELL_EXEC, CapabilityKey.EXTERNAL_API_CALL)),
    ProviderCatalogEntry("graphify", "Graphify", "graphify", listOf(CapabilityKey.KNOWLEDGE_GRAPH_READ, CapabilityKey.KNOWLEDGE_GRAPH_WRITE)),
    ProviderCatalogEntry("qwen", "Qwen CLI", "qwen", listOf(CapabilityKey.SHELL_EXEC, CapabilityKey.EXTERNAL_API_CALL)),
    ProviderCatalogEntry("ollama", "Ollama", "ollama", listOf(CapabilityKey.EXTERNAL_API_CALL), aliases = listOf("gemma4")),
    ProviderCatalogEntry("lm-studio", "LM Studio CLI", "lms", listOf(CapabilityKey.EXTERNAL_API_CALL), aliases = listOf("lmstudio")),
    ProviderCatalogEntry("gh", "GitHub CLI", "gh", listOf(CapabilityKey.GITHUB_READ, CapabilityKey.GITHUB_PR_CREATE, CapabilityKey.GITHUB_PR_UPDATE)),
    ProviderCatalogEntry("git", "Git", "git", listOf(CapabilityKey.GIT_READ, CapabilityKey.GIT_WRITE)),
    ProviderCatalogEntry(
        "playwright",
        "Playwright",
        "playwright-cli",
        listOf(
            CapabilityKey.BROWSER_READ,
            CapabilityKey.BROWSER_INTERACT,
            CapabilityKey.BROWSER_SCREENSHOT,
            CapabilityKey.BROWSER_EXTERNAL_DOMAIN,
            CapabilityKey.BROWSER_LOGIN_FLOW
        )
    ),
    ProviderCatalogEntry("ffmpeg", "FFmpeg", "ffmpeg", listOf(CapabilityKey.VIDEO_TRANSCODE, CapabilityKey.VIDEO_RENDER_LOCAL)),
    ProviderCatalogEntry("remotion", "Remotion", "remotion", listOf(CapabilityKey.VIDEO_SCRIPT_WRITE, CapabilityKey.VIDEO_RENDER_LOCAL)),
    ProviderCatalogEntry("manim", "Manim", "manim", listOf(CapabilityKey.VIDEO_SCRIPT_WRITE, CapabilityKey.VIDEO_RENDER_LOCAL)),
    ProviderCatalogEntry("osv-scanner", "OSV Scanner", "osv-scanner", listOf(CapabilityKey.OSV_SCAN, CapabilityKey.SECURITY_SCAN)),
    ProviderCatalogEntry("node", "Node.js", "node", listOf(CapabilityKey.BUILD_RUN, CapabilityKey.TEST_RUN)),
    ProviderCatalogEntry("npm", "npm", "npm", listOf(CapabilityKey.PACKAGE_INSTALL, CapabilityKey.TEST_RUN)),
    ProviderCatalogEntry("pnpm", "pnpm", "pnpm", listOf(CapabilityKey.PACKAGE_INSTALL, CapabilityKey.TEST_RUN)),
    ProviderCatalogEntry("bun", "Bun", "bun", listOf(CapabilityKey.PACKAGE_INSTALL, CapabilityKey.TEST_RUN)),
    ProviderCatalogEntry("python", "Python", "python3", listOf(CapabilityKey.TEST_RUN, CapabilityKey.BUILD_RUN)),
    ProviderCatalogEntry("uv", "uv", "uv", listOf(CapabilityKey.PACKAGE_INSTALL, CapabilityKey.TEST_RUN)),
    ProviderCatalogEntry("pip", "pip", "pip", listOf(CapabilityKey.PACKAGE_INSTALL))
)

fun ProviderCatalogEntry.matchesIdOrAlias(providerId: String): Boolean {
    val normalized = providerId.trim()
    if (normalized.isBlank()) return false
    return id.equals(normalized, ignoreCase = true) ||
        aliases.any { it.equals(normalized, ignoreCase = true) }
}

fun findProviderByIdOrAlias(providerId: String): ProviderCatalogEntry? =
    providerCatalog().firstOrNull { it.matchesIdOrAlias(providerId) }

fun directChatProviderCatalog(): List<DirectChatProviderCatalogEntry> = listOf(
    DirectChatProviderCatalogEntry(
        id = "ollama",
        providerId = "ollama",
        displayName = "Ollama (local)",
        iconSystemName = "cpu.fill",
        defaultModel = "gemma3",
        defaultBaseUrl = "http://127.0.0.1:11434",
        allowsBaseUrl = true,
        supportsModelDiscovery = true
    ),
    DirectChatProviderCatalogEntry(
        id = "lmstudio",
        providerId = "lm-studio",
        displayName = "LM Studio (local)",
        iconSystemName = "server.rack",
        defaultModel = "model-name",
        defaultBaseUrl = "http://127.0.0.1:1234",
        allowsBaseUrl = true
    ),
    DirectChatProviderCatalogEntry(
        id = "claude-cli",
        providerId = "claude-code",
        displayName = "Claude CLI",
        iconSystemName = "sparkles",
        defaultModel = "claude",
        allowsBaseUrl = false
    )
)

fun findDirectChatProvider(providerId: String): DirectChatProviderCatalogEntry? {
    val normalized = providerId.trim()
    if (normalized.isBlank()) return null
    return directChatProviderCatalog().firstOrNull { entry ->
        entry.id.equals(normalized, ignoreCase = true) ||
            entry.providerId.equals(normalized, ignoreCase = true) ||
            findProviderByIdOrAlias(entry.providerId)?.matchesIdOrAlias(normalized) == true
    }
}
