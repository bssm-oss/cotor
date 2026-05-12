package com.cotor.app.runtime

import com.cotor.app.CompanyIssue
import com.cotor.app.DesktopAppState
import com.cotor.app.IssueStatus
import com.cotor.runtime.durable.DurableRunStatus

object CompanyIssueReadiness {
    const val RUNNABLE = "RUNNABLE"
    const val ACTIVE = "ACTIVE"
    const val WAITING_FOR_APPROVAL = "WAITING_FOR_APPROVAL"
    const val WAITING_FOR_CI = "WAITING_FOR_CI"
    const val WAITING_FOR_DEPENDENCY = "WAITING_FOR_DEPENDENCY"
    const val QUARANTINED = "QUARANTINED"
    const val RECOVERABLE = "RECOVERABLE"
    const val TERMINAL = "TERMINAL"

    private val startableStatuses = setOf(IssueStatus.BACKLOG, IssueStatus.PLANNED, IssueStatus.DELEGATED)
    private val runtimeActiveStatuses = startableStatuses + IssueStatus.IN_PROGRESS

    fun runtimeDisposition(
        issue: CompanyIssue,
        state: DesktopAppState,
        pullRequestChecksSummary: String?,
        matchingRunStatus: DurableRunStatus?,
        hasPendingApprovalPause: Boolean,
        hasActiveTask: Boolean = false
    ): String = when {
        matchingRunStatus == DurableRunStatus.WAITING_FOR_APPROVAL || hasPendingApprovalPause ->
            WAITING_FOR_APPROVAL
        issue.status == IssueStatus.WAITING_FOR_APPROVAL ->
            WAITING_FOR_APPROVAL
        pullRequestChecksSummary?.contains("FAILURE", ignoreCase = true) == true ->
            WAITING_FOR_CI
        matchingRunStatus == DurableRunStatus.FAILED && issue.status == IssueStatus.BLOCKED ->
            QUARANTINED
        issue.status == IssueStatus.BLOCKED && !issue.providerBlockReason.isNullOrBlank() ->
            QUARANTINED
        issue.status == IssueStatus.BLOCKED &&
            (pullRequestChecksSummary?.contains("SUCCESS", ignoreCase = true) == true) ->
            RECOVERABLE
        issue.status in startableStatuses && !dependenciesSatisfied(issue, state) ->
            WAITING_FOR_DEPENDENCY
        issue.status == IssueStatus.IN_PROGRESS && hasActiveTask ->
            ACTIVE
        issue.status in runtimeActiveStatuses ->
            RUNNABLE
        issue.status in setOf(IssueStatus.DONE, IssueStatus.CANCELED) ->
            TERMINAL
        else ->
            TERMINAL
    }

    fun isRuntimeStartCandidate(issue: CompanyIssue, state: DesktopAppState): Boolean =
        issue.runtimeDisposition == RUNNABLE &&
            issue.status in runtimeActiveStatuses &&
            dependenciesSatisfied(issue, state)

    fun dependenciesSatisfied(issue: CompanyIssue, state: DesktopAppState): Boolean =
        dependencyIds(issue, state).all { dependencyId ->
            val dependency = state.issues.firstOrNull { it.id == dependencyId } ?: return@all false
            isDependencySatisfied(issue, dependency, state)
        }

    private fun dependencyIds(issue: CompanyIssue, state: DesktopAppState): Set<String> =
        (issue.dependsOn + state.issueDependencies
            .filter { it.issueId == issue.id }
            .map { it.dependsOnIssueId })
            .filter { it.isNotBlank() }
            .toSet()

    fun isDependencySatisfied(
        issue: CompanyIssue,
        dependency: CompanyIssue,
        state: DesktopAppState
    ): Boolean {
        if (isSupersededCanceledDependency(dependency, state)) {
            return true
        }
        return when (issue.kind.lowercase()) {
            "review" ->
                dependency.status == IssueStatus.IN_REVIEW ||
                    dependency.status == IssueStatus.READY_FOR_CEO ||
                    dependency.status == IssueStatus.DONE
            else -> dependency.status == IssueStatus.DONE
        }
    }

    private fun isSupersededCanceledDependency(
        dependency: CompanyIssue,
        state: DesktopAppState
    ): Boolean {
        if (dependency.status != IssueStatus.CANCELED) {
            return false
        }
        val latestSuccessfulReplacement = state.issues
            .asSequence()
            .filter { candidate ->
                candidate.companyId == dependency.companyId &&
                    candidate.id != dependency.id &&
                    candidate.status == IssueStatus.DONE &&
                    candidate.kind.equals(dependency.kind, ignoreCase = true) &&
                    candidate.title.trim().equals(dependency.title.trim(), ignoreCase = true)
            }
            .maxOfOrNull { it.updatedAt }
        return latestSuccessfulReplacement != null && latestSuccessfulReplacement > dependency.updatedAt
    }
}
