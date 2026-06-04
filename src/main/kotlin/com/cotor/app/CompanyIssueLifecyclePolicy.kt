package com.cotor.app

import com.cotor.providers.github.CheckSnapshot

/**
 * File overview for CompanyIssueLifecyclePolicy.
 *
 * This file owns pure issue lifecycle decisions that are shared by execution,
 * review, approval, and publish recovery flows. Keep storage mutation and
 * runtime orchestration in DesktopAppService; add status/policy rules here.
 */

internal fun finalTaskStatus(runs: List<AgentRun>): DesktopTaskStatus = when {
    runs.isEmpty() -> DesktopTaskStatus.FAILED
    runs.all { it.status == AgentRunStatus.COMPLETED } -> DesktopTaskStatus.COMPLETED
    runs.any { it.status == AgentRunStatus.COMPLETED } &&
        runs.any { it.status == AgentRunStatus.FAILED } -> DesktopTaskStatus.PARTIAL
    else -> DesktopTaskStatus.FAILED
}

internal fun providerBlockReasonForIssue(
    nextStatus: IssueStatus,
    run: AgentRun?
): String? {
    if (nextStatus != IssueStatus.BLOCKED && nextStatus != IssueStatus.WAITING_FOR_APPROVAL) {
        return null
    }
    return run?.publish?.checksSummary
        ?.takeIf { it.isNotBlank() }
        ?: run?.publish?.error
            ?.takeIf { it.isNotBlank() }
        ?: run?.error
            ?.takeIf { it.isNotBlank() }
}

internal fun issueAttentionSeverity(status: IssueStatus): String =
    if (status == IssueStatus.BLOCKED || status == IssueStatus.WAITING_FOR_APPROVAL) "warning" else "info"

internal fun parseChecks(summary: String?): List<CheckSnapshot> {
    if (summary.isNullOrBlank()) {
        return emptyList()
    }
    return summary.split(';')
        .map { it.trim() }
        .filter { it.isNotBlank() }
        .map { token ->
            val name = token.substringBefore('=').trim()
            val statusPart = token.substringAfter('=', "UNKNOWN").trim()
            val status = statusPart.substringBefore('/').trim()
            val conclusion = statusPart.substringAfter('/', "").trim().ifBlank { null }
            CheckSnapshot(
                name = name,
                status = status,
                conclusion = conclusion
            )
        }
}

internal fun checksFailing(summary: String?): Boolean {
    if (summary.isNullOrBlank()) return false
    val checks = parseChecks(summary)
    return when {
        checks.isNotEmpty() -> checks.any { check ->
            check.status.equals("COMPLETED", ignoreCase = true) &&
                !check.conclusion.equals("SUCCESS", ignoreCase = true)
        }
        else -> summary.contains("FAILURE", ignoreCase = true) ||
            summary.contains("ERROR", ignoreCase = true)
    }
}

internal fun checksExplicitlyPassing(summary: String?): Boolean {
    if (summary.isNullOrBlank()) return false
    val checks = parseChecks(summary)
    return when {
        checks.isNotEmpty() -> checks.all { check ->
            !check.status.equals("COMPLETED", ignoreCase = true) ||
                check.conclusion.equals("SUCCESS", ignoreCase = true)
        }
        else -> !checksFailing(summary)
    }
}

internal fun recoveredReviewQueueStatus(item: ReviewQueueItem): ReviewQueueStatus =
    when {
        item.ceoVerdict.equals("APPROVE", ignoreCase = true) -> ReviewQueueStatus.READY_FOR_CEO
        item.qaVerdict.equals("PASS", ignoreCase = true) -> ReviewQueueStatus.READY_FOR_CEO
        else -> ReviewQueueStatus.AWAITING_QA
    }

internal fun recoveredIssueStatus(issue: CompanyIssue, queueItem: ReviewQueueItem? = null): IssueStatus =
    when {
        issue.ceoVerdict.equals("APPROVE", ignoreCase = true) -> IssueStatus.READY_FOR_CEO
        issue.qaVerdict.equals("PASS", ignoreCase = true) -> IssueStatus.READY_FOR_CEO
        queueItem?.ceoVerdict.equals("APPROVE", ignoreCase = true) -> IssueStatus.READY_FOR_CEO
        queueItem?.qaVerdict.equals("PASS", ignoreCase = true) -> IssueStatus.READY_FOR_CEO
        issue.pullRequestUrl != null || issue.pullRequestNumber != null -> IssueStatus.IN_REVIEW
        else -> issue.status
    }

internal fun requiresGitHubPullRequest(issue: CompanyIssue?, state: DesktopAppState): Boolean {
    if (!requiresCodePublish(issue)) {
        return false
    }
    return when (issue?.requiresPullRequest) {
        false -> false
        true -> true
        null -> {
            if (state.backendSettings.codePublishMode != CodePublishMode.REQUIRE_GITHUB_PR) {
                return false
            }
            val company = issue?.companyId?.let { companyId ->
                state.companies.firstOrNull { it.id == companyId }
            }
            val repository = issue?.let { repositoryForIssue(it, state) }
            if (
                company?.operatorAutomationMode == OperatorAutomationMode.FULL_AUTO &&
                repository?.remoteUrl.isNullOrBlank()
            ) {
                return false
            }
            true
        }
    }
}

internal fun inferIssueRequiresPullRequest(title: String, description: String): Boolean? {
    val text = "$title\n$description".lowercase()
    val disablesRemotePublish = listOf(
        "no external deployment",
        "no external publishing",
        "no github pr",
        "without github pr",
        "do not create a github pr",
        "do not open a github pr",
        "do not perform external publishing",
        "do not push",
        "remote push",
        "원격 push",
        "원격 푸시",
        "외부 배포",
        "github pr",
        "깃허브 pr"
    ).any { marker -> marker in text }
    if (disablesRemotePublish && listOf("하지 말", "금지", "no ", "without", "do not").any { it in text }) {
        return false
    }
    val explicitlyRequiresPr = listOf(
        "open a github pr",
        "create a github pr",
        "github pull request",
        "pull request",
        "pr을",
        "pr를",
        "pr "
    ).any { marker -> marker in text } &&
        listOf("필수", "must", "required", "open", "create").any { marker -> marker in text }
    return if (explicitlyRequiresPr) true else null
}

internal fun isValidationOnlyExecutionFollowUpTitle(title: String): Boolean =
    isValidationOnlyExecutionFollowUpText(title)

internal fun isValidationOnlyExecutionFollowUpText(
    title: String,
    description: String = ""
): Boolean {
    val normalized = listOf(title, description)
        .joinToString("\n")
        .trim()
        .lowercase()
    if (normalized.isBlank()) return false
    val validationSignals = listOf(
        "re-run validation",
        "rerun validation",
        "revalidate",
        "validate",
        "validation",
        "residual risk",
        "summarize any residual risk",
        "summarize any residual risks",
        "capture any residual risk",
        "capture residual risk"
    )
    val implementationSignals = listOf(
        "implement",
        "implementation",
        "fix ",
        "patch",
        "build ",
        "create ",
        "add ",
        "deliver ",
        "ship ",
        "feature",
        "page",
        "screen",
        "endpoint",
        "component"
    )
    return validationSignals.any(normalized::contains) && implementationSignals.none(normalized::contains)
}

internal fun isPrReuseHandoffExecutionText(
    title: String,
    description: String = ""
): Boolean {
    val normalized = listOf(title, description)
        .joinToString("\n")
        .trim()
        .lowercase()
    if (normalized.isBlank()) return false
    val handoffSignals = listOf(
        "hand the result back",
        "hand back",
        "report back",
        "summarize what the ceo should decide next",
        "summarize what ceo should decide next",
        "decide next",
        "decision cycle",
        "next decision cycle",
        "another decision cycle",
        "summarize the current pr",
        "report the current pr"
    )
    val implementationSignals = listOf(
        "implement",
        "implementation",
        "fix ",
        "patch",
        "build ",
        "create ",
        "add ",
        "deliver ",
        "ship ",
        "feature",
        "page",
        "screen",
        "endpoint",
        "component"
    )
    return handoffSignals.any(normalized::contains) && implementationSignals.none(normalized::contains)
}

internal fun isMergeConflictRemediationText(
    title: String,
    description: String = ""
): Boolean {
    val normalized = listOf(title, description)
        .joinToString("\n")
        .trim()
        .lowercase()
    if (normalized.isBlank()) return false
    return normalized.contains("merge conflict") ||
        normalized.contains("merges cleanly") ||
        normalized.contains("resolve the conflict") ||
        normalized.contains("resolve conflicts") ||
        normalized.contains("rebase")
}

internal fun inferExecutionIntent(
    kind: String,
    title: String,
    description: String = "",
    plannedCodeProducing: Boolean? = null
): ExecutionIntent? {
    if (!kind.equals("execution", ignoreCase = true)) {
        return null
    }
    return when {
        isMergeConflictRemediationText(title, description) -> ExecutionIntent.MERGE_CONFLICT_REMEDIATION
        isValidationOnlyExecutionFollowUpText(title, description) -> ExecutionIntent.VALIDATION_ONLY
        isPrReuseHandoffExecutionText(title, description) -> ExecutionIntent.PR_REUSE_HANDOFF
        plannedCodeProducing == false -> ExecutionIntent.PR_REUSE_HANDOFF
        else -> ExecutionIntent.CODE_CHANGE
    }
}

internal fun requiresCodePublish(issue: CompanyIssue?): Boolean {
    if (issue == null) return true
    issue.executionIntent?.let { intent ->
        return when (intent) {
            ExecutionIntent.CODE_CHANGE, ExecutionIntent.MERGE_CONFLICT_REMEDIATION -> true
            ExecutionIntent.VALIDATION_ONLY, ExecutionIntent.PR_REUSE_HANDOFF -> false
        }
    }
    if (issue.kind.equals("execution", ignoreCase = true) && isValidationOnlyExecutionFollowUpTitle(issue.title)) {
        return false
    }
    issue.codeProducing?.let { return it }
    return when (issue.kind.lowercase()) {
        "review", "approval", "planning", "infra" -> false
        else -> true
    }
}

private fun repositoryForIssue(issue: CompanyIssue, state: DesktopAppState): ManagedRepository? {
    val workspace = state.workspaces.firstOrNull { it.id == issue.workspaceId } ?: return null
    return state.repositories.firstOrNull { it.id == workspace.repositoryId }
}
