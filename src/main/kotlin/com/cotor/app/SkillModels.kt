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
        displayName = "Repository Mapper",
        description = "Read the repository map and explain how important parts of the codebase connect.",
        requiredCapabilities = listOf(CapabilityKey.SKILL_RUN, CapabilityKey.KNOWLEDGE_GRAPH_READ),
        dangerous = false
    ),
    SkillCatalogEntry(
        name = "browser-smoke",
        displayName = "Browser Tester",
        description = "Check an app in a browser and collect screenshot or trace evidence when needed.",
        requiredCapabilities = listOf(CapabilityKey.SKILL_RUN, CapabilityKey.BROWSER_READ, CapabilityKey.BROWSER_SCREENSHOT)
    ),
    SkillCatalogEntry(
        name = "marketing-operator",
        displayName = "Marketing Operator",
        description = "Operate owned web, CMS, and organic social channels inside a delegation policy.",
        requiredCapabilities = listOf(
            CapabilityKey.SKILL_RUN,
            CapabilityKey.BROWSER_READ,
            CapabilityKey.BROWSER_INTERACT,
            CapabilityKey.BROWSER_EXTERNAL_DOMAIN,
            CapabilityKey.BROWSER_LOGIN_FLOW,
            CapabilityKey.WEB_PUBLISH,
            CapabilityKey.SOCIAL_POST_CREATE,
            CapabilityKey.MARKETING_ANALYTICS_READ
        )
    ),
    SkillCatalogEntry(
        name = "audience-scout",
        displayName = "Audience Scout",
        description = "Research owned and organic-channel audience signals without publishing.",
        requiredCapabilities = listOf(CapabilityKey.SKILL_RUN, CapabilityKey.BROWSER_READ, CapabilityKey.MARKETING_ANALYTICS_READ)
    ),
    SkillCatalogEntry(
        name = "content-publisher",
        displayName = "Content Publisher",
        description = "Draft and publish owned web or CMS content through the Marketing Operator policy.",
        requiredCapabilities = listOf(CapabilityKey.SKILL_RUN, CapabilityKey.BROWSER_READ, CapabilityKey.BROWSER_INTERACT, CapabilityKey.WEB_PUBLISH)
    ),
    SkillCatalogEntry(
        name = "social-publisher",
        displayName = "Social Publisher",
        description = "Create organic social posts through delegated channel accounts.",
        requiredCapabilities = listOf(CapabilityKey.SKILL_RUN, CapabilityKey.BROWSER_READ, CapabilityKey.BROWSER_INTERACT, CapabilityKey.SOCIAL_POST_CREATE)
    ),
    SkillCatalogEntry(
        name = "analytics-reporter",
        displayName = "Analytics Reporter",
        description = "Read delegated marketing analytics and summarize channel performance.",
        requiredCapabilities = listOf(CapabilityKey.SKILL_RUN, CapabilityKey.MARKETING_ANALYTICS_READ),
        dangerous = false
    ),
    SkillCatalogEntry(
        name = "video-plan",
        displayName = "Video Builder",
        description = "Plan local video work with Remotion or FFmpeg without rendering or uploading by default.",
        requiredCapabilities = listOf(CapabilityKey.SKILL_RUN, CapabilityKey.VIDEO_SCRIPT_WRITE)
    )
)
