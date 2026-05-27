package com.cotor.app

import com.cotor.data.config.ConfigRepository
import com.cotor.data.config.YamlParser
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import io.kotest.matchers.string.shouldContain
import io.mockk.mockk
import kotlinx.coroutines.delay
import java.nio.file.Files
import java.nio.file.attribute.PosixFilePermission
import kotlin.io.path.readText
import kotlin.io.path.writeText

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

    test("openSession returns failed transcript when the TUI process cannot start") {
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
            logger = mockk(relaxed = true),
            ptyBridgeExecutable = "/definitely/missing/cotor-python3"
        )

        val session = service.openSession("workspace-1", preferredAgent = "echo")

        session.status shouldBe TuiSessionStatus.FAILED
        session.exitCode shouldBe 127
        session.transcript shouldContain "Cotor desktop TUI failed to start."
        session.transcript shouldContain "/definitely/missing/cotor-python3"
        service.getSession(session.id).status shouldBe TuiSessionStatus.FAILED
        service.getDelta(session.id, 0).chunk shouldContain "failed to start"
        service.listSessions().map { it.id } shouldBe listOf(session.id)
        shouldThrow<IllegalStateException> {
            service.sendInput(session.id, "hello\n")
        }

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

    test("terminateSession destroys the TUI process tree") {
        val appHome = Files.createTempDirectory("desktop-tui-session-home")
        val repoRoot = Files.createTempDirectory("desktop-tui-session-repo")
        val marker = Files.createTempFile("desktop-tui-child", ".pid")
        val fakeBridge = Files.createTempFile("desktop-tui-bridge", ".sh")
        fakeBridge.writeText(
            """
            #!/usr/bin/env bash
            sleep 30 &
            printf '%s\n' "${'$'}!" > "$marker"
            wait
            """.trimIndent()
        )
        Files.setPosixFilePermissions(
            fakeBridge,
            setOf(
                PosixFilePermission.OWNER_READ,
                PosixFilePermission.OWNER_WRITE,
                PosixFilePermission.OWNER_EXECUTE
            )
        )
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
            logger = mockk(relaxed = true),
            ptyBridgeExecutable = fakeBridge.toString()
        )

        val session = service.openSession("workspace-1", preferredAgent = "echo")
        val childPid = waitForPid(marker)

        ProcessHandle.of(childPid).orElse(null)?.isAlive shouldBe true

        service.terminateSession(session.id)

        eventuallyFalse {
            ProcessHandle.of(childPid).orElse(null)?.isAlive == true
        } shouldBe true
        service.shutdown()
    }
})

private suspend fun waitForPid(path: java.nio.file.Path): Long {
    repeat(20) {
        val text = runCatching { path.readText().trim() }.getOrDefault("")
        text.toLongOrNull()?.let { return it }
        delay(100)
    }
    error("Timed out waiting for pid marker: $path")
}

private suspend fun eventuallyFalse(predicate: () -> Boolean): Boolean {
    repeat(20) {
        if (!predicate()) {
            return true
        }
        delay(100)
    }
    return !predicate()
}
