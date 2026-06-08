package com.cotor.app

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.nio.file.Files

class DesktopUpdateStatusTest : FunSpec({
    test("Homebrew outdated output marks desktop update available even when brew exits nonzero") {
        val installRoot = Files.createTempDirectory("cotor-desktop-update-status")
        val appPath = installRoot.resolve("Cotor Desktop.app")
        appPath.resolve("Contents").toFile().mkdirs()

        val status = desktopUpdateStatusResponse(
            environment = mapOf("COTOR_DESKTOP_APP_PATH" to appPath.toString()),
            homeDirectoryProvider = { installRoot.resolve("home") },
            commandRunner = { command, _ ->
                when {
                    command.contains("list") -> UpdateStatusCommandResult(0, "cotor 1.0.6\n")
                    command.contains("outdated") -> UpdateStatusCommandResult(1, "bssm-oss/cotor/cotor\n")
                    command.contains("rev-parse") -> UpdateStatusCommandResult(0, "abc1234\n")
                    else -> UpdateStatusCommandResult(127, "unexpected command")
                }
            }
        )

        status.installedAppPath shouldBe appPath.toString()
        status.updateAvailable shouldBe true
        status.status shouldBe "UPDATE_AVAILABLE"
        status.updateCommand shouldBe "cotor update --verify"
    }
})
