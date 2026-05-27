package com.cotor.presentation.cli

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.nio.file.Files
import java.nio.file.attribute.PosixFilePermission
import kotlin.io.path.writeText

class CliProcessProbeTest : FunSpec({
    test("runDiscardingOutputProbe returns true for a successful command") {
        val script = executableScript("cli-probe-success") {
            "exit 0\n"
        }

        runDiscardingOutputProbe(listOf(script.toString()), timeoutSeconds = 2) shouldBe true
    }

    test("runDiscardingOutputProbe returns false for failures and missing commands") {
        val script = executableScript("cli-probe-failure") {
            "exit 7\n"
        }

        runDiscardingOutputProbe(listOf(script.toString()), timeoutSeconds = 2) shouldBe false
        runDiscardingOutputProbe(listOf("/definitely/missing/cotor-probe-command"), timeoutSeconds = 2) shouldBe false
    }

    test("runDiscardingOutputProbe times out hanging commands") {
        val script = executableScript("cli-probe-timeout") {
            "sleep 30\n"
        }

        runDiscardingOutputProbe(listOf(script.toString()), timeoutSeconds = 1) shouldBe false
    }
})

private fun executableScript(prefix: String, body: () -> String): java.nio.file.Path {
    val script = Files.createTempFile(prefix, ".sh")
    script.writeText(
        """
        #!/usr/bin/env bash
        ${body()}
        """.trimIndent()
    )
    Files.setPosixFilePermissions(
        script,
        setOf(
            PosixFilePermission.OWNER_READ,
            PosixFilePermission.OWNER_WRITE,
            PosixFilePermission.OWNER_EXECUTE
        )
    )
    return script
}
