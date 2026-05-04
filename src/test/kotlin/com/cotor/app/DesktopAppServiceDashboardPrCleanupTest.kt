package com.cotor.app

import com.cotor.data.config.ConfigRepository
import com.cotor.domain.executor.AgentExecutor
import com.cotor.model.ProcessExecutionException
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import java.nio.file.Files

class DesktopAppServiceDashboardPrCleanupTest : FunSpec({
    test("createCompany falls back to detected default branch when requested branch is missing") {
        val appHome = Files.createTempDirectory("desktop-create-company-default-branch-home")
        val repoRoot = Files.createDirectories(Files.createTempDirectory("desktop-create-company-default-branch-repo").resolve("repo"))
        val stateStore = DesktopStateStore { appHome }
        val gitWorkspaceService = mockk<GitWorkspaceService>(relaxed = true)
        coEvery { gitWorkspaceService.ensureInitializedRepositoryRoot(any(), any()) } returns repoRoot
        coEvery { gitWorkspaceService.detectDefaultBranch(repoRoot) } returns "main"
        coEvery { gitWorkspaceService.hasLocalBranch(repoRoot, "master") } returns false
        coEvery { gitWorkspaceService.detectRemoteUrl(repoRoot) } returns null
        val service = DesktopAppService(
            stateStore = stateStore,
            gitWorkspaceService = gitWorkspaceService,
            configRepository = mockk<ConfigRepository>(relaxed = true),
            agentExecutor = mockk<AgentExecutor>(relaxed = true)
        )

        val company = service.createCompany(
            name = "Main Branch Co",
            rootPath = repoRoot.toString(),
            defaultBaseBranch = "master"
        )

        company.defaultBaseBranch shouldBe "main"
        val loaded = stateStore.load()
        loaded.workspaces.single().baseBranch shouldBe "main"
        loaded.agentCapabilityProfiles.size shouldBe loaded.companyAgentDefinitions.size
        loaded.agentCapabilityProfiles.forEach { profile ->
            profile.settings.getValue(CapabilityKey.SHELL_EXEC).mode shouldBe CapabilityMode.AUTO
            profile.settings.getValue(CapabilityKey.SHELL_EXEC).pathAllowlist shouldBe listOf(repoRoot.toAbsolutePath().normalize().toString())
            profile.settings.getValue(CapabilityKey.GIT_WRITE).mode shouldBe CapabilityMode.AUTO
            profile.settings.getValue(CapabilityKey.GITHUB_PR_CREATE).mode shouldBe CapabilityMode.APPROVAL_REQUIRED
        }
    }

    test("company dashboard skips superseded PR cleanup when there are no tracked live pull requests") {
        val appHome = Files.createTempDirectory("desktop-dashboard-no-tracked-prs-home")
        val repoRoot = Files.createDirectories(Files.createTempDirectory("desktop-dashboard-no-tracked-prs-repo").resolve("repo"))
        val stateStore = DesktopStateStore { appHome }
        val gitWorkspaceService = mockk<GitWorkspaceService>(relaxed = true)
        coEvery { gitWorkspaceService.ensureInitializedRepositoryRoot(any(), any()) } returns repoRoot
        coEvery {
            gitWorkspaceService.closeSupersededManagedPullRequests(any(), any(), any(), any())
        } throws ProcessExecutionException(
            message = "GH command failed",
            exitCode = 1,
            stdout = "",
            stderr = ""
        )
        val service = DesktopAppService(
            stateStore = stateStore,
            gitWorkspaceService = gitWorkspaceService,
            configRepository = mockk<ConfigRepository>(relaxed = true),
            agentExecutor = mockk<AgentExecutor>(relaxed = true)
        )

        val company = service.createCompany(
            name = "Dashboard No PR Co",
            rootPath = repoRoot.toString(),
            defaultBaseBranch = "master"
        )

        service.companyDashboard(company.id)

        coVerify(exactly = 0) {
            gitWorkspaceService.closeSupersededManagedPullRequests(any(), any(), any(), any())
        }
    }
})
