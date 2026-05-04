package com.cotor.data.plugin

import com.cotor.data.process.ProcessManager
import com.cotor.model.ExecutionContext
import com.cotor.model.ProcessResult
import com.sun.net.httpserver.HttpServer
import io.kotest.core.spec.style.FunSpec
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
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.createContext(path) { exchange ->
        val bytes = body.toByteArray()
        exchange.responseHeaders.add("Content-Type", "application/json")
        exchange.sendResponseHeaders(200, bytes.size.toLong())
        exchange.responseBody.use { it.write(bytes) }
    }
    server.start()
    return server
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
