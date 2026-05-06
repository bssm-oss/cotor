package com.cotor.app

import com.cotor.data.config.ConfigRepository
import com.cotor.domain.executor.AgentExecutor
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldHaveSize
import io.kotest.matchers.shouldBe
import io.mockk.mockk
import java.nio.file.Files

class DesktopAppServiceMarketingTest : FunSpec({
    test("marketing delegation policy opens allowlist based AUTO capabilities and run records browser action") {
        val appHome = Files.createTempDirectory("desktop-marketing-home")
        val stateStore = DesktopStateStore { appHome }
        stateStore.save(marketingState())
        val runner = FakeMarketingBrowserRunner()
        val service = marketingService(stateStore, runner)

        val policy = service.upsertMarketingDelegationPolicy(
            UpsertMarketingDelegationPolicyRequest(
                companyId = "company-1",
                agentId = "agent-marketing",
                allowedDomains = listOf("cms.example.com"),
                channelAccounts = listOf(MarketingChannelAccount(channel = "web", allowedDomains = listOf("cms.example.com"))),
                dailyPostLimit = 2,
                brandTone = "Helpful and precise",
                secretRefs = listOf("secret://cms/session"),
                browserSessionRef = appHome.resolve("storage-state.json").toString()
            )
        )
        val run = service.createMarketingRun(
            MarketingRunRequest(
                companyId = "company-1",
                agentId = "agent-marketing",
                objective = "Publish launch notes for owned audience",
                channels = listOf("web"),
                delegationPolicyId = policy.id
            )
        )
        val profile = service.agentCapabilities("company-1", "agent-marketing")

        run.status shouldBe MarketingRunStatus.COMPLETED
        run.actions shouldHaveSize 1
        run.actions.single().status shouldBe MarketingActionStatus.SUCCEEDED
        run.actions.single().postedUrl shouldBe "https://cms.example.com/published"
        runner.calls shouldBe 1
        profile.settings.getValue(CapabilityKey.BROWSER_READ).mode shouldBe CapabilityMode.AUTO
        profile.settings.getValue(CapabilityKey.BROWSER_READ).domainAllowlist shouldBe listOf("cms.example.com")
        profile.settings.getValue(CapabilityKey.BROWSER_READ).channelAllowlist shouldBe listOf("web")
        profile.settings.getValue(CapabilityKey.WEB_PUBLISH).mode shouldBe CapabilityMode.AUTO
    }

    test("marketing run denies policy-outside channels, forbidden terms, and daily post overflow without approval") {
        val appHome = Files.createTempDirectory("desktop-marketing-deny-home")
        val stateStore = DesktopStateStore { appHome }
        stateStore.save(marketingState())
        val runner = FakeMarketingBrowserRunner()
        val service = marketingService(stateStore, runner)
        val policy = service.upsertMarketingDelegationPolicy(
            UpsertMarketingDelegationPolicyRequest(
                companyId = "company-1",
                agentId = "agent-marketing",
                allowedDomains = listOf("cms.example.com"),
                channelAccounts = listOf(MarketingChannelAccount(channel = "web", allowedDomains = listOf("cms.example.com"))),
                dailyPostLimit = 1,
                forbiddenTerms = listOf("unapproved")
            )
        )

        val forbidden = service.createMarketingRun(
            MarketingRunRequest(
                companyId = "company-1",
                agentId = "agent-marketing",
                objective = "Publish unapproved announcement",
                channels = listOf("web"),
                delegationPolicyId = policy.id
            )
        )
        val wrongChannel = service.createMarketingRun(
            MarketingRunRequest(
                companyId = "company-1",
                agentId = "agent-marketing",
                objective = "Publish launch notes",
                channels = listOf("x"),
                delegationPolicyId = policy.id
            )
        )
        val firstAllowed = service.createMarketingRun(
            MarketingRunRequest(
                companyId = "company-1",
                agentId = "agent-marketing",
                objective = "Publish first daily post",
                channels = listOf("web"),
                delegationPolicyId = policy.id
            )
        )
        val limitExceeded = service.createMarketingRun(
            MarketingRunRequest(
                companyId = "company-1",
                agentId = "agent-marketing",
                objective = "Publish second daily post",
                channels = listOf("web"),
                delegationPolicyId = policy.id
            )
        )

        forbidden.status shouldBe MarketingRunStatus.DENIED
        forbidden.error?.contains("forbidden term") shouldBe true
        wrongChannel.status shouldBe MarketingRunStatus.DENIED
        wrongChannel.error?.contains("not delegated") shouldBe true
        firstAllowed.status shouldBe MarketingRunStatus.COMPLETED
        limitExceeded.status shouldBe MarketingRunStatus.DENIED
        limitExceeded.error?.contains("daily post limit") shouldBe true
        runner.calls shouldBe 1
    }
})

private class FakeMarketingBrowserRunner : MarketingBrowserRunner {
    var calls: Int = 0

    override suspend fun execute(command: MarketingBrowserCommand, timeoutSeconds: Int): MarketingBrowserResult {
        calls += 1
        return MarketingBrowserResult(
            postedUrl = "https://cms.example.com/published",
            screenshotPath = command.screenshotPath,
            inputSummary = "${command.channel} form filled",
            outputSummary = "published"
        )
    }
}

private fun marketingService(
    stateStore: DesktopStateStore,
    runner: MarketingBrowserRunner
): DesktopAppService =
    DesktopAppService(
        stateStore = stateStore,
        gitWorkspaceService = mockk(relaxed = true),
        configRepository = mockk<ConfigRepository>(relaxed = true),
        agentExecutor = mockk<AgentExecutor>(relaxed = true),
        marketingBrowserRunner = runner
    )

private fun marketingState(): DesktopAppState =
    DesktopAppState(
        companies = listOf(
            Company(
                id = "company-1",
                name = "Marketing Co",
                rootPath = "/tmp/marketing-co",
                repositoryId = "repo-1",
                defaultBaseBranch = "master",
                createdAt = 1L,
                updatedAt = 1L
            )
        ),
        companyAgentDefinitions = listOf(
            CompanyAgentDefinition(
                id = "agent-marketing",
                companyId = "company-1",
                title = "Marketing Operator",
                agentCli = "opencode",
                roleSummary = "marketing operator",
                specialties = listOf("marketing"),
                createdAt = 1L,
                updatedAt = 1L
            )
        )
    )

