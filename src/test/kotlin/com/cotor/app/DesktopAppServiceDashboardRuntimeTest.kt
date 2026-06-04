package com.cotor.app

import com.cotor.data.config.ConfigRepository
import com.cotor.domain.executor.AgentExecutor
import com.cotor.model.AgentConfig
import com.cotor.model.AgentResult
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContainExactly
import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout
import java.nio.file.Files

class DesktopAppServiceDashboardRuntimeTest : FunSpec({
    afterTest {
        DesktopAppService.shutdownAllForTesting()
    }

    test("company dashboard read only scopes companies and metrics to the selected company") {
        val appHome = Files.createTempDirectory("desktop-dashboard-scoped-payload-home")
        val stateStore = DesktopStateStore { appHome }
        val service = DesktopAppService(
            stateStore = stateStore,
            gitWorkspaceService = mockk<GitWorkspaceService>(relaxed = true),
            configRepository = mockk<ConfigRepository>(relaxed = true),
            agentExecutor = mockk<AgentExecutor>(relaxed = true)
        )
        val now = System.currentTimeMillis()
        val selectedCompany = Company(
            id = "company-selected",
            name = "Selected Company",
            rootPath = "/tmp/selected",
            repositoryId = "repo-selected",
            defaultBaseBranch = "master",
            createdAt = now,
            updatedAt = now
        )
        val otherCompany = selectedCompany.copy(
            id = "company-other",
            name = "Other Company",
            rootPath = "/tmp/other",
            repositoryId = "repo-other"
        )
        val selectedGoal = CompanyGoal(
            id = "goal-selected",
            companyId = selectedCompany.id,
            title = "Selected goal",
            description = "Selected goal",
            status = GoalStatus.ACTIVE,
            createdAt = now,
            updatedAt = now
        )
        val otherGoal = selectedGoal.copy(
            id = "goal-other",
            companyId = otherCompany.id,
            title = "Other goal"
        )
        val selectedIssue = CompanyIssue(
            id = "issue-selected",
            companyId = selectedCompany.id,
            goalId = selectedGoal.id,
            workspaceId = "workspace-selected",
            title = "Selected issue",
            description = "Selected issue",
            status = IssueStatus.IN_PROGRESS,
            createdAt = now,
            updatedAt = now
        )
        val otherIssue = selectedIssue.copy(
            id = "issue-other",
            companyId = otherCompany.id,
            goalId = otherGoal.id,
            title = "Other issue",
            status = IssueStatus.BLOCKED
        )
        stateStore.save(
            DesktopAppState(
                companies = listOf(selectedCompany, otherCompany),
                goals = listOf(selectedGoal, otherGoal),
                issues = listOf(selectedIssue, otherIssue),
                reviewQueue = listOf(
                    ReviewQueueItem(
                        id = "review-selected",
                        companyId = selectedCompany.id,
                        issueId = selectedIssue.id,
                        runId = "run-selected",
                        status = ReviewQueueStatus.READY_TO_MERGE,
                        createdAt = now,
                        updatedAt = now
                    ),
                    ReviewQueueItem(
                        id = "review-other",
                        companyId = otherCompany.id,
                        issueId = otherIssue.id,
                        runId = "run-other",
                        status = ReviewQueueStatus.MERGED,
                        createdAt = now,
                        updatedAt = now
                    )
                )
            )
        )

        val dashboard = service.companyDashboardReadOnly(selectedCompany.id)

        dashboard.companies.map { it.id } shouldContainExactly listOf(selectedCompany.id)
        dashboard.goals.map { it.id } shouldContainExactly listOf(selectedGoal.id)
        dashboard.issues.map { it.id } shouldContainExactly listOf(selectedIssue.id)
        dashboard.opsMetrics.openGoals shouldBe 1
        dashboard.opsMetrics.activeIssues shouldBe 1
        dashboard.opsMetrics.blockedIssues shouldBe 0
        dashboard.opsMetrics.readyToMergeCount shouldBe 1
        dashboard.opsMetrics.mergedCount shouldBe 0
    }

    test("company dashboard keeps manually stopped autonomous runtimes stopped") {
        val appHome = Files.createTempDirectory("desktop-dashboard-runtime-home")
        val repoRoot = Files.createDirectories(Files.createTempDirectory("desktop-dashboard-runtime-test").resolve("repo"))
        val worktreeRoot = Files.createDirectories(Files.createTempDirectory("desktop-dashboard-runtime-worktree"))
        val stateStore = DesktopStateStore { appHome }
        val gitWorkspaceService = mockk<GitWorkspaceService>()
        val agentExecutor = mockk<AgentExecutor>()
        coEvery { gitWorkspaceService.ensureInitializedRepositoryRoot(any(), any()) } returns repoRoot
        coEvery { gitWorkspaceService.resolveRepositoryRoot(any()) } returns repoRoot
        coEvery { gitWorkspaceService.detectDefaultBranch(any()) } returns "master"
        coEvery { gitWorkspaceService.detectRemoteUrl(any()) } returns "https://github.com/heodongun/cotor.git"
        coEvery { gitWorkspaceService.ensureGitHubPublishReady(any(), any()) } returns GitHubPublishReadiness(ready = true)
        coEvery { gitWorkspaceService.ensureWorktree(any(), any(), any(), any(), any()) } answers {
            val agentName = invocation.args[3] as String
            WorktreeBinding(
                branchName = "codex/cotor/dashboard-runtime/$agentName",
                worktreePath = worktreeRoot.resolve(agentName)
            )
        }
        coEvery { gitWorkspaceService.publishRun(any(), any(), any(), any(), any(), any(), any()) } returns PublishMetadata()
        coEvery { agentExecutor.executeAgent(any(), any(), any()) } answers {
            val agent = invocation.args[0] as AgentConfig
            AgentResult(
                agentName = agent.name,
                isSuccess = true,
                output = "done",
                error = null,
                duration = 25,
                metadata = emptyMap(),
                processId = 6001
            )
        }
        val service = DesktopAppService(
            stateStore = stateStore,
            gitWorkspaceService = gitWorkspaceService,
            configRepository = mockk<ConfigRepository>(relaxed = true),
            agentExecutor = agentExecutor,
            companyRuntimeTickIntervalMs = 50,
            commandAvailability = { command -> command in setOf("codex", "opencode") }
        )

        val company = service.createCompany(
            name = "Dashboard Runtime Co",
            rootPath = repoRoot.toString(),
            defaultBaseBranch = "master"
        )
        service.createGoal(
            companyId = company.id,
            title = "Resume on dashboard",
            description = "Opening the company dashboard should revive autonomous execution.",
            autonomyEnabled = true,
            startRuntimeIfNeeded = false
        )
        service.stopCompanyRuntime(company.id)
        val taskIdsBeforeDashboard = stateStore.load().tasks.filter { it.issueId != null }.map { it.id }.toSet()

        service.companyDashboardPrepared(company.id)
        delay(150)

        val runtime = service.runtimeStatus(company.id)
        runtime.status shouldBe CompanyRuntimeStatus.STOPPED
        runtime.manuallyStoppedAt shouldNotBe null
        stateStore.load().tasks.filter { it.issueId != null }.map { it.id }.toSet() shouldBe taskIdsBeforeDashboard
    }

    test("company dashboard re-ticks autonomous companies when pending issues are idle") {
        val appHome = Files.createTempDirectory("desktop-dashboard-idle-home")
        val repoRoot = Files.createDirectories(Files.createTempDirectory("desktop-dashboard-idle-test").resolve("repo"))
        val worktreeRoot = Files.createDirectories(Files.createTempDirectory("desktop-dashboard-idle-worktree"))
        val stateStore = DesktopStateStore { appHome }
        val gitWorkspaceService = mockk<GitWorkspaceService>()
        val agentExecutor = mockk<AgentExecutor>()
        coEvery { gitWorkspaceService.ensureInitializedRepositoryRoot(any(), any()) } returns repoRoot
        coEvery { gitWorkspaceService.resolveRepositoryRoot(any()) } returns repoRoot
        coEvery { gitWorkspaceService.detectDefaultBranch(any()) } returns "master"
        coEvery { gitWorkspaceService.detectRemoteUrl(any()) } returns "https://github.com/heodongun/cotor.git"
        coEvery { gitWorkspaceService.ensureWorktree(any(), any(), any(), any(), any()) } answers {
            val agentName = invocation.args[3] as String
            WorktreeBinding(
                branchName = "codex/cotor/dashboard-idle/$agentName",
                worktreePath = worktreeRoot.resolve(agentName)
            )
        }
        coEvery { gitWorkspaceService.publishRun(any(), any(), any(), any(), any(), any(), any()) } returns PublishMetadata()
        coEvery { gitWorkspaceService.ensureGitHubPublishReady(any(), any()) } returns GitHubPublishReadiness(ready = true)
        coEvery { agentExecutor.executeAgent(any(), any(), any()) } answers {
            val agent = invocation.args[0] as AgentConfig
            AgentResult(
                agentName = agent.name,
                isSuccess = true,
                output = "done",
                error = null,
                duration = 25,
                metadata = emptyMap(),
                processId = 6101
            )
        }
        val service = DesktopAppService(
            stateStore = stateStore,
            gitWorkspaceService = gitWorkspaceService,
            configRepository = mockk<ConfigRepository>(relaxed = true),
            agentExecutor = agentExecutor,
            companyRuntimeTickIntervalMs = 50,
            commandAvailability = { command -> command in setOf("codex", "opencode") }
        )

        val company = service.createCompany(
            name = "Dashboard Idle Co",
            rootPath = repoRoot.toString(),
            defaultBaseBranch = "master"
        )
        val baseState = stateStore.load()
        val workspace = baseState.workspaces.first { it.repositoryId == company.repositoryId }
        val projectContext = baseState.projectContexts.first { it.companyId == company.id }
        val assigneeProfile = service.listOrgProfiles().first { it.companyId == company.id && it.enabled }
        val now = System.currentTimeMillis()
        val goal = CompanyGoal(
            id = "goal-dashboard-idle",
            companyId = company.id,
            projectContextId = projectContext.id,
            title = "Recover idle work",
            description = "The dashboard should resume pending autonomous work.",
            status = GoalStatus.ACTIVE,
            autonomyEnabled = true,
            createdAt = now,
            updatedAt = now
        )
        val pendingIssue = CompanyIssue(
            id = "issue-dashboard-idle",
            companyId = company.id,
            projectContextId = projectContext.id,
            goalId = goal.id,
            workspaceId = workspace.id,
            title = "Resume delegated execution",
            description = "Delegated issue left idle.",
            status = IssueStatus.DELEGATED,
            priority = 1,
            kind = "execution",
            assigneeProfileId = assigneeProfile.id,
            createdAt = now,
            updatedAt = now - 10_000
        )
        stateStore.save(
            baseState.copy(
                goals = baseState.goals + goal,
                issues = baseState.issues + pendingIssue,
                companyRuntimes = baseState.companyRuntimes.map {
                    if (it.companyId == company.id) {
                        it.copy(
                            status = CompanyRuntimeStatus.RUNNING,
                            lastTickAt = now - 10_000,
                            lastAction = "stale-running-state",
                            manuallyStoppedAt = null
                        )
                    } else {
                        it
                    }
                }
            )
        )

        service.companyDashboardPrepared(company.id)

        withTimeout(30_000) {
            while (stateStore.load().tasks.none { it.issueId == pendingIssue.id }) {
                service.companyDashboardPrepared(company.id)
                delay(100)
            }
        }

        stateStore.load().tasks.filter { it.issueId == pendingIssue.id }.map { it.issueId }.distinct() shouldContainExactly listOf(pendingIssue.id)
    }

    test("company dashboard read only does not re-tick autonomous companies when pending issues are idle") {
        val appHome = Files.createTempDirectory("desktop-dashboard-readonly-home")
        val repoRoot = Files.createDirectories(Files.createTempDirectory("desktop-dashboard-readonly-test").resolve("repo"))
        val worktreeRoot = Files.createDirectories(Files.createTempDirectory("desktop-dashboard-readonly-worktree"))
        val stateStore = DesktopStateStore { appHome }
        val gitWorkspaceService = mockk<GitWorkspaceService>()
        val agentExecutor = mockk<AgentExecutor>()
        coEvery { gitWorkspaceService.ensureInitializedRepositoryRoot(any(), any()) } returns repoRoot
        coEvery { gitWorkspaceService.resolveRepositoryRoot(any()) } returns repoRoot
        coEvery { gitWorkspaceService.detectDefaultBranch(any()) } returns "master"
        coEvery { gitWorkspaceService.detectRemoteUrl(any()) } returns "https://github.com/heodongun/cotor.git"
        coEvery { gitWorkspaceService.ensureWorktree(any(), any(), any(), any(), any()) } answers {
            val agentName = invocation.args[3] as String
            WorktreeBinding(
                branchName = "codex/cotor/dashboard-readonly/$agentName",
                worktreePath = worktreeRoot.resolve(agentName)
            )
        }
        coEvery { gitWorkspaceService.publishRun(any(), any(), any(), any(), any(), any(), any()) } returns PublishMetadata()
        coEvery { gitWorkspaceService.ensureGitHubPublishReady(any(), any()) } returns GitHubPublishReadiness(ready = true)
        coEvery { agentExecutor.executeAgent(any(), any(), any()) } answers {
            val agent = invocation.args[0] as AgentConfig
            AgentResult(
                agentName = agent.name,
                isSuccess = true,
                output = "done",
                error = null,
                duration = 25,
                metadata = emptyMap(),
                processId = 6201
            )
        }
        val service = DesktopAppService(
            stateStore = stateStore,
            gitWorkspaceService = gitWorkspaceService,
            configRepository = mockk<ConfigRepository>(relaxed = true),
            agentExecutor = agentExecutor,
            companyRuntimeTickIntervalMs = 50,
            commandAvailability = { command -> command in setOf("codex", "opencode") }
        )

        val company = service.createCompany(
            name = "Dashboard Read Only Co",
            rootPath = repoRoot.toString(),
            defaultBaseBranch = "master"
        )
        service.stopCompanyRuntime(company.id)
        delay(100)
        val baseState = stateStore.load()
        val workspace = baseState.workspaces.first { it.repositoryId == company.repositoryId }
        val projectContext = baseState.projectContexts.first { it.companyId == company.id }
        val assigneeProfile = service.listOrgProfiles().first { it.companyId == company.id && it.enabled }
        val now = System.currentTimeMillis()
        val goal = CompanyGoal(
            id = "goal-dashboard-readonly",
            companyId = company.id,
            projectContextId = projectContext.id,
            title = "Observe idle work only",
            description = "Read-only dashboard access must not resume autonomous work.",
            status = GoalStatus.ACTIVE,
            autonomyEnabled = true,
            createdAt = now,
            updatedAt = now
        )
        val pendingIssue = CompanyIssue(
            id = "issue-dashboard-readonly",
            companyId = company.id,
            projectContextId = projectContext.id,
            goalId = goal.id,
            workspaceId = workspace.id,
            title = "Remain delegated until prepared dashboard runs",
            description = "Delegated issue should stay idle during read-only access.",
            status = IssueStatus.DELEGATED,
            priority = 1,
            kind = "execution",
            assigneeProfileId = assigneeProfile.id,
            createdAt = now,
            updatedAt = now - 10_000
        )
        stateStore.save(
            baseState.copy(
                goals = baseState.goals + goal,
                issues = baseState.issues + pendingIssue,
                companyRuntimes = baseState.companyRuntimes.map {
                    if (it.companyId == company.id) {
                        it.copy(
                            status = CompanyRuntimeStatus.RUNNING,
                            lastTickAt = now - 10_000,
                            lastAction = "stale-running-state",
                            manuallyStoppedAt = null
                        )
                    } else {
                        it
                    }
                }
            )
        )

        service.companyDashboardReadOnly(company.id)
        delay(250)

        stateStore.load().tasks.none { it.issueId == pendingIssue.id } shouldBe true

        service.companyDashboardPrepared(company.id)
        withTimeout(30_000) {
            while (stateStore.load().tasks.none { it.issueId == pendingIssue.id }) {
                delay(100)
            }
        }

        stateStore.load().tasks.filter { it.issueId == pendingIssue.id }.map { it.issueId }.distinct() shouldContainExactly listOf(pendingIssue.id)
    }
})
