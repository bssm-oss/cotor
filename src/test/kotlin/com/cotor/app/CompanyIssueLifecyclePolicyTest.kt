package com.cotor.app

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe

class CompanyIssueLifecyclePolicyTest : FunSpec({
    test("validation-only execution does not require code publishing") {
        val now = System.currentTimeMillis()
        val issue = CompanyIssue(
            id = "issue-validation-only",
            companyId = "company-1",
            goalId = "goal-1",
            workspaceId = "workspace-1",
            title = "Re-run validation",
            description = "Capture residual risk without implementation changes.",
            status = IssueStatus.IN_PROGRESS,
            kind = "execution",
            executionIntent = ExecutionIntent.VALIDATION_ONLY,
            codeProducing = true,
            createdAt = now,
            updatedAt = now
        )

        requiresCodePublish(issue) shouldBe false
    }

    test("implicit GitHub PR requirement is suppressed for full auto companies without a remote") {
        val now = System.currentTimeMillis()
        val issue = CompanyIssue(
            id = "issue-full-auto-local",
            companyId = "company-1",
            goalId = "goal-1",
            workspaceId = "workspace-1",
            title = "Implement local fix",
            description = "Make a code change.",
            status = IssueStatus.PLANNED,
            kind = "execution",
            codeProducing = true,
            createdAt = now,
            updatedAt = now
        )
        val state = DesktopAppState(
            companies = listOf(
                Company(
                    id = "company-1",
                    name = "Company",
                    rootPath = "/tmp/company",
                    repositoryId = "repo-1",
                    defaultBaseBranch = "main",
                    createdAt = now,
                    updatedAt = now,
                    operatorAutomationMode = OperatorAutomationMode.FULL_AUTO
                )
            ),
            repositories = listOf(
                ManagedRepository(
                    id = "repo-1",
                    name = "repo",
                    localPath = "/tmp/company",
                    sourceKind = RepositorySourceKind.LOCAL,
                    remoteUrl = null,
                    defaultBranch = "main",
                    createdAt = now,
                    updatedAt = now
                )
            ),
            workspaces = listOf(
                Workspace(
                    id = "workspace-1",
                    repositoryId = "repo-1",
                    name = "main",
                    baseBranch = "main",
                    createdAt = now,
                    updatedAt = now
                )
            )
        )

        requiresGitHubPullRequest(issue, state) shouldBe false
    }

    test("passing checks recover blocked review state without losing approval verdicts") {
        val now = System.currentTimeMillis()
        val issue = CompanyIssue(
            id = "issue-pr",
            companyId = "company-1",
            goalId = "goal-1",
            workspaceId = "workspace-1",
            title = "Implement reviewed fix",
            description = "Review queue should recover after checks pass.",
            status = IssueStatus.BLOCKED,
            kind = "execution",
            pullRequestUrl = "https://github.com/example/repo/pull/1",
            qaVerdict = "PASS",
            createdAt = now,
            updatedAt = now
        )
        val queueItem = ReviewQueueItem(
            id = "review-1",
            companyId = "company-1",
            issueId = issue.id,
            runId = "run-1",
            status = ReviewQueueStatus.FAILED_CHECKS,
            qaVerdict = "PASS",
            checksSummary = "build=COMPLETED/SUCCESS",
            createdAt = now,
            updatedAt = now
        )

        checksExplicitlyPassing(queueItem.checksSummary) shouldBe true
        recoveredIssueStatus(issue, queueItem) shouldBe IssueStatus.READY_FOR_CEO
        recoveredReviewQueueStatus(queueItem) shouldBe ReviewQueueStatus.READY_FOR_CEO
    }
})
