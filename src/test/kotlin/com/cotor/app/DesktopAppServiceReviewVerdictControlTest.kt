package com.cotor.app

import com.cotor.data.config.ConfigRepository
import com.cotor.domain.executor.AgentExecutor
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.nulls.shouldNotBeNull
import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import java.nio.file.Files

class DesktopAppServiceReviewVerdictControlTest : FunSpec({
    test("submitQaReviewVerdict moves a review queue item into CEO approval") {
        val appHome = Files.createTempDirectory("desktop-review-verdict-qa-home")
        val repoRoot = Files.createDirectories(Files.createTempDirectory("desktop-review-verdict-qa-repo").resolve("repo"))
        val stateStore = DesktopStateStore { appHome }
        val gitWorkspaceService = mockk<GitWorkspaceService>(relaxed = true)
        coEvery { gitWorkspaceService.ensureInitializedRepositoryRoot(any(), any()) } returns repoRoot
        coEvery { gitWorkspaceService.resolveRepositoryRoot(any()) } returns repoRoot
        coEvery { gitWorkspaceService.detectDefaultBranch(any()) } returns "master"
        coEvery { gitWorkspaceService.detectRemoteUrl(any()) } returns "https://github.com/example/cotor.git"
        coEvery { gitWorkspaceService.commentOnPullRequest(any(), any(), any(), any(), any()) } returns Unit
        coEvery {
            gitWorkspaceService.submitPullRequestReview(any(), any(), PullRequestReviewVerdict.APPROVE, any(), any(), any())
        } returns PublishMetadata(
            pullRequestNumber = 42,
            pullRequestUrl = "https://github.com/example/cotor/pull/42",
            pullRequestState = "OPEN"
        )
        val service = DesktopAppService(
            stateStore = stateStore,
            gitWorkspaceService = gitWorkspaceService,
            configRepository = mockk<ConfigRepository>(relaxed = true),
            agentExecutor = mockk<AgentExecutor>(relaxed = true),
            autoStartAutomationRefresh = false
        )

        val company = service.createCompany(
            name = "Review Verdict Co",
            rootPath = repoRoot.toString(),
            defaultBaseBranch = "master"
        )
        val baseState = stateStore.load()
        val workspace = baseState.workspaces.first { it.repositoryId == company.repositoryId }
        val projectContext = baseState.projectContexts.first { it.companyId == company.id }
        val now = System.currentTimeMillis()
        val goal = CompanyGoal(
            id = "goal-review-verdict",
            companyId = company.id,
            projectContextId = projectContext.id,
            title = "Ship reviewed work",
            description = "Move reviewed work through QA and CEO lanes.",
            status = GoalStatus.ACTIVE,
            autonomyEnabled = true,
            createdAt = now,
            updatedAt = now
        )
        val executionIssue = CompanyIssue(
            id = "issue-execution-review-verdict",
            companyId = company.id,
            projectContextId = projectContext.id,
            goalId = goal.id,
            workspaceId = workspace.id,
            title = "Implement feature",
            description = "Execution issue under review.",
            status = IssueStatus.IN_REVIEW,
            priority = 1,
            kind = "execution",
            branchName = "codex/cotor/review-verdict/codex",
            worktreePath = repoRoot.resolve(".cotor/worktrees/review-verdict/codex").toString(),
            pullRequestNumber = 42,
            pullRequestUrl = "https://github.com/example/cotor/pull/42",
            pullRequestState = "OPEN",
            createdAt = now,
            updatedAt = now
        )
        val reviewIssue = CompanyIssue(
            id = "issue-qa-review-verdict",
            companyId = company.id,
            projectContextId = projectContext.id,
            goalId = goal.id,
            workspaceId = workspace.id,
            title = "QA review Implement feature",
            description = "Review the pull request.",
            status = IssueStatus.PLANNED,
            priority = 2,
            kind = "review",
            dependsOn = listOf(executionIssue.id),
            branchName = executionIssue.branchName,
            worktreePath = executionIssue.worktreePath,
            pullRequestNumber = executionIssue.pullRequestNumber,
            pullRequestUrl = executionIssue.pullRequestUrl,
            pullRequestState = executionIssue.pullRequestState,
            sourceSignal = "qa-review:${executionIssue.id}",
            createdAt = now,
            updatedAt = now
        )
        val queueItem = ReviewQueueItem(
            id = "queue-review-verdict",
            companyId = company.id,
            projectContextId = projectContext.id,
            issueId = executionIssue.id,
            runId = "run-review-verdict",
            branchName = executionIssue.branchName,
            worktreePath = executionIssue.worktreePath,
            pullRequestNumber = executionIssue.pullRequestNumber,
            pullRequestUrl = executionIssue.pullRequestUrl,
            pullRequestState = executionIssue.pullRequestState,
            status = ReviewQueueStatus.AWAITING_QA,
            qaIssueId = reviewIssue.id,
            createdAt = now,
            updatedAt = now
        )
        stateStore.save(
            baseState.copy(
                goals = baseState.goals + goal,
                issues = baseState.issues + listOf(executionIssue, reviewIssue),
                reviewQueue = baseState.reviewQueue + queueItem
            )
        )

        val updated = service.submitQaReviewVerdict(queueItem.id, "PASS", "Looks good")
        val refreshed = stateStore.load()
        val refreshedExecution = refreshed.issues.first { it.id == executionIssue.id }
        val refreshedReview = refreshed.issues.first { it.id == reviewIssue.id }
        val approvalIssue = refreshed.issues.first { it.kind == "approval" && it.sourceSignal == "ceo-approval:${executionIssue.id}" }

        updated.status shouldBe ReviewQueueStatus.READY_FOR_CEO
        updated.qaVerdict shouldBe "PASS"
        updated.approvalIssueId shouldBe approvalIssue.id
        refreshedReview.status shouldBe IssueStatus.DONE
        refreshedReview.qaVerdict shouldBe "PASS"
        refreshedExecution.status shouldBe IssueStatus.READY_FOR_CEO
        refreshedExecution.qaVerdict shouldBe "PASS"
        approvalIssue.status shouldBe IssueStatus.PLANNED
        approvalIssue.qaVerdict shouldBe "PASS"
        coVerify(exactly = 1) {
            gitWorkspaceService.submitPullRequestReview(any(), 42, PullRequestReviewVerdict.APPROVE, any(), any(), any())
        }
    }

    test("submitQaReviewVerdict records requested changes and re-plans execution") {
        val appHome = Files.createTempDirectory("desktop-review-verdict-qa-changes-home")
        val repoRoot = Files.createDirectories(Files.createTempDirectory("desktop-review-verdict-qa-changes-repo").resolve("repo"))
        val stateStore = DesktopStateStore { appHome }
        val gitWorkspaceService = mockk<GitWorkspaceService>(relaxed = true)
        coEvery { gitWorkspaceService.ensureInitializedRepositoryRoot(any(), any()) } returns repoRoot
        coEvery { gitWorkspaceService.resolveRepositoryRoot(any()) } returns repoRoot
        coEvery { gitWorkspaceService.detectDefaultBranch(any()) } returns "master"
        coEvery { gitWorkspaceService.detectRemoteUrl(any()) } returns "https://github.com/example/cotor.git"
        coEvery { gitWorkspaceService.commentOnPullRequest(any(), any(), any(), any(), any()) } returns Unit
        coEvery {
            gitWorkspaceService.submitPullRequestReview(any(), any(), PullRequestReviewVerdict.REQUEST_CHANGES, any(), any(), any())
        } returns PublishMetadata(
            pullRequestNumber = 43,
            pullRequestUrl = "https://github.com/example/cotor/pull/43",
            pullRequestState = "OPEN"
        )
        val service = DesktopAppService(
            stateStore = stateStore,
            gitWorkspaceService = gitWorkspaceService,
            configRepository = mockk<ConfigRepository>(relaxed = true),
            agentExecutor = mockk<AgentExecutor>(relaxed = true),
            autoStartAutomationRefresh = false
        )

        val company = service.createCompany(
            name = "Review Verdict Changes Co",
            rootPath = repoRoot.toString(),
            defaultBaseBranch = "master"
        )
        val baseState = stateStore.load()
        val workspace = baseState.workspaces.first { it.repositoryId == company.repositoryId }
        val projectContext = baseState.projectContexts.first { it.companyId == company.id }
        val now = System.currentTimeMillis()
        val goal = CompanyGoal(
            id = "goal-review-verdict-changes",
            companyId = company.id,
            projectContextId = projectContext.id,
            title = "Re-plan reviewed work",
            description = "Move reviewed work back to execution when QA requests changes.",
            status = GoalStatus.ACTIVE,
            autonomyEnabled = true,
            createdAt = now,
            updatedAt = now
        )
        val executionIssue = CompanyIssue(
            id = "issue-execution-review-verdict-changes",
            companyId = company.id,
            projectContextId = projectContext.id,
            goalId = goal.id,
            workspaceId = workspace.id,
            title = "Implement feature changes",
            description = "Execution issue under review.",
            status = IssueStatus.IN_REVIEW,
            priority = 1,
            kind = "execution",
            branchName = "codex/cotor/review-verdict-changes/codex",
            worktreePath = repoRoot.resolve(".cotor/worktrees/review-verdict-changes/codex").toString(),
            pullRequestNumber = 43,
            pullRequestUrl = "https://github.com/example/cotor/pull/43",
            pullRequestState = "OPEN",
            createdAt = now,
            updatedAt = now
        )
        val reviewIssue = CompanyIssue(
            id = "issue-qa-review-verdict-changes",
            companyId = company.id,
            projectContextId = projectContext.id,
            goalId = goal.id,
            workspaceId = workspace.id,
            title = "QA review Implement feature changes",
            description = "Review the pull request.",
            status = IssueStatus.PLANNED,
            priority = 2,
            kind = "review",
            dependsOn = listOf(executionIssue.id),
            branchName = executionIssue.branchName,
            worktreePath = executionIssue.worktreePath,
            pullRequestNumber = executionIssue.pullRequestNumber,
            pullRequestUrl = executionIssue.pullRequestUrl,
            pullRequestState = executionIssue.pullRequestState,
            sourceSignal = "qa-review:${executionIssue.id}",
            createdAt = now,
            updatedAt = now
        )
        val queueItem = ReviewQueueItem(
            id = "queue-review-verdict-changes",
            companyId = company.id,
            projectContextId = projectContext.id,
            issueId = executionIssue.id,
            runId = "run-review-verdict-changes",
            branchName = executionIssue.branchName,
            worktreePath = executionIssue.worktreePath,
            pullRequestNumber = executionIssue.pullRequestNumber,
            pullRequestUrl = executionIssue.pullRequestUrl,
            pullRequestState = executionIssue.pullRequestState,
            status = ReviewQueueStatus.AWAITING_QA,
            qaIssueId = reviewIssue.id,
            createdAt = now,
            updatedAt = now
        )
        stateStore.save(
            baseState.copy(
                goals = baseState.goals + goal,
                issues = baseState.issues + listOf(executionIssue, reviewIssue),
                reviewQueue = baseState.reviewQueue + queueItem
            )
        )

        val updated = service.submitQaReviewVerdict(queueItem.id, "CHANGES_REQUESTED", "Please revise")
        val refreshed = stateStore.load()
        val refreshedExecution = refreshed.issues.first { it.id == executionIssue.id }
        val refreshedReview = refreshed.issues.first { it.id == reviewIssue.id }

        updated.status shouldBe ReviewQueueStatus.CHANGES_REQUESTED
        updated.qaVerdict shouldBe "CHANGES_REQUESTED"
        refreshedReview.status shouldBe IssueStatus.BLOCKED
        refreshedReview.qaVerdict shouldBe "CHANGES_REQUESTED"
        refreshedExecution.status shouldBe IssueStatus.PLANNED
        refreshedExecution.qaVerdict shouldBe "CHANGES_REQUESTED"
        coVerify(exactly = 1) {
            gitWorkspaceService.submitPullRequestReview(any(), 43, PullRequestReviewVerdict.REQUEST_CHANGES, any(), any(), any())
        }
    }

    test("submitCeoReviewVerdict records changes requested without merging") {
        val appHome = Files.createTempDirectory("desktop-review-verdict-ceo-home")
        val repoRoot = Files.createDirectories(Files.createTempDirectory("desktop-review-verdict-ceo-repo").resolve("repo"))
        val stateStore = DesktopStateStore { appHome }
        val gitWorkspaceService = mockk<GitWorkspaceService>(relaxed = true)
        coEvery { gitWorkspaceService.ensureInitializedRepositoryRoot(any(), any()) } returns repoRoot
        coEvery { gitWorkspaceService.resolveRepositoryRoot(any()) } returns repoRoot
        coEvery { gitWorkspaceService.detectDefaultBranch(any()) } returns "master"
        coEvery { gitWorkspaceService.detectRemoteUrl(any()) } returns "https://github.com/example/cotor.git"
        coEvery { gitWorkspaceService.commentOnPullRequest(any(), any(), any(), any(), any()) } returns Unit
        coEvery {
            gitWorkspaceService.submitPullRequestReview(any(), any(), PullRequestReviewVerdict.REQUEST_CHANGES, any(), any(), any())
        } returns PublishMetadata(
            pullRequestNumber = 77,
            pullRequestUrl = "https://github.com/example/cotor/pull/77",
            pullRequestState = "OPEN"
        )
        val service = DesktopAppService(
            stateStore = stateStore,
            gitWorkspaceService = gitWorkspaceService,
            configRepository = mockk<ConfigRepository>(relaxed = true),
            agentExecutor = mockk<AgentExecutor>(relaxed = true),
            autoStartAutomationRefresh = false
        )

        val company = service.createCompany(
            name = "CEO Verdict Co",
            rootPath = repoRoot.toString(),
            defaultBaseBranch = "master"
        )
        val baseState = stateStore.load()
        val workspace = baseState.workspaces.first { it.repositoryId == company.repositoryId }
        val projectContext = baseState.projectContexts.first { it.companyId == company.id }
        val now = System.currentTimeMillis()
        val goal = CompanyGoal(
            id = "goal-ceo-verdict",
            companyId = company.id,
            projectContextId = projectContext.id,
            title = "Approve reviewed work",
            description = "Move reviewed work through CEO lane.",
            status = GoalStatus.ACTIVE,
            autonomyEnabled = true,
            createdAt = now,
            updatedAt = now
        )
        val executionIssue = CompanyIssue(
            id = "issue-execution-ceo-verdict",
            companyId = company.id,
            projectContextId = projectContext.id,
            goalId = goal.id,
            workspaceId = workspace.id,
            title = "Implement approved feature",
            description = "Execution issue awaiting CEO approval.",
            status = IssueStatus.READY_FOR_CEO,
            priority = 1,
            kind = "execution",
            branchName = "codex/cotor/ceo-verdict/codex",
            worktreePath = repoRoot.resolve(".cotor/worktrees/ceo-verdict/codex").toString(),
            pullRequestNumber = 77,
            pullRequestUrl = "https://github.com/example/cotor/pull/77",
            pullRequestState = "OPEN",
            qaVerdict = "PASS",
            qaFeedback = "Looks good",
            createdAt = now,
            updatedAt = now
        )
        val approvalIssue = CompanyIssue(
            id = "issue-approval-ceo-verdict",
            companyId = company.id,
            projectContextId = projectContext.id,
            goalId = goal.id,
            workspaceId = workspace.id,
            title = "CEO approve Implement approved feature",
            description = "Approve or request changes.",
            status = IssueStatus.PLANNED,
            priority = 3,
            kind = "approval",
            dependsOn = listOf("issue-qa-review-ceo-verdict"),
            branchName = executionIssue.branchName,
            worktreePath = executionIssue.worktreePath,
            pullRequestNumber = executionIssue.pullRequestNumber,
            pullRequestUrl = executionIssue.pullRequestUrl,
            pullRequestState = executionIssue.pullRequestState,
            qaVerdict = "PASS",
            qaFeedback = "Looks good",
            sourceSignal = "ceo-approval:${executionIssue.id}",
            createdAt = now,
            updatedAt = now
        )
        val queueItem = ReviewQueueItem(
            id = "queue-ceo-verdict",
            companyId = company.id,
            projectContextId = projectContext.id,
            issueId = executionIssue.id,
            runId = "run-ceo-verdict",
            branchName = executionIssue.branchName,
            worktreePath = executionIssue.worktreePath,
            pullRequestNumber = executionIssue.pullRequestNumber,
            pullRequestUrl = executionIssue.pullRequestUrl,
            pullRequestState = executionIssue.pullRequestState,
            status = ReviewQueueStatus.READY_FOR_CEO,
            qaVerdict = "PASS",
            qaFeedback = "Looks good",
            approvalIssueId = approvalIssue.id,
            createdAt = now,
            updatedAt = now
        )
        stateStore.save(
            baseState.copy(
                goals = baseState.goals + goal,
                issues = baseState.issues + listOf(executionIssue, approvalIssue),
                reviewQueue = baseState.reviewQueue + queueItem
            )
        )

        val updated = service.submitCeoReviewVerdict(queueItem.id, "CHANGES_REQUESTED", "Needs another pass")
        val refreshed = stateStore.load()
        val refreshedExecution = refreshed.issues.first { it.id == executionIssue.id }
        val refreshedApproval = refreshed.issues.first { it.id == approvalIssue.id }

        updated.status shouldBe ReviewQueueStatus.CHANGES_REQUESTED
        updated.ceoVerdict shouldBe "CHANGES_REQUESTED"
        refreshedApproval.status shouldBe IssueStatus.BLOCKED
        refreshedApproval.ceoVerdict shouldBe "CHANGES_REQUESTED"
        refreshedExecution.status shouldBe IssueStatus.PLANNED
        refreshedExecution.ceoVerdict shouldBe "CHANGES_REQUESTED"
        coVerify(exactly = 1) {
            gitWorkspaceService.submitPullRequestReview(any(), 77, PullRequestReviewVerdict.REQUEST_CHANGES, any(), any(), any())
        }
    }

    test("submitCeoReviewVerdict approves and merges a ready review queue item") {
        val appHome = Files.createTempDirectory("desktop-review-verdict-ceo-approve-home")
        val repoRoot = Files.createDirectories(Files.createTempDirectory("desktop-review-verdict-ceo-approve-repo").resolve("repo"))
        val stateStore = DesktopStateStore { appHome }
        val gitWorkspaceService = mockk<GitWorkspaceService>(relaxed = true)
        coEvery { gitWorkspaceService.ensureInitializedRepositoryRoot(any(), any()) } returns repoRoot
        coEvery { gitWorkspaceService.resolveRepositoryRoot(any()) } returns repoRoot
        coEvery { gitWorkspaceService.detectDefaultBranch(any()) } returns "master"
        coEvery { gitWorkspaceService.detectRemoteUrl(any()) } returns "https://github.com/example/cotor.git"
        coEvery { gitWorkspaceService.commentOnPullRequest(any(), any(), any(), any(), any()) } returns Unit
        coEvery {
            gitWorkspaceService.submitPullRequestReview(any(), any(), PullRequestReviewVerdict.APPROVE, any(), any(), any())
        } returns PublishMetadata(
            pullRequestNumber = 88,
            pullRequestUrl = "https://github.com/example/cotor/pull/88",
            pullRequestState = "OPEN",
            mergeability = "CLEAN"
        )
        coEvery { gitWorkspaceService.mergePullRequest(any(), 88, true, any(), any()) } returns PullRequestMergeResult(
            number = 88,
            url = "https://github.com/example/cotor/pull/88",
            state = "MERGED",
            mergeCommitSha = "merge-commit-88"
        )
        coEvery { gitWorkspaceService.syncBaseBranchAfterMerge(any(), any()) } returns BaseBranchSyncResult(synced = false)
        val service = DesktopAppService(
            stateStore = stateStore,
            gitWorkspaceService = gitWorkspaceService,
            configRepository = mockk<ConfigRepository>(relaxed = true),
            agentExecutor = mockk<AgentExecutor>(relaxed = true),
            autoStartAutomationRefresh = false
        )

        val company = service.createCompany(
            name = "CEO Approve Co",
            rootPath = repoRoot.toString(),
            defaultBaseBranch = "master"
        )
        val baseState = stateStore.load()
        val workspace = baseState.workspaces.first { it.repositoryId == company.repositoryId }
        val projectContext = baseState.projectContexts.first { it.companyId == company.id }
        val now = System.currentTimeMillis()
        val goal = CompanyGoal(
            id = "goal-ceo-approve",
            companyId = company.id,
            projectContextId = projectContext.id,
            title = "Merge approved work",
            description = "Move approved work through CEO merge.",
            status = GoalStatus.ACTIVE,
            autonomyEnabled = true,
            createdAt = now,
            updatedAt = now
        )
        val executionIssue = CompanyIssue(
            id = "issue-execution-ceo-approve",
            companyId = company.id,
            projectContextId = projectContext.id,
            goalId = goal.id,
            workspaceId = workspace.id,
            title = "Implement mergeable feature",
            description = "Execution issue awaiting CEO approval.",
            status = IssueStatus.READY_FOR_CEO,
            priority = 1,
            kind = "execution",
            branchName = "codex/cotor/ceo-approve/codex",
            worktreePath = repoRoot.resolve(".cotor/worktrees/ceo-approve/codex").toString(),
            pullRequestNumber = 88,
            pullRequestUrl = "https://github.com/example/cotor/pull/88",
            pullRequestState = "OPEN",
            qaVerdict = "PASS",
            qaFeedback = "Looks good",
            createdAt = now,
            updatedAt = now
        )
        val approvalIssue = CompanyIssue(
            id = "issue-approval-ceo-approve",
            companyId = company.id,
            projectContextId = projectContext.id,
            goalId = goal.id,
            workspaceId = workspace.id,
            title = "CEO approve Implement mergeable feature",
            description = "Approve or request changes.",
            status = IssueStatus.PLANNED,
            priority = 3,
            kind = "approval",
            branchName = executionIssue.branchName,
            worktreePath = executionIssue.worktreePath,
            pullRequestNumber = executionIssue.pullRequestNumber,
            pullRequestUrl = executionIssue.pullRequestUrl,
            pullRequestState = executionIssue.pullRequestState,
            qaVerdict = "PASS",
            qaFeedback = "Looks good",
            sourceSignal = "ceo-approval:${executionIssue.id}",
            createdAt = now,
            updatedAt = now
        )
        val queueItem = ReviewQueueItem(
            id = "queue-ceo-approve",
            companyId = company.id,
            projectContextId = projectContext.id,
            issueId = executionIssue.id,
            runId = "run-ceo-approve",
            branchName = executionIssue.branchName,
            worktreePath = executionIssue.worktreePath,
            pullRequestNumber = executionIssue.pullRequestNumber,
            pullRequestUrl = executionIssue.pullRequestUrl,
            pullRequestState = executionIssue.pullRequestState,
            status = ReviewQueueStatus.READY_FOR_CEO,
            mergeability = "CLEAN",
            qaVerdict = "PASS",
            qaFeedback = "Looks good",
            approvalIssueId = approvalIssue.id,
            createdAt = now,
            updatedAt = now
        )
        stateStore.save(
            baseState.copy(
                goals = baseState.goals + goal,
                issues = baseState.issues + listOf(executionIssue, approvalIssue),
                reviewQueue = baseState.reviewQueue + queueItem
            )
        )

        val updated = service.submitCeoReviewVerdict(queueItem.id, "APPROVE", "Ship it")
        val refreshed = stateStore.load()
        val refreshedExecution = refreshed.issues.first { it.id == executionIssue.id }
        val refreshedApproval = refreshed.issues.first { it.id == approvalIssue.id }

        updated.status shouldBe ReviewQueueStatus.MERGED
        updated.ceoVerdict shouldBe "APPROVE"
        refreshedExecution.status shouldBe IssueStatus.DONE
        refreshedExecution.ceoVerdict shouldBe "APPROVE"
        refreshedExecution.verificationStatus shouldBe null
        refreshedExecution.verificationSummary shouldBe null
        refreshedApproval.status shouldBe IssueStatus.DONE
        refreshedApproval.ceoVerdict shouldBe "APPROVE"
        coVerify(exactly = 1) {
            gitWorkspaceService.submitPullRequestReview(any(), 88, PullRequestReviewVerdict.APPROVE, any(), any(), any())
        }
        coVerify(exactly = 1) { gitWorkspaceService.mergePullRequest(any(), 88, true, any(), any()) }
    }

    test("mergeReviewQueueItem records failed checks without calling merge") {
        val fixture = mergeGuardFixture(
            pullRequestNumber = 91,
            pullRequestState = "OPEN",
            mergeability = "CLEAN",
            checksSummary = "ci=COMPLETED/FAILURE"
        )

        val updated = fixture.service.mergeReviewQueueItem(fixture.queueItem.id)
        val refreshedIssue = fixture.stateStore.load().issues.first { it.id == fixture.executionIssue.id }

        updated.status shouldBe ReviewQueueStatus.FAILED_CHECKS
        updated.providerBlockReason shouldBe "ci=COMPLETED/FAILURE"
        refreshedIssue.status shouldBe IssueStatus.BLOCKED
        coVerify(exactly = 0) {
            fixture.gitWorkspaceService.mergePullRequest(any(), 91, any(), any(), any())
        }
    }

    test("mergeReviewQueueItem routes non-clean mergeability to remediation without calling merge") {
        listOf("UNKNOWN", "BLOCKED", "DIRTY").forEachIndexed { index, mergeability ->
            val pullRequestNumber = 92 + index
            val fixture = mergeGuardFixture(
                pullRequestNumber = pullRequestNumber,
                pullRequestState = "OPEN",
                mergeability = mergeability,
                checksSummary = "ci=COMPLETED/SUCCESS"
            )

            val updated = fixture.service.mergeReviewQueueItem(fixture.queueItem.id)
            val refreshedIssue = fixture.stateStore.load().issues.first { it.id == fixture.executionIssue.id }

            updated.status shouldBe ReviewQueueStatus.CHANGES_REQUESTED
            updated.mergeability shouldBe mergeability
            refreshedIssue.status shouldBe IssueStatus.PLANNED
            refreshedIssue.executionIntent shouldBe ExecutionIntent.MERGE_CONFLICT_REMEDIATION
            coVerify(exactly = 0) {
                fixture.gitWorkspaceService.mergePullRequest(any(), pullRequestNumber, any(), any(), any())
            }
        }
    }

    test("mergeReviewQueueItem waits on unstable mergeability instead of reopening remediation") {
        val fixture = mergeGuardFixture(
            pullRequestNumber = 120,
            pullRequestState = "OPEN",
            mergeability = "UNSTABLE",
            checksSummary = "ci=COMPLETED/SUCCESS"
        )

        val updated = fixture.service.mergeReviewQueueItem(fixture.queueItem.id)
        val refreshedState = fixture.stateStore.load()
        val refreshedIssue = refreshedState.issues.first { it.id == fixture.executionIssue.id }
        val approvalIssue = refreshedState.issues.first {
            it.kind.equals("approval", ignoreCase = true) &&
                it.pullRequestNumber == 120
        }

        updated.status shouldBe ReviewQueueStatus.READY_FOR_CEO
        updated.mergeability shouldBe "UNSTABLE"
        refreshedIssue.status shouldBe IssueStatus.READY_FOR_CEO
        refreshedIssue.executionIntent shouldNotBe ExecutionIntent.MERGE_CONFLICT_REMEDIATION
        approvalIssue.status shouldBe IssueStatus.PLANNED
        coVerify(exactly = 0) {
            fixture.gitWorkspaceService.mergePullRequest(any(), 120, any(), any(), any())
        }
    }

    test("submitQaReviewVerdict rejects a missing review queue item") {
        val appHome = Files.createTempDirectory("desktop-review-verdict-missing-home")
        val repoRoot = Files.createDirectories(Files.createTempDirectory("desktop-review-verdict-missing-repo").resolve("repo"))
        val stateStore = DesktopStateStore { appHome }
        val gitWorkspaceService = mockk<GitWorkspaceService>()
        coEvery { gitWorkspaceService.ensureInitializedRepositoryRoot(any(), any()) } returns repoRoot
        val service = DesktopAppService(
            stateStore = stateStore,
            gitWorkspaceService = gitWorkspaceService,
            configRepository = mockk<ConfigRepository>(relaxed = true),
            agentExecutor = mockk<AgentExecutor>(relaxed = true),
            autoStartAutomationRefresh = false
        )

        val error = runCatching {
            service.submitQaReviewVerdict("missing-item", "PASS", "ok")
        }.exceptionOrNull()

        error.shouldNotBeNull()
        (error is IllegalArgumentException) shouldBe true
    }
})

private data class MergeGuardFixture(
    val service: DesktopAppService,
    val stateStore: DesktopStateStore,
    val gitWorkspaceService: GitWorkspaceService,
    val queueItem: ReviewQueueItem,
    val executionIssue: CompanyIssue
)

private suspend fun mergeGuardFixture(
    pullRequestNumber: Int,
    pullRequestState: String,
    mergeability: String,
    checksSummary: String
): MergeGuardFixture {
    val appHome = Files.createTempDirectory("desktop-review-merge-guard-home")
    val repoRoot = Files.createDirectories(Files.createTempDirectory("desktop-review-merge-guard-repo").resolve("repo"))
    val stateStore = DesktopStateStore { appHome }
    val gitWorkspaceService = mockk<GitWorkspaceService>(relaxed = true)
    coEvery { gitWorkspaceService.commentOnPullRequest(any(), any(), any(), any(), any()) } returns Unit
    coEvery {
        gitWorkspaceService.submitPullRequestReview(
            any(),
            pullRequestNumber,
            PullRequestReviewVerdict.APPROVE,
            any(),
            any(),
            any()
        )
    } returns PublishMetadata(
        pullRequestNumber = pullRequestNumber,
        pullRequestUrl = "https://github.com/example/cotor/pull/$pullRequestNumber",
        pullRequestState = pullRequestState,
        mergeability = mergeability,
        checksSummary = checksSummary
    )
    val service = DesktopAppService(
        stateStore = stateStore,
        gitWorkspaceService = gitWorkspaceService,
        configRepository = mockk<ConfigRepository>(relaxed = true),
        agentExecutor = mockk<AgentExecutor>(relaxed = true),
        autoStartAutomationRefresh = false
    )
    val now = System.currentTimeMillis()
    val company = Company(
        id = "company-merge-guard-$pullRequestNumber",
        name = "Merge Guard Co",
        rootPath = repoRoot.toString(),
        repositoryId = "repo-merge-guard-$pullRequestNumber",
        defaultBaseBranch = "master",
        createdAt = now,
        updatedAt = now
    )
    val workspace = Workspace(
        id = "workspace-merge-guard-$pullRequestNumber",
        repositoryId = company.repositoryId,
        name = "repo · master",
        baseBranch = "master",
        createdAt = now,
        updatedAt = now
    )
    val goal = CompanyGoal(
        id = "goal-merge-guard-$pullRequestNumber",
        companyId = company.id,
        title = "Merge guarded work",
        description = "Only clean PRs should merge.",
        status = GoalStatus.ACTIVE,
        autonomyEnabled = true,
        createdAt = now,
        updatedAt = now
    )
    val executionIssue = CompanyIssue(
        id = "issue-merge-guard-$pullRequestNumber",
        companyId = company.id,
        goalId = goal.id,
        workspaceId = workspace.id,
        title = "Implement guarded feature",
        description = "Ready for CEO merge.",
        status = IssueStatus.READY_FOR_CEO,
        priority = 1,
        kind = "execution",
        branchName = "codex/cotor/merge-guard-$pullRequestNumber/codex",
        worktreePath = repoRoot.resolve(".cotor/worktrees/merge-guard-$pullRequestNumber/codex").toString(),
        pullRequestNumber = pullRequestNumber,
        pullRequestUrl = "https://github.com/example/cotor/pull/$pullRequestNumber",
        pullRequestState = "OPEN",
        qaVerdict = "PASS",
        createdAt = now,
        updatedAt = now
    )
    val approvalIssue = CompanyIssue(
        id = "issue-approval-merge-guard-$pullRequestNumber",
        companyId = company.id,
        goalId = goal.id,
        workspaceId = workspace.id,
        title = "CEO approve guarded feature",
        description = "Approve or request changes.",
        status = IssueStatus.PLANNED,
        priority = 3,
        kind = "approval",
        branchName = executionIssue.branchName,
        worktreePath = executionIssue.worktreePath,
        pullRequestNumber = executionIssue.pullRequestNumber,
        pullRequestUrl = executionIssue.pullRequestUrl,
        pullRequestState = executionIssue.pullRequestState,
        qaVerdict = "PASS",
        sourceSignal = "ceo-approval:${executionIssue.id}",
        createdAt = now,
        updatedAt = now
    )
    val queueItem = ReviewQueueItem(
        id = "queue-merge-guard-$pullRequestNumber",
        companyId = company.id,
        issueId = executionIssue.id,
        runId = "run-merge-guard-$pullRequestNumber",
        branchName = executionIssue.branchName,
        worktreePath = executionIssue.worktreePath,
        pullRequestNumber = pullRequestNumber,
        pullRequestUrl = executionIssue.pullRequestUrl,
        pullRequestState = executionIssue.pullRequestState,
        status = ReviewQueueStatus.READY_FOR_CEO,
        mergeability = "CLEAN",
        checksSummary = "ci=COMPLETED/SUCCESS",
        qaVerdict = "PASS",
        ceoVerdict = "APPROVE",
        ceoFeedback = "Ship it",
        approvalIssueId = approvalIssue.id,
        createdAt = now,
        updatedAt = now
    )
    stateStore.save(
        DesktopAppState(
            companies = listOf(company),
            workspaces = listOf(workspace),
            goals = listOf(goal),
            issues = listOf(executionIssue, approvalIssue),
            reviewQueue = listOf(queueItem)
        )
    )
    return MergeGuardFixture(
        service = service,
        stateStore = stateStore,
        gitWorkspaceService = gitWorkspaceService,
        queueItem = queueItem,
        executionIssue = executionIssue
    )
}
