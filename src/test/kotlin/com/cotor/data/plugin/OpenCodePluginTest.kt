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

private fun localRoutingServer(handler: (HttpExchange) -> Unit): HttpServer {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
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
