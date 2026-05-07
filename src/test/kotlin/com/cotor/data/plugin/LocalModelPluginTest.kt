package com.cotor.data.plugin

import com.cotor.data.process.ProcessManager
import com.cotor.model.AgentExecutionException
import com.cotor.model.ExecutionContext
import com.cotor.model.ProcessResult
import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.matchers.shouldBe
import java.net.InetSocketAddress
import java.nio.file.Path

class LocalModelPluginTest : FunSpec({
    test("calls Ollama chat endpoint with Gemma model") {
        val server = localJsonServer("/api/chat", """{"message":{"content":"ollama ok"}}""")
        try {
            val output = LocalModelPlugin().execute(
                context = localModelContext(
                    provider = "ollama",
                    baseUrl = "http://127.0.0.1:${server.address.port}",
                    model = "gemma4:e2b"
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
                    if (request.contains("\"model\":\"gemma4:e2b\"")) {
                        exchange.respondJson("""{"error":"model 'gemma4:e2b' not found"}""", status = 404)
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
                    model = "gemma4:e2b"
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
                    {"models":[{"name":"gemma3:4b","remote_host":"https://ollama.com:443"},{"name":"gemma4:e2b:cloud"}]}
                    """.trimIndent()
                )
                "/api/chat" -> exchange.respondJson("""{"error":"model 'gemma4:e2b' not found"}""", status = 404)
                else -> exchange.sendResponseHeaders(404, -1)
            }
        }
        try {
            val error = shouldThrow<AgentExecutionException> {
                LocalModelPlugin().execute(
                    context = localModelContext(
                        provider = "ollama",
                        baseUrl = "http://127.0.0.1:${server.address.port}",
                        model = "gemma4:e2b"
                    ),
                    processManager = unusedProcessManager()
                )
            }

            error.message.orEmpty() shouldBe "Local model request failed (404): {\"error\":\"model 'gemma4:e2b' not found\"}"
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
                    model = "gemma4:e2b"
                ),
                processManager = unusedProcessManager()
            )

            output.output shouldBe "lm studio ok"
        } finally {
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
