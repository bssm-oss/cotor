package com.cotor.app

import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContain
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import java.nio.file.Files
import kotlin.io.path.createDirectories

class LocalPlaywrightDependencyTest : FunSpec({
    test("uses existing runtime node_modules without requiring npm") {
        val runtimeDir = Files.createTempDirectory("playwright-existing")
        runtimeDir.resolve("node_modules").resolve("playwright").createDirectories()
        var processRuns = 0
        val resolver = LocalPlaywrightDependencyResolver(
            commandAvailability = { it == "node" },
            processRunner = LocalSkillProcessRunner { _, _, _, _, _ ->
                processRuns += 1
                LocalSkillProcessResult(exitCode = 0, output = "")
            },
            environment = { emptyMap() }
        )

        val nodePath = resolver.requireNodePath(runtimeDir, timeoutSeconds = 15, label = "Browser skill")

        nodePath shouldBe runtimeDir.resolve("node_modules")
        processRuns shouldBe 0
    }

    test("refuses runtime npm install unless explicitly allowed") {
        val runtimeDir = Files.createTempDirectory("playwright-refuse-install")
        val resolver = LocalPlaywrightDependencyResolver(
            commandAvailability = { it in setOf("node", "npm") },
            processRunner = LocalSkillProcessRunner { _, _, _, _, _ ->
                LocalSkillProcessResult(exitCode = 0, output = "")
            },
            environment = { emptyMap() }
        )

        val error = shouldThrow<IllegalStateException> {
            resolver.requireNodePath(runtimeDir, timeoutSeconds = 15, label = "Browser skill")
        }

        error.message shouldContain "requires a preinstalled Playwright dependency"
    }

    test("explicit runtime install is pinned") {
        val runtimeDir = Files.createTempDirectory("playwright-install")
        val commands = mutableListOf<List<String>>()
        val resolver = LocalPlaywrightDependencyResolver(
            commandAvailability = { it in setOf("node", "npm") },
            processRunner = LocalSkillProcessRunner { command, workingDirectory, _, _, _ ->
                commands += command
                workingDirectory.resolve("node_modules").resolve("playwright").createDirectories()
                LocalSkillProcessResult(exitCode = 0, output = "installed")
            },
            environment = { mapOf("COTOR_BROWSER_SKILL_ALLOW_NPM_INSTALL" to "1") }
        )

        val nodePath = resolver.requireNodePath(runtimeDir, timeoutSeconds = 15, label = "Browser skill")

        nodePath shouldBe runtimeDir.resolve("node_modules")
        commands.single() shouldContain "playwright@1.52.0"
    }
})
