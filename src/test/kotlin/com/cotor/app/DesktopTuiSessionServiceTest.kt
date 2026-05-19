package com.cotor.app

import com.cotor.data.config.ConfigRepository
import com.cotor.data.config.YamlParser
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import io.mockk.mockk
import kotlinx.coroutines.delay
import java.nio.file.Files

class DesktopTuiSessionServiceTest : FunSpec({
    test("listSessions includes active sessions in most-recent order") {
        val appHome = Files.createTempDirectory("desktop-tui-session-home")
        val repoRoot = Files.createTempDirectory("desktop-tui-session-repo")
        val stateStore = DesktopStateStore { appHome }
        stateStore.save(
            DesktopAppState(
                repositories = listOf(
                    ManagedRepository(
                        id = "repo-1",
                        name = "repo",
                        localPath = repoRoot.toString(),
                        sourceKind = RepositorySourceKind.LOCAL,
                        defaultBranch = "master",
                        createdAt = 1,
                        updatedAt = 1
                    )
                ),
                workspaces = listOf(
                    Workspace(
                        id = "workspace-1",
                        repositoryId = "repo-1",
                        name = "repo · master",
                        baseBranch = "master",
                        createdAt = 1,
                        updatedAt = 1
                    )
                )
            )
        )

        val service = DesktopTuiSessionService(
            stateStore = stateStore,
            configRepository = mockk<ConfigRepository>(relaxed = true),
            yamlParser = YamlParser(),
            logger = mockk(relaxed = true)
        )

        val session = service.openSession("workspace-1", preferredAgent = "echo")

        val listed = service.listSessions()

        listed.map { it.id } shouldBe listOf(session.id)

        service.shutdown()
    }

    test("openSession reuses only same workspace session") {
        val appHome = Files.createTempDirectory("desktop-tui-session-home")
        val repoRoot = Files.createTempDirectory("desktop-tui-session-repo")
        val stateStore = DesktopStateStore { appHome }
        stateStore.save(
            DesktopAppState(
                repositories = listOf(
                    ManagedRepository(
                        id = "repo-1",
                        name = "repo",
                        localPath = repoRoot.toString(),
                        sourceKind = RepositorySourceKind.LOCAL,
                        defaultBranch = "master",
                        createdAt = 1,
                        updatedAt = 1
                    )
                ),
                workspaces = listOf(
                    Workspace(id = "workspace-1", repositoryId = "repo-1", name = "repo · master", baseBranch = "master", createdAt = 1, updatedAt = 1),
                    Workspace(id = "workspace-2", repositoryId = "repo-1", name = "repo · dev", baseBranch = "dev", createdAt = 2, updatedAt = 2)
                )
            )
        )
        val service = DesktopTuiSessionService(
            stateStore = stateStore,
            configRepository = mockk<ConfigRepository>(relaxed = true),
            yamlParser = YamlParser(),
            logger = mockk(relaxed = true)
        )

        val first = service.openSession("workspace-1", preferredAgent = "echo")
        val reused = service.openSession("workspace-1", preferredAgent = "echo")

        reused.id shouldBe first.id

        service.shutdown()
    }

    test("openSession creates new session for different workspace even when old session is alive") {
        val appHome = Files.createTempDirectory("desktop-tui-session-home")
        val repoRoot = Files.createTempDirectory("desktop-tui-session-repo")
        val stateStore = DesktopStateStore { appHome }
        stateStore.save(
            DesktopAppState(
                repositories = listOf(
                    ManagedRepository(
                        id = "repo-1",
                        name = "repo",
                        localPath = repoRoot.toString(),
                        sourceKind = RepositorySourceKind.LOCAL,
                        defaultBranch = "master",
                        createdAt = 1,
                        updatedAt = 1
                    )
                ),
                workspaces = listOf(
                    Workspace(id = "workspace-1", repositoryId = "repo-1", name = "repo · master", baseBranch = "master", createdAt = 1, updatedAt = 1),
                    Workspace(id = "workspace-2", repositoryId = "repo-1", name = "repo · dev", baseBranch = "dev", createdAt = 2, updatedAt = 2)
                )
            )
        )
        val service = DesktopTuiSessionService(
            stateStore = stateStore,
            configRepository = mockk<ConfigRepository>(relaxed = true),
            yamlParser = YamlParser(),
            logger = mockk(relaxed = true)
        )

        val ws1Session = service.openSession("workspace-1", preferredAgent = "echo")
        val ws2Session = service.openSession("workspace-2", preferredAgent = "echo")

        ws2Session.id shouldNotBe ws1Session.id
        ws2Session.workspaceId shouldBe "workspace-2"

        service.shutdown()
    }

    test("session repositoryPath always matches requested workspace repository") {
        val appHome = Files.createTempDirectory("desktop-tui-session-home")
        val repoRoot = Files.createTempDirectory("desktop-tui-session-repo")
        val stateStore = DesktopStateStore { appHome }
        stateStore.save(
            DesktopAppState(
                repositories = listOf(
                    ManagedRepository(
                        id = "repo-1",
                        name = "repo",
                        localPath = repoRoot.toString(),
                        sourceKind = RepositorySourceKind.LOCAL,
                        defaultBranch = "master",
                        createdAt = 1,
                        updatedAt = 1
                    )
                ),
                workspaces = listOf(
                    Workspace(id = "workspace-1", repositoryId = "repo-1", name = "repo · master", baseBranch = "master", createdAt = 1, updatedAt = 1)
                )
            )
        )
        val service = DesktopTuiSessionService(
            stateStore = stateStore,
            configRepository = mockk<ConfigRepository>(relaxed = true),
            yamlParser = YamlParser(),
            logger = mockk(relaxed = true)
        )

        val session = service.openSession("workspace-1", preferredAgent = "echo")

        session.repositoryPath shouldBe repoRoot.toString()

        service.shutdown()
    }

    test("terminateSession returns an exited snapshot and removes the session") {
        val appHome = Files.createTempDirectory("desktop-tui-session-home")
        val repoRoot = Files.createTempDirectory("desktop-tui-session-repo")
        val stateStore = DesktopStateStore { appHome }
        stateStore.save(
            DesktopAppState(
                repositories = listOf(
                    ManagedRepository(
                        id = "repo-1",
                        name = "repo",
                        localPath = repoRoot.toString(),
                        sourceKind = RepositorySourceKind.LOCAL,
                        defaultBranch = "master",
                        createdAt = 1,
                        updatedAt = 1
                    )
                ),
                workspaces = listOf(
                    Workspace(
                        id = "workspace-1",
                        repositoryId = "repo-1",
                        name = "repo · master",
                        baseBranch = "master",
                        createdAt = 1,
                        updatedAt = 1
                    )
                )
            )
        )

        val service = DesktopTuiSessionService(
            stateStore = stateStore,
            configRepository = mockk<ConfigRepository>(relaxed = true),
            yamlParser = YamlParser(),
            logger = mockk(relaxed = true)
        )

        val session = service.openSession("workspace-1", preferredAgent = "echo")
        service.sendInput(session.id, "terminate smoke\n")
        delay(300)

        val terminated = service.terminateSession(session.id)

        terminated.status shouldBe TuiSessionStatus.EXITED
        terminated.exitCode shouldNotBe null
        shouldThrow<IllegalArgumentException> {
            service.getSession(session.id)
        }

        service.shutdown()
    }
})
