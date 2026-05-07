package com.cotor.app

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContain
import io.kotest.matchers.collections.shouldNotContain
import io.kotest.matchers.shouldBe
import io.mockk.mockk
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.FileTime

class DesktopAppServiceRuntimeCleanupTest : FunSpec({
    test("shutdown clears retained runtime cache state") {
        val appHome = Files.createTempDirectory("desktop-app-service-runtime-cleanup")
        val service = DesktopAppService(
            stateStore = DesktopStateStore { appHome },
            gitWorkspaceService = mockk(relaxed = true),
            configRepository = mockk(relaxed = true),
            agentExecutor = mockk(relaxed = true)
        )

        service.primeRuntimeCachesForTesting(companyId = "company-cache", taskId = "task-cache")
        service.runtimeCacheSizesForTesting().values.any { it > 0 } shouldBe true

        service.shutdown()

        service.runtimeCacheSizesForTesting().values.forEach { it shouldBe 0 }
    }

    test("runtime cleanup protects active issue and review worktrees while pruning stale terminal worktrees") {
        val appHome = Files.createTempDirectory("desktop-app-service-runtime-retention")
        val stateStore = DesktopStateStore { appHome }
        val service = testService(stateStore)
        val now = System.currentTimeMillis()
        val repo = Files.createTempDirectory("cotor-retention-repo")
        val activePath = worktree(repo, "task-active", "builder", now - 20.days)
        val openPath = worktree(repo, "task-open", "builder", now - 20.days)
        val reviewPath = worktree(repo, "task-review", "qa", now - 20.days)
        val stalePath = worktree(repo, "task-stale", "builder", now - 20.days)
        val companyId = "company-retention"

        stateStore.save(
            baseState(companyId, repo).copy(
                tasks = listOf(
                    task("task-active", "issue-active"),
                    task("task-stale", "issue-stale")
                ),
                issues = listOf(
                    issue("issue-active", companyId, IssueStatus.IN_PROGRESS, activePath),
                    issue("issue-open", companyId, IssueStatus.IN_PROGRESS, openPath),
                    issue("issue-review", companyId, IssueStatus.IN_REVIEW, reviewPath, pullRequestNumber = 7),
                    issue("issue-stale", companyId, IssueStatus.DONE, stalePath)
                ),
                reviewQueue = listOf(
                    ReviewQueueItem(
                        id = "review-1",
                        companyId = companyId,
                        issueId = "issue-review",
                        runId = "run-review",
                        worktreePath = reviewPath.toString(),
                        pullRequestNumber = 7,
                        status = ReviewQueueStatus.READY_FOR_CEO,
                        createdAt = now,
                        updatedAt = now
                    )
                ),
                runs = listOf(
                    run("run-active", "task-active", activePath, AgentRunStatus.RUNNING, now),
                    run("run-stale", "task-stale", stalePath, AgentRunStatus.COMPLETED, now - 20.days)
                )
            )
        )

        val preview = service.previewRuntimeCleanup(companyId)
        val eligiblePaths = preview.candidates.filter { it.eligible }.mapNotNull { it.path }
        eligiblePaths shouldContain stalePath.toString()
        eligiblePaths shouldNotContain activePath.toString()
        eligiblePaths shouldNotContain openPath.toString()
        eligiblePaths shouldNotContain reviewPath.toString()

        val result = service.cleanupRuntime(RuntimeCleanupRequest(companyId = companyId, apply = true))
        result.deletedWorktreeCount shouldBe 1
        Files.exists(stalePath) shouldBe false
        Files.exists(activePath) shouldBe true
        Files.exists(openPath) shouldBe true
        Files.exists(reviewPath) shouldBe true
    }

    test("runtime cleanup keeps young orphan worktrees by default") {
        val appHome = Files.createTempDirectory("desktop-app-service-runtime-orphan")
        val stateStore = DesktopStateStore { appHome }
        val service = testService(stateStore)
        val now = System.currentTimeMillis()
        val repo = Files.createTempDirectory("cotor-retention-orphan")
        val orphanPath = worktree(repo, "task-orphan", "builder", now - 10.days)
        val companyId = "company-orphan"
        stateStore.save(baseState(companyId, repo))

        val preview = service.previewRuntimeCleanup(companyId)
        val candidate = preview.candidates.first { it.path == orphanPath.toString() }
        candidate.classification shouldBe "unknown"
        candidate.eligible shouldBe false
    }

    test("runtime tick failures stay running until retry budget is exhausted") {
        val appHome = Files.createTempDirectory("desktop-app-service-runtime-loop")
        val stateStore = DesktopStateStore { appHome }
        val service = testService(stateStore)
        val companyId = "company-loop"
        stateStore.save(
            DesktopAppState(
                companies = listOf(company(companyId, Files.createTempDirectory("runtime-loop-repo"))),
                companyRuntimes = listOf(CompanyRuntimeSnapshot(companyId = companyId, status = CompanyRuntimeStatus.RUNNING))
            )
        )

        service.recordCompanyRuntimeTickFailureForTesting(companyId, IllegalStateException("recoverable"), 1, 5)
        service.runtimeStatus(companyId).status shouldBe CompanyRuntimeStatus.RUNNING
        service.runtimeStatus(companyId).consecutiveFailures shouldBe 1

        service.recordCompanyRuntimeTickFailureForTesting(companyId, IllegalStateException("recoverable"), 4, 5)
        service.runtimeStatus(companyId).status shouldBe CompanyRuntimeStatus.RUNNING
        service.runtimeStatus(companyId).lastAction shouldBe "runtime-tick-retry"

        service.recordCompanyRuntimeTickFailureForTesting(companyId, IllegalStateException("recoverable"), 5, 5)
        service.runtimeStatus(companyId).status shouldBe CompanyRuntimeStatus.ERROR
        service.runtimeStatus(companyId).lastAction shouldBe "runtime-error"
    }
})

private val Int.days: Long get() = this * 24L * 60L * 60L * 1_000L

private fun testService(stateStore: DesktopStateStore): DesktopAppService =
    DesktopAppService(
        stateStore = stateStore,
        gitWorkspaceService = mockk(relaxed = true),
        configRepository = mockk(relaxed = true),
        agentExecutor = mockk(relaxed = true),
        autoStartAutomationRefresh = false
    )

private fun worktree(repo: Path, taskId: String, agent: String, modifiedAt: Long): Path {
    val path = repo.resolve(".cotor").resolve("worktrees").resolve(taskId).resolve(agent).toAbsolutePath().normalize()
    Files.createDirectories(path)
    Files.setLastModifiedTime(path, FileTime.fromMillis(modifiedAt))
    return path
}

private fun baseState(companyId: String, repo: Path): DesktopAppState =
    DesktopAppState(
        companies = listOf(company(companyId, repo)),
        repositories = listOf(
            ManagedRepository(
                id = "repo-$companyId",
                name = "Repo",
                localPath = repo.toString(),
                sourceKind = RepositorySourceKind.LOCAL,
                defaultBranch = "main",
                createdAt = 1,
                updatedAt = 1
            )
        ),
        workspaces = listOf(
            Workspace(
                id = "workspace",
                repositoryId = "repo-$companyId",
                name = "Main",
                baseBranch = "main",
                createdAt = 1,
                updatedAt = 1
            )
        ),
        companyRuntimes = listOf(CompanyRuntimeSnapshot(companyId = companyId))
    )

private fun company(companyId: String, repo: Path): Company =
    Company(
        id = companyId,
        name = "Company",
        rootPath = repo.toString(),
        repositoryId = "repo-$companyId",
        defaultBaseBranch = "main",
        createdAt = 1,
        updatedAt = 1
    )

private fun task(taskId: String, issueId: String): AgentTask =
    AgentTask(
        id = taskId,
        workspaceId = "workspace",
        issueId = issueId,
        title = taskId,
        prompt = "prompt",
        agents = listOf("Builder"),
        status = DesktopTaskStatus.COMPLETED,
        createdAt = 1,
        updatedAt = 1
    )

private fun issue(
    issueId: String,
    companyId: String,
    status: IssueStatus,
    worktreePath: Path,
    pullRequestNumber: Int? = null
): CompanyIssue =
    CompanyIssue(
        id = issueId,
        companyId = companyId,
        goalId = "goal",
        workspaceId = "workspace",
        title = issueId,
        description = issueId,
        status = status,
        worktreePath = worktreePath.toString(),
        pullRequestNumber = pullRequestNumber,
        createdAt = 1,
        updatedAt = 1
    )

private fun run(
    runId: String,
    taskId: String,
    worktreePath: Path,
    status: AgentRunStatus,
    updatedAt: Long
): AgentRun =
    AgentRun(
        id = runId,
        taskId = taskId,
        workspaceId = "workspace",
        repositoryId = "repo-company-retention",
        agentName = "Builder",
        repoRoot = worktreePath.parent?.parent?.parent?.parent?.toString().orEmpty(),
        baseBranch = "main",
        branchName = "branch-$runId",
        worktreePath = worktreePath.toString(),
        status = status,
        createdAt = updatedAt,
        updatedAt = updatedAt
    )
