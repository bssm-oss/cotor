package com.cotor.policy

import com.cotor.runtime.actions.ActionInterceptor
import com.cotor.runtime.actions.ActionInterceptorDecision
import com.cotor.runtime.actions.ActionKind
import com.cotor.runtime.actions.ActionRequest
import kotlinx.serialization.Serializable

@Serializable
data class RiskSignal(
    val key: String,
    val weight: Int,
    val detail: String
)

@Serializable
data class RiskScore(
    val total: Int,
    val signals: List<RiskSignal> = emptyList()
)

@Serializable
data class ApprovalRequirement(
    val required: Boolean,
    val reason: String,
    val score: RiskScore
)

class RiskApprovalInterceptor(
    private val threshold: Int = 80
) : ActionInterceptor {
    override suspend fun before(request: ActionRequest): ActionInterceptorDecision {
        val requirement = evaluate(request)
        return if (requirement.required) {
            ActionInterceptorDecision.requireApproval(requirement.reason)
        } else {
            ActionInterceptorDecision.allow()
        }
    }

    fun evaluate(request: ActionRequest): ApprovalRequirement {
        val signals = mutableListOf<RiskSignal>()
        when (request.kind) {
            ActionKind.GITHUB_MERGE -> {
                val preApprovedReviewFlow = request.metadata["preApprovedReviewFlow"]?.equals("true", ignoreCase = true) == true
                if (!preApprovedReviewFlow) {
                    signals += RiskSignal("github-merge", 90, "Merging a pull request changes repository state permanently.")
                }
            }
            ActionKind.GIT_PUBLISH -> signals += RiskSignal("git-publish", 70, "Publishing a branch or PR affects shared repository state.")
            ActionKind.SHELL_EXEC -> signals += RiskSignal("shell-exec", 40, "Shell execution may mutate local state.")
            ActionKind.SKILL_RUN -> signals += RiskSignal("skill-run", 80, "Running a skill pack can execute bundled automation.")
            ActionKind.BROWSER_INTERACT,
            ActionKind.BROWSER_SCREENSHOT,
            ActionKind.BROWSER_TRACE,
            ActionKind.BROWSER_RECORD,
            ActionKind.BROWSER_EXTERNAL_DOMAIN,
            ActionKind.BROWSER_LOGIN_FLOW -> signals += RiskSignal("browser-automation", 80, "Browser automation can expose private state or mutate remote pages.")
            ActionKind.WEB_PUBLISH -> signals += RiskSignal("web-publish", 90, "Publishing owned web or CMS content mutates an external marketing surface.")
            ActionKind.SOCIAL_POST_CREATE -> signals += RiskSignal("social-post", 90, "Creating social posts mutates an external marketing channel.")
            ActionKind.MARKETING_ANALYTICS_READ -> signals += RiskSignal("marketing-analytics", 45, "Marketing analytics can expose business performance data.")
            ActionKind.VIDEO_GENERATE_REMOTE,
            ActionKind.VIDEO_UPLOAD -> signals += RiskSignal("remote-media", 85, "Remote media generation or upload can spend money or publish artifacts externally.")
            ActionKind.VIDEO_RENDER_LOCAL,
            ActionKind.VIDEO_TRANSCODE -> signals += RiskSignal("local-media", 60, "Local media work can consume significant compute and disk.")
            ActionKind.SECRET_READ -> signals += RiskSignal("secret-read", 95, "Secret access is highly sensitive.")
            else -> Unit
        }
        val commandText = request.command.joinToString(" ").lowercase()
        if (commandText.contains("rm ") || commandText.contains("git push") || commandText.contains("git rebase")) {
            signals += RiskSignal("dangerous-command", 35, "Command includes a destructive or publish-like operation.")
        }
        val path = request.path?.lowercase().orEmpty()
        if (listOf("auth", "secret", "config", "migration").any { path.contains(it) }) {
            signals += RiskSignal("sensitive-path", 35, "Path suggests auth/config/migration-sensitive changes.")
        }
        if (request.networkTarget?.contains("github.com", ignoreCase = true) == true &&
            request.kind in setOf(ActionKind.GITHUB_MERGE, ActionKind.GIT_PUBLISH, ActionKind.GITHUB_REVIEW)
        ) {
            signals += RiskSignal("external-side-effect", 20, "Action mutates external GitHub state.")
        }
        val total = signals.sumOf { it.weight }
        return ApprovalRequirement(
            required = total >= threshold,
            reason = if (total >= threshold) {
                "Risk approval required (score=$total): ${signals.joinToString { it.key }}"
            } else {
                "Risk score $total is below the approval threshold."
            },
            score = RiskScore(total = total, signals = signals)
        )
    }
}
