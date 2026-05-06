package com.cotor.app

import com.cotor.runtime.actions.ActionKind
import com.cotor.runtime.actions.ActionRequest
import com.cotor.runtime.actions.ActionSubject
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.nio.file.Files

class AgentCapabilityGuardTest : FunSpec({
    test("default company agent profile requires approval for shell execution") {
        val appHome = Files.createTempDirectory("capability-guard-default-home")
        val store = DesktopStateStore { appHome }
        store.save(
            DesktopAppState(
                companies = listOf(testCompany()),
                companyAgentDefinitions = listOf(testAgent())
            )
        )
        val guard = AgentCapabilityGuard(store)

        val decision = guard.simulate(
            ActionRequest(
                kind = ActionKind.SHELL_EXEC,
                label = "shell.exec:test",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                command = listOf("bash", "-lc", "touch file")
            )
        )

        decision.capability shouldBe CapabilityKey.SHELL_EXEC
        decision.mode shouldBe CapabilityMode.APPROVAL_REQUIRED
        decision.allowed shouldBe true
        decision.requiresApproval shouldBe true
    }

    test("disabled capability denies mapped action before execution") {
        val appHome = Files.createTempDirectory("capability-guard-deny-home")
        val store = DesktopStateStore { appHome }
        store.save(
            DesktopAppState(
                companies = listOf(testCompany()),
                companyAgentDefinitions = listOf(testAgent()),
                agentCapabilityProfiles = listOf(
                    AgentCapabilityProfile(
                        companyId = "company-1",
                        agentId = "agent-1",
                        settings = defaultAgentCapabilitySettings() + mapOf(
                            CapabilityKey.GITHUB_MERGE_EXECUTE to AgentCapabilitySetting(
                                enabled = false,
                                mode = CapabilityMode.DISABLED
                            )
                        )
                    )
                )
            )
        )
        val guard = AgentCapabilityGuard(store)

        val decision = guard.simulate(
            ActionRequest(
                kind = ActionKind.GITHUB_MERGE,
                label = "github.merge:12",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1")
            )
        )

        decision.capability shouldBe CapabilityKey.GITHUB_MERGE_EXECUTE
        decision.allowed shouldBe false
        decision.requiresApproval shouldBe false
    }

    test("skill runs map to skill capability and honor skill allowlist") {
        val appHome = Files.createTempDirectory("capability-guard-skill-home")
        val store = DesktopStateStore { appHome }
        store.save(
            DesktopAppState(
                companies = listOf(testCompany()),
                companyAgentDefinitions = listOf(testAgent()),
                agentCapabilityProfiles = listOf(
                    AgentCapabilityProfile(
                        companyId = "company-1",
                        agentId = "agent-1",
                        settings = defaultAgentCapabilitySettings() + mapOf(
                            CapabilityKey.SKILL_RUN to AgentCapabilitySetting(
                                enabled = true,
                                mode = CapabilityMode.AUTO,
                                skillAllowlist = listOf("graphify")
                            )
                        )
                    )
                )
            )
        )
        val guard = AgentCapabilityGuard(store)

        val allowed = guard.simulate(
            ActionRequest(
                kind = ActionKind.SKILL_RUN,
                label = "skill.run:graphify",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                metadata = mapOf("skill" to "graphify")
            )
        )
        val denied = guard.simulate(
            ActionRequest(
                kind = ActionKind.SKILL_RUN,
                label = "skill.run:video",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                metadata = mapOf("skill" to "video")
            )
        )

        allowed.capability shouldBe CapabilityKey.SKILL_RUN
        allowed.mode shouldBe CapabilityMode.AUTO
        allowed.allowed shouldBe true
        allowed.requiresApproval shouldBe false
        denied.capability shouldBe CapabilityKey.SKILL_RUN
        denied.allowed shouldBe false
    }

    test("browser and video actions map to disabled by default capability gates") {
        val appHome = Files.createTempDirectory("capability-guard-media-home")
        val store = DesktopStateStore { appHome }
        store.save(
            DesktopAppState(
                companies = listOf(testCompany()),
                companyAgentDefinitions = listOf(testAgent())
            )
        )
        val guard = AgentCapabilityGuard(store)

        val browser = guard.simulate(
            ActionRequest(
                kind = ActionKind.BROWSER_SCREENSHOT,
                label = "browser.screenshot:smoke",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1")
            )
        )
        val video = guard.simulate(
            ActionRequest(
                kind = ActionKind.VIDEO_RENDER_LOCAL,
                label = "video.render-local:smoke",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1")
            )
        )

        browser.capability shouldBe CapabilityKey.BROWSER_SCREENSHOT
        browser.mode shouldBe CapabilityMode.DISABLED
        browser.allowed shouldBe false
        video.capability shouldBe CapabilityKey.VIDEO_RENDER_LOCAL
        video.mode shouldBe CapabilityMode.DISABLED
        video.allowed shouldBe false
    }

    test("marketing operator auto capabilities require delegated domain and channel allowlists") {
        val appHome = Files.createTempDirectory("capability-guard-marketing-home")
        val store = DesktopStateStore { appHome }
        val marketingSetting = AgentCapabilitySetting(
            enabled = true,
            mode = CapabilityMode.AUTO,
            domainAllowlist = listOf("cms.example.com"),
            channelAllowlist = listOf("web"),
            secretRefs = listOf("secret://cms/session")
        )
        store.save(
            DesktopAppState(
                companies = listOf(testCompany()),
                companyAgentDefinitions = listOf(testAgent().copy(title = "Marketing Operator", roleSummary = "marketing")),
                agentCapabilityProfiles = listOf(
                    AgentCapabilityProfile(
                        companyId = "company-1",
                        agentId = "agent-1",
                        settings = defaultAgentCapabilitySettings() + mapOf(
                            CapabilityKey.BROWSER_READ to marketingSetting,
                            CapabilityKey.BROWSER_INTERACT to marketingSetting,
                            CapabilityKey.BROWSER_EXTERNAL_DOMAIN to marketingSetting,
                            CapabilityKey.BROWSER_LOGIN_FLOW to marketingSetting,
                            CapabilityKey.WEB_PUBLISH to marketingSetting,
                            CapabilityKey.SOCIAL_POST_CREATE to marketingSetting,
                            CapabilityKey.MARKETING_ANALYTICS_READ to marketingSetting
                        )
                    )
                )
            )
        )
        val guard = AgentCapabilityGuard(store)

        val allowed = guard.simulate(
            ActionRequest(
                kind = ActionKind.WEB_PUBLISH,
                label = "web.publish:cms",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                networkTarget = "https://cms.example.com/posts/new",
                metadata = mapOf("channel" to "web")
            )
        )
        val outsideDomain = guard.simulate(
            ActionRequest(
                kind = ActionKind.WEB_PUBLISH,
                label = "web.publish:outside",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                networkTarget = "https://evil.example.net/posts/new",
                metadata = mapOf("channel" to "web")
            )
        )
        val outsideChannel = guard.simulate(
            ActionRequest(
                kind = ActionKind.SOCIAL_POST_CREATE,
                label = "social.post-create:x",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                networkTarget = "https://cms.example.com/social",
                metadata = mapOf("channel" to "x")
            )
        )
        val defaultAgent = guard.simulate(
            ActionRequest(
                kind = ActionKind.SOCIAL_POST_CREATE,
                label = "social.post-create:ordinary",
                subject = ActionSubject(companyId = "company-1", agentName = "unknown"),
                networkTarget = "https://cms.example.com/social",
                metadata = mapOf("channel" to "web")
            )
        )

        allowed.capability shouldBe CapabilityKey.WEB_PUBLISH
        allowed.mode shouldBe CapabilityMode.AUTO
        allowed.allowed shouldBe true
        outsideDomain.allowed shouldBe false
        outsideChannel.allowed shouldBe false
        defaultAgent.capability shouldBe CapabilityKey.SOCIAL_POST_CREATE
        defaultAgent.mode shouldBe CapabilityMode.DISABLED
        defaultAgent.allowed shouldBe false
    }

    test("git shell mutations map to git write instead of git read") {
        val appHome = Files.createTempDirectory("capability-guard-git-home")
        val store = DesktopStateStore { appHome }
        store.save(
            DesktopAppState(
                companies = listOf(testCompany()),
                companyAgentDefinitions = listOf(testAgent())
            )
        )
        val guard = AgentCapabilityGuard(store)

        val read = guard.simulate(
            ActionRequest(
                kind = ActionKind.SHELL_EXEC,
                label = "git.status",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                command = listOf("git", "status")
            )
        )
        val write = guard.simulate(
            ActionRequest(
                kind = ActionKind.SHELL_EXEC,
                label = "git.push",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                command = listOf("git", "push")
            )
        )

        read.capability shouldBe CapabilityKey.GIT_READ
        read.allowed shouldBe true
        write.capability shouldBe CapabilityKey.GIT_WRITE
        write.requiresApproval shouldBe true
    }

    test("scoped dangerous actions deny missing subjects and honor recorded approval") {
        val appHome = Files.createTempDirectory("capability-guard-subject-home")
        val store = DesktopStateStore { appHome }
        store.save(
            DesktopAppState(
                companies = listOf(testCompany()),
                companyAgentDefinitions = listOf(testAgent())
            )
        )
        val guard = AgentCapabilityGuard(store)

        val missingSubject = guard.before(
            ActionRequest(
                kind = ActionKind.GITHUB_COMMENT,
                label = "github.comment:12"
            )
        )
        val pendingApproval = guard.simulate(
            ActionRequest(
                kind = ActionKind.GITHUB_COMMENT,
                label = "github.comment:12",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1")
            )
        )
        val recordedApproval = guard.simulate(
            ActionRequest(
                kind = ActionKind.GITHUB_COMMENT,
                label = "github.comment:12",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                metadata = mapOf("approvedBy" to "qa-cli")
            )
        )
        val recordedPublishApproval = guard.simulate(
            ActionRequest(
                kind = ActionKind.GIT_PUBLISH,
                label = "git.publish:branch",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                metadata = mapOf("approvedBy" to "company-chief:CEO:agent-ceo")
            )
        )

        missingSubject.allow shouldBe false
        pendingApproval.requiresApproval shouldBe true
        recordedApproval.allowed shouldBe true
        recordedApproval.requiresApproval shouldBe false
        recordedPublishApproval.allowed shouldBe true
        recordedPublishApproval.requiresApproval shouldBe false
    }

    test("unscoped generic agent execution stays outside company capability authority") {
        val guard = AgentCapabilityGuard(DesktopStateStore { Files.createTempDirectory("capability-guard-unscoped-home") })

        val decision = guard.before(
            ActionRequest(
                kind = ActionKind.AGENT_EXEC,
                label = "agent.exec:pipeline"
            )
        )

        decision.allow shouldBe true
        decision.requireApproval shouldBe false
    }

    test("repository scoped company agent execution honors path allowlists") {
        val appHome = Files.createTempDirectory("capability-guard-agent-exec-home")
        val allowedRoot = Files.createTempDirectory("capability-agent-exec-repo")
        val outsideRoot = Files.createTempDirectory("capability-agent-exec-outside")
        val store = DesktopStateStore { appHome }
        store.save(
            DesktopAppState(
                companies = listOf(testCompany()),
                companyAgentDefinitions = listOf(testAgent()),
                agentCapabilityProfiles = listOf(
                    AgentCapabilityProfile(
                        companyId = "company-1",
                        agentId = "agent-1",
                        settings = defaultAgentCapabilitySettings() + mapOf(
                            CapabilityKey.SHELL_EXEC to AgentCapabilitySetting(
                                enabled = true,
                                mode = CapabilityMode.AUTO,
                                pathAllowlist = listOf(allowedRoot.toString())
                            )
                        )
                    )
                )
            )
        )
        val guard = AgentCapabilityGuard(store)

        val allowed = guard.simulate(
            ActionRequest(
                kind = ActionKind.AGENT_EXEC,
                label = "agent.exec:opencode",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                metadata = mapOf("repositoryRoot" to allowedRoot.toString())
            )
        )
        val denied = guard.simulate(
            ActionRequest(
                kind = ActionKind.AGENT_EXEC,
                label = "agent.exec:opencode",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                metadata = mapOf("repositoryRoot" to outsideRoot.toString())
            )
        )

        allowed.capability shouldBe CapabilityKey.SHELL_EXEC
        allowed.allowed shouldBe true
        allowed.requiresApproval shouldBe false
        denied.capability shouldBe CapabilityKey.SHELL_EXEC
        denied.allowed shouldBe false
    }

    test("path and domain allowlists require normalized containment and host matches") {
        val appHome = Files.createTempDirectory("capability-guard-allowlist-home")
        val allowedRoot = Files.createTempDirectory("capability-project")
        val sibling = allowedRoot.resolveSibling("${allowedRoot.fileName}-evil")
        val store = DesktopStateStore { appHome }
        store.save(
            DesktopAppState(
                companies = listOf(testCompany()),
                companyAgentDefinitions = listOf(testAgent()),
                agentCapabilityProfiles = listOf(
                    AgentCapabilityProfile(
                        companyId = "company-1",
                        agentId = "agent-1",
                        settings = defaultAgentCapabilitySettings() + mapOf(
                            CapabilityKey.FILE_WRITE to AgentCapabilitySetting(
                                mode = CapabilityMode.AUTO,
                                pathAllowlist = listOf(allowedRoot.toString())
                            ),
                            CapabilityKey.BROWSER_EXTERNAL_DOMAIN to AgentCapabilitySetting(
                                mode = CapabilityMode.AUTO,
                                domainAllowlist = listOf("example.com")
                            )
                        )
                    )
                )
            )
        )
        val guard = AgentCapabilityGuard(store)

        val insidePath = guard.simulate(
            ActionRequest(
                kind = ActionKind.FILE_WRITE,
                label = "file.write:inside",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                path = allowedRoot.resolve("ok.txt").toString()
            )
        )
        val siblingPath = guard.simulate(
            ActionRequest(
                kind = ActionKind.FILE_WRITE,
                label = "file.write:sibling",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                path = sibling.resolve("bad.txt").toString()
            )
        )
        val subdomain = guard.simulate(
            ActionRequest(
                kind = ActionKind.BROWSER_EXTERNAL_DOMAIN,
                label = "browser.external-domain:subdomain",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                networkTarget = "docs.example.com"
            )
        )
        val lookalike = guard.simulate(
            ActionRequest(
                kind = ActionKind.BROWSER_EXTERNAL_DOMAIN,
                label = "browser.external-domain:lookalike",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                networkTarget = "example.com.evil.tld"
            )
        )

        insidePath.allowed shouldBe true
        siblingPath.allowed shouldBe false
        subdomain.allowed shouldBe true
        lookalike.allowed shouldBe false
    }

    test("marketing capabilities honor delegated domain and channel allowlists") {
        val appHome = Files.createTempDirectory("capability-guard-marketing-home")
        val store = DesktopStateStore { appHome }
        val marketingSetting = AgentCapabilitySetting(
            enabled = true,
            mode = CapabilityMode.AUTO,
            domainAllowlist = listOf("example.com"),
            channelAllowlist = listOf("web", "linkedin")
        )
        store.save(
            DesktopAppState(
                companies = listOf(testCompany()),
                companyAgentDefinitions = listOf(testAgent()),
                agentCapabilityProfiles = listOf(
                    AgentCapabilityProfile(
                        companyId = "company-1",
                        agentId = "agent-1",
                        settings = defaultAgentCapabilitySettings() + mapOf(
                            CapabilityKey.WEB_PUBLISH to marketingSetting,
                            CapabilityKey.SOCIAL_POST_CREATE to marketingSetting,
                            CapabilityKey.MARKETING_ANALYTICS_READ to marketingSetting
                        )
                    )
                )
            )
        )
        val guard = AgentCapabilityGuard(store)

        val allowed = guard.simulate(
            ActionRequest(
                kind = ActionKind.WEB_PUBLISH,
                label = "web.publish:cms",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                networkTarget = "cms.example.com",
                metadata = mapOf("channel" to "web")
            )
        )
        val wrongChannel = guard.simulate(
            ActionRequest(
                kind = ActionKind.WEB_PUBLISH,
                label = "web.publish:cms",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                networkTarget = "cms.example.com",
                metadata = mapOf("channel" to "tiktok")
            )
        )
        val wrongDomain = guard.simulate(
            ActionRequest(
                kind = ActionKind.SOCIAL_POST_CREATE,
                label = "social.post-create:linkedin",
                subject = ActionSubject(companyId = "company-1", agentName = "agent-1"),
                networkTarget = "evil.example.net",
                metadata = mapOf("channel" to "linkedin")
            )
        )

        allowed.capability shouldBe CapabilityKey.WEB_PUBLISH
        allowed.mode shouldBe CapabilityMode.AUTO
        allowed.allowed shouldBe true
        wrongChannel.allowed shouldBe false
        wrongDomain.allowed shouldBe false
    }

    test("capability profiles survive desktop state persistence") {
        val appHome = Files.createTempDirectory("capability-state-home")
        val store = DesktopStateStore { appHome }
        store.save(
            DesktopAppState(
                companies = listOf(testCompany()),
                companyAgentDefinitions = listOf(testAgent()),
                agentCapabilityProfiles = listOf(
                    AgentCapabilityProfile(
                        companyId = "company-1",
                        agentId = "agent-1",
                        settings = defaultAgentCapabilitySettings() + mapOf(
                            CapabilityKey.FILE_WRITE to AgentCapabilitySetting(
                                enabled = true,
                                mode = CapabilityMode.PROPOSE_ONLY,
                                pathAllowlist = listOf("/tmp/project")
                            )
                        )
                    )
                )
            )
        )

        val loaded = store.load()

        loaded.agentCapabilityProfiles.single().settings.getValue(CapabilityKey.FILE_WRITE).mode shouldBe CapabilityMode.PROPOSE_ONLY
        loaded.agentCapabilityProfiles.single().settings.getValue(CapabilityKey.FILE_WRITE).pathAllowlist shouldBe listOf("/tmp/project")
    }
})

private fun testCompany() = Company(
    id = "company-1",
    name = "Capability Co",
    rootPath = "/tmp/capability-co",
    repositoryId = "repo-1",
    defaultBaseBranch = "master",
    createdAt = 1L,
    updatedAt = 1L
)

private fun testAgent() = CompanyAgentDefinition(
    id = "agent-1",
    companyId = "company-1",
    title = "Builder",
    agentCli = "opencode",
    roleSummary = "build",
    createdAt = 1L,
    updatedAt = 1L
)
