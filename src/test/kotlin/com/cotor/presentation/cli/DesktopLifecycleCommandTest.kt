package com.cotor.presentation.cli

/**
 * File overview for DesktopLifecycleCommandTest.
 *
 * This file belongs to the test suite that documents expected behavior and protects against regressions.
 * It groups declarations around desktop lifecycle command test so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import com.github.ajalt.clikt.testing.test
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import kotlin.io.path.createDirectories
import kotlin.io.path.createFile
import kotlin.io.path.createParentDirectories
import kotlin.io.path.exists
import kotlin.io.path.writeText

class DesktopLifecycleCommandTest : FunSpec({
    test("desktopInstallHomeDirectory prefers HOME over user.home") {
        val resolved = desktopInstallHomeDirectory(
            environment = mapOf("HOME" to "/tmp/cotor-desktop-home"),
            systemHome = "/tmp/cotor-system-home"
        )

        resolved shouldBe Paths.get("/tmp/cotor-desktop-home").toAbsolutePath().normalize()
    }

    test("detectDesktopInstallLayout recognizes a source checkout only with full source markers") {
        val root = Files.createTempDirectory("cotor-source-layout")
        root.resolve("gradlew").createFile()
        root.resolve("build.gradle.kts").createFile()
        root.resolve("shell/install-desktop-app.sh").createParentDirectories().createFile()
        root.resolve("macos/Package.swift").createParentDirectories().createFile()

        val layout = detectDesktopInstallLayout(
            environment = emptyMap(),
            cwd = root,
            codeSourcePath = null
        )

        layout shouldBe DesktopInstallLayout(
            kind = DesktopInstallLayoutKind.SOURCE_CHECKOUT,
            root = root
        )
    }

    test("detectDesktopInstallLayout recognizes a packaged install from env markers") {
        val packagedRoot = Files.createTempDirectory("cotor-packaged-layout")
        createPackagedBundle(packagedRoot)

        val layout = detectDesktopInstallLayout(
            environment = mapOf(
                "COTOR_INSTALL_KIND" to "packaged",
                "COTOR_INSTALL_ROOT" to packagedRoot.toString()
            ),
            cwd = packagedRoot,
            codeSourcePath = null
        )

        layout shouldBe DesktopInstallLayout(
            kind = DesktopInstallLayoutKind.PACKAGED_INSTALL,
            root = packagedRoot,
            desktopBundle = packagedRoot.resolve("desktop").resolve(BUNDLED_DESKTOP_APP_NAME)
        )
    }

    test("install runs desktop install script on macOS for source checkouts") {
        val root = Paths.get("/tmp/cotor-install-test")
        val calls = mutableListOf<Pair<Path, String>>()
        val command = InstallCommand(
            scriptRunner = { projectRoot, scriptName ->
                calls += projectRoot to scriptName
                DesktopScriptResult(exitCode = 0, output = "installed\n")
            },
            packagedActionRunner = { _, _ -> error("should not run packaged flow") },
            layoutResolver = { DesktopInstallLayout(DesktopInstallLayoutKind.SOURCE_CHECKOUT, root) },
            osNameProvider = { "Mac OS X" }
        )

        val result = command.test("")

        result.statusCode shouldBe 0
        result.output shouldContain "installed"
        calls shouldBe listOf(root to "install-desktop-app.sh")
    }

    test("update runs packaged desktop action on macOS when wrapper resolves packaged layout") {
        val packagedRoot = Files.createTempDirectory("cotor-packaged-command")
        createPackagedBundle(packagedRoot)
        val calls = mutableListOf<Pair<DesktopInstallLayout, DesktopInstallAction>>()
        val command = UpdateCommand(
            scriptRunner = { _, _ -> error("should not run source script") },
            packagedActionRunner = { layout, action ->
                calls += layout to action
                DesktopScriptResult(exitCode = 0, output = "updated\n")
            },
            layoutResolver = {
                DesktopInstallLayout(
                    DesktopInstallLayoutKind.PACKAGED_INSTALL,
                    packagedRoot,
                    packagedRoot.resolve("desktop").resolve(BUNDLED_DESKTOP_APP_NAME)
                )
            },
            osNameProvider = { "Mac OS X" }
        )

        val result = command.test("")

        result.statusCode shouldBe 0
        result.output shouldContain "updated"
        calls.single().second shouldBe DesktopInstallAction.UPDATE
    }

    test("update verify runs installed desktop verification after successful source update") {
        val root = Paths.get("/tmp/cotor-update-verify-test")
        val lifecycleCalls = mutableListOf<Pair<Path, String>>()
        val verificationCalls = mutableListOf<DesktopInstallLayout>()
        val layout = DesktopInstallLayout(DesktopInstallLayoutKind.SOURCE_CHECKOUT, root)
        val command = UpdateCommand(
            scriptRunner = { projectRoot, scriptName ->
                lifecycleCalls += projectRoot to scriptName
                DesktopScriptResult(exitCode = 0, output = "updated\n")
            },
            packagedActionRunner = { _, _ -> error("should not run packaged flow") },
            verificationRunner = {
                verificationCalls += it
                DesktopScriptResult(exitCode = 0, output = "verified\n")
            },
            layoutResolver = { layout },
            osNameProvider = { "Mac OS X" }
        )

        val result = command.test("--verify")

        result.statusCode shouldBe 0
        result.output shouldContain "updated"
        result.output shouldContain "verified"
        lifecycleCalls shouldBe listOf(root to "update-desktop-app.sh")
        verificationCalls shouldBe listOf(layout)
    }

    test("upgrade is a user-facing alias for desktop update") {
        val root = Paths.get("/tmp/cotor-upgrade-alias-test")
        val calls = mutableListOf<Pair<Path, String>>()
        val command = UpgradeCommand(
            scriptRunner = { projectRoot, scriptName ->
                calls += projectRoot to scriptName
                DesktopScriptResult(exitCode = 0, output = "upgraded\n")
            },
            packagedActionRunner = { _, _ -> error("should not run packaged flow") },
            verificationRunner = { DesktopScriptResult(exitCode = 0, output = "") },
            layoutResolver = { DesktopInstallLayout(DesktopInstallLayoutKind.SOURCE_CHECKOUT, root) },
            osNameProvider = { "Mac OS X" }
        )

        val result = command.test("")

        result.statusCode shouldBe 0
        result.output shouldContain "upgraded"
        calls shouldBe listOf(root to "update-desktop-app.sh")
    }

    test("runPackagedDesktopAction installs the bundled app into the override root") {
        val packagedRoot = Files.createTempDirectory("cotor-packaged-install")
        val bundle = createPackagedBundle(packagedRoot)
        val installRoot = Files.createTempDirectory("cotor-app-install-root")

        val result = runPackagedDesktopAction(
            layout = DesktopInstallLayout(
                kind = DesktopInstallLayoutKind.PACKAGED_INSTALL,
                root = packagedRoot,
                desktopBundle = bundle
            ),
            action = DesktopInstallAction.INSTALL,
            environment = mapOf("COTOR_DESKTOP_INSTALL_ROOT" to installRoot.toString()),
            homeDirectoryProvider = { installRoot.resolve("home") }
        )

        result.exitCode shouldBe 0
        installRoot.resolve(BUNDLED_DESKTOP_APP_NAME).exists() shouldBe true
        installRoot.resolve(BUNDLED_DESKTOP_APP_NAME).resolve("Contents/Info.plist").exists() shouldBe true
    }

    test("runPackagedDesktopAction delete removes installed artifacts from the override root") {
        val packagedRoot = Files.createTempDirectory("cotor-packaged-delete")
        val bundle = createPackagedBundle(packagedRoot)
        val installRoot = Files.createTempDirectory("cotor-app-delete-root")
        val installedBundle = installRoot.resolve(BUNDLED_DESKTOP_APP_NAME)
        installedBundle.resolve("Contents").createDirectories()
        installedBundle.resolve("Contents/Info.plist").createFile()

        val result = runPackagedDesktopAction(
            layout = DesktopInstallLayout(
                kind = DesktopInstallLayoutKind.PACKAGED_INSTALL,
                root = packagedRoot,
                desktopBundle = bundle
            ),
            action = DesktopInstallAction.DELETE,
            environment = mapOf("COTOR_DESKTOP_INSTALL_ROOT" to installRoot.toString()),
            homeDirectoryProvider = { installRoot.resolve("home") }
        )

        result.exitCode shouldBe 0
        installedBundle.exists() shouldBe false
    }

    test("runPackagedDesktopAction update runs Homebrew through the injectable bounded runner") {
        val packagedRoot = Files.createTempDirectory("cotor-packaged-update")
        val bundle = createPackagedBundle(packagedRoot)
        val installRoot = Files.createTempDirectory("cotor-app-update-root")
        val calls = mutableListOf<List<String>>()

        val result = runPackagedDesktopAction(
            layout = DesktopInstallLayout(
                kind = DesktopInstallLayoutKind.PACKAGED_INSTALL,
                root = packagedRoot,
                desktopBundle = bundle
            ),
            action = DesktopInstallAction.UPDATE,
            environment = mapOf("COTOR_DESKTOP_INSTALL_ROOT" to installRoot.toString()),
            homeDirectoryProvider = { installRoot.resolve("home") },
            homebrewRunner = { args ->
                calls += args
                DesktopScriptResult(exitCode = 0, output = "homebrew ${args.first()} ok\n")
            }
        )

        result.exitCode shouldBe 0
        calls shouldBe listOf(
            listOf("tap", COTOR_BREW_TAP, COTOR_BREW_TAP_URL),
            listOf("upgrade", COTOR_BREW_FORMULA)
        )
        installRoot.resolve(BUNDLED_DESKTOP_APP_NAME).exists() shouldBe true
        result.output shouldContain "Homebrew package upgraded"
    }

    test("resolveInstalledDesktopAppPath respects explicit app path and install root") {
        val installRoot = Files.createTempDirectory("cotor-resolve-installed-app")
        val appPath = installRoot.resolve(BUNDLED_DESKTOP_APP_NAME)
        appPath.resolve("Contents").createDirectories()

        resolveInstalledDesktopAppPath(
            environment = mapOf("COTOR_DESKTOP_APP_PATH" to appPath.toString()),
            homeDirectoryProvider = { installRoot.resolve("home") }
        ) shouldBe appPath

        resolveInstalledDesktopAppPath(
            environment = mapOf("COTOR_DESKTOP_INSTALL_ROOT" to installRoot.toString()),
            homeDirectoryProvider = { installRoot.resolve("home") }
        ) shouldBe appPath
    }

    test("runDesktopScript times out hanging source lifecycle scripts") {
        val root = Files.createTempDirectory("cotor-desktop-script-timeout")
        root.resolve("shell").createDirectories()
        root.resolve("shell/install-desktop-app.sh").writeText(
            """
            #!/usr/bin/env bash
            printf 'started\n'
            sleep 30
            """.trimIndent()
        )

        val result = runDesktopScript(
            projectRoot = root,
            scriptName = "install-desktop-app.sh",
            timeoutSeconds = 1,
            outputLimitChars = 1024
        )

        result.exitCode shouldBe 124
        result.output shouldContain "started"
        result.output shouldContain "timed out after 1s"
    }

    test("runDesktopScript keeps a bounded output tail") {
        val root = Files.createTempDirectory("cotor-desktop-script-output")
        root.resolve("shell").createDirectories()
        root.resolve("shell/install-desktop-app.sh").writeText(
            """
            #!/usr/bin/env bash
            printf 'prefix-'
            printf '0123456789%.0s' {1..20}
            printf -- '-suffix'
            """.trimIndent()
        )

        val result = runDesktopScript(
            projectRoot = root,
            scriptName = "install-desktop-app.sh",
            timeoutSeconds = 5,
            outputLimitChars = 32
        )

        result.exitCode shouldBe 0
        result.output shouldContain "truncated to last 32 chars"
        result.output shouldContain "-suffix"
    }

    test("desktop lifecycle commands fail outside macOS") {
        val command = InstallCommand(
            scriptRunner = { _, _ -> error("should not run") },
            packagedActionRunner = { _, _ -> error("should not run") },
            layoutResolver = { DesktopInstallLayout(DesktopInstallLayoutKind.SOURCE_CHECKOUT, Paths.get("/tmp/cotor-non-mac")) },
            osNameProvider = { "Linux" }
        )

        val result = command.test("")

        result.statusCode shouldBe 1
        result.output shouldContain "supports macOS only"
    }
})

private fun createPackagedBundle(root: Path): Path {
    val bundle = root.resolve("desktop").resolve(BUNDLED_DESKTOP_APP_NAME)
    bundle.resolve("Contents").createDirectories()
    bundle.resolve("Contents/Info.plist").createFile()
    return bundle
}
