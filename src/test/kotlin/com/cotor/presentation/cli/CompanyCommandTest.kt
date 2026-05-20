package com.cotor.presentation.cli

import com.cotor.app.Company
import com.cotor.app.CompanyAgentDefinition
import com.cotor.app.CompanyIssue
import com.cotor.app.DesktopAppService
import com.cotor.app.ReviewQueueItem
import com.cotor.app.ReviewQueueStatus
import com.cotor.app.RuntimeCleanupPreview
import com.cotor.app.RuntimeCleanupRequest
import com.cotor.app.RuntimeCleanupResult
import com.cotor.provenance.EvidenceBundle
import com.github.ajalt.clikt.testing.test
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import io.mockk.coEvery
import io.mockk.mockk
import org.koin.core.context.startKoin
import org.koin.core.context.stopKoin
import org.koin.dsl.module

class CompanyCommandTest : FunSpec({
    val service = mockk<DesktopAppService>(relaxed = true)

    beforeSpec {
        runCatching { stopKoin() }
        startKoin {
            modules(
                module {
                    single { service }
                }
            )
        }
    }

    afterSpec {
        stopKoin()
    }

    test("company list prints json companies") {
        coEvery { service.listCompanies() } returns listOf(
            Company(
                id = "company-1",
                name = "Test Company",
                rootPath = "/tmp/company",
                repositoryId = "repo-1",
                defaultBaseBranch = "master",
                createdAt = 1L,
                updatedAt = 2L
            )
        )

        val result = CompanyCommand().test("list")

        result.statusCode shouldBe 0
        result.output shouldContain "\"id\": \"company-1\""
        result.output shouldContain "\"name\": \"Test Company\""
    }

    test("company create can disable autonomy at creation time") {
        coEvery {
            service.createCompany(
                name = "Smoke",
                rootPath = "/tmp/company",
                defaultBaseBranch = null,
                autonomyEnabled = false,
                dailyBudgetCents = null,
                monthlyBudgetCents = null
            )
        } returns Company(
            id = "company-disabled",
            name = "Smoke",
            rootPath = "/tmp/company",
            repositoryId = "repo-1",
            defaultBaseBranch = "master",
            autonomyEnabled = false,
            createdAt = 1L,
            updatedAt = 2L
        )

        val result = CompanyCommand().test("create --name Smoke --root /tmp/company --autonomy-disabled")

        result.statusCode shouldBe 0
        result.output shouldContain "\"id\": \"company-disabled\""
        result.output shouldContain "\"autonomyEnabled\": false"
    }

    test("company agent batch-update forwards selected patch fields") {
        coEvery {
            service.batchUpdateCompanyAgentDefinitions(
                companyId = "company-1",
                agentIds = listOf("agent-1", "agent-2"),
                agentCli = "opencode",
                specialties = listOf("qa", "review"),
                enabled = false
            )
        } returns listOf(
            CompanyAgentDefinition(
                id = "agent-1",
                companyId = "company-1",
                title = "QA",
                agentCli = "opencode",
                roleSummary = "review",
                specialties = listOf("qa", "review"),
                enabled = false,
                displayOrder = 0,
                createdAt = 1L,
                updatedAt = 2L
            )
        )

        val result = CompanyCommand().test(
            "agent batch-update --company-id company-1 --agent-id agent-1 --agent-id agent-2 --agent-cli opencode --specialty qa --specialty review --enabled false"
        )

        result.statusCode shouldBe 0
        result.output shouldContain "\"agentCli\": \"opencode\""
        result.output shouldContain "\"enabled\": false"
    }

    test("company agent batch-update defaults to all company agents when no agent id is provided") {
        coEvery { service.listCompanyAgentDefinitions("company-1") } returns listOf(
            CompanyAgentDefinition(
                id = "agent-1",
                companyId = "company-1",
                title = "Builder",
                agentCli = "opencode",
                roleSummary = "build",
                displayOrder = 0,
                createdAt = 1L,
                updatedAt = 1L
            ),
            CompanyAgentDefinition(
                id = "agent-2",
                companyId = "company-1",
                title = "QA",
                agentCli = "opencode",
                roleSummary = "review",
                displayOrder = 1,
                createdAt = 1L,
                updatedAt = 1L
            )
        )
        coEvery {
            service.batchUpdateCompanyAgentDefinitions(
                companyId = "company-1",
                agentIds = listOf("agent-1", "agent-2"),
                agentCli = "opencode",
                model = "opencode/deepseek-v4-flash-free"
            )
        } returns listOf(
            CompanyAgentDefinition(
                id = "agent-1",
                companyId = "company-1",
                title = "Builder",
                agentCli = "opencode",
                model = "opencode/deepseek-v4-flash-free",
                roleSummary = "build",
                displayOrder = 0,
                createdAt = 1L,
                updatedAt = 2L
            )
        )

        val result = CompanyCommand().test(
            "agent batch-update --company-id company-1 --agent-cli opencode --model opencode/deepseek-v4-flash-free"
        )

        result.statusCode shouldBe 0
        result.output shouldContain "\"model\": \"opencode/deepseek-v4-flash-free\""
    }

    test("company agent capabilities prints backend profile") {
        coEvery { service.agentCapabilities("company-1", "agent-1") } returns com.cotor.app.AgentCapabilityProfile(
            companyId = "company-1",
            agentId = "agent-1"
        )

        val result = CompanyCommand().test("agent capabilities agent-1 --company-id company-1")

        result.statusCode shouldBe 0
        result.output shouldContain "\"agentId\": \"agent-1\""
        result.output shouldContain "SHELL_EXEC"
    }

    test("company agent capability set forwards one mode patch") {
        coEvery { service.agentCapabilities("company-1", "agent-1") } returns com.cotor.app.AgentCapabilityProfile(
            companyId = "company-1",
            agentId = "agent-1"
        )
        coEvery {
            service.updateAgentCapabilities(
                companyId = "company-1",
                agentId = "agent-1",
                settings = match { settings ->
                    settings[com.cotor.app.CapabilityKey.SHELL_EXEC]?.mode == com.cotor.app.CapabilityMode.AUTO
                }
            )
        } returns com.cotor.app.AgentCapabilityProfile(
            companyId = "company-1",
            agentId = "agent-1",
            settings = com.cotor.app.defaultAgentCapabilitySettings() + mapOf(
                com.cotor.app.CapabilityKey.SHELL_EXEC to com.cotor.app.AgentCapabilitySetting(
                    enabled = true,
                    mode = com.cotor.app.CapabilityMode.AUTO
                )
            )
        )

        val result = CompanyCommand().test("agent capability agent-1 SHELL_EXEC --company-id company-1 --mode AUTO")

        result.statusCode shouldBe 0
        result.output shouldContain "SHELL_EXEC"
        result.output shouldContain "AUTO"
    }

    test("company issue run waits for settled issue output") {
        coEvery { service.runIssueAndAwaitSettlement("issue-1") } returns CompanyIssue(
            id = "issue-1",
            companyId = "company-1",
            projectContextId = "project-1",
            goalId = "goal-1",
            workspaceId = "workspace-1",
            title = "Issue",
            description = "Do work",
            status = com.cotor.app.IssueStatus.DONE,
            createdAt = 1L,
            updatedAt = 2L
        )

        val result = CompanyCommand().test("issue run issue-1")

        result.statusCode shouldBe 0
        result.output shouldContain "\"id\": \"issue-1\""
        result.output shouldContain "\"status\": \"DONE\""
    }

    test("company issue run can use an explicit wait timeout") {
        coEvery { service.runIssueAndAwaitSettlement("issue-timeout", 5_000L) } returns CompanyIssue(
            id = "issue-timeout",
            companyId = "company-1",
            projectContextId = "project-1",
            goalId = "goal-1",
            workspaceId = "workspace-1",
            title = "Issue",
            description = "Do work",
            status = com.cotor.app.IssueStatus.DONE,
            createdAt = 1L,
            updatedAt = 2L
        )

        val result = CompanyCommand().test("issue run issue-timeout --wait-timeout-seconds 5")

        result.statusCode shouldBe 0
        result.output shouldContain "\"id\": \"issue-timeout\""
        result.output shouldContain "\"status\": \"DONE\""
    }

    test("company issue run supports explicit async start") {
        coEvery { service.runIssue("issue-async") } returns CompanyIssue(
            id = "issue-async",
            companyId = "company-1",
            projectContextId = "project-1",
            goalId = "goal-1",
            workspaceId = "workspace-1",
            title = "Issue",
            description = "Do work",
            status = com.cotor.app.IssueStatus.IN_PROGRESS,
            createdAt = 1L,
            updatedAt = 2L
        )

        val result = CompanyCommand().test("issue run issue-async --async")

        result.statusCode shouldBe 0
        result.output shouldContain "\"id\": \"issue-async\""
        result.output shouldContain "\"status\": \"IN_PROGRESS\""
        io.mockk.coVerify(exactly = 1) { service.runIssue("issue-async") }
    }

    test("evidence pr prints pull request evidence bundle") {
        coEvery { service.evidenceForPullRequest(12) } returns EvidenceBundle(query = "pr:12")

        val result = EvidenceCommand().test("pr 12")

        result.statusCode shouldBe 0
        result.output shouldContain "\"query\": \"pr:12\""
    }

    test("skill run prints backend skill payload") {
        coEvery { service.runSkill("graphify", "company-1", "agent-1", "map-repo") } returns com.cotor.app.SkillRunResult(
            skill = "graphify",
            status = "COMPLETED",
            capability = com.cotor.app.CapabilitySimulationResult(
                action = "skill.run",
                capability = com.cotor.app.CapabilityKey.SKILL_RUN,
                mode = com.cotor.app.CapabilityMode.AUTO,
                allowed = true,
                reason = "allowed"
            ),
            summary = "Graphify returned repository map evidence.",
            output = "Graphify returned repository map evidence."
        )

        val result = SkillCommand().test("run graphify --company company-1 --agent agent-1 --input map-repo")

        result.statusCode shouldBe 0
        result.output shouldContain "\"skill\": \"graphify\""
        result.output shouldContain "\"status\": \"COMPLETED\""
    }

    test("provider test prints provider availability payload") {
        io.mockk.every { service.testProvider("gh") } returns com.cotor.app.ProviderScanResult(
            provider = com.cotor.app.ProviderCatalogEntry(
                id = "gh",
                displayName = "GitHub CLI",
                command = "gh",
                capabilities = listOf(com.cotor.app.CapabilityKey.GITHUB_READ)
            ),
            available = true,
            message = "gh is available on PATH."
        )

        val result = ProviderCommand().test("test gh")

        result.statusCode shouldBe 0
        result.output shouldContain "\"id\": \"gh\""
        result.output shouldContain "\"available\": true"
    }

    test("capability inspect and simulate print backend capability payloads") {
        coEvery {
            service.simulateAgentCapability(
                companyId = "company-1",
                agentId = "agent-1",
                action = "browser.external-domain",
                path = null,
                networkTarget = "example.com",
                command = null,
                skill = null
            )
        } returns com.cotor.app.CapabilitySimulationResult(
            action = "browser.external-domain",
            capability = com.cotor.app.CapabilityKey.BROWSER_EXTERNAL_DOMAIN,
            mode = com.cotor.app.CapabilityMode.DISABLED,
            allowed = false,
            reason = "disabled"
        )

        val inspect = CapabilityCommand().test("inspect browser.external-domain")
        val simulate = CapabilityCommand().test("simulate --company company-1 --agent agent-1 --action browser.external-domain --network-target example.com")

        inspect.statusCode shouldBe 0
        inspect.output shouldContain "BROWSER_EXTERNAL_DOMAIN"
        simulate.statusCode shouldBe 0
        simulate.output shouldContain "\"allowed\": false"
    }

    test("browser smoke prints guarded browser plan") {
        coEvery {
            service.planBrowserSmoke(
                com.cotor.app.BrowserSmokeRequest(
                    companyId = "company-1",
                    agentId = "agent-1",
                    url = "http://127.0.0.1:3000",
                    screenshot = true
                )
            )
        } returns com.cotor.app.BrowserSmokeResult(
            url = "http://127.0.0.1:3000",
            status = "READY",
            checks = listOf(
                com.cotor.app.CapabilitySimulationResult(
                    action = "browser.read",
                    capability = com.cotor.app.CapabilityKey.BROWSER_READ,
                    mode = com.cotor.app.CapabilityMode.AUTO,
                    allowed = true,
                    reason = "allowed"
                )
            ),
            command = listOf("playwright", "open", "http://127.0.0.1:3000", "--screenshot"),
            message = "Browser smoke is allowed."
        )

        val result = BrowserCommand().test("smoke --company company-1 --agent agent-1 --url http://127.0.0.1:3000 --screenshot")

        result.statusCode shouldBe 0
        result.output shouldContain "\"status\": \"READY\""
        result.output shouldContain "--screenshot"
    }

    test("video plan prints guarded video plan") {
        coEvery {
            service.planVideoScript(
                com.cotor.app.VideoPlanRequest(
                    companyId = "company-1",
                    agentId = "agent-1",
                    issueId = "issue-1",
                    projectPath = "/tmp/video"
                )
            )
        } returns com.cotor.app.VideoPlanResult(
            action = "video.script-write",
            status = "READY",
            checks = listOf(
                com.cotor.app.CapabilitySimulationResult(
                    action = "video.script-write",
                    capability = com.cotor.app.CapabilityKey.VIDEO_SCRIPT_WRITE,
                    mode = com.cotor.app.CapabilityMode.AUTO,
                    allowed = true,
                    reason = "allowed"
                )
            ),
            command = listOf("video-plan", "--issue=issue-1", "--project=/tmp/video"),
            message = "Video script planning is allowed."
        )

        val result = VideoCommand().test("plan --company company-1 --agent agent-1 --issue issue-1 --project /tmp/video")

        result.statusCode shouldBe 0
        result.output shouldContain "\"action\": \"video.script-write\""
        result.output shouldContain "\"status\": \"READY\""
    }

    test("company issue show uses the projected issue path") {
        coEvery { service.getIssueProjected("issue-2") } returns CompanyIssue(
            id = "issue-2",
            companyId = "company-1",
            projectContextId = "project-1",
            goalId = "goal-1",
            workspaceId = "workspace-1",
            title = "Projected Issue",
            description = "desc",
            status = com.cotor.app.IssueStatus.IN_PROGRESS,
            runtimeDisposition = "RUNNABLE",
            createdAt = 1L,
            updatedAt = 2L
        )

        val result = CompanyCommand().test("issue show issue-2")

        result.statusCode shouldBe 0
        result.output shouldContain "\"id\": \"issue-2\""
        result.output shouldContain "\"runtimeDisposition\": \"RUNNABLE\""
    }

    test("company dashboard uses the read-only dashboard path") {
        coEvery { service.companyDashboardReadOnly("company-1") } returns com.cotor.app.CompanyDashboardResponse()

        val result = CompanyCommand().test("dashboard --company-id company-1")

        result.statusCode shouldBe 0
        result.output shouldContain "\"companies\""
        io.mockk.coVerify(exactly = 1) { service.companyDashboardReadOnly("company-1") }
        io.mockk.coVerify(exactly = 0) { service.companyDashboard("company-1") }
    }

    test("company review qa forwards verdict and feedback") {
        coEvery { service.submitQaReviewVerdict("item-1", "PASS", "looks good") } returns ReviewQueueItem(
            id = "item-1",
            issueId = "issue-1",
            runId = "run-1",
            status = ReviewQueueStatus.READY_FOR_CEO,
            qaVerdict = "PASS",
            qaFeedback = "looks good",
            createdAt = 1L,
            updatedAt = 2L
        )

        val result = CompanyCommand().test("review qa item-1 --verdict PASS --feedback 'looks good'")

        result.statusCode shouldBe 0
        result.output shouldContain "\"id\": \"item-1\""
        result.output shouldContain "\"qaVerdict\": \"PASS\""
    }

    test("company review ceo forwards verdict and feedback") {
        coEvery { service.submitCeoReviewVerdict("item-2", "APPROVE", "ship it") } returns ReviewQueueItem(
            id = "item-2",
            issueId = "issue-2",
            runId = "run-2",
            status = ReviewQueueStatus.READY_FOR_CEO,
            ceoVerdict = "APPROVE",
            ceoFeedback = "ship it",
            createdAt = 1L,
            updatedAt = 2L
        )

        val result = CompanyCommand().test("review ceo item-2 --verdict APPROVE --feedback 'ship it'")

        result.statusCode shouldBe 0
        result.output shouldContain "\"id\": \"item-2\""
        result.output shouldContain "\"ceoVerdict\": \"APPROVE\""
    }

    test("company runtime cleanup defaults to dry-run and can apply explicitly") {
        val preview = RuntimeCleanupPreview(
            companyId = "company-1",
            allCompanies = false,
            generatedAt = 1,
            terminalRetentionDays = 7,
            orphanRetentionDays = 14
        )
        coEvery {
            service.cleanupRuntime(
                RuntimeCleanupRequest(
                    companyId = "company-1",
                    allCompanies = false,
                    olderThanDays = null,
                    dryRun = true,
                    apply = false
                )
            )
        } returns RuntimeCleanupResult(dryRun = true, preview = preview)
        coEvery {
            service.cleanupRuntime(
                RuntimeCleanupRequest(
                    companyId = "company-1",
                    allCompanies = false,
                    olderThanDays = null,
                    dryRun = false,
                    apply = true
                )
            )
        } returns RuntimeCleanupResult(dryRun = false, preview = preview, deletedWorktreeCount = 1)

        val dryRun = CompanyCommand().test("runtime cleanup --company-id company-1")
        val apply = CompanyCommand().test("runtime cleanup --company-id company-1 --apply")

        dryRun.statusCode shouldBe 0
        dryRun.output shouldContain "\"dryRun\": true"
        apply.statusCode shouldBe 0
        apply.output shouldContain "\"dryRun\": false"
        apply.output shouldContain "\"deletedWorktreeCount\": 1"
    }

    test("completion output includes company and auth nested commands") {
        val result = CompletionCommand().test("bash")

        result.statusCode shouldBe 0
        result.output shouldContain "company"
        result.output shouldContain "batch-update"
        result.output shouldContain "cleanup"
        result.output shouldContain "codex-oauth"
    }
})
