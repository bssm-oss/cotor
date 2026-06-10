package com.cotor.app

import com.cotor.data.config.ConfigRepository
import com.cotor.domain.executor.AgentExecutor
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldHaveSize
import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import io.kotest.matchers.string.shouldContain
import io.mockk.mockk
import java.nio.file.Files

class DesktopAppServiceMarketingTest : FunSpec({
    afterTest {
        DesktopAppService.shutdownAllForTesting()
    }

    test("marketing delegation policy opens scoped browser and publish capabilities and records a browser run") {
        val appHome = Files.createTempDirectory("desktop-marketing-home")
        val runner = RecordingMarketingBrowserRunner()
        val service = marketingService(appHome, runner)
        val company = service.createCompany(name = "Marketing Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Marketing Operator" }

        val policy = service.upsertMarketingDelegationPolicy(
            UpsertMarketingDelegationPolicyRequest(
                companyId = company.id,
                agentId = agent.id,
                allowedDomains = listOf("cms.example.com"),
                channelAccounts = listOf(
                    MarketingChannelAccount(channel = "web", accountRef = "cms", allowedDomains = listOf("cms.example.com"))
                ),
                dailyPostLimit = 2,
                brandTone = "Helpful and precise"
            )
        )
        val profile = service.agentCapabilities(company.id, agent.id)
        val browserSetting = profile.settings.getValue(CapabilityKey.BROWSER_READ)

        val run = service.createMarketingRun(
            MarketingRunRequest(
                companyId = company.id,
                agentId = agent.id,
                objective = "Publish an owned web update about Cotor workflows",
                channels = listOf("web"),
                delegationPolicyId = policy.id
            )
        )

        browserSetting.mode shouldBe CapabilityMode.AUTO
        browserSetting.domainAllowlist shouldBe listOf("cms.example.com")
        browserSetting.channelAllowlist shouldBe listOf("web")
        runner.commands.shouldHaveSize(1)
        runner.commands.single().targetUrl shouldContain "cms.example.com"
        run.status shouldBe MarketingRunStatus.COMPLETED
        run.actions.single().status shouldBe MarketingActionStatus.SUCCEEDED
        service.marketingRun(run.id)?.id shouldBe run.id
    }

    test("analytics reporter uses marketing policy scope when checking delegated analytics access") {
        val appHome = Files.createTempDirectory("desktop-marketing-policy-analytics-home")
        val runner = RecordingMarketingBrowserRunner()
        val service = marketingService(appHome, runner)
        val company = service.createCompany(name = "Marketing Analytics Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Marketing Operator" }
        service.upsertMarketingDelegationPolicy(
            UpsertMarketingDelegationPolicyRequest(
                companyId = company.id,
                agentId = agent.id,
                allowedDomains = listOf("cms.example.com"),
                channelAccounts = listOf(
                    MarketingChannelAccount(channel = "web", accountRef = "cms", allowedDomains = listOf("cms.example.com"))
                ),
                dailyPostLimit = 2
            )
        )
        service.createMarketingRun(
            MarketingRunRequest(
                companyId = company.id,
                agentId = agent.id,
                objective = "Publish an owned web update",
                channels = listOf("web")
            )
        )
        service.updateAgentCapabilities(
            companyId = company.id,
            agentId = agent.id,
            settings = mapOf(
                CapabilityKey.SKILL_RUN to AgentCapabilitySetting(
                    enabled = true,
                    mode = CapabilityMode.AUTO,
                    skillAllowlist = listOf("analytics-reporter")
                )
            )
        )

        val result = service.runSkill(
            name = "analytics-reporter",
            companyId = company.id,
            agentId = agent.id,
            input = "Summarize recent marketing runs"
        )

        result.status shouldBe "COMPLETED"
        result.actions.single() shouldBe "summarized 1 marketing run(s)"
        result.output shouldContain "Succeeded actions: 1"
    }

    test("marketing delegation policy denies forbidden terms, outside channels, and daily limit overflow") {
        val appHome = Files.createTempDirectory("desktop-marketing-deny-home")
        val runner = RecordingMarketingBrowserRunner()
        val service = marketingService(appHome, runner)
        val company = service.createCompany(name = "Marketing Deny Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Marketing Operator" }
        val policy = service.upsertMarketingDelegationPolicy(
            UpsertMarketingDelegationPolicyRequest(
                companyId = company.id,
                agentId = agent.id,
                allowedDomains = listOf("cms.example.com"),
                channelAccounts = listOf(
                    MarketingChannelAccount(channel = "web", accountRef = "cms", allowedDomains = listOf("cms.example.com"))
                ),
                dailyPostLimit = 1,
                forbiddenTerms = listOf("unapproved")
            )
        )

        val forbidden = service.createMarketingRun(
            MarketingRunRequest(
                companyId = company.id,
                agentId = agent.id,
                objective = "Publish an unapproved launch claim",
                channels = listOf("web"),
                delegationPolicyId = policy.id
            )
        )
        val outsideChannel = service.createMarketingRun(
            MarketingRunRequest(
                companyId = company.id,
                agentId = agent.id,
                objective = "Publish a scoped update",
                channels = listOf("x"),
                delegationPolicyId = policy.id
            )
        )
        val firstAllowed = service.createMarketingRun(
            MarketingRunRequest(
                companyId = company.id,
                agentId = agent.id,
                objective = "Publish a scoped product update",
                channels = listOf("web"),
                delegationPolicyId = policy.id
            )
        )
        val overLimit = service.createMarketingRun(
            MarketingRunRequest(
                companyId = company.id,
                agentId = agent.id,
                objective = "Publish another scoped product update",
                channels = listOf("web"),
                delegationPolicyId = policy.id
            )
        )

        forbidden.status shouldBe MarketingRunStatus.DENIED
        forbidden.error shouldContain "forbidden term"
        outsideChannel.status shouldBe MarketingRunStatus.DENIED
        outsideChannel.error shouldContain "outside the MarketingDelegationPolicy"
        firstAllowed.status shouldBe MarketingRunStatus.COMPLETED
        overLimit.status shouldBe MarketingRunStatus.DENIED
        overLimit.error shouldContain "daily post limit"
        runner.commands.shouldHaveSize(1)
    }

    test("marketing skill runners connect to MarketingRun and preserve policy denials") {
        val appHome = Files.createTempDirectory("desktop-marketing-skill-home")
        val runner = RecordingMarketingBrowserRunner()
        val service = marketingService(appHome, runner)
        val company = service.createCompany(name = "Marketing Skill Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Marketing Operator" }
        service.upsertMarketingDelegationPolicy(
            UpsertMarketingDelegationPolicyRequest(
                companyId = company.id,
                agentId = agent.id,
                allowedDomains = listOf("cms.example.com"),
                channelAccounts = listOf(
                    MarketingChannelAccount(channel = "web", accountRef = "cms", allowedDomains = listOf("cms.example.com"))
                ),
                dailyPostLimit = 2
            )
        )

        val completed = service.runSkill(
            name = "content-publisher",
            companyId = company.id,
            agentId = agent.id,
            input = "Publish a delegated product update",
            parameters = mapOf("channels" to "web")
        )
        val denied = service.runSkill(
            name = "social-publisher",
            companyId = company.id,
            agentId = agent.id,
            input = "Post a delegated update",
            parameters = mapOf("channels" to "web")
        )

        completed.status shouldBe "COMPLETED"
        completed.evidence.any { it.type == "screenshot" } shouldBe true
        denied.status shouldBe "DENIED"
        denied.error shouldContain "Requested channels"
        runner.commands.shouldHaveSize(1)
    }

    test("marketing browser screenshot-only no-op is recorded as failed instead of completed") {
        val appHome = Files.createTempDirectory("desktop-marketing-noop-home")
        val runner = NoOpMarketingBrowserRunner()
        val service = marketingService(appHome, runner)
        val company = service.createCompany(name = "Marketing Noop Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Marketing Operator" }
        service.upsertMarketingDelegationPolicy(
            UpsertMarketingDelegationPolicyRequest(
                companyId = company.id,
                agentId = agent.id,
                allowedDomains = listOf("cms.example.com"),
                channelAccounts = listOf(
                    MarketingChannelAccount(channel = "web", accountRef = "cms", allowedDomains = listOf("cms.example.com"))
                ),
                dailyPostLimit = 2
            )
        )

        val run = service.createMarketingRun(
            MarketingRunRequest(
                companyId = company.id,
                agentId = agent.id,
                objective = "Publish an owned web update",
                channels = listOf("web")
            )
        )
        val skillRun = service.runSkill(
            name = "content-publisher",
            companyId = company.id,
            agentId = agent.id,
            input = "Publish a delegated product update",
            parameters = mapOf("channels" to "web")
        )

        run.status shouldBe MarketingRunStatus.FAILED
        run.actions.single().status shouldBe MarketingActionStatus.FAILED
        run.error shouldContain "did not expose an editable field"
        skillRun.status shouldBe "FAILED"
        skillRun.error shouldContain "did not expose an editable field"
    }

    test("analytics reporter without marketing runs is not marked completed") {
        val appHome = Files.createTempDirectory("desktop-marketing-empty-analytics-home")
        val service = marketingService(appHome, RecordingMarketingBrowserRunner())
        val company = service.createCompany(name = "Marketing Empty Analytics Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Marketing Operator" }
        service.upsertMarketingDelegationPolicy(
            UpsertMarketingDelegationPolicyRequest(
                companyId = company.id,
                agentId = agent.id,
                allowedDomains = listOf("cms.example.com"),
                channelAccounts = listOf(
                    MarketingChannelAccount(channel = "web", accountRef = "cms", allowedDomains = listOf("cms.example.com"))
                ),
                dailyPostLimit = 2
            )
        )
        val auto = AgentCapabilitySetting(enabled = true, mode = CapabilityMode.AUTO)
        service.updateAgentCapabilities(
            companyId = company.id,
            agentId = agent.id,
            settings = mapOf(
                CapabilityKey.SKILL_RUN to auto,
                CapabilityKey.MARKETING_ANALYTICS_READ to auto
            )
        )

        val result = service.runSkill(
            name = "analytics-reporter",
            companyId = company.id,
            agentId = agent.id,
            input = "Summarize recent marketing runs"
        )

        result.status shouldBe "FAILED_SETUP"
        result.error shouldContain "No MarketingRun evidence"
        result.actions.single() shouldBe "summarized 0 marketing run(s)"
    }

    test("browserSessionRef raw file path is rejected at policy save time") {
        val appHome = Files.createTempDirectory("desktop-marketing-session-ref-home")
        val service = marketingService(appHome, RecordingMarketingBrowserRunner())
        val company = service.createCompany(name = "Session Ref Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Marketing Operator" }
        val request = UpsertMarketingDelegationPolicyRequest(
            companyId = company.id,
            agentId = agent.id,
            allowedDomains = listOf("cms.example.com"),
            channelAccounts = listOf(MarketingChannelAccount(channel = "web", accountRef = "cms")),
            browserSessionRef = "/home/user/.config/browser/Default/Cookies"
        )
        shouldThrow<IllegalArgumentException> { service.upsertMarketingDelegationPolicy(request) }
            .message shouldContain "session://"
    }

    test("browserSessionRef file:// scheme is rejected at policy save time") {
        val appHome = Files.createTempDirectory("desktop-marketing-session-ref-file-home")
        val service = marketingService(appHome, RecordingMarketingBrowserRunner())
        val company = service.createCompany(name = "Session File Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Marketing Operator" }
        shouldThrow<IllegalArgumentException> {
            service.upsertMarketingDelegationPolicy(
                UpsertMarketingDelegationPolicyRequest(
                    companyId = company.id,
                    agentId = agent.id,
                    allowedDomains = listOf("cms.example.com"),
                    channelAccounts = listOf(MarketingChannelAccount(channel = "web", accountRef = "cms")),
                    browserSessionRef = "file:///var/secret/session.json"
                )
            )
        }
    }

    test("browserSessionRef path traversal in session id is rejected at policy save time") {
        val appHome = Files.createTempDirectory("desktop-marketing-session-ref-traversal-home")
        val service = marketingService(appHome, RecordingMarketingBrowserRunner())
        val company = service.createCompany(name = "Traversal Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Marketing Operator" }
        shouldThrow<IllegalArgumentException> {
            service.upsertMarketingDelegationPolicy(
                UpsertMarketingDelegationPolicyRequest(
                    companyId = company.id,
                    agentId = agent.id,
                    allowedDomains = listOf("cms.example.com"),
                    channelAccounts = listOf(MarketingChannelAccount(channel = "web", accountRef = "cms")),
                    browserSessionRef = "session://../../etc/passwd"
                )
            )
        }
    }

    test("browserSessionRef session:// scheme with safe id is accepted at policy save time") {
        val appHome = Files.createTempDirectory("desktop-marketing-session-ref-ok-home")
        val service = marketingService(appHome, RecordingMarketingBrowserRunner())
        val company = service.createCompany(name = "Session OK Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Marketing Operator" }
        val policy = service.upsertMarketingDelegationPolicy(
            UpsertMarketingDelegationPolicyRequest(
                companyId = company.id,
                agentId = agent.id,
                allowedDomains = listOf("cms.example.com"),
                channelAccounts = listOf(MarketingChannelAccount(channel = "web", accountRef = "cms")),
                browserSessionRef = "session://abc123"
            )
        )
        policy.browserSessionRef shouldBe "session://abc123"
    }

    test("resolveMarketingSessionRef does not pass path to runner when session file does not exist") {
        val appHome = Files.createTempDirectory("desktop-marketing-resolve-home")
        val runner = RecordingMarketingBrowserRunner()
        val service = marketingService(appHome, runner)
        val company = service.createCompany(name = "Resolve Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Marketing Operator" }
        service.upsertMarketingDelegationPolicy(
            UpsertMarketingDelegationPolicyRequest(
                companyId = company.id,
                agentId = agent.id,
                allowedDomains = listOf("cms.example.com"),
                channelAccounts = listOf(MarketingChannelAccount(channel = "web", accountRef = "cms")),
                dailyPostLimit = 2,
                browserSessionRef = "session://nonexistent-session-id"
            )
        )
        service.createMarketingRun(
            MarketingRunRequest(
                companyId = company.id,
                agentId = agent.id,
                objective = "Publish a product update",
                channels = listOf("web")
            )
        )
        runner.commands.shouldHaveSize(1)
        runner.commands.single().browserSessionRef shouldBe null
    }

    test("resolveMarketingSessionRef passes canonical path when session file exists within sessions dir") {
        val appHome = Files.createTempDirectory("desktop-marketing-resolve-exists-home")
        val runner = RecordingMarketingBrowserRunner()
        val service = marketingService(appHome, runner)
        val sessionsDir = appHome.resolve("runtime/marketing-browser/sessions")
        Files.createDirectories(sessionsDir)
        val sessionFile = sessionsDir.resolve("my-session.json")
        sessionFile.toFile().writeText("{}")
        val company = service.createCompany(name = "Resolve Exists Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Marketing Operator" }
        service.upsertMarketingDelegationPolicy(
            UpsertMarketingDelegationPolicyRequest(
                companyId = company.id,
                agentId = agent.id,
                allowedDomains = listOf("cms.example.com"),
                channelAccounts = listOf(MarketingChannelAccount(channel = "web", accountRef = "cms")),
                dailyPostLimit = 2,
                browserSessionRef = "session://my-session"
            )
        )
        service.createMarketingRun(
            MarketingRunRequest(
                companyId = company.id,
                agentId = agent.id,
                objective = "Publish a product update",
                channels = listOf("web")
            )
        )
        runner.commands.shouldHaveSize(1)
        runner.commands.single().browserSessionRef shouldNotBe null
        runner.commands.single().browserSessionRef shouldContain "my-session.json"
    }

    test("content and social skill runners default to only their delegated channel class") {
        val appHome = Files.createTempDirectory("desktop-marketing-skill-scope-home")
        val runner = RecordingMarketingBrowserRunner()
        val service = marketingService(appHome, runner)
        val company = service.createCompany(name = "Marketing Skill Scope Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Marketing Operator" }
        service.upsertMarketingDelegationPolicy(
            UpsertMarketingDelegationPolicyRequest(
                companyId = company.id,
                agentId = agent.id,
                allowedDomains = listOf("cms.example.com", "social.example.com"),
                channelAccounts = listOf(
                    MarketingChannelAccount(channel = "web", accountRef = "cms", allowedDomains = listOf("cms.example.com")),
                    MarketingChannelAccount(channel = "x", accountRef = "owned-social", allowedDomains = listOf("social.example.com"))
                ),
                dailyPostLimit = 4
            )
        )

        val content = service.runSkill(
            name = "content-publisher",
            companyId = company.id,
            agentId = agent.id,
            input = "Publish an owned product update"
        )
        val social = service.runSkill(
            name = "social-publisher",
            companyId = company.id,
            agentId = agent.id,
            input = "Post an owned social update"
        )

        content.status shouldBe "COMPLETED"
        social.status shouldBe "COMPLETED"
        content.actions.single() shouldContain "web:"
        social.actions.single() shouldContain "x:"
        runner.commands.shouldHaveSize(2)
    }

    test("Threads and Product Hunt skill runners require matching delegated channels") {
        val appHome = Files.createTempDirectory("desktop-marketing-launch-channel-home")
        val runner = RecordingMarketingBrowserRunner()
        val service = marketingService(appHome, runner)
        val company = service.createCompany(name = "Launch Channel Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Marketing Operator" }
        service.upsertMarketingDelegationPolicy(
            UpsertMarketingDelegationPolicyRequest(
                companyId = company.id,
                agentId = agent.id,
                allowedDomains = listOf("threads.net", "producthunt.com"),
                channelAccounts = listOf(
                    MarketingChannelAccount(channel = "threads", accountRef = "threads-owned", allowedDomains = listOf("threads.net")),
                    MarketingChannelAccount(channel = "producthunt", accountRef = "ph-owned", allowedDomains = listOf("producthunt.com"))
                ),
                dailyPostLimit = 4
            )
        )

        val threads = service.runSkill(
            name = "threads-publisher",
            companyId = company.id,
            agentId = agent.id,
            input = "Publish a Threads launch update"
        )
        val productHunt = service.runSkill(
            name = "producthunt-publisher",
            companyId = company.id,
            agentId = agent.id,
            input = "Publish Product Hunt launch copy"
        )
        val denied = service.runSkill(
            name = "producthunt-publisher",
            companyId = company.id,
            agentId = agent.id,
            input = "Publish to the wrong channel",
            parameters = mapOf("channels" to "threads")
        )

        threads.status shouldBe "COMPLETED"
        productHunt.status shouldBe "COMPLETED"
        denied.status shouldBe "DENIED"
        threads.actions.single() shouldContain "threads:"
        productHunt.actions.single() shouldContain "producthunt:"
        runner.commands.shouldHaveSize(2)
    }
})

private fun marketingService(
    appHome: java.nio.file.Path,
    runner: MarketingBrowserRunner
): DesktopAppService =
    DesktopAppService(
        stateStore = DesktopStateStore { appHome },
        gitWorkspaceService = mockk(relaxed = true),
        configRepository = mockk<ConfigRepository>(relaxed = true),
        agentExecutor = mockk<AgentExecutor>(relaxed = true),
        commandAvailability = { command -> command in setOf("opencode", "npx") },
        marketingBrowserRunner = runner
    )

private class RecordingMarketingBrowserRunner : MarketingBrowserRunner {
    val commands = mutableListOf<MarketingBrowserCommand>()

    override suspend fun execute(command: MarketingBrowserCommand): MarketingBrowserResult {
        commands += command
        return MarketingBrowserResult(
            targetUrl = command.targetUrl,
            postedUrl = command.targetUrl,
            screenshotPath = command.screenshotPath,
            inputSummary = command.inputSummary
        )
    }
}

private class NoOpMarketingBrowserRunner : MarketingBrowserRunner {
    override suspend fun execute(command: MarketingBrowserCommand): MarketingBrowserResult =
        MarketingBrowserResult(
            targetUrl = command.targetUrl,
            postedUrl = command.targetUrl,
            screenshotPath = command.screenshotPath,
            inputSummary = "${command.channel}: no editable field; no publish button"
        )
}
