package com.cotor.app

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContain
import io.kotest.matchers.nulls.shouldBeNull
import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import java.nio.file.Files

class AutonomousDiscoveryServiceTest : FunSpec({
    test("scan records internal quality signals and cooldown suppresses duplicate triage") {
        val now = 1_800_000L
        val repoRoot = Files.createTempDirectory("autonomous-discovery-repo")
        Files.createDirectories(repoRoot.resolve("graphify-out"))
        Files.writeString(repoRoot.resolve("graphify-out").resolve("GRAPH_REPORT.md"), "# graph")
        val company = Company(
            id = "company-1",
            name = "Discovery Co",
            rootPath = repoRoot.toString(),
            repositoryId = "repo-1",
            defaultBaseBranch = "main",
            createdAt = 1,
            updatedAt = 1
        )
        val issue = CompanyIssue(
            id = "issue-1",
            companyId = company.id,
            goalId = "goal-1",
            workspaceId = "workspace-1",
            title = "Blocked implementation",
            description = "Needs autonomous triage.",
            status = IssueStatus.BLOCKED,
            kind = "execution",
            createdAt = 1,
            updatedAt = 1
        )
        val state = DesktopAppState(companies = listOf(company), issues = listOf(issue))
        val service = AutonomousDiscoveryService(
            signalCooldownMs = 60_000L,
            staleBlockedIssueMs = 1_000L
        )

        val scan = service.scan(state, company.id, now)

        scan.signals.map { it.kind }.shouldContain("stale-blocked-issue")
        scan.actionableSignal shouldNotBe null
        val triaged = service.markTriaged(scan.signals, scan.actionableSignal!!.id, triageGoalId = "goal-triage", now = now)
        val cooledState = state.copy(
            problemSignals = triaged,
            goals = listOf(
                CompanyGoal(
                    id = "goal-triage",
                    companyId = company.id,
                    title = "Triage discovery signal",
                    description = "Investigate.",
                    status = GoalStatus.ACTIVE,
                    operatingPolicy = "auto-discovery:${scan.actionableSignal!!.id}",
                    createdAt = now,
                    updatedAt = now
                )
            )
        )

        val rescan = service.scan(cooledState, company.id, now + 1_000L)

        rescan.signals.count { it.dedupeKey == scan.actionableSignal!!.dedupeKey } shouldBe 1
        rescan.actionableSignal.shouldBeNull()
    }
})
