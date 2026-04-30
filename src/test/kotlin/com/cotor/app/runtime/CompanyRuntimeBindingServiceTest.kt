package com.cotor.app.runtime

import com.cotor.app.Company
import com.cotor.app.CompanyIssue
import com.cotor.app.CompanyRuntimeSnapshot
import com.cotor.app.CompanyRuntimeStatus
import com.cotor.app.DesktopAppState
import com.cotor.app.ExecutionBackendKind
import com.cotor.app.IssueStatus
import com.cotor.app.ReviewQueueItem
import com.cotor.app.ReviewQueueStatus
import com.cotor.policy.PolicyEngine
import com.cotor.policy.PolicyStore
import com.cotor.providers.github.GitHubControlPlaneService
import com.cotor.providers.github.GitHubControlPlaneStore
import com.cotor.providers.github.PullRequestSnapshot
import com.cotor.runtime.actions.ActionExecutionRecord
import com.cotor.runtime.actions.ActionKind
import com.cotor.runtime.actions.ActionRequest
import com.cotor.runtime.actions.ActionScope
import com.cotor.runtime.actions.ActionStatus
import com.cotor.runtime.actions.ActionStore
import com.cotor.runtime.actions.ActionSubject
import com.cotor.runtime.durable.ApprovalPauseState
import com.cotor.runtime.durable.ApprovalPauseStatus
import com.cotor.runtime.durable.CheckpointNode
import com.cotor.runtime.durable.CheckpointNodeState
import com.cotor.runtime.durable.DurableRunSnapshot
import com.cotor.runtime.durable.DurableRunStatus
import com.cotor.runtime.durable.DurableRuntimeService
import com.cotor.runtime.durable.DurableRuntimeStore
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContain
import io.kotest.matchers.shouldBe
import java.nio.file.Files

class CompanyRuntimeBindingServiceTest : FunSpec({
    test("bind adds resumable and approval state from durable runs and provider snapshots") {
        val appHome = Files.createTempDirectory("company-runtime-binding")
        val runStore = DurableRuntimeStore(appHome.resolve("runtime"))
        val actionStore = ActionStore { appHome }
        val githubStore = GitHubControlPlaneStore { appHome }
        val companyId = "company-1"
        val issueId = "issue-1"
        val runId = "run-1"

        runStore.saveRun(
            DurableRunSnapshot(
                runId = runId,
                pipelineName = "company-execution-run",
                status = DurableRunStatus.WAITING_FOR_APPROVAL,
                createdAt = 1L,
                updatedAt = 2L,
                checkpoints = listOf(
                    CheckpointNode(
                        ordinal = 1,
                        stageId = "company-agent-execution",
                        state = CheckpointNodeState.COMPLETED,
                        createdAt = 1L
                    )
                ),
                approvalPauses = listOf(
                    ApprovalPauseState(
                        id = "pause-1",
                        checkpointId = "checkpoint-1",
                        sideEffectId = "side-effect-1",
                        label = "github.merge:12",
                        status = ApprovalPauseStatus.PENDING,
                        reason = "approval needed",
                        requestedAt = 2L
                    )
                )
            )
        )
        actionStore.append(
            runId,
            ActionExecutionRecord(
                id = "action-1",
                runId = runId,
                request = ActionRequest(
                    kind = ActionKind.GITHUB_MERGE,
                    label = "github.merge:12",
                    scope = ActionScope.COMPANY,
                    subject = ActionSubject(runId = runId, companyId = companyId, issueId = issueId)
                ),
                status = ActionStatus.WAITING_FOR_APPROVAL,
                createdAt = 1L,
                updatedAt = 2L
            )
        )
        GitHubControlPlaneService(
            store = githubStore
        ).recordSnapshot(
            PullRequestSnapshot(
                number = 12,
                state = "OPEN",
                checksSummary = "ci=COMPLETED/FAILURE",
                companyId = companyId,
                issueId = issueId,
                runId = runId
            ),
            eventType = "sync",
            detail = "sync"
        )

        val service = CompanyRuntimeBindingService(
            durableRuntimeService = DurableRuntimeService(runtimeStore = runStore),
            actionStore = actionStore,
            policyEngine = PolicyEngine(PolicyStore { appHome }),
            gitHubControlPlaneService = GitHubControlPlaneService(store = githubStore)
        )
        val bound = service.bind(
            state = DesktopAppState(
                companies = listOf(
                    Company(
                        id = companyId,
                        name = "Test",
                        rootPath = ".",
                        repositoryId = "repo-1",
                        defaultBaseBranch = "main",
                        backendKind = ExecutionBackendKind.LOCAL_COTOR,
                        createdAt = 1L,
                        updatedAt = 1L
                    )
                ),
                issues = listOf(
                    CompanyIssue(
                        id = issueId,
                        companyId = companyId,
                        goalId = "goal-1",
                        workspaceId = "workspace-1",
                        title = "Issue",
                        description = "desc",
                        status = IssueStatus.BLOCKED,
                        durableRunId = runId,
                        createdAt = 1L,
                        updatedAt = 1L
                    )
                ),
                reviewQueue = listOf(
                    ReviewQueueItem(
                        id = "review-1",
                        companyId = companyId,
                        issueId = issueId,
                        runId = runId,
                        pullRequestNumber = 12,
                        status = ReviewQueueStatus.READY_FOR_CEO,
                        createdAt = 1L,
                        updatedAt = 1L
                    )
                )
            ),
            companyId = companyId,
            runtime = CompanyRuntimeSnapshot(companyId = companyId, status = CompanyRuntimeStatus.RUNNING)
        )

        bound.runtime.resumableRunCount shouldBe 1
        bound.runtime.waitingApprovalCount shouldBe 1
        bound.runtime.blockedByPolicyCount shouldBe 1
        bound.runtime.blockedByCiCount shouldBe 1
        bound.issues.single().approvalPauseId shouldBe "pause-1"
        bound.issues.single().providerBlockReason shouldBe "ci=COMPLETED/FAILURE"
        bound.reviewQueue.single().providerBlockReason shouldBe "ci=COMPLETED/FAILURE"
    }

    test("bind keeps provider-blocked execution failures in blocked runtime attention without durable snapshots") {
        val appHome = Files.createTempDirectory("company-runtime-provider-blocked")
        val companyId = "company-provider-blocked"
        val issueId = "issue-provider-blocked"
        val service = CompanyRuntimeBindingService(
            durableRuntimeService = DurableRuntimeService(runtimeStore = DurableRuntimeStore(appHome.resolve("runtime"))),
            actionStore = ActionStore { appHome },
            policyEngine = PolicyEngine(PolicyStore { appHome }),
            gitHubControlPlaneService = GitHubControlPlaneService(store = GitHubControlPlaneStore { appHome })
        )

        val bound = service.bind(
            state = DesktopAppState(
                companies = listOf(
                    Company(
                        id = companyId,
                        name = "Provider Blocked",
                        rootPath = ".",
                        repositoryId = "repo-provider-blocked",
                        defaultBaseBranch = "main",
                        backendKind = ExecutionBackendKind.LOCAL_COTOR,
                        createdAt = 1L,
                        updatedAt = 1L
                    )
                ),
                issues = listOf(
                    CompanyIssue(
                        id = issueId,
                        companyId = companyId,
                        goalId = "goal-provider-blocked",
                        workspaceId = "workspace-provider-blocked",
                        title = "Provider failed issue",
                        description = "desc",
                        status = IssueStatus.BLOCKED,
                        durableRunId = "missing-run",
                        providerBlockReason = "OpenCode execution failed (exit=0): \"Provider returned error\"",
                        createdAt = 1L,
                        updatedAt = 1L
                    )
                )
            ),
            companyId = companyId,
            runtime = CompanyRuntimeSnapshot(companyId = companyId, status = CompanyRuntimeStatus.RUNNING)
        )

        bound.issues.single().runtimeDisposition shouldBe "QUARANTINED"
        bound.runtime.blockedIssueIds shouldContain issueId
    }

    test("bind falls back to pipeline id when issue durable run id is missing") {
        val appHome = Files.createTempDirectory("company-runtime-pipeline-fallback")
        val runStore = DurableRuntimeStore(appHome.resolve("runtime"))
        val companyId = "company-pipeline-fallback"
        val issueId = "issue-pipeline-fallback"
        runStore.saveRun(
            DurableRunSnapshot(
                runId = "actual-run-id",
                pipelineName = "issue-pipeline-id",
                status = DurableRunStatus.FAILED,
                createdAt = 1L,
                updatedAt = 2L
            )
        )
        val service = CompanyRuntimeBindingService(
            durableRuntimeService = DurableRuntimeService(runtimeStore = runStore),
            actionStore = ActionStore { appHome },
            policyEngine = PolicyEngine(PolicyStore { appHome }),
            gitHubControlPlaneService = GitHubControlPlaneService(store = GitHubControlPlaneStore { appHome })
        )

        val bound = service.bind(
            state = DesktopAppState(
                companies = listOf(
                    Company(
                        id = companyId,
                        name = "Pipeline Fallback",
                        rootPath = ".",
                        repositoryId = "repo-pipeline-fallback",
                        defaultBaseBranch = "main",
                        backendKind = ExecutionBackendKind.LOCAL_COTOR,
                        createdAt = 1L,
                        updatedAt = 1L
                    )
                ),
                issues = listOf(
                    CompanyIssue(
                        id = issueId,
                        companyId = companyId,
                        goalId = "goal-pipeline-fallback",
                        workspaceId = "workspace-pipeline-fallback",
                        pipelineId = "issue-pipeline-id",
                        title = "Issue",
                        description = "desc",
                        status = IssueStatus.BLOCKED,
                        createdAt = 1L,
                        updatedAt = 1L
                    )
                )
            ),
            companyId = companyId,
            runtime = CompanyRuntimeSnapshot(companyId = companyId, status = CompanyRuntimeStatus.RUNNING)
        )

        bound.issues.single().durableRunId shouldBe "actual-run-id"
        bound.issues.single().runtimeDisposition shouldBe "QUARANTINED"
        bound.runtime.blockedIssueIds shouldContain issueId
    }
})
