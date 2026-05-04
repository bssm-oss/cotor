package com.cotor.app

import kotlinx.serialization.Serializable

@Serializable
data class SkillCatalogEntry(
    val name: String,
    val displayName: String,
    val description: String,
    val requiredCapabilities: List<CapabilityKey> = listOf(CapabilityKey.SKILL_RUN),
    val localOnly: Boolean = true,
    val dangerous: Boolean = true
)

@Serializable
data class SkillValidationRequest(
    val path: String
)

@Serializable
data class SkillValidationResult(
    val valid: Boolean,
    val name: String? = null,
    val displayName: String? = null,
    val description: String? = null,
    val errors: List<String> = emptyList()
)

@Serializable
data class SkillRunRequest(
    val companyId: String,
    val agentId: String,
    val input: String? = null
)

@Serializable
data class SkillRunResult(
    val skill: String,
    val status: String,
    val capability: CapabilitySimulationResult,
    val output: String? = null,
    val error: String? = null
)

fun skillCatalog(): List<SkillCatalogEntry> = listOf(
    SkillCatalogEntry(
        name = "graphify",
        displayName = "Graphify",
        description = "Query and explain repository graph structure from graphify-out artifacts.",
        requiredCapabilities = listOf(CapabilityKey.SKILL_RUN, CapabilityKey.KNOWLEDGE_GRAPH_READ),
        dangerous = false
    ),
    SkillCatalogEntry(
        name = "browser-smoke",
        displayName = "Browser Smoke",
        description = "Plan a local-first Playwright smoke check with screenshot or trace evidence.",
        requiredCapabilities = listOf(CapabilityKey.SKILL_RUN, CapabilityKey.BROWSER_READ, CapabilityKey.BROWSER_SCREENSHOT)
    ),
    SkillCatalogEntry(
        name = "video-plan",
        displayName = "Video Plan",
        description = "Plan local Remotion or FFmpeg video work without rendering or uploading by default.",
        requiredCapabilities = listOf(CapabilityKey.SKILL_RUN, CapabilityKey.VIDEO_SCRIPT_WRITE)
    )
)
