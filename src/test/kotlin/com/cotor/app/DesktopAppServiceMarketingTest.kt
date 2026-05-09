package com.cotor.app

import com.cotor.data.config.ConfigRepository
import com.cotor.domain.executor.AgentExecutor
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldHaveSize
import io.kotest.matchers.shouldBe
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
