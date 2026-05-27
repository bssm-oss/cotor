package com.cotor.presentation.cli

import com.github.ajalt.clikt.testing.test
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

class AuthCommandTest : FunSpec({
    test("auth codex-oauth status prints managed auth paths") {
        val result = AuthCommand().test("codex-oauth status")

        result.statusCode shouldBe 0
        result.output shouldContain "home:"
        result.output shouldContain "authFile:"
        result.output shouldContain "authenticated:"
    }

    test("codex oauth login process kills process tree when interrupted") {
        val scriptDir = Files.createTempDirectory("codex-oauth-interrupt")
        val script = scriptDir.resolve("fake-codex")
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
        val resultRef = AtomicReference<Int?>()
        val errorRef = AtomicReference<Throwable?>()
        val worker = thread(start = true, name = "codex-oauth-interrupt-test") {
            try {
                resultRef.set(runCodexOAuthLoginProcess(script.toString(), scriptDir))
            } catch (error: Throwable) {
                errorRef.set(error)
            }
        }

        waitForFile(childPidFile) shouldBe true
        val childPid = childPidFile.readText().trim().toLong()
        worker.interrupt()
        worker.join(5_000)

        errorRef.get() shouldBe null
        resultRef.get() shouldBe 130
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
