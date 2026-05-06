package com.cotor.app

import kotlinx.serialization.Serializable

@Serializable
enum class CapabilityKey {
    FILE_READ,
    FILE_WRITE,
    FILE_DELETE,
    SHELL_READ,
    SHELL_EXEC,
    PACKAGE_INSTALL,
    GIT_READ,
    GIT_WRITE,
    GITHUB_READ,
    GITHUB_PR_CREATE,
    GITHUB_PR_UPDATE,
    GITHUB_MERGE_PROPOSE,
    GITHUB_MERGE_EXECUTE,
    BROWSER_READ,
    BROWSER_INTERACT,
    BROWSER_SCREENSHOT,
    BROWSER_TRACE,
    BROWSER_RECORD,
    BROWSER_EXTERNAL_DOMAIN,
    BROWSER_LOGIN_FLOW,
    WEB_PUBLISH,
    SOCIAL_POST_CREATE,
    MARKETING_ANALYTICS_READ,
    VIDEO_SCRIPT_WRITE,
    VIDEO_RENDER_LOCAL,
    VIDEO_GENERATE_REMOTE,
    VIDEO_TRANSCODE,
    VIDEO_UPLOAD,
    IMAGE_GENERATE_REMOTE,
    ASSET_DOWNLOAD,
    MEMORY_READ,
    MEMORY_WRITE,
    KNOWLEDGE_INGEST,
    KNOWLEDGE_GRAPH_READ,
    KNOWLEDGE_GRAPH_WRITE,
    SECURITY_SCAN,
    OSV_SCAN,
    TEST_RUN,
    LINT_RUN,
    BUILD_RUN,
    DEPLOY_PROPOSE,
    DEPLOY_EXECUTE,
    SKILL_RUN,
    MCP_READ,
    MCP_CONTROL,
    NOTIFICATION_SEND,
    EXTERNAL_API_CALL
}

@Serializable
enum class CapabilityMode {
    DISABLED,
    READ_ONLY,
    PROPOSE_ONLY,
    APPROVAL_REQUIRED,
    AUTO
}

@Serializable
data class AgentCapabilitySetting(
    val enabled: Boolean = true,
    val mode: CapabilityMode = CapabilityMode.DISABLED,
    val providerId: String? = null,
    val modelOverride: String? = null,
    val costLimitDaily: Int? = null,
    val costLimitMonthly: Int? = null,
    val maxRuntimeSeconds: Int? = null,
    val domainAllowlist: List<String> = emptyList(),
    val channelAllowlist: List<String> = emptyList(),
    val pathAllowlist: List<String> = emptyList(),
    val skillAllowlist: List<String> = emptyList(),
    val secretRefs: List<String> = emptyList(),
    val requiresEvidence: Boolean = true,
    val requiresReview: Boolean = false,
    val notes: String? = null
)

@Serializable
data class AgentCapabilityProfile(
    val companyId: String,
    val agentId: String,
    val settings: Map<CapabilityKey, AgentCapabilitySetting> = defaultAgentCapabilitySettings(),
    val updatedAt: Long = System.currentTimeMillis()
)

@Serializable
data class CapabilityCatalogEntry(
    val key: CapabilityKey,
    val defaultMode: CapabilityMode,
    val description: String,
    val dangerous: Boolean = false,
    val requiresEvidence: Boolean = true,
    val requiresReview: Boolean = false
)

@Serializable
data class CapabilitySimulationRequest(
    val action: String,
    val path: String? = null,
    val networkTarget: String? = null,
    val command: String? = null,
    val skill: String? = null,
    val channel: String? = null
)

@Serializable
data class CapabilitySimulationResult(
    val action: String,
    val capability: CapabilityKey,
    val mode: CapabilityMode,
    val allowed: Boolean,
    val requiresApproval: Boolean = false,
    val reason: String
)

@Serializable
data class UpdateAgentCapabilitiesRequest(
    val settings: Map<CapabilityKey, AgentCapabilitySetting> = emptyMap()
)

fun defaultAgentCapabilitySettings(): Map<CapabilityKey, AgentCapabilitySetting> =
    capabilityCatalog().associate { entry ->
        entry.key to AgentCapabilitySetting(
            enabled = entry.defaultMode != CapabilityMode.DISABLED,
            mode = entry.defaultMode,
            requiresEvidence = entry.requiresEvidence,
            requiresReview = entry.requiresReview
        )
    }

fun capabilityCatalog(): List<CapabilityCatalogEntry> = listOf(
    CapabilityCatalogEntry(CapabilityKey.FILE_READ, CapabilityMode.READ_ONLY, "Read files inside the assigned workspace.", dangerous = false),
    CapabilityCatalogEntry(CapabilityKey.FILE_WRITE, CapabilityMode.APPROVAL_REQUIRED, "Write or modify files.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.FILE_DELETE, CapabilityMode.APPROVAL_REQUIRED, "Delete files or directories.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.SHELL_READ, CapabilityMode.READ_ONLY, "Run read-only shell probes.", dangerous = false),
    CapabilityCatalogEntry(CapabilityKey.SHELL_EXEC, CapabilityMode.APPROVAL_REQUIRED, "Run shell commands with side effects.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.PACKAGE_INSTALL, CapabilityMode.APPROVAL_REQUIRED, "Install packages or mutate dependency state.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.GIT_READ, CapabilityMode.AUTO, "Read local git state.", dangerous = false),
    CapabilityCatalogEntry(CapabilityKey.GIT_WRITE, CapabilityMode.APPROVAL_REQUIRED, "Create branches, worktrees, commits, rebases, or pushes.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.GITHUB_READ, CapabilityMode.READ_ONLY, "Read GitHub metadata.", dangerous = false),
    CapabilityCatalogEntry(CapabilityKey.GITHUB_PR_CREATE, CapabilityMode.APPROVAL_REQUIRED, "Create GitHub pull requests.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.GITHUB_PR_UPDATE, CapabilityMode.APPROVAL_REQUIRED, "Review, comment on, or update GitHub pull requests.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.GITHUB_MERGE_PROPOSE, CapabilityMode.APPROVAL_REQUIRED, "Propose a GitHub merge.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.GITHUB_MERGE_EXECUTE, CapabilityMode.DISABLED, "Execute a GitHub merge.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.BROWSER_READ, CapabilityMode.DISABLED, "Read browser-rendered page state.", dangerous = true),
    CapabilityCatalogEntry(CapabilityKey.BROWSER_INTERACT, CapabilityMode.DISABLED, "Click, type, or submit browser state.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.BROWSER_SCREENSHOT, CapabilityMode.DISABLED, "Capture browser screenshots.", dangerous = true),
    CapabilityCatalogEntry(CapabilityKey.BROWSER_TRACE, CapabilityMode.DISABLED, "Record browser traces.", dangerous = true),
    CapabilityCatalogEntry(CapabilityKey.BROWSER_RECORD, CapabilityMode.DISABLED, "Record browser sessions.", dangerous = true),
    CapabilityCatalogEntry(CapabilityKey.BROWSER_EXTERNAL_DOMAIN, CapabilityMode.DISABLED, "Use a browser against external domains.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.BROWSER_LOGIN_FLOW, CapabilityMode.DISABLED, "Drive login or authenticated browser flows.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.WEB_PUBLISH, CapabilityMode.DISABLED, "Publish owned website or CMS content under a marketing delegation policy.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.SOCIAL_POST_CREATE, CapabilityMode.DISABLED, "Create organic social posts under a marketing delegation policy.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.MARKETING_ANALYTICS_READ, CapabilityMode.DISABLED, "Read marketing analytics for delegated owned or social channels.", dangerous = true),
    CapabilityCatalogEntry(CapabilityKey.VIDEO_SCRIPT_WRITE, CapabilityMode.APPROVAL_REQUIRED, "Write video generation scripts.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.VIDEO_RENDER_LOCAL, CapabilityMode.DISABLED, "Render videos locally.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.VIDEO_GENERATE_REMOTE, CapabilityMode.DISABLED, "Call remote video generation APIs.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.VIDEO_TRANSCODE, CapabilityMode.DISABLED, "Transcode media files.", dangerous = true),
    CapabilityCatalogEntry(CapabilityKey.VIDEO_UPLOAD, CapabilityMode.DISABLED, "Upload rendered videos.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.IMAGE_GENERATE_REMOTE, CapabilityMode.DISABLED, "Call remote image generation APIs.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.ASSET_DOWNLOAD, CapabilityMode.APPROVAL_REQUIRED, "Download external assets.", dangerous = true),
    CapabilityCatalogEntry(CapabilityKey.MEMORY_READ, CapabilityMode.READ_ONLY, "Read company memory.", dangerous = false),
    CapabilityCatalogEntry(CapabilityKey.MEMORY_WRITE, CapabilityMode.APPROVAL_REQUIRED, "Write persistent company memory.", dangerous = true),
    CapabilityCatalogEntry(CapabilityKey.KNOWLEDGE_INGEST, CapabilityMode.APPROVAL_REQUIRED, "Ingest new knowledge records.", dangerous = true),
    CapabilityCatalogEntry(CapabilityKey.KNOWLEDGE_GRAPH_READ, CapabilityMode.READ_ONLY, "Read graphify/context graph data.", dangerous = false),
    CapabilityCatalogEntry(CapabilityKey.KNOWLEDGE_GRAPH_WRITE, CapabilityMode.APPROVAL_REQUIRED, "Regenerate or mutate graphify/context graph data.", dangerous = true),
    CapabilityCatalogEntry(CapabilityKey.SECURITY_SCAN, CapabilityMode.APPROVAL_REQUIRED, "Run local security scans.", dangerous = true),
    CapabilityCatalogEntry(CapabilityKey.OSV_SCAN, CapabilityMode.APPROVAL_REQUIRED, "Run OSV scans.", dangerous = true),
    CapabilityCatalogEntry(CapabilityKey.TEST_RUN, CapabilityMode.AUTO, "Run tests.", dangerous = false),
    CapabilityCatalogEntry(CapabilityKey.LINT_RUN, CapabilityMode.AUTO, "Run linters.", dangerous = false),
    CapabilityCatalogEntry(CapabilityKey.BUILD_RUN, CapabilityMode.AUTO, "Run builds.", dangerous = false),
    CapabilityCatalogEntry(CapabilityKey.DEPLOY_PROPOSE, CapabilityMode.APPROVAL_REQUIRED, "Propose deployment changes.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.DEPLOY_EXECUTE, CapabilityMode.DISABLED, "Execute deployments.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.SKILL_RUN, CapabilityMode.APPROVAL_REQUIRED, "Run installed skill packs.", dangerous = true),
    CapabilityCatalogEntry(CapabilityKey.MCP_READ, CapabilityMode.READ_ONLY, "Read MCP surfaces.", dangerous = false),
    CapabilityCatalogEntry(CapabilityKey.MCP_CONTROL, CapabilityMode.DISABLED, "Call MCP control operations.", dangerous = true, requiresReview = true),
    CapabilityCatalogEntry(CapabilityKey.NOTIFICATION_SEND, CapabilityMode.APPROVAL_REQUIRED, "Send external notifications.", dangerous = true),
    CapabilityCatalogEntry(CapabilityKey.EXTERNAL_API_CALL, CapabilityMode.APPROVAL_REQUIRED, "Call external HTTP APIs.", dangerous = true, requiresReview = true)
)
