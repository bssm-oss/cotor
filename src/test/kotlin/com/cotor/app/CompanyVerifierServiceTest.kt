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
})
