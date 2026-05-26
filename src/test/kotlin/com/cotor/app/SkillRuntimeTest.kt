package com.cotor.app

import com.cotor.data.config.ConfigRepository
import com.cotor.domain.executor.AgentExecutor
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldHaveSize
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import io.mockk.coEvery
import io.mockk.mockk
import java.nio.file.Files
import kotlin.io.path.createDirectories
import kotlin.io.path.exists
import kotlin.io.path.writeText

class SkillRuntimeTest : FunSpec({
    afterTest {
        DesktopAppService.shutdownAllForTesting()
    }

    test("graphify catalog advertises write capability because missing reports are refreshed") {
        val graphify = skillCatalog().single { it.name == "graphify" }

        graphify.requiredCapabilities.contains(CapabilityKey.KNOWLEDGE_GRAPH_READ) shouldBe true
        graphify.requiredCapabilities.contains(CapabilityKey.KNOWLEDGE_GRAPH_WRITE) shouldBe true
    }

    test("new companies seed a repository mapper agent for the operator repo map shortcut") {
        val appHome = Files.createTempDirectory("skill-graphify-seed-home")
        val repoRoot = Files.createDirectories(appHome.resolve("repo"))
        val service = skillRuntimeService(appHome)
        val company = service.createCompany(name = "Graph Seed Co", rootPath = repoRoot.toString())
        val companyRoot = java.nio.file.Path.of(company.rootPath).toAbsolutePath().normalize()
        companyRoot.resolve("graphify-out").createDirectories()
        companyRoot.resolve("graphify-out").resolve("GRAPH_REPORT.md").writeText("# Graph\n\n- service: DesktopAppService")
        val dashboard = service.dashboard()
        val engineeringLead = dashboard.companyAgentDefinitions.first {
            it.companyId == company.id && it.title == "Engineering Lead"
        }
        val profile = dashboard.agentCapabilityProfiles.first {
            it.companyId == company.id && it.agentId == engineeringLead.id
        }
        val skillRun = profile.settings.getValue(CapabilityKey.SKILL_RUN)
        val graphWrite = profile.settings.getValue(CapabilityKey.KNOWLEDGE_GRAPH_WRITE)

        skillRun.mode shouldBe CapabilityMode.AUTO
        skillRun.skillAllowlist.contains("graphify") shouldBe true
        graphWrite.mode shouldBe CapabilityMode.AUTO
        graphWrite.pathAllowlist.contains(companyRoot.toString()) shouldBe true

        val result = service.runSkill(
            name = "graphify",
            companyId = company.id,
            agentId = engineeringLead.id,
            parameters = mapOf("refresh" to "false")
        )

        result.status shouldBe "COMPLETED"
        result.output shouldContain "DesktopAppService"
    }

    test("runSkill dispatches graphify to graph report evidence instead of READY") {
        val appHome = Files.createTempDirectory("skill-graphify-home")
        val service = skillRuntimeService(appHome)
        val company = service.createCompany(name = "Graph Skill Co", rootPath = appHome.toString())
        val ceo = service.listCompanyAgentDefinitions(company.id).first { it.title == "CEO" }
        java.nio.file.Path.of(company.rootPath).resolve("graphify-out").createDirectories()
        java.nio.file.Path.of(company.rootPath).resolve("graphify-out").resolve("GRAPH_REPORT.md").writeText("# Graph\n\n- service: DesktopAppService")
        service.updateAgentCapabilities(
            companyId = company.id,
            agentId = ceo.id,
            settings = mapOf(
                CapabilityKey.SKILL_RUN to AgentCapabilitySetting(
                    enabled = true,
                    mode = CapabilityMode.AUTO,
                    skillAllowlist = listOf("graphify")
                ),
                CapabilityKey.KNOWLEDGE_GRAPH_READ to AgentCapabilitySetting(enabled = true, mode = CapabilityMode.READ_ONLY)
            )
        )

        val result = service.runSkill(
            name = "graphify",
            companyId = company.id,
            agentId = ceo.id,
            parameters = mapOf("refresh" to "false")
        )

        result.status shouldBe "COMPLETED"
        result.output shouldContain "DesktopAppService"
        result.evidence.single().path shouldContain "GRAPH_REPORT.md"
        service.dashboard().skillRuns.first().status shouldBe "COMPLETED"
    }

    test("runSkill executes browser-smoke with browser evidence") {
        val appHome = Files.createTempDirectory("skill-browser-home")
        val browser = RecordingBrowserSkillRunner()
        val service = skillRuntimeService(appHome, browser)
        val company = service.createCompany(name = "Browser Skill Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Builder" }
        service.updateAgentCapabilities(
            companyId = company.id,
            agentId = agent.id,
            settings = mapOf(
                CapabilityKey.SKILL_RUN to AgentCapabilitySetting(
                    enabled = true,
                    mode = CapabilityMode.AUTO,
                    skillAllowlist = listOf("browser-smoke")
                ),
                CapabilityKey.BROWSER_READ to AgentCapabilitySetting(enabled = true, mode = CapabilityMode.AUTO),
                CapabilityKey.BROWSER_SCREENSHOT to AgentCapabilitySetting(enabled = true, mode = CapabilityMode.AUTO)
            )
        )

        val result = service.runSkill(
            name = "browser-smoke",
            companyId = company.id,
            agentId = agent.id,
            parameters = mapOf("url" to "http://localhost:3000")
        )

        result.status shouldBe "COMPLETED"
        result.evidence.any { it.type == "screenshot" } shouldBe true
        browser.commands.shouldHaveSize(1)
        browser.commands.single().url shouldBe "http://localhost:3000"
    }

    test("runSkill writes video-plan artifacts without rendering") {
        val appHome = Files.createTempDirectory("skill-video-home")
        val service = skillRuntimeService(appHome)
        val company = service.createCompany(name = "Video Skill Co", rootPath = appHome.toString())
        val agent = service.listCompanyAgentDefinitions(company.id).first { it.title == "Builder" }
        service.updateAgentCapabilities(
            companyId = company.id,
            agentId = agent.id,
            settings = mapOf(
                CapabilityKey.SKILL_RUN to AgentCapabilitySetting(
                    enabled = true,
                    mode = CapabilityMode.AUTO,
                    skillAllowlist = listOf("video-plan")
                ),
                CapabilityKey.VIDEO_SCRIPT_WRITE to AgentCapabilitySetting(enabled = true, mode = CapabilityMode.AUTO)
            )
        )

        val result = service.runSkill(
            name = "video-plan",
            companyId = company.id,
            agentId = agent.id,
            input = "Make a workflow demo video",
            parameters = mapOf("provider" to "ffmpeg")
        )

        result.status shouldBe "COMPLETED"
        result.evidence.shouldHaveSize(2)
        result.evidence.mapNotNull { it.path }.forEach { path -> Files.exists(java.nio.file.Path.of(path)) shouldBe true }
        result.output shouldContain "Video Plan"
    }

    test("seeded Engineering Lead profile allowlists browser-smoke and enables browser capabilities") {
        val appHome = Files.createTempDirectory("skill-eng-lead-browser-home")
        val repoRoot = Files.createDirectories(appHome.resolve("repo"))
        val service = skillRuntimeService(appHome)
        val company = service.createCompany(name = "Eng Lead Browser Co", rootPath = repoRoot.toString())
        val dashboard = service.dashboard()
        val engineeringLead = dashboard.companyAgentDefinitions.first {
            it.companyId == company.id && it.title == "Engineering Lead"
        }
        val profile = dashboard.agentCapabilityProfiles.first {
            it.companyId == company.id && it.agentId == engineeringLead.id
        }

        profile.settings.getValue(CapabilityKey.SKILL_RUN).skillAllowlist.contains("browser-smoke") shouldBe true
        profile.settings.getValue(CapabilityKey.BROWSER_READ).mode shouldBe CapabilityMode.AUTO
        profile.settings.getValue(CapabilityKey.BROWSER_SCREENSHOT).mode shouldBe CapabilityMode.AUTO
    }

    test("seeded Marketing Operator profile enables all marketing capabilities") {
        val appHome = Files.createTempDirectory("skill-marketing-seed-home")
        val repoRoot = Files.createDirectories(appHome.resolve("repo"))
        val service = skillRuntimeService(appHome)
        val company = service.createCompany(name = "Marketing Seed Co", rootPath = repoRoot.toString())
        val dashboard = service.dashboard()
        val marketingAgent = dashboard.companyAgentDefinitions.first {
            it.companyId == company.id && it.title == "Marketing Operator"
        }
        val profile = dashboard.agentCapabilityProfiles.first {
            it.companyId == company.id && it.agentId == marketingAgent.id
        }

        profile.settings.getValue(CapabilityKey.BROWSER_READ).mode shouldBe CapabilityMode.AUTO
        profile.settings.getValue(CapabilityKey.BROWSER_INTERACT).mode shouldBe CapabilityMode.AUTO
        profile.settings.getValue(CapabilityKey.BROWSER_EXTERNAL_DOMAIN).mode shouldBe CapabilityMode.AUTO
        profile.settings.getValue(CapabilityKey.BROWSER_LOGIN_FLOW).mode shouldBe CapabilityMode.AUTO
        profile.settings.getValue(CapabilityKey.WEB_PUBLISH).mode shouldBe CapabilityMode.AUTO
        profile.settings.getValue(CapabilityKey.SOCIAL_POST_CREATE).mode shouldBe CapabilityMode.AUTO
        profile.settings.getValue(CapabilityKey.MARKETING_ANALYTICS_READ).mode shouldBe CapabilityMode.AUTO
        profile.settings.getValue(CapabilityKey.VIDEO_SCRIPT_WRITE).mode shouldBe CapabilityMode.AUTO
    }

    test("looksLikeOperatorSkillRequest does not false-positive on passive inquiry phrases") {
        val service = skillRuntimeService(Files.createTempDirectory("nlp-fp-home"))

        service.looksLikeOperatorSkillRequest("analytics 요약 알려줘") shouldBe false
        service.looksLikeOperatorSkillRequest("analytics 보고서 보여줘") shouldBe false
        service.looksLikeOperatorSkillRequest("마케팅 리포트 알려줘") shouldBe false
        service.looksLikeOperatorSkillRequest("analytics run") shouldBe true
        service.looksLikeOperatorSkillRequest("browser-smoke 실행해줘") shouldBe true
        service.looksLikeOperatorSkillRequest("repo map 실행") shouldBe true
    }

    test("inferOperatorSkillName does not fall back to graphify for unrecognized input") {
        val service = skillRuntimeService(Files.createTempDirectory("nlp-infer-home"))

        service.inferOperatorSkillName("random unrelated message") shouldBe ""
        service.inferOperatorSkillName("help me please") shouldBe ""
        service.inferOperatorSkillName("analytics") shouldBe "analytics-reporter"
        service.inferOperatorSkillName("browser screenshot test") shouldBe "browser-smoke"
        service.inferOperatorSkillName("graphify repo structure") shouldBe "graphify"
    }

    test("prewarm is a no-op and completes without error when node and npm are unavailable") {
        val runner = LocalPlaywrightBrowserSkillRunner(
            appHomeProvider = { Files.createTempDirectory("prewarm-noop-home") },
            commandAvailability = { false }
        )
        runner.prewarm()
    }

    test("marketing operator skillAllowlist includes video-plan skill") {
        val appHome = Files.createTempDirectory("skill-mktg-vidplan-home")
        val repoRoot = Files.createDirectories(appHome.resolve("repo"))
        val service = skillRuntimeService(appHome)
        val company = service.createCompany(name = "Mktg VideoPlan Co", rootPath = repoRoot.toString())
        val dashboard = service.dashboard()
        val marketingAgent = dashboard.companyAgentDefinitions.first {
            it.companyId == company.id && it.title == "Marketing Operator"
        }
        val profile = dashboard.agentCapabilityProfiles.first {
            it.companyId == company.id && it.agentId == marketingAgent.id
        }
        val allowlist = profile.settings.getValue(CapabilityKey.SKILL_RUN).skillAllowlist

        allowlist.contains("video-plan") shouldBe true
        allowlist.contains("analytics-reporter") shouldBe true
        allowlist.contains("social-publisher") shouldBe true
    }

    test("looksLikeOperatorSkillRequest matches Korean social and content keywords") {
        val service = skillRuntimeService(Files.createTempDirectory("nlp-korean-kw-home"))

        service.looksLikeOperatorSkillRequest("소셜 실행해줘") shouldBe true
        service.looksLikeOperatorSkillRequest("블로그 실행해줘") shouldBe true
        service.looksLikeOperatorSkillRequest("cms 돌려") shouldBe true
        service.looksLikeOperatorSkillRequest("고객 타깃 실행") shouldBe true
        service.looksLikeOperatorSkillRequest("콘텐츠 run") shouldBe true
        service.looksLikeOperatorSkillRequest("소셜 요약해줘") shouldBe false
        service.looksLikeOperatorSkillRequest("콘텐츠 보여줘") shouldBe false
    }

    test("prewarm is called eagerly when service starts") {
        val appHome = Files.createTempDirectory("prewarm-startup-home")
        val prewarmCalled = java.util.concurrent.atomic.AtomicBoolean(false)
        val runner = object : BrowserSkillRunner {
            override suspend fun execute(command: BrowserSkillCommand): BrowserSkillResult =
                error("not expected in this test")
            override suspend fun prewarm() { prewarmCalled.set(true) }
        }
        skillRuntimeService(appHome, runner)
        val deadline = System.currentTimeMillis() + 2_000L
        while (!prewarmCalled.get() && System.currentTimeMillis() < deadline) {
            Thread.sleep(20)
        }
        prewarmCalled.get() shouldBe true
    }
})

private fun skillRuntimeService(
    appHome: java.nio.file.Path,
    browserRunner: BrowserSkillRunner = RecordingBrowserSkillRunner()
): DesktopAppService {
    val gitWorkspaceService = mockk<GitWorkspaceService>(relaxed = true)
    coEvery { gitWorkspaceService.ensureInitializedRepositoryRoot(any(), any()) } answers { firstArg() }
    return DesktopAppService(
        stateStore = DesktopStateStore { appHome },
        gitWorkspaceService = gitWorkspaceService,
        configRepository = mockk<ConfigRepository>(relaxed = true),
        agentExecutor = mockk<AgentExecutor>(relaxed = true),
        commandAvailability = { command -> command in setOf("graphify", "node", "npm") },
        browserSkillRunner = browserRunner
    )
}

private class RecordingBrowserSkillRunner : BrowserSkillRunner {
    val commands = mutableListOf<BrowserSkillCommand>()

    override suspend fun execute(command: BrowserSkillCommand): BrowserSkillResult {
        commands += command
        Files.createDirectories(java.nio.file.Path.of(command.screenshotPath).parent)
        Files.writeString(java.nio.file.Path.of(command.screenshotPath), "fake screenshot")
        return BrowserSkillResult(
            url = command.url,
            finalUrl = command.url,
            title = "Cotor Test",
            screenshotPath = command.screenshotPath,
            tracePath = command.tracePath,
            consoleErrors = emptyList(),
            actions = listOf("goto ${command.url}", "screenshot ${command.screenshotPath}")
        )
    }
}
