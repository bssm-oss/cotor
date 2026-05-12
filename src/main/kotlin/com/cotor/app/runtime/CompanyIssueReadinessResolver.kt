package com.cotor.app.runtime

import com.cotor.app.CompanyIssue
import com.cotor.app.CompanyRuntimeWorkItem
import com.cotor.app.CompanyRuntimeWorkItemStatus
import com.cotor.app.DesktopAppState
import com.cotor.app.IssueStatus
import java.util.UUID

data class CompanyIssueReadinessResolution(
    val issueId: String,
    val workItemStatus: CompanyRuntimeWorkItemStatus,
    val runtimeDisposition: String,
    val blockedByIssueIds: List<String> = emptyList(),
    val reason: String? = null,
    val activeTaskId: String? = null,
    val durableRunId: String? = null
) {
    val canStart: Boolean
        get() = workItemStatus == CompanyRuntimeWorkItemStatus.READY
}

data class CompanyIssueReadinessOverrides(
    val waitingForApproval: Boolean = false,
    val waitingForCi: Boolean = false,
    val quarantined: Boolean = false,
    val recoverable: Boolean = false,
    val retryCooldown: Boolean = false,
    val activeTaskId: String? = null,
    val durableRunId: String? = null,
    val providerReason: String? = null
)

object CompanyIssueReadinessResolver {
    const val RUNNABLE = "RUNNABLE"
    const val RUNNING = "RUNNING"
    const val WAITING_DEPENDENCY = "WAITING_DEPENDENCY"
    const val WAITING_FOR_APPROVAL = "WAITING_FOR_APPROVAL"
    const val WAITING_FOR_CI = "WAITING_FOR_CI"
    const val QUARANTINED = "QUARANTINED"
    const val RECOVERABLE = "RECOVERABLE"
    const val RETRY_COOLDOWN = "RETRY_COOLDOWN"
    const val TERMINAL = "TERMINAL"

    fun resolve(
        issue: CompanyIssue,
        issuesById: Map<String, CompanyIssue>,
        state: DesktopAppState,
        overrides: CompanyIssueReadinessOverrides = CompanyIssueReadinessOverrides()
    ): CompanyIssueReadinessResolution {
        if (issue.status in setOf(IssueStatus.DONE, IssueStatus.CANCELED)) {
            return CompanyIssueReadinessResolution(
                issueId = issue.id,
                workItemStatus = CompanyRuntimeWorkItemStatus.DONE,
                runtimeDisposition = TERMINAL,
                reason = "Issue is ${issue.status.name.lowercase()}."
            )
        }
        overrides.activeTaskId?.let { taskId ->
            return CompanyIssueReadinessResolution(
                issueId = issue.id,
                workItemStatus = CompanyRuntimeWorkItemStatus.RUNNING,
                runtimeDisposition = RUNNING,
                activeTaskId = taskId,
                durableRunId = overrides.durableRunId,
                reason = "Issue has an active task."
            )
        }
        if (overrides.waitingForApproval || issue.status == IssueStatus.WAITING_FOR_APPROVAL) {
            return CompanyIssueReadinessResolution(
                issueId = issue.id,
                workItemStatus = CompanyRuntimeWorkItemStatus.WAITING_APPROVAL,
                runtimeDisposition = WAITING_FOR_APPROVAL,
                durableRunId = overrides.durableRunId,
                reason = overrides.providerReason ?: "Issue is waiting for approval."
            )
        }
        if (overrides.waitingForCi) {
            return CompanyIssueReadinessResolution(
                issueId = issue.id,
                workItemStatus = CompanyRuntimeWorkItemStatus.WAITING_CI,
                runtimeDisposition = WAITING_FOR_CI,
                durableRunId = overrides.durableRunId,
                reason = overrides.providerReason ?: "Issue is waiting for CI."
            )
        }
        if (overrides.quarantined || (issue.status == IssueStatus.BLOCKED && !issue.providerBlockReason.isNullOrBlank())) {
            return CompanyIssueReadinessResolution(
                issueId = issue.id,
                workItemStatus = CompanyRuntimeWorkItemStatus.QUARANTINED,
                runtimeDisposition = QUARANTINED,
                durableRunId = overrides.durableRunId,
                reason = overrides.providerReason ?: issue.providerBlockReason ?: "Issue is blocked."
            )
        }
        if (overrides.recoverable) {
            return CompanyIssueReadinessResolution(
                issueId = issue.id,
                workItemStatus = CompanyRuntimeWorkItemStatus.READY,
                runtimeDisposition = RECOVERABLE,
                durableRunId = overrides.durableRunId,
                reason = overrides.providerReason ?: "Issue can be retried."
            )
        }
        if (overrides.retryCooldown) {
            return CompanyIssueReadinessResolution(
                issueId = issue.id,
                workItemStatus = CompanyRuntimeWorkItemStatus.RETRY_COOLDOWN,
                runtimeDisposition = RETRY_COOLDOWN,
                durableRunId = overrides.durableRunId,
                reason = "Issue is waiting for retry cooldown."
            )
        }

        val unmetDependencies = issue.dependsOn.filter { dependencyId ->
            val dependency = issuesById[dependencyId] ?: return@filter true
            !isDependencySatisfied(issue, dependency, state)
        }
        if (unmetDependencies.isNotEmpty()) {
            return CompanyIssueReadinessResolution(
                issueId = issue.id,
                workItemStatus = CompanyRuntimeWorkItemStatus.WAITING_DEPENDENCY,
                runtimeDisposition = WAITING_DEPENDENCY,
                blockedByIssueIds = unmetDependencies,
                reason = "Waiting for ${unmetDependencies.size} dependency issue(s)."
            )
        }

        return when (issue.status) {
            IssueStatus.BACKLOG,
            IssueStatus.PLANNED,
            IssueStatus.DELEGATED -> CompanyIssueReadinessResolution(
                issueId = issue.id,
                workItemStatus = CompanyRuntimeWorkItemStatus.READY,
                runtimeDisposition = RUNNABLE,
                reason = "All dependencies are satisfied."
            )
            IssueStatus.IN_PROGRESS -> CompanyIssueReadinessResolution(
                issueId = issue.id,
                workItemStatus = CompanyRuntimeWorkItemStatus.READY,
                runtimeDisposition = RUNNABLE,
                reason = "Issue is marked in progress but has no active task; runtime queue can restart it."
            )
            IssueStatus.IN_REVIEW,
            IssueStatus.READY_FOR_CEO -> CompanyIssueReadinessResolution(
                issueId = issue.id,
                workItemStatus = CompanyRuntimeWorkItemStatus.WAITING_APPROVAL,
                runtimeDisposition = WAITING_FOR_APPROVAL,
                reason = "Issue is in review or CEO gate."
            )
            IssueStatus.BLOCKED -> CompanyIssueReadinessResolution(
                issueId = issue.id,
                workItemStatus = CompanyRuntimeWorkItemStatus.QUARANTINED,
                runtimeDisposition = QUARANTINED,
                reason = issue.providerBlockReason ?: issue.transitionReason ?: "Issue is blocked."
            )
            IssueStatus.WAITING_FOR_APPROVAL,
            IssueStatus.DONE,
            IssueStatus.CANCELED -> CompanyIssueReadinessResolution(
                issueId = issue.id,
                workItemStatus = CompanyRuntimeWorkItemStatus.DONE,
                runtimeDisposition = TERMINAL,
                reason = "Issue is terminal."
            )
        }
    }

    fun toWorkItem(
        readiness: CompanyIssueReadinessResolution,
        issue: CompanyIssue,
        previous: CompanyRuntimeWorkItem?,
        now: Long
    ): CompanyRuntimeWorkItem =
        CompanyRuntimeWorkItem(
            id = previous?.id ?: UUID.randomUUID().toString(),
            companyId = issue.companyId,
            goalId = issue.goalId,
            issueId = issue.id,
            status = readiness.workItemStatus,
            blockedByIssueIds = readiness.blockedByIssueIds,
            activeTaskId = readiness.activeTaskId,
            durableRunId = readiness.durableRunId ?: issue.durableRunId,
            reason = readiness.reason,
            createdAt = previous?.createdAt ?: now,
            updatedAt = if (previous.matches(readiness, issue)) previous!!.updatedAt else now
        )

    private fun CompanyRuntimeWorkItem?.matches(readiness: CompanyIssueReadinessResolution, issue: CompanyIssue): Boolean =
        this != null &&
            companyId == issue.companyId &&
            goalId == issue.goalId &&
            issueId == issue.id &&
            status == readiness.workItemStatus &&
            blockedByIssueIds == readiness.blockedByIssueIds &&
            activeTaskId == readiness.activeTaskId &&
            durableRunId == (readiness.durableRunId ?: issue.durableRunId) &&
            reason == readiness.reason

    private fun isDependencySatisfied(
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
            "approval" ->
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
