package com.cotor.presentation.cli

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermission
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
import kotlin.io.path.readText
import kotlin.io.path.writeText

class DesktopCommandProcessTest : FunSpec({
    test("runDesktopCommand kills process tree when interrupted") {
        val scriptDir = Files.createTempDirectory("desktop-command-interrupt")
        val script = scriptDir.resolve("fake-desktop-command")
        val childPidFile = scriptDir.resolve("child.pid")
        executableScript(
            script,
            """
            sleep 30 &
            child=${'$'}!
            printf '%s\n' "${'$'}child" > '${childPidFile.toString().replace("'", "'\\''")}'
            wait "${'$'}child"
            """.trimIndent()
        )
        val resultRef = AtomicReference<DesktopScriptResult?>()
        val errorRef = AtomicReference<Throwable?>()
        val worker = thread(start = true, name = "desktop-command-interrupt-test") {
            try {
                resultRef.set(
                    runDesktopCommand(
                        command = listOf(script.toString()),
                        timeoutSeconds = 30,
                        timeoutMessage = { "timed out" }
                    )
                )
            } catch (error: Throwable) {
                errorRef.set(error)
            }
        }

        waitForFile(childPidFile) shouldBe true
        val childPid = childPidFile.readText().trim().toLong()
        worker.interrupt()
        worker.join(5_000)

        errorRef.get() shouldBe null
        resultRef.get()?.exitCode shouldBe 130
        resultRef.get()?.output shouldContain "interrupted"
        waitUntilNotAlive(childPid) shouldBe true
    }
})

private fun executableScript(path: Path, body: String) {
    path.writeText(
        """
        #!/usr/bin/env bash
        $body
        """.trimIndent()
    )
    Files.setPosixFilePermissions(
        path,
        setOf(
            PosixFilePermission.OWNER_READ,
            PosixFilePermission.OWNER_WRITE,
            PosixFilePermission.OWNER_EXECUTE
        )
    )
}

private fun waitForFile(path: Path): Boolean {
    repeat(200) {
        if (Files.exists(path)) {
            return true
        }
        Thread.sleep(25)
    }
    return Files.exists(path)
}

private fun waitUntilNotAlive(pid: Long): Boolean {
    repeat(40) {
        if (!isProcessAlive(pid)) {
            return true
        }
        Thread.sleep(100)
    }
    return !isProcessAlive(pid)
}

private fun isProcessAlive(pid: Long): Boolean =
    ProcessHandle.of(pid).map { it.isAlive }.orElse(false)
