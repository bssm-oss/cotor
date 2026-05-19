package com.cotor.app

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain

class CompanyVerifierServiceTest : FunSpec({
    test("evidence-free code issue completion is blocked separately from execution failure") {
        val now = System.currentTimeMillis()
        val issue = CompanyIssue(
            id = "issue-1",
            companyId = "company-1",
            goalId = "goal-1",
            workspaceId = "workspace-1",
            title = "Implement durable behavior",
            description = "Needs concrete evidence before completion.",
            status = IssueStatus.PLANNED,
            kind = "execution",
            acceptanceCriteria = listOf("Implementation evidence is recorded."),
            codeProducing = true,
            createdAt = now,
            updatedAt = now
        )
        val run = AgentRun(
            id = "run-1",
            taskId = "task-1",
            workspaceId = "workspace-1",
            repositoryId = "repo-1",
            agentId = "builder",
            agentName = "builder",
            repoRoot = "/tmp/repo",
            baseBranch = "main",
            branchName = "codex/test",
            worktreePath = "/tmp/repo/.cotor/worktrees/test",
            status = AgentRunStatus.COMPLETED,
            createdAt = now,
            updatedAt = now
        )
        val state = DesktopAppState(issues = listOf(issue), runs = listOf(run))

        val decision = CompanyVerifierService().verifyIssueCompletion(state, issue, run)

        decision.passed shouldBe false
        decision.status shouldBe "FAIL"
        decision.summary shouldContain "Verification blocked completion"
    }

    test("validation-only execution ignores stale review rejection metadata during completion verification") {
        val now = System.currentTimeMillis()
        val issue = CompanyIssue(
            id = "issue-validation",
            companyId = "company-1",
            goalId = "goal-1",
            workspaceId = "workspace-1",
            title = "Re-run validation",
            description = "Capture residual risk without publishing code.",
            status = IssueStatus.IN_PROGRESS,
            kind = "execution",
            acceptanceCriteria = listOf("Validation rerun completed."),
            codeProducing = false,
            executionIntent = ExecutionIntent.VALIDATION_ONLY,
            qaVerdict = "CHANGES_REQUESTED",
            qaFeedback = "Previous review feedback.",
            ceoVerdict = "CHANGES_REQUESTED",
            ceoFeedback = "Previous approval feedback.",
            createdAt = now,
            updatedAt = now
        )
        val run = AgentRun(
            id = "run-validation",
            taskId = "task-validation",
            workspaceId = "workspace-1",
            repositoryId = "repo-1",
            agentId = "builder",
            agentName = "builder",
            repoRoot = "/tmp/repo",
            baseBranch = "main",
            branchName = "codex/validation",
            worktreePath = "/tmp/repo/.cotor/worktrees/validation",
            status = AgentRunStatus.COMPLETED,
            output = "Validation rerun complete.",
            createdAt = now,
            updatedAt = now
        )
        val state = DesktopAppState(issues = listOf(issue), runs = listOf(run))

        val decision = CompanyVerifierService().verifyIssueCompletion(state, issue, run)

        decision.passed shouldBe true
        decision.status shouldBe "PASS"
    }
})
