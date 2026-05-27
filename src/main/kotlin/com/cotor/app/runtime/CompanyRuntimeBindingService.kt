package com.cotor.app.runtime

import com.cotor.app.CompanyIssue
import com.cotor.app.CompanyRuntimeSnapshot
import com.cotor.app.CompanyRuntimeWorkItemStatus
import com.cotor.app.DesktopAppState
import com.cotor.app.DesktopTaskStatus
import com.cotor.app.IssueStatus
import com.cotor.app.ReviewQueueItem
import com.cotor.policy.PolicyEngine
import com.cotor.providers.github.GitHubControlPlaneService
import com.cotor.providers.github.PullRequestSnapshot
import com.cotor.runtime.actions.ActionLogSummary
import com.cotor.runtime.actions.ActionStore
import com.cotor.runtime.durable.DurableRunStatus
import com.cotor.runtime.durable.DurableRunSummary
import com.cotor.runtime.durable.DurableRuntimeService
import java.util.concurrent.ConcurrentHashMap

data class BoundCompanyRuntime(
    val runtime: CompanyRuntimeSnapshot,
    val issues: List<CompanyIssue>,
    val reviewQueue: List<ReviewQueueItem>
)

class CompanyRuntimeBindingService(
    private val durableRuntimeService: DurableRuntimeService = DurableRuntimeService(),
    private val actionStore: ActionStore = ActionStore(),
    private val policyEngine: PolicyEngine = PolicyEngine(),
    private val gitHubControlPlaneService: GitHubControlPlaneService = GitHubControlPlaneService(),
    private val cacheTtlMs: Long = 5_000L,
    private val nowProvider: () -> Long = { System.currentTimeMillis() }
) {
    private data class CachedValue<T>(val value: T, val storedAt: Long)

    private val durableRunSummaryCache = ConcurrentHashMap<String, CachedValue<List<DurableRunSummary>>>()
    private val actionSummaryCache = ConcurrentHashMap<String, CachedValue<List<ActionLogSummary>>>()
    private val githubPullRequestCache = ConcurrentHashMap<String, CachedValue<List<PullRequestSnapshot>>>()

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
        val directRunsById = directRuns.associateBy { it.runId }
        val runs = if (boundRunIds.isNotEmpty() && directRuns.size == boundRunIds.size) {
            directRuns
        } else {
            (
                directRuns + cachedRunSummaries(companyId).filter { summary ->
                    summary.runId in boundRunIds ||
                        summary.pipelineName in boundPipelineIds ||
                        companyId in summary.companyIds
                }.mapNotNull { summary ->
                    directRunsById[summary.runId] ?: durableRuntimeService.inspectRun(summary.runId)
                }
                ).distinctBy { it.runId }
        }
        val githubPullRequests = cachedGithubPullRequests(companyId)
        val actionSummaries = cachedActionSummaries(companyId)

        val resumableRunIds = runs
            .filter { it.status != DurableRunStatus.COMPLETED }
            .map { it.runId }
        val pendingApprovalRunIds = runs
            .filter { it.status == DurableRunStatus.WAITING_FOR_APPROVAL }
            .map { it.runId }
        val blockedByPolicy = actionSummaries.sumOf { summary -> summary.blockedByCompany[companyId] ?: 0 }
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
        val workItemsByIssueId = state.companyRuntimeWorkItems
            .filter { it.companyId == companyId }
            .associateBy { it.issueId }
        val issueCompanyById = state.issues.associate { it.id to it.companyId }
        val activeIssueIds = state.tasks
            .filter { it.status == DesktopTaskStatus.RUNNING || it.status == DesktopTaskStatus.QUEUED }
            .mapNotNull { it.issueId }
            .filter { issueCompanyById[it] == companyId }
            .toSet()
        val activeTaskByIssueId = state.tasks
            .filter { it.status == DesktopTaskStatus.RUNNING || it.status == DesktopTaskStatus.QUEUED }
            .mapNotNull { task ->
                val issueId = task.issueId ?: return@mapNotNull null
                issueId to task.id
            }
            .toMap()
        val boundIssues = state.issues
            .filter { it.companyId == companyId }
            .map { issue ->
                val issuePullRequest = issue.pullRequestNumber?.let(providerBlockByPr::get)
                    ?: providerBlockByIssueId[issue.id]
                val matchingRun = runs.firstOrNull { run ->
                    run.runId == issue.durableRunId || run.pipelineName == issue.pipelineId
                }
                val storedWorkItem = workItemsByIssueId[issue.id]
                val readinessDisposition = CompanyIssueReadiness.runtimeDisposition(
                    issue = issue,
                    state = state,
                    pullRequestChecksSummary = issuePullRequest?.checksSummary,
                    matchingRunStatus = matchingRun?.status,
                    hasPendingApprovalPause = matchingRun?.approvalPauses?.any { it.status.name == "PENDING" } == true,
                    hasActiveTask = issue.id in activeIssueIds
                )
                val runtimeDisposition = when (storedWorkItem?.status) {
                    CompanyRuntimeWorkItemStatus.WAITING_DEPENDENCY -> CompanyIssueReadiness.WAITING_FOR_DEPENDENCY
                    CompanyRuntimeWorkItemStatus.READY -> CompanyIssueReadiness.RUNNABLE
                    CompanyRuntimeWorkItemStatus.RUNNING -> CompanyIssueReadiness.ACTIVE
                    CompanyRuntimeWorkItemStatus.WAITING_APPROVAL -> CompanyIssueReadiness.WAITING_FOR_APPROVAL
                    CompanyRuntimeWorkItemStatus.WAITING_CI -> CompanyIssueReadiness.WAITING_FOR_CI
                    CompanyRuntimeWorkItemStatus.RETRY_COOLDOWN -> CompanyIssueReadiness.RECOVERABLE
                    CompanyRuntimeWorkItemStatus.QUARANTINED -> CompanyIssueReadiness.QUARANTINED
                    CompanyRuntimeWorkItemStatus.DONE -> CompanyIssueReadiness.TERMINAL
                    null -> readinessDisposition
                }
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
        val boundQueue = state.reviewQueue
            .filter { it.companyId == companyId }
            .map { item ->
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
        val pendingIssueIds = boundIssues
            .filter { it.companyId == companyId }
            .filter { it.runtimeDisposition == CompanyIssueReadiness.RUNNABLE }
            .filter { it.status in setOf(IssueStatus.BACKLOG, IssueStatus.PLANNED, IssueStatus.DELEGATED, IssueStatus.IN_PROGRESS) }
            .filterNot { activeTaskByIssueId.containsKey(it.id) }
            .map { it.id }
        val pendingApprovalIssueIds = boundIssues
            .filter { it.companyId == companyId }
            .filter { it.runtimeDisposition == CompanyIssueReadiness.WAITING_FOR_APPROVAL && it.durableRunId !in pendingApprovalRunIds }
            .map { it.id }
        val blockedIssueIds = boundIssues
            .filter { it.companyId == companyId }
            .filter {
                it.runtimeDisposition in setOf(
                    CompanyIssueReadiness.WAITING_FOR_CI,
                    CompanyIssueReadiness.WAITING_FOR_DEPENDENCY,
                    CompanyIssueReadiness.QUARANTINED
                )
            }.map { it.id }
        val reviewQueueAttentionIds = boundQueue
            .filter { it.companyId == companyId }
            .filter {
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
                lastReconciliationAt = nowProvider()
            ),
            issues = boundIssues,
            reviewQueue = boundQueue
        )
    }

    private fun cachedRunSummaries(companyId: String): List<DurableRunSummary> =
        cached(companyId, durableRunSummaryCache) { durableRuntimeService.listRunSummaries() }

    private fun cachedActionSummaries(companyId: String): List<ActionLogSummary> =
        cached(companyId, actionSummaryCache) { actionStore.listSummaries() }

    private fun cachedGithubPullRequests(companyId: String): List<PullRequestSnapshot> =
        cached(companyId, githubPullRequestCache) { gitHubControlPlaneService.listPullRequests(companyId) }

    private fun <T> cached(
        companyId: String,
        cache: ConcurrentHashMap<String, CachedValue<List<T>>>,
        loader: () -> List<T>
    ): List<T> {
        val now = nowProvider()
        cache[companyId]?.takeIf { now - it.storedAt <= cacheTtlMs }?.let { return it.value }
        val loaded = loader()
        cache[companyId] = CachedValue(loaded, now)
        return loaded
    }
}
