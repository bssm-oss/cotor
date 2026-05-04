package com.cotor.data.plugin

/**
 * File overview for OpenCodePluginTest.
 *
 * This file belongs to the test suite that documents expected behavior and protects against regressions.
 * It groups declarations around open code plugin test so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import com.cotor.data.process.ProcessManager
import com.cotor.model.ExecutionContext
import com.cotor.model.OpenCodeDefaults
import com.cotor.model.ProcessExecutionException
import com.cotor.model.ProcessResult
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.nio.file.Files
import java.nio.file.Path

/**
 * Regression test for the OpenCode wrapper.
 *
 * The important behavior here is that a failing child process keeps its exit code
 * and captured streams when translated into a ProcessExecutionException.
 */
class OpenCodePluginTest : FunSpec({
    test("passes explicit model to opencode run") {
        val plugin = OpenCodePlugin()
        var sawModelsLookup = false
        val processManager = object : ProcessManager {
            override suspend fun executeProcess(
                command: List<String>,
                input: String?,
                environment: Map<String, String>,
                timeout: Long,
                workingDirectory: Path?,
                onStart: ((Long) -> Unit)?
            ): ProcessResult {
                return when (command) {
                    listOf("opencode", "models") -> {
                        sawModelsLookup = true
                        ProcessResult(
                            exitCode = 0,
                            stdout = "opencode/qwen3.6-plus-free\nopencode/minimax-m2.5-free\n",
                            stderr = "",
                            isSuccess = true
                        )
                    }
                    else -> {
                        assertOpenCodeRunCommand(command, "opencode/qwen3.6-plus-free", "hello")
                        ProcessResult(
                            exitCode = 0,
                            stdout = "",
                            stderr = "",
                            isSuccess = true
                        )
                    }
                }
            }
        }

        plugin.execute(
            ExecutionContext(
                agentName = "opencode",
                input = "hello",
                timeout = 1_000,
                parameters = mapOf("model" to "opencode/qwen3.6-plus-free"),
                environment = emptyMap()
            ),
            processManager
        )

        sawModelsLookup shouldBe true
    }

    test("throws ProcessExecutionException with exit code and streams on failure") {
        val plugin = OpenCodePlugin()
        val processManager = object : ProcessManager {
            override suspend fun executeProcess(
                command: List<String>,
                input: String?,
                environment: Map<String, String>,
                timeout: Long,
                workingDirectory: Path?,
                onStart: ((Long) -> Unit)?
            ): ProcessResult {
                return when (command) {
                    listOf("opencode", "models") -> ProcessResult(
                        exitCode = 1,
                        stdout = "",
                        stderr = "models lookup unavailable",
                        isSuccess = false
                    )
                    else -> {
                        assertOpenCodeRunCommand(command, OpenCodeDefaults.DEFAULT_MODEL, "hello")
                        ProcessResult(
                            exitCode = 2,
                            stdout = "partial output",
                            stderr = "cli error",
                            isSuccess = false
                        )
                    }
                }
            }
        }

        val error = shouldThrow<ProcessExecutionException> {
            plugin.execute(
                ExecutionContext(
                    // The rest of the execution context is intentionally minimal because
                    // this test only cares about error propagation from the CLI wrapper.
                    agentName = "opencode",
                    input = "hello",
                    timeout = 1_000,
                    parameters = mapOf("model" to OpenCodeDefaults.DEFAULT_MODEL),
                    environment = emptyMap()
                ),
                processManager
            )
        }

        error.message shouldBe "OpenCode execution failed"
        error.exitCode shouldBe 2
        error.stdout shouldBe "partial output"
        error.stderr shouldBe "cli error"
    }

    test("parses ndjson event streams into readable text instead of returning raw envelopes") {
        val plugin = OpenCodePlugin()
        val processManager = object : ProcessManager {
            override suspend fun executeProcess(
                command: List<String>,
                input: String?,
                environment: Map<String, String>,
                timeout: Long,
                workingDirectory: Path?,
                onStart: ((Long) -> Unit)?
            ): ProcessResult = when (command) {
                listOf("opencode", "models") -> ProcessResult(
                    exitCode = 1,
                    stdout = "",
                    stderr = "models lookup unavailable",
                    isSuccess = false
                )
                else -> {
                    assertOpenCodeRunCommand(command, OpenCodeDefaults.DEFAULT_MODEL, "hello")
                    ProcessResult(
                        exitCode = 0,
                        stdout = """
                            {"type":"step_start","timestamp":1,"sessionID":"session-1"}
                            {"type":"text","text":"QA_VERDICT: PASS"}
                            {"type":"text","text":"The PR is ready to merge after QA review."}
                            {"type":"tool_use","tool":"bash","state":{"output":"{\"huge\":true}"}}
                        """.trimIndent(),
                        stderr = "",
                        isSuccess = true
                    )
                }
            }
        }

        val result = plugin.execute(
            ExecutionContext(
                agentName = "opencode",
                input = "hello",
                timeout = 1_000,
                parameters = mapOf("model" to OpenCodeDefaults.DEFAULT_MODEL),
                environment = emptyMap()
            ),
            processManager
        )

        result.output shouldBe "QA_VERDICT: PASS\n\nThe PR is ready to merge after QA review."
    }

    test("retries with an available opencode model when the configured model is missing") {
        val plugin = OpenCodePlugin()
        var runCount = 0
        val processManager = object : ProcessManager {
            override suspend fun executeProcess(
                command: List<String>,
                input: String?,
                environment: Map<String, String>,
                timeout: Long,
                workingDirectory: Path?,
                onStart: ((Long) -> Unit)?
            ): ProcessResult {
                return when {
                    command == listOf("opencode", "models") -> ProcessResult(
                        exitCode = 0,
                        stdout = "opencode/minimax-m2.5-free\nopencode/gpt-5-nano\n",
                        stderr = "",
                        isSuccess = true
                    )
                    command.take(2) == listOf("opencode", "run") -> {
                        runCount += 1
                        when (runCount) {
                            1 -> {
                                assertOpenCodeRunCommand(command, "opencode/minimax-m2.5-free", "hello")
                                ProcessResult(
                                    exitCode = 0,
                                    stdout = """{"type":"text","text":"fixed"}""",
                                    stderr = "",
                                    isSuccess = true,
                                    processId = 88L
                                )
                            }
                            else -> error("unexpected extra opencode run invocation")
                        }
                    }
                    else -> error("unexpected command: $command")
                }
            }
        }

        val result = plugin.execute(
            ExecutionContext(
                agentName = "opencode",
                input = "hello",
                timeout = 1_000,
                parameters = mapOf("model" to OpenCodeDefaults.DEFAULT_MODEL),
                environment = emptyMap()
            ),
            processManager
        )

        runCount shouldBe 1
        result.output shouldBe "fixed"
        result.processId shouldBe 88L
    }

    test("preflights an unavailable explicit opencode model before the first run") {
        val plugin = OpenCodePlugin()
        val commands = mutableListOf<List<String>>()
        val processManager = object : ProcessManager {
            override suspend fun executeProcess(
                command: List<String>,
                input: String?,
                environment: Map<String, String>,
                timeout: Long,
                workingDirectory: Path?,
                onStart: ((Long) -> Unit)?
            ): ProcessResult {
                commands += command
                return when (command) {
                    listOf("opencode", "models") -> ProcessResult(
                        exitCode = 0,
                        stdout = "opencode/minimax-m2.5-free\nopencode/gpt-5-nano\n",
                        stderr = "",
                        isSuccess = true
                    )
                    else -> {
                        assertOpenCodeRunCommand(command, "opencode/minimax-m2.5-free", "hello")
                        ProcessResult(
                            exitCode = 0,
                            stdout = """{"type":"text","text":"fixed"}""",
                            stderr = "",
                            isSuccess = true,
                            processId = 101L
                        )
                    }
                }
            }
        }

        val result = plugin.execute(
            ExecutionContext(
                agentName = "opencode",
                input = "hello",
                timeout = 1_000,
                parameters = mapOf("model" to OpenCodeDefaults.DEFAULT_MODEL),
                environment = emptyMap()
            ),
            processManager
        )

        commands.size shouldBe 2
        commands[0] shouldBe listOf("opencode", "models")
        result.output shouldBe "fixed"
        result.processId shouldBe 101L
    }
})

private const val OPENCODE_PROMPT_INSTRUCTION = "Execute the instructions in the attached prompt file."

private fun assertOpenCodeRunCommand(command: List<String>, model: String, expectedPrompt: String) {
    command.size shouldBe 8
    command[0] shouldBe "opencode"
    command[1] shouldBe "run"
    command[2] shouldBe "--model"
    command[3] shouldBe model
    command[4] shouldBe "--format"
    command[5] shouldBe "json"
    command[6] shouldBe OPENCODE_PROMPT_INSTRUCTION
    command[7].startsWith("--file=") shouldBe true
    Files.readString(Path.of(command[7].removePrefix("--file="))) shouldBe expectedPrompt
}
