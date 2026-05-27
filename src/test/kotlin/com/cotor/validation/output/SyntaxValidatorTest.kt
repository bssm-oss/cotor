package com.cotor.validation.output

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.booleans.shouldBeFalse
import io.kotest.matchers.booleans.shouldBeTrue
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import java.nio.file.Files

class SyntaxValidatorTest : FunSpec({
    test("kotlin script validation refuses executable scripts before starting a command") {
        val dir = Files.createTempDirectory("syntax-validator-kts")
        val marker = dir.resolve("executed.txt")
        val script = dir.resolve("unsafe.kts")
        Files.writeString(
            script,
            """
            java.nio.file.Files.writeString(
                java.nio.file.Path.of("${marker.toString().replace("\\", "\\\\").replace("\"", "\\\"")}"),
                "executed"
            )
            """.trimIndent()
        )
        var commandStarted = false
        val validator = SyntaxValidator(
            timeoutSeconds = 1,
            maxOutputChars = 1_024,
            commandFactory = { _, _ ->
                commandStarted = true
                SyntaxValidationCommand(listOf("/bin/sh", "-c", "exit 0"), "Kotlin")
            }
        )

        val result = validator.validate("kotlin", script.toString())

        result.isValid.shouldBeFalse()
        result.errors.single() shouldContain "execute code"
        commandStarted shouldBe false
        Files.exists(marker) shouldBe false
    }

    test("python syntax validation parses without writing bytecode beside the source") {
        val dir = Files.createTempDirectory("syntax-validator-python")
        val source = dir.resolve("sample.py")
        Files.writeString(source, "def ok():\n    return 1\n")

        val result = SyntaxValidator().validate("python", source.toString())

        result.isValid.shouldBeTrue()
        result.message shouldBe "Python syntax valid"
        Files.exists(dir.resolve("__pycache__")) shouldBe false
    }

    test("timeout kills descendant processes started by the validator command") {
        val dir = Files.createTempDirectory("syntax-validator-timeout")
        val pidFile = dir.resolve("child.pid")
        val command = "sleep 30 & child=\$!; printf '%s' \"\$child\" > '${pidFile.toString().replace("'", "'\\''")}'; wait \"\$child\""
        var childPid: Long? = null
        val validator = SyntaxValidator(
            timeoutSeconds = 1,
            maxOutputChars = 1_024,
            commandFactory = { _, _ ->
                SyntaxValidationCommand(listOf("/bin/sh", "-c", command), "Test")
            }
        )

        try {
            val result = validator.validate("javascript", dir.resolve("unused.js").toString())

            result.isValid.shouldBeFalse()
            result.errors.single() shouldContain "timed out"
            childPid = Files.readString(pidFile).trim().toLong()
            waitUntilNotAlive(childPid).shouldBeTrue()
        } finally {
            childPid?.let { pid ->
                ProcessHandle.of(pid).ifPresent { handle ->
                    if (handle.isAlive) {
                        handle.destroyForcibly()
                    }
                }
            }
        }
    }

    test("validator infrastructure failures are invalid instead of fail-open skipped") {
        val validator = SyntaxValidator(
            timeoutSeconds = 1,
            maxOutputChars = 1_024,
            commandFactory = { _, _ ->
                SyntaxValidationCommand(listOf("/path/to/nonexistent-validator"), "Test")
            }
        )

        val result = validator.validate("javascript", "unused.js")

        result.isValid.shouldBeFalse()
        result.message shouldBe "Test syntax validation failed to run"
        result.errors.single() shouldContain "failed to run"
    }
})

private fun waitUntilNotAlive(pid: Long): Boolean {
    repeat(30) {
        if (!isProcessAlive(pid)) {
            return true
        }
        Thread.sleep(100)
    }
    return !isProcessAlive(pid)
}

private fun isProcessAlive(pid: Long): Boolean =
    ProcessHandle.of(pid).map { it.isAlive }.orElse(false)
