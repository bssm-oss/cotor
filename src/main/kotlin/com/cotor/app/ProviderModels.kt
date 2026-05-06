package com.cotor.app

import kotlinx.serialization.Serializable

@Serializable
data class ProviderCatalogEntry(
    val id: String,
    val displayName: String,
    val command: String,
    val capabilities: List<CapabilityKey> = emptyList(),
    val noNetworkScan: Boolean = true
)

@Serializable
data class ProviderScanResult(
    val provider: ProviderCatalogEntry,
    val available: Boolean,
    val message: String
)

fun providerCatalog(): List<ProviderCatalogEntry> = listOf(
    ProviderCatalogEntry("codex-cli", "Codex CLI", "codex", listOf(CapabilityKey.SHELL_EXEC, CapabilityKey.EXTERNAL_API_CALL)),
    ProviderCatalogEntry("claude-code", "Claude Code", "claude", listOf(CapabilityKey.SHELL_EXEC, CapabilityKey.EXTERNAL_API_CALL)),
    ProviderCatalogEntry("goose", "Goose", "goose", listOf(CapabilityKey.SHELL_EXEC, CapabilityKey.EXTERNAL_API_CALL)),
    ProviderCatalogEntry("opencode", "OpenCode", "opencode", listOf(CapabilityKey.SHELL_EXEC, CapabilityKey.EXTERNAL_API_CALL)),
    ProviderCatalogEntry("ollama", "Ollama", "ollama", listOf(CapabilityKey.EXTERNAL_API_CALL)),
    ProviderCatalogEntry("lm-studio", "LM Studio CLI", "lms", listOf(CapabilityKey.EXTERNAL_API_CALL)),
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
