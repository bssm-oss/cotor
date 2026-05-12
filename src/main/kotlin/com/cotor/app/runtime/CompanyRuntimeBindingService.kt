package com.cotor.app.runtime

import com.cotor.app.CompanyIssue
import com.cotor.app.CompanyRuntimeSnapshot
import com.cotor.app.DesktopAppState
import com.cotor.app.DesktopTaskStatus
import com.cotor.app.ReviewQueueItem
import com.cotor.policy.PolicyEngine
import com.cotor.providers.github.GitHubControlPlaneService
import com.cotor.runtime.actions.ActionStatus
import com.cotor.runtime.actions.ActionStore
import com.cotor.runtime.durable.DurableRunStatus
import com.cotor.runtime.durable.DurableRuntimeService

data class BoundCompanyRuntime(
    val runtime: CompanyRuntimeSnapshot,
    val issues: List<CompanyIssue>,
    val reviewQueue: List<ReviewQueueItem>
)

class CompanyRuntimeBindingService(
    private val durableRuntimeService: DurableRuntimeService = DurableRuntimeService(),
    private val actionStore: ActionStore = ActionStore(),
    private val policyEngine: PolicyEngine = PolicyEngine(),
    private val gitHubControlPlaneService: GitHubControlPlaneService = GitHubControlPlaneService()
) {
    fun bind(state: DesktopAppState, companyId: String, runtime: CompanyRuntimeSnapshot): BoundCompanyRuntime {
        val boundRunIds = state.issues
            .filter { it.companyId == companyId }
            .mapNotNull { it.durableRunId }
            .toSet() + state.reviewQueue
            .filter { it.companyId == companyId }
            .map { it.runId }
            .filter { it.isNotBlank() }
            .toSet()
        val boundPipelineIds = state.issues
            .filter { it.companyId == companyId }
            .mapNotNull { it.pipelineId }
            .filter { it.isNotBlank() }
            .toSet()
        val directRuns = boundRunIds.mapNotNull(durableRuntimeService::inspectRun)
        val runs = if (boundRunIds.isNotEmpty() && directRuns.size == boundRunIds.size) {
            directRuns
        } else {
            (
                directRuns + durableRuntimeService.listRuns().filter { run ->
                    run.runId in boundRunIds ||
                        run.pipelineName in boundPipelineIds ||
                        run.checkpoints.any { node -> node.metadata["companyId"] == companyId } ||
                        run.sideEffects.any { effect -> effect.metadata["companyId"] == companyId }
                }
                ).distinctBy { it.runId }
        }
        val githubPullRequests = gitHubControlPlaneService.listPullRequests(companyId)
        val directActionLogs = boundRunIds.mapNotNull(actionStore::load)
        val actionLogs = if (boundRunIds.isNotEmpty() && directActionLogs.size == boundRunIds.size) {
            directActionLogs
        } else {
            (directActionLogs + actionStore.listSnapshots()).distinctBy { it.runId }
        }

        val resumableRunIds = runs
            .filter { it.status != DurableRunStatus.COMPLETED }
            .map { it.runId }
        val pendingApprovalRunIds = runs
            .filter { it.status == DurableRunStatus.WAITING_FOR_APPROVAL }
            .map { it.runId }
        val blockedByPolicy = actionLogs.sumOf { snapshot ->
            snapshot.records.count { record ->
                record.request.subject.companyId == companyId &&
                    (record.status == ActionStatus.DENIED || record.status == ActionStatus.WAITING_FOR_APPROVAL)
            }
        }
        val blockedByCi = githubPullRequests.count { pullRequest ->
            val stateValue = pullRequest.state?.uppercase()
            stateValue == "OPEN" && (
                pullRequest.checks.any { check ->
                    check.status.equals("COMPLETED", ignoreCase = true) &&
                        !check.conclusion.equals("SUCCESS", ignoreCase = true)
                } || pullRequest.checksSummary?.contains("FAILURE", ignoreCase = true) == true
                )
        }

        val providerBlockByPr = githubPullRequests.associateBy { it.number }
        val providerBlockByIssueId = githubPullRequests
            .filter { !it.issueId.isNullOrBlank() }
            .associateBy { it.issueId!! }
        val issueCompanyById = state.issues.associate { it.id to it.companyId }
        val activeIssueIds = state.tasks
            .filter { it.status == DesktopTaskStatus.RUNNING || it.status == DesktopTaskStatus.QUEUED }
            .mapNotNull { it.issueId }
            .filter { issueCompanyById[it] == companyId }
            .toSet()
        val boundIssues = state.issues.map { issue ->
            if (issue.companyId != companyId) {
                issue
            } else {
                val issuePullRequest = issue.pullRequestNumber?.let(providerBlockByPr::get)
                    ?: providerBlockByIssueId[issue.id]
                val matchingRun = runs.firstOrNull { run ->
                    run.runId == issue.durableRunId || run.pipelineName == issue.pipelineId
                }
                val runtimeDisposition = CompanyIssueReadiness.runtimeDisposition(
                    issue = issue,
                    state = state,
                    pullRequestChecksSummary = issuePullRequest?.checksSummary,
                    matchingRunStatus = matchingRun?.status,
                    hasPendingApprovalPause = matchingRun?.approvalPauses?.any { it.status.name == "PENDING" } == true,
                    hasActiveTask = issue.id in activeIssueIds
                )
                issue.copy(
                    durableRunId = matchingRun?.runId ?: issue.durableRunId,
                    approvalPauseId = matchingRun?.approvalPauses?.firstOrNull { it.status.name == "PENDING" }?.id ?: issue.approvalPauseId,
                    providerBlockReason = issuePullRequest?.takeIf { pr ->
                        pr.checks.any { check ->
                            check.status.equals("COMPLETED", ignoreCase = true) &&
                                !check.conclusion.equals("SUCCESS", ignoreCase = true)
                        } || pr.checksSummary?.contains("FAILURE", ignoreCase = true) == true
                    }?.checksSummary ?: issue.providerBlockReason,
                    runtimeDisposition = runtimeDisposition
                )
            }
        }
        val boundQueue = state.reviewQueue.map { item ->
            if (item.companyId != companyId) {
                item
            } else {
                val snapshot = item.pullRequestNumber?.let(providerBlockByPr::get)
                val runtimeDisposition = when {
                    item.approvalPauseId != null -> CompanyIssueReadiness.WAITING_FOR_APPROVAL
                    snapshot?.checksSummary?.contains("FAILURE", ignoreCase = true) == true -> CompanyIssueReadiness.WAITING_FOR_CI
                    item.status == com.cotor.app.ReviewQueueStatus.FAILED_CHECKS -> CompanyIssueReadiness.RECOVERABLE
                    item.status in setOf(
                        com.cotor.app.ReviewQueueStatus.AWAITING_QA,
                        com.cotor.app.ReviewQueueStatus.READY_FOR_CEO,
                        com.cotor.app.ReviewQueueStatus.READY_TO_MERGE
                    ) -> CompanyIssueReadiness.RUNNABLE
                    item.status == com.cotor.app.ReviewQueueStatus.MERGED -> CompanyIssueReadiness.TERMINAL
                    else -> CompanyIssueReadiness.TERMINAL
                }
                item.copy(
                    approvalPauseId = boundIssues.firstOrNull { it.id == item.issueId }?.approvalPauseId ?: item.approvalPauseId,
                    providerBlockReason = snapshot?.checksSummary ?: item.providerBlockReason,
                    runtimeDisposition = runtimeDisposition
                )
            }
        }
        val pendingIssueIds = boundIssues.filter { it.runtimeDisposition == CompanyIssueReadiness.RUNNABLE }.map { it.id }
        val pendingApprovalIssueIds = boundIssues
            .filter { it.runtimeDisposition == CompanyIssueReadiness.WAITING_FOR_APPROVAL && it.durableRunId !in pendingApprovalRunIds }
            .map { it.id }
        val blockedIssueIds = boundIssues.filter {
            it.runtimeDisposition in setOf(
                CompanyIssueReadiness.WAITING_FOR_CI,
                CompanyIssueReadiness.WAITING_FOR_DEPENDENCY,
                CompanyIssueReadiness.QUARANTINED
            )
        }.map { it.id }
        val reviewQueueAttentionIds = boundQueue.filter {
            it.runtimeDisposition in setOf(
                CompanyIssueReadiness.WAITING_FOR_APPROVAL,
                CompanyIssueReadiness.WAITING_FOR_CI,
                CompanyIssueReadiness.RECOVERABLE
            )
        }.map { it.id }
        return BoundCompanyRuntime(
            runtime = runtime.copy(
                resumableRunCount = resumableRunIds.size,
                waitingApprovalCount = pendingApprovalRunIds.size + pendingApprovalIssueIds.size,
                blockedByPolicyCount = blockedByPolicy,
                blockedByCiCount = blockedByCi,
                resumableRunIds = resumableRunIds,
                pendingApprovalRunIds = pendingApprovalRunIds,
                pendingIssueIds = pendingIssueIds,
                blockedIssueIds = blockedIssueIds,
                reviewQueueAttentionIds = reviewQueueAttentionIds,
                lastReconciliationAt = System.currentTimeMillis()
            ),
            issues = boundIssues,
            reviewQueue = boundQueue
        )
    }
}
