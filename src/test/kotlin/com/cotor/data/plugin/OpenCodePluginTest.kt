package com.cotor.data.plugin

/**
 * File overview for OpenCodePluginTest.
 *
 * This file belongs to the test suite that documents expected behavior and protects against regressions.
 * It groups declarations around open code plugin test so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import com.cotor.data.process.ProcessManager
import com.cotor.model.AgentExecutionException
import com.cotor.model.ExecutionContext
import com.cotor.model.OpenCodeDefaults
import com.cotor.model.ProcessExecutionException
import com.cotor.model.ProcessResult
import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.net.InetSocketAddress
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
                            stdout = """{"type":"text","text":"ok"}""",
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

    test("writes task-scoped execution config with explicit tool permissions") {
        val plugin = OpenCodePlugin()
        val workdir = Files.createTempDirectory("opencode-execution-config")
        val configPath = workdir.resolve(".opencode").resolve("opencode.json")
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
                        workingDirectory shouldBe workdir
                        Files.exists(configPath) shouldBe true
                        val config = Files.readString(configPath)
                        config.contains("\"read\": \"allow\"") shouldBe true
                        config.contains("\"write\": \"allow\"") shouldBe true
                        config.contains("\"edit\": \"allow\"") shouldBe true
                        config.contains("\"bash\": \"allow\"") shouldBe true
                        config.contains("\"external_directory\": \"deny\"") shouldBe true
                        assertOpenCodeRunCommand(command, OpenCodeDefaults.DEFAULT_MODEL, "hello")
                        ProcessResult(
                            exitCode = 0,
                            stdout = """{"type":"text","text":"configured"}""",
                            stderr = "",
                            isSuccess = true
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
                environment = emptyMap(),
                workingDirectory = workdir
            ),
            processManager
        )

        result.output shouldBe "configured"
        Files.exists(configPath) shouldBe false
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
            val result = plugin.execute(
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

    test("parses assistant message content from newer opencode event shapes") {
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
                            {"type":"message","role":"assistant","content":[{"type":"text","text":"```json\n{\"goalSummary\":\"Plan\",\"issues\":[]}\n```"}]}
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

        result.output shouldBe "```json\n{\"goalSummary\":\"Plan\",\"issues\":[]}\n```"
    }

    test("keeps assistant text when opencode appends DecimalError after text") {
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
                        exitCode = 1,
                        stdout = """
                            {"type":"step_start","timestamp":1,"sessionID":"session-1"}
                            {"type":"text","text":"```json\n{\"ok\":true}\n```"}
                            {"type":"error","error":{"name":"UnknownError","data":{"message":"Error: [DecimalError] Invalid argument: [object Object]"}}}
                        """.trimIndent(),
                        stderr = "",
                        isSuccess = false
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

        result.output shouldBe "```json\n{\"ok\":true}\n```"
    }

    test("tool-only opencode event streams fail instead of pretending success") {
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
                            {"type":"tool_use","tool":"bash","state":{"output":"permission denied"}}
                            {"type":"step_finish","reason":"tool-calls"}
                        """.trimIndent(),
                        stderr = "",
                        isSuccess = true
                    )
                }
            }
        }

        val error = shouldThrow<ProcessExecutionException> {
            plugin.execute(
                ExecutionContext(
                    agentName = "opencode",
                    input = "hello",
                    timeout = 1_000,
                    parameters = mapOf("model" to OpenCodeDefaults.DEFAULT_MODEL),
                    environment = emptyMap()
                ),
                processManager
            )
        }

        error.stderr shouldBe "opencode run completed without assistant text"
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

    test("retries with fallback model when opencode provider rate limit is reported") {
        val plugin = OpenCodePlugin()
        val runModels = mutableListOf<String>()
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
                        stdout = """
                            ${OpenCodeDefaults.DEFAULT_MODEL}
                            deepseek/deepseek-v4-flash
                        """.trimIndent(),
                        stderr = "",
                        isSuccess = true
                    )
                    command.take(2) == listOf("opencode", "run") -> {
                        val model = command[command.indexOf("--model") + 1]
                        runModels += model
                        if (model == OpenCodeDefaults.DEFAULT_MODEL) {
                            ProcessResult(
                                exitCode = 143,
                                stdout = """{"type":"text","text":"partial"}""",
                                stderr = """FreeUsageLimitError: Rate limit exceeded. retry-after=21907""",
                                isSuccess = false,
                                processId = 301L
                            )
                        } else {
                            assertOpenCodeRunCommand(command, "deepseek/deepseek-v4-flash", "hello")
                            ProcessResult(
                                exitCode = 0,
                                stdout = """{"type":"text","text":"fallback ok"}""",
                                stderr = "",
                                isSuccess = true,
                                processId = 302L
                            )
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

        runModels shouldBe listOf(OpenCodeDefaults.DEFAULT_MODEL, "deepseek/deepseek-v4-flash")
        result.output shouldBe "fallback ok"
        result.processId shouldBe 302L
    }

    test("passes local Ollama Gemma model to opencode without cloud fallback") {
        val server = localRoutingServer { exchange ->
            if (exchange.requestURI.path == "/api/tags") {
                exchange.respondJson("""{"models":[{"name":"gemma3:4b"},{"name":"gemma3:4b:cloud","remote_host":"https://ollama.com:443"}]}""")
            } else {
                exchange.sendResponseHeaders(404, -1)
            }
        }
        val plugin = OpenCodePlugin()
        val environments = mutableListOf<Map<String, String>>()
        val processManager = object : ProcessManager {
            override suspend fun executeProcess(
                command: List<String>,
                input: String?,
                environment: Map<String, String>,
                timeout: Long,
                workingDirectory: Path?,
                onStart: ((Long) -> Unit)?
            ): ProcessResult {
                environments += environment
                return when (command) {
                    listOf("opencode", "models") -> ProcessResult(
                        exitCode = 0,
                        stdout = "${OpenCodeDefaults.LOCAL_OLLAMA_GEMMA_MODEL}\nopencode/minimax-m2.5-free\n",
                        stderr = "",
                        isSuccess = true
                    )
                    else -> {
                        assertOpenCodeRunCommand(command, OpenCodeDefaults.LOCAL_OLLAMA_GEMMA_MODEL, "edit files")
                        ProcessResult(
                            exitCode = 0,
                            stdout = """{"type":"text","text":"edited"}""",
                            stderr = "",
                            isSuccess = true,
                            processId = 202L
                        )
                    }
                }
            }
        }

        try {
            val result = plugin.execute(
                ExecutionContext(
                    agentName = "opencode",
                    input = "edit files",
                    timeout = 1_000,
                    parameters = mapOf(
                        "model" to OpenCodeDefaults.LOCAL_OLLAMA_GEMMA_MODEL,
                        "ollamaBaseUrl" to "http://127.0.0.1:${server.address.port}"
                    ),
                    environment = mapOf("OLLAMA_API_KEY" to "should-be-cleared")
                ),
                processManager
            )

            result.output shouldBe "edited"
            result.processId shouldBe 202L
            environments.all { it["OLLAMA_HOST"] == "127.0.0.1:11434" } shouldBe true
            environments.all { it["OLLAMA_NO_CLOUD"] == "1" } shouldBe true
            environments.all { it["OLLAMA_API_KEY"].orEmpty().isBlank() } shouldBe true
        } finally {
            server.stop(0)
        }
    }

    test("surfaces local Ollama Gemma tool-call incompatibility without fallback") {
        val server = localRoutingServer { exchange ->
            if (exchange.requestURI.path == "/api/tags") {
                exchange.respondJson("""{"models":[{"name":"gemma3:4b"}]}""")
            } else {
                exchange.sendResponseHeaders(404, -1)
            }
        }
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
                assertOpenCodeRunCommand(command, OpenCodeDefaults.LOCAL_OLLAMA_GEMMA_MODEL, "edit files")
                return ProcessResult(
                    exitCode = 1,
                    stdout = """
                        {"type":"error","error":{"name":"APIError","data":{"message":"registry.ollama.ai/library/gemma3:4b does not support tools","statusCode":400}}}
                    """.trimIndent(),
                    stderr = "",
                    isSuccess = false
                )
            }
        }

        try {
            val error = shouldThrow<ProcessExecutionException> {
                plugin.execute(
                    ExecutionContext(
                        agentName = "opencode",
                        input = "edit files",
                        timeout = 1_000,
                        parameters = mapOf(
                            "model" to OpenCodeDefaults.LOCAL_OLLAMA_GEMMA_MODEL,
                            "ollamaBaseUrl" to "http://127.0.0.1:${server.address.port}"
                        ),
                        environment = emptyMap()
                    ),
                    processManager
                )
            }

            error.stderr.startsWith("LOCAL_GEMMA_TOOLS_UNSUPPORTED:") shouldBe true
            error.stderr.contains("does not support the OpenCode tool calls required for code editing") shouldBe true
        } finally {
            server.stop(0)
        }
    }

    test("does not fall back to cloud or free OpenCode models when local Ollama Gemma is missing") {
        val server = localRoutingServer { exchange ->
            if (exchange.requestURI.path == "/api/tags") {
                exchange.respondJson("""{"models":[{"name":"gemma3:4b","remote_host":"https://ollama.com:443"},{"name":"gemma3:4b:cloud"}]}""")
            } else {
                exchange.sendResponseHeaders(404, -1)
            }
        }
        val plugin = OpenCodePlugin()
        var runInvoked = false
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
                        exitCode = 0,
                        stdout = "opencode/minimax-m2.5-free\nollama/gemma3:4b:cloud\n",
                        stderr = "",
                        isSuccess = true
                    )
                    else -> {
                        runInvoked = true
                        ProcessResult(exitCode = 0, stdout = "", stderr = "", isSuccess = true)
                    }
                }
            }
        }

        try {
            val error = shouldThrow<AgentExecutionException> {
                plugin.execute(
                    ExecutionContext(
                        agentName = "opencode",
                        input = "edit files",
                        timeout = 1_000,
                        parameters = mapOf(
                            "model" to OpenCodeDefaults.LOCAL_OLLAMA_GEMMA_MODEL,
                            "ollamaBaseUrl" to "http://127.0.0.1:${server.address.port}"
                        ),
                        environment = emptyMap()
                    ),
                    processManager
                )
            }

            error.message shouldBe "LOCAL_GEMMA_MODEL_MISSING: local Ollama model gemma3:4b was not discovered."
            runInvoked shouldBe false
        } finally {
            server.stop(0)
        }
    }

    test("exit 0 with blank stdout and stderr throws ProcessExecutionException") {
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
                else -> ProcessResult(
                    exitCode = 0,
                    stdout = "",
                    stderr = "",
                    isSuccess = true
                )
            }
        }

        val error = shouldThrow<ProcessExecutionException> {
            plugin.execute(
                ExecutionContext(
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
        error.stdout shouldBe "opencode run exit 0 but stdout and stderr were both empty"
        error.stderr shouldBe "opencode run exit 0 but stdout and stderr were both empty"
    }

    test("writes prompt file inside working directory when workingDirectory is set") {
        val workDir = Files.createTempDirectory("cotor-test-workdir-")
        val plugin = OpenCodePlugin()
        var capturedPromptPath: String? = null
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
                    capturedPromptPath = command.firstOrNull { it.startsWith("--file=") }
                        ?.removePrefix("--file=")
                    ProcessResult(
                        exitCode = 0,
                        stdout = """{"type":"text","text":"done"}""",
                        stderr = "",
                        isSuccess = true
                    )
                }
            }
        }

        try {
            val result = plugin.execute(
                ExecutionContext(
                    agentName = "opencode",
                    input = "hello",
                    timeout = 1_000,
                    parameters = mapOf("model" to OpenCodeDefaults.DEFAULT_MODEL),
                    environment = emptyMap(),
                    workingDirectory = workDir
                ),
                processManager
            )

            val promptPath = Path.of(capturedPromptPath!!)
            promptPath.startsWith(workDir.resolve(".cotor/runtime/opencode-prompts")) shouldBe true
        } finally {
            workDir.toFile().deleteRecursively()
        }
    }

    test("planning-only opencode uses isolated stdin prompt and config content") {
        val workDir = Files.createTempDirectory("cotor-test-opencode-config-")
        val plugin = OpenCodePlugin()
        var sawAgentFlag = false
        var sawPureFlag = false
        var capturedInputPath: Path? = null
        var capturedInputText: String? = null
        var capturedEnvironment: Map<String, String> = emptyMap()
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
                    sawAgentFlag = command.windowed(2).any { it == listOf("--agent", "cotor-plan") }
                    sawPureFlag = "--pure" in command
                    capturedEnvironment = environment
                    ProcessResult(
                        exitCode = 0,
                        stdout = """{"type":"text","text":"done"}""",
                        stderr = "",
                        isSuccess = true
                    )
                }
            }

            override suspend fun executeProcessWithInputFile(
                command: List<String>,
                inputFile: Path,
                environment: Map<String, String>,
                timeout: Long,
                workingDirectory: Path?,
                onStart: ((Long) -> Unit)?,
                onStdoutChunk: ((String) -> Unit)?,
                onStderrChunk: ((String) -> Unit)?
            ): ProcessResult {
                capturedInputPath = inputFile
                capturedInputText = Files.readString(inputFile)
                return executeProcess(
                    command = command,
                    input = Files.readString(inputFile),
                    environment = environment,
                    timeout = timeout,
                    workingDirectory = workingDirectory,
                    onStart = onStart,
                    onStdoutChunk = onStdoutChunk,
                    onStderrChunk = onStderrChunk
                )
            }
        }

        try {
            val result = plugin.execute(
                ExecutionContext(
                    agentName = "opencode",
                    input = "hello",
                    timeout = 1_000,
                    parameters = mapOf(
                        "model" to OpenCodeDefaults.DEFAULT_MODEL,
                        "agent" to "cotor-plan",
                        "ephemeralOpencodeProfile" to "planning-only"
                    ),
                    environment = emptyMap(),
                    workingDirectory = workDir
                ),
                processManager
            )

            sawAgentFlag shouldBe true
            sawPureFlag shouldBe true
            capturedInputPath?.startsWith(workDir.resolve(".cotor/runtime/opencode-prompts")) shouldBe true
            capturedInputText shouldBe "hello"
            capturedEnvironment["OPENCODE_DISABLE_PROJECT_CONFIG"] shouldBe "true"
            capturedEnvironment["OPENCODE_DISABLE_DEFAULT_PLUGINS"] shouldBe "true"
            capturedEnvironment["OPENCODE_CONFIG_CONTENT"].orEmpty().contains("cotor-plan") shouldBe true
            capturedEnvironment["OPENCODE_CONFIG_CONTENT"].orEmpty().contains("\"external_directory\": \"deny\"") shouldBe true
            capturedEnvironment["OPENCODE_CONFIG_CONTENT"].orEmpty().contains("\"read\": false") shouldBe true
            Files.exists(workDir.resolve(".opencode").resolve("opencode.json")) shouldBe false
        } finally {
            workDir.toFile().deleteRecursively()
        }
    }

    test("opencode permission audit logs with allowed action do not fail execution") {
        val workDir = Files.createTempDirectory("cotor-test-opencode-allowed-permission-")
        val plugin = OpenCodePlugin()
        val processManager = object : ProcessManager {
            override suspend fun executeProcess(
                command: List<String>,
                input: String?,
                environment: Map<String, String>,
                timeout: Long,
                workingDirectory: Path?,
                onStart: ((Long) -> Unit)?
            ): ProcessResult = ProcessResult(
                exitCode = 0,
                stdout = "",
                stderr = "",
                isSuccess = true
            )

            override suspend fun executeProcess(
                command: List<String>,
                input: String?,
                environment: Map<String, String>,
                timeout: Long,
                workingDirectory: Path?,
                onStart: ((Long) -> Unit)?,
                onStdoutChunk: ((String) -> Unit)?,
                onStderrChunk: ((String) -> Unit)?
            ): ProcessResult {
                if (command == listOf("opencode", "models")) {
                    return ProcessResult(
                        exitCode = 1,
                        stdout = "",
                        stderr = "models lookup unavailable",
                        isSuccess = false
                    )
                }
                onStderrChunk?.invoke(
                    """service=permission permission=write action={"permission":"write","path":"docs/check.md","action":"allow"} permission.asked"""
                )
                return ProcessResult(
                    exitCode = 0,
                    stdout = """{"type":"text","text":"completed"}""",
                    stderr = "",
                    isSuccess = true
                )
            }
        }

        try {
            val result = plugin.execute(
                ExecutionContext(
                    agentName = "opencode",
                    input = "hello",
                    timeout = 1_000,
                    parameters = mapOf("model" to OpenCodeDefaults.DEFAULT_MODEL),
                    environment = emptyMap(),
                    workingDirectory = workDir
                ),
                processManager
            )
            result.output shouldBe "completed"
        } finally {
            workDir.toFile().deleteRecursively()
        }
    }

    test("planning-only opencode aborts interactive permission requests") {
        val workDir = Files.createTempDirectory("cotor-test-opencode-permission-")
        val plugin = OpenCodePlugin()
        val processManager = object : ProcessManager {
            override suspend fun executeProcess(
                command: List<String>,
                input: String?,
                environment: Map<String, String>,
                timeout: Long,
                workingDirectory: Path?,
                onStart: ((Long) -> Unit)?
            ): ProcessResult = ProcessResult(
                exitCode = 0,
                stdout = "",
                stderr = "",
                isSuccess = true
            )

            override suspend fun executeProcess(
                command: List<String>,
                input: String?,
                environment: Map<String, String>,
                timeout: Long,
                workingDirectory: Path?,
                onStart: ((Long) -> Unit)?,
                onStdoutChunk: ((String) -> Unit)?,
                onStderrChunk: ((String) -> Unit)?
            ): ProcessResult {
                if (command == listOf("opencode", "models")) {
                    return ProcessResult(
                        exitCode = 1,
                        stdout = "",
                        stderr = "models lookup unavailable",
                        isSuccess = false
                    )
                }
                onStderrChunk?.invoke(
                    """service=permission permission=external_directory pattern=/tmp/repo/* action={"permission":"external_directory","pattern":"*","action":"ask"} permission.asked"""
                )
                return ProcessResult(
                    exitCode = 143,
                    stdout = "",
                    stderr = "permission.asked",
                    isSuccess = false
                )
            }
        }

        try {
            val error = shouldThrow<ProcessExecutionException> {
                plugin.execute(
                    ExecutionContext(
                        agentName = "opencode",
                        input = "hello",
                        timeout = 1_000,
                        parameters = mapOf(
                            "model" to OpenCodeDefaults.DEFAULT_MODEL,
                            "agent" to "cotor-plan",
                            "ephemeralOpencodeProfile" to "planning-only"
                        ),
                        environment = emptyMap(),
                        workingDirectory = workDir
                    ),
                    processManager
                )
            }
            error.stderr.contains("OPENCODE_PERMISSION_BLOCKED") shouldBe true
        } finally {
            workDir.toFile().deleteRecursively()
        }
    }
})

private const val OPENCODE_PROMPT_INSTRUCTION = "Execute the instructions in the attached prompt file."

private fun assertOpenCodeRunCommand(command: List<String>, model: String, expectedPrompt: String) {
    command.size shouldBe 11
    command[0] shouldBe "opencode"
    command[1] shouldBe "run"
    command[2] shouldBe "--print-logs"
    command[3] shouldBe "--log-level"
    command[4] shouldBe "ERROR"
    command[5] shouldBe "--model"
    command[6] shouldBe model
    command[7] shouldBe "--format"
    command[8] shouldBe "json"
    command[9] shouldBe OPENCODE_PROMPT_INSTRUCTION
    command[10].startsWith("--file=") shouldBe true
    Files.readString(Path.of(command[10].removePrefix("--file="))) shouldBe expectedPrompt
}

private fun localRoutingServer(handler: (HttpExchange) -> Unit): HttpServer {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.executor = java.util.concurrent.Executor { command ->
        Thread(command, "opencode-plugin-http-test").apply { isDaemon = true }.start()
    }
    server.createContext("/") { exchange ->
        handler(exchange)
    }
    server.start()
    return server
}

private fun HttpExchange.respondJson(body: String, status: Int = 200) {
    val bytes = body.toByteArray()
    responseHeaders.add("Content-Type", "application/json")
    sendResponseHeaders(status, bytes.size.toLong())
    responseBody.use { it.write(bytes) }
}
