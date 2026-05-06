package com.cotor.app

import com.cotor.runtime.actions.ActionInterceptor
import com.cotor.runtime.actions.ActionInterceptorDecision
import com.cotor.runtime.actions.ActionKind
import com.cotor.runtime.actions.ActionRequest
import java.net.URI
import java.nio.file.Path

class AgentCapabilityGuard(
    private val stateStore: DesktopStateStore = DesktopStateStore()
) : ActionInterceptor {
    override suspend fun before(request: ActionRequest): ActionInterceptorDecision {
        val capability = capabilityFor(request)
        if (request.subject.companyId.isNullOrBlank() || request.subject.agentName.isNullOrBlank()) {
            return if (request.requiresScopedSubject()) {
                ActionInterceptorDecision.deny(
                    "Capability $capability cannot evaluate ${request.kind.wireValue} without company and agent subject metadata."
                )
            } else {
                ActionInterceptorDecision.allow()
            }
        }
        val simulation = simulate(request)
        return when {
            simulation.allowed && simulation.requiresApproval ->
                ActionInterceptorDecision.requireApproval(simulation.reason)
            simulation.allowed -> ActionInterceptorDecision.allow()
            else -> ActionInterceptorDecision.deny(simulation.reason)
        }
    }

    suspend fun simulate(request: ActionRequest): CapabilitySimulationResult {
        val capability = capabilityFor(request)
        val companyId = request.subject.companyId
        val agentName = request.subject.agentName
        val setting = resolveSetting(companyId, agentName, capability)
        val mode = if (!setting.enabled) CapabilityMode.DISABLED else setting.mode
        val scope = listOfNotNull(companyId?.let { "company=$it" }, agentName?.let { "agent=$it" })
            .joinToString(" ")
            .ifBlank { "global" }

        val allowedByAllowlist = allowlistsPermit(setting, request)
        return when {
            !allowedByAllowlist -> CapabilitySimulationResult(
                action = request.kind.wireValue,
                capability = capability,
                mode = mode,
                allowed = false,
                reason = "Capability $capability rejected ${request.kind.wireValue} for $scope because allowlist constraints did not match."
            )
            mode == CapabilityMode.DISABLED -> CapabilitySimulationResult(
                action = request.kind.wireValue,
                capability = capability,
                mode = mode,
                allowed = false,
                reason = "Capability $capability is disabled for $scope."
            )
            mode == CapabilityMode.READ_ONLY && !isReadAction(request.kind) -> CapabilitySimulationResult(
                action = request.kind.wireValue,
                capability = capability,
                mode = mode,
                allowed = false,
                reason = "Capability $capability is read-only and cannot run ${request.kind.wireValue} for $scope."
            )
            mode == CapabilityMode.PROPOSE_ONLY -> CapabilitySimulationResult(
                action = request.kind.wireValue,
                capability = capability,
                mode = mode,
                allowed = true,
                requiresApproval = true,
                reason = "Capability $capability can only propose ${request.kind.wireValue}; approval is required for $scope."
            )
            mode == CapabilityMode.APPROVAL_REQUIRED -> CapabilitySimulationResult(
                action = request.kind.wireValue,
                capability = capability,
                mode = mode,
                allowed = true,
                requiresApproval = !request.hasRecordedApproval(),
                reason = if (request.hasRecordedApproval()) {
                    "Capability $capability uses recorded approval for ${request.kind.wireValue} in $scope."
                } else {
                    "Capability $capability requires approval for ${request.kind.wireValue} in $scope."
                }
            )
            else -> CapabilitySimulationResult(
                action = request.kind.wireValue,
                capability = capability,
                mode = mode,
                allowed = true,
                reason = "Capability $capability allows ${request.kind.wireValue} for $scope."
            )
        }
    }

    private suspend fun resolveSetting(
        companyId: String?,
        agentName: String?,
        capability: CapabilityKey
    ): AgentCapabilitySetting {
        if (companyId.isNullOrBlank() || agentName.isNullOrBlank()) {
            return defaultAgentCapabilitySettings().getValue(capability)
        }
        val state = stateStore.load()
        val definition = state.companyAgentDefinitions.firstOrNull { definition ->
            definition.companyId == companyId &&
                (
                    definition.id.equals(agentName, ignoreCase = true) ||
                        definition.agentCli.equals(agentName, ignoreCase = true) ||
                        definition.title.equals(agentName, ignoreCase = true)
                    )
        }
        val agentId = definition?.id ?: agentName
        val profile = state.agentCapabilityProfiles.firstOrNull { profile ->
            profile.companyId == companyId && profile.agentId == agentId
        }
        return profile?.settings?.get(capability) ?: defaultAgentCapabilitySettings().getValue(capability)
    }

    private fun allowlistsPermit(setting: AgentCapabilitySetting, request: ActionRequest): Boolean {
        if (setting.pathAllowlist.isNotEmpty()) {
            val path = request.path ?: request.metadata["repositoryRoot"] ?: request.metadata["worktreePath"]
            val requestedPath = path?.toNormalizedPathOrNull()
            if (requestedPath == null || setting.pathAllowlist.none { allowlistPath -> requestedPath.isWithin(allowlistPath) }) {
                return false
            }
        }
        if (setting.domainAllowlist.isNotEmpty()) {
            val target = request.networkTarget ?: request.metadata["networkTarget"]
            val host = target?.toHostOrNull()
            if (host == null || setting.domainAllowlist.none { allowlistHost -> host.matchesDomainAllowlist(allowlistHost) }) {
                return false
            }
        }
        if (setting.channelAllowlist.isNotEmpty()) {
            val channel = request.metadata["channel"] ?: request.metadata["marketingChannel"]
            if (channel.isNullOrBlank() || setting.channelAllowlist.none { it.equals(channel.trim(), ignoreCase = true) }) {
                return false
            }
        }
        if (setting.skillAllowlist.isNotEmpty()) {
            val skill = request.metadata["skill"] ?: request.metadata["skillName"]
            if (skill.isNullOrBlank() || setting.skillAllowlist.none { it.equals(skill.trim(), ignoreCase = true) }) {
                return false
            }
        }
        return true
    }

    private fun capabilityFor(request: ActionRequest): CapabilityKey = when (request.kind) {
        ActionKind.SHELL_EXEC -> classifyShellCapability(request.command)
        ActionKind.FILE_WRITE -> CapabilityKey.FILE_WRITE
        ActionKind.HTTP_REQUEST -> CapabilityKey.EXTERNAL_API_CALL
        ActionKind.AGENT_EXEC -> CapabilityKey.SHELL_EXEC
        ActionKind.SKILL_RUN -> CapabilityKey.SKILL_RUN
        ActionKind.BROWSER_READ -> CapabilityKey.BROWSER_READ
        ActionKind.BROWSER_INTERACT -> CapabilityKey.BROWSER_INTERACT
        ActionKind.BROWSER_SCREENSHOT -> CapabilityKey.BROWSER_SCREENSHOT
        ActionKind.BROWSER_TRACE -> CapabilityKey.BROWSER_TRACE
        ActionKind.BROWSER_RECORD -> CapabilityKey.BROWSER_RECORD
        ActionKind.BROWSER_EXTERNAL_DOMAIN -> CapabilityKey.BROWSER_EXTERNAL_DOMAIN
        ActionKind.BROWSER_LOGIN_FLOW -> CapabilityKey.BROWSER_LOGIN_FLOW
        ActionKind.WEB_PUBLISH -> CapabilityKey.WEB_PUBLISH
        ActionKind.SOCIAL_POST_CREATE -> CapabilityKey.SOCIAL_POST_CREATE
        ActionKind.MARKETING_ANALYTICS_READ -> CapabilityKey.MARKETING_ANALYTICS_READ
        ActionKind.VIDEO_SCRIPT_WRITE -> CapabilityKey.VIDEO_SCRIPT_WRITE
        ActionKind.VIDEO_RENDER_LOCAL -> CapabilityKey.VIDEO_RENDER_LOCAL
        ActionKind.VIDEO_GENERATE_REMOTE -> CapabilityKey.VIDEO_GENERATE_REMOTE
        ActionKind.VIDEO_TRANSCODE -> CapabilityKey.VIDEO_TRANSCODE
        ActionKind.VIDEO_UPLOAD -> CapabilityKey.VIDEO_UPLOAD
        ActionKind.GIT_WORKTREE -> CapabilityKey.GIT_WRITE
        ActionKind.GIT_PUBLISH -> CapabilityKey.GITHUB_PR_CREATE
        ActionKind.GITHUB_REVIEW -> CapabilityKey.GITHUB_PR_UPDATE
        ActionKind.GITHUB_COMMENT -> CapabilityKey.GITHUB_PR_UPDATE
        ActionKind.GITHUB_MERGE -> CapabilityKey.GITHUB_MERGE_EXECUTE
        ActionKind.SECRET_READ -> CapabilityKey.EXTERNAL_API_CALL
    }

    private fun classifyShellCapability(command: List<String>): CapabilityKey {
        val text = command.joinToString(" ").lowercase()
        val tokens = text.split(Regex("\\s+")).filter { it.isNotBlank() }
        return when {
            text.contains("npm install") || text.contains("pnpm install") || text.contains("pip install") || text.contains("brew install") -> CapabilityKey.PACKAGE_INSTALL
            text.contains("npm test") || text.contains("gradlew test") || text.contains("swift test") || text.contains("pytest") -> CapabilityKey.TEST_RUN
            text.contains("lint") -> CapabilityKey.LINT_RUN
            text.contains("build") || text.contains("gradlew") || text.contains("swift build") -> CapabilityKey.BUILD_RUN
            tokens.firstOrNull() == "git" -> classifyGitCapability(tokens.drop(1))
            else -> CapabilityKey.SHELL_EXEC
        }
    }

    private fun classifyGitCapability(args: List<String>): CapabilityKey {
        val verb = args.firstOrNull { !it.startsWith("-") } ?: return CapabilityKey.GIT_WRITE
        return when (verb) {
            "status", "diff", "log", "show", "rev-parse", "remote", "describe", "ls-files", "grep", "blame" -> CapabilityKey.GIT_READ
            "branch" -> if (args.any { it == "-d" || it == "-D" || it == "--delete" || it == "--move" || it == "-m" || it == "-M" }) {
                CapabilityKey.GIT_WRITE
            } else {
                CapabilityKey.GIT_READ
            }
            else -> CapabilityKey.GIT_WRITE
        }
    }

    private fun isReadAction(kind: ActionKind): Boolean = when (kind) {
        ActionKind.BROWSER_READ,
        ActionKind.HTTP_REQUEST,
        ActionKind.MARKETING_ANALYTICS_READ,
        ActionKind.SECRET_READ -> true
        else -> false
    }

    private fun ActionRequest.requiresScopedSubject(): Boolean = when (kind) {
        ActionKind.GIT_PUBLISH,
        ActionKind.GITHUB_REVIEW,
        ActionKind.GITHUB_COMMENT,
        ActionKind.GITHUB_MERGE,
        ActionKind.WEB_PUBLISH,
        ActionKind.SOCIAL_POST_CREATE,
        ActionKind.MARKETING_ANALYTICS_READ -> true
        else -> false
    }

    private fun ActionRequest.hasRecordedApproval(): Boolean =
        metadata["approvedBy"]?.isNotBlank() == true || metadata["capabilityApproval"]?.isNotBlank() == true

    private fun String.toNormalizedPathOrNull(): Path? = runCatching {
        Path.of(this).toAbsolutePath().normalize()
    }.getOrNull()

    private fun Path.isWithin(allowlistPath: String): Boolean {
        val allowed = allowlistPath.toNormalizedPathOrNull() ?: return false
        return this == allowed || startsWith(allowed)
    }

    private fun String.toHostOrNull(): String? = runCatching {
        val raw = trim()
        val uri = if (raw.contains("://")) URI(raw) else URI("scheme://$raw")
        uri.host?.trim('[', ']')?.lowercase()?.takeIf { it.isNotBlank() }
    }.getOrNull()

    private fun String.matchesDomainAllowlist(allowlistHost: String): Boolean {
        val allowed = allowlistHost.toHostOrNull() ?: return false
        return this == allowed || endsWith(".$allowed")
    }
}
