package com.cotor.data.plugin

import com.cotor.data.process.ProcessManager
import com.cotor.model.AgentExecutionException
import com.cotor.model.ExecutionContext
import com.cotor.model.ProcessResult
import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeout
import java.io.IOException
import java.net.InetSocketAddress
import java.nio.file.Path
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class LocalModelPluginTest : FunSpec({
    test("calls Ollama chat endpoint with Gemma model") {
        val server = localJsonServer("/api/chat", """{"message":{"content":"ollama ok"}}""")
        try {
            val output = LocalModelPlugin().execute(
                context = localModelContext(
                    provider = "ollama",
                    baseUrl = "http://127.0.0.1:${server.address.port}",
                    model = "gemma4:12b"
                ),
                processManager = unusedProcessManager()
            )

            output.output shouldBe "ollama ok"
        } finally {
            server.stop(0)
        }
    }

    test("retries Ollama with an installed Gemma model when the embedded default alias is missing") {
        val server = localRoutingServer { exchange ->
            when (exchange.requestURI.path) {
                "/api/tags" -> exchange.respondJson(
                    """
                    {"models":[{"name":"gemma3:4b"},{"name":"gemma3:4b:cloud","remote_host":"https://ollama.com:443"},{"name":"qwen2.5:3b"}]}
                    """.trimIndent()
                )
                "/api/chat" -> {
                    val request = exchange.requestBody.bufferedReader().readText()
                    if (request.contains("\"model\":\"gemma4:12b\"")) {
                        exchange.respondJson("""{"error":"model 'gemma4:12b' not found"}""", status = 404)
                    } else {
                        request.contains("\"model\":\"gemma3:4b\"") shouldBe true
                        exchange.respondJson("""{"message":{"content":"fallback gemma ok"}}""")
                    }
                }
                else -> exchange.sendResponseHeaders(404, -1)
            }
        }
        try {
            val output = LocalModelPlugin().execute(
                context = localModelContext(
                    provider = "ollama",
                    baseUrl = "http://127.0.0.1:${server.address.port}",
                    model = "gemma4:12b"
                ),
                processManager = unusedProcessManager()
            )

            output.output shouldBe "fallback gemma ok"
        } finally {
            server.stop(0)
        }
    }

    test("does not treat Ollama cloud tags as local Gemma fallback candidates") {
        val server = localRoutingServer { exchange ->
            when (exchange.requestURI.path) {
                "/api/tags" -> exchange.respondJson(
                    """
                    {"models":[{"name":"gemma3:4b","remote_host":"https://ollama.com:443"},{"name":"gemma4:12b:cloud"}]}
                    """.trimIndent()
                )
                "/api/chat" -> exchange.respondJson("""{"error":"model 'gemma4:12b' not found"}""", status = 404)
                else -> exchange.sendResponseHeaders(404, -1)
            }
        }
        try {
            val error = shouldThrow<AgentExecutionException> {
                LocalModelPlugin().execute(
                    context = localModelContext(
                        provider = "ollama",
                        baseUrl = "http://127.0.0.1:${server.address.port}",
                        model = "gemma4:12b"
                    ),
                    processManager = unusedProcessManager()
                )
            }

            error.message.orEmpty() shouldBe "Local model request failed (404): {\"error\":\"model 'gemma4:12b' not found\"}"
        } finally {
            server.stop(0)
        }
    }

    test("calls LM Studio chat completions endpoint with Gemma model") {
        val server = localJsonServer("/v1/chat/completions", """{"choices":[{"message":{"content":"lm studio ok"}}]}""")
        try {
            val output = LocalModelPlugin().execute(
                context = localModelContext(
                    provider = "lmstudio",
                    baseUrl = "http://127.0.0.1:${server.address.port}/v1",
                    model = "gemma4:12b"
                ),
                processManager = unusedProcessManager()
            )

            output.output shouldBe "lm studio ok"
        } finally {
            server.stop(0)
        }
    }

    test("managed Ollama start failure surfaces an actionable agent error") {
        val plugin = LocalModelPlugin(
            ollamaExecutableResolver = { "/tmp/fake-ollama" },
            managedOllamaProcessStarter = { throw IOException("Permission denied") },
            managedOllamaReachability = { false }
        )

        val error = shouldThrow<AgentExecutionException> {
            plugin.execute(
                context = localModelContext(
                    provider = "ollama",
                    baseUrl = "http://127.0.0.1:11434",
                    model = "gemma4:12b"
                ),
                processManager = unusedProcessManager()
            )
        }

        error.message.orEmpty() shouldContain "Failed to start managed Ollama server"
        error.message.orEmpty() shouldContain "/tmp/fake-ollama"
    }

    test("managed Ollama readiness failure tears down the started process") {
        val startedProcess = ProcessBuilder("sleep", "30").start()
        val plugin = LocalModelPlugin(
            ollamaExecutableResolver = { "/tmp/fake-ollama" },
            managedOllamaProcessStarter = { startedProcess },
            managedOllamaReachability = { false },
            managedOllamaStartupTimeoutMs = 200,
            managedOllamaStartupPollMs = 25
        )

        try {
            val error = shouldThrow<AgentExecutionException> {
                plugin.execute(
                    context = localModelContext(
                        provider = "ollama",
                        baseUrl = "http://127.0.0.1:11434",
                        model = "gemma4:12b"
                    ),
                    processManager = unusedProcessManager()
                )
            }

            error.message.orEmpty() shouldContain "Managed Ollama server did not become ready"
            eventuallyProcessExited(startedProcess) shouldBe true
        } finally {
            runCatching { startedProcess.destroyForcibly() }
        }
    }

    test("local model failure response body is capped") {
        val server = localRoutingServer { exchange ->
            if (exchange.requestURI.path == "/api/chat") {
                exchange.respondJson("x".repeat(256), status = 500)
            } else {
                exchange.sendResponseHeaders(404, -1)
            }
        }
        try {
            val error = shouldThrow<AgentExecutionException> {
                LocalModelPlugin(httpResponseBodyLimitChars = 32).execute(
                    context = localModelContext(
                        provider = "ollama",
                        baseUrl = "http://127.0.0.1:${server.address.port}",
                        model = "gemma4:12b"
                    ),
                    processManager = unusedProcessManager()
                )
            }
            val message = error.message.orEmpty()
            message shouldContain "Local model request failed (500)"
            message shouldContain "cotor truncated HTTP response body"
            message.contains("x".repeat(64)) shouldBe false
        } finally {
            server.stop(0)
        }
    }

    test("local model HTTP request does not block caller coroutine dispatcher") {
        val requestEntered = CountDownLatch(1)
        val releaseResponse = CountDownLatch(1)
        val server = localRoutingServer { exchange ->
            when (exchange.requestURI.path) {
                "/api/chat" -> {
                    requestEntered.countDown()
                    releaseResponse.await(2, TimeUnit.SECONDS)
                    exchange.respondJson("""{"message":{"content":"dispatcher ok"}}""")
                }
                else -> exchange.sendResponseHeaders(404, -1)
            }
        }
        val dispatcher = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        try {
            coroutineScope {
                val running = async(dispatcher) {
                    LocalModelPlugin().execute(
                        context = localModelContext(
                            provider = "ollama",
                            baseUrl = "http://127.0.0.1:${server.address.port}",
                            model = "gemma4:12b"
                        ),
                        processManager = unusedProcessManager()
                    )
                }

                requestEntered.await(1, TimeUnit.SECONDS) shouldBe true
                val marker = withTimeout(500) {
                    async(dispatcher) { "caller dispatcher free" }.await()
                }
                marker shouldBe "caller dispatcher free"

                releaseResponse.countDown()
                running.await().output shouldBe "dispatcher ok"
            }
        } finally {
            releaseResponse.countDown()
            dispatcher.close()
            server.stop(0)
        }
    }
})

private fun localJsonServer(path: String, body: String): HttpServer {
    return localRoutingServer { exchange ->
        if (exchange.requestURI.path == path) {
            exchange.respondJson(body)
        } else {
            exchange.sendResponseHeaders(404, -1)
        }
    }
}

private fun localRoutingServer(handler: (HttpExchange) -> Unit): HttpServer {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.executor = java.util.concurrent.Executor { command ->
        Thread(command, "local-model-plugin-http-test").apply { isDaemon = true }.start()
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

private fun localModelContext(provider: String, baseUrl: String, model: String): ExecutionContext =
    ExecutionContext(
        agentName = provider,
        input = "hello",
        parameters = mapOf(
            "provider" to provider,
            "baseUrl" to baseUrl,
            "model" to model
        ),
        environment = emptyMap(),
        timeout = 5_000
    )

private fun unusedProcessManager(): ProcessManager = object : ProcessManager {
    override suspend fun executeProcess(
        command: List<String>,
        input: String?,
        environment: Map<String, String>,
        timeout: Long,
        workingDirectory: Path?,
        onStart: ((Long) -> Unit)?
    ): ProcessResult = error("LocalModelPlugin should not spawn child processes")
}

private fun eventuallyProcessExited(process: Process): Boolean {
    repeat(20) {
        if (!process.isAlive) {
            return true
        }
        Thread.sleep(50)
    }
    return !process.isAlive
}
