package com.cotor.app

import com.sun.net.httpserver.HttpServer
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldHaveSize
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.withTimeout
import java.net.InetSocketAddress
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermission
import kotlin.io.path.readText

class DirectChatServiceTest : FunSpec({
    test("listAvailableModels caps oversized provider responses") {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/api/tags") { exchange ->
            val body = """{"models":[""" + "x".repeat(256) + "]}"
            val bytes = body.toByteArray()
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
        try {
            val models = DirectChatService(modelListResponseLimitChars = 32)
                .listAvailableModels("http://127.0.0.1:${server.address.port}")

            models shouldBe emptyList()
        } finally {
            server.stop(0)
        }
    }

    test("ollama stream emits a single terminal done chunk") {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/api/chat") { exchange ->
            val body = """
                {"message":{"content":"hello"},"done":false}
                {"message":{"content":""},"done":true}
            """.trimIndent()
            val bytes = body.toByteArray()
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
        try {
            val baseUrl = "http://127.0.0.1:${server.address.port}"
            val conversation = DirectChatConversation(
                id = "conversation-1",
                companyId = "company-1",
                title = "test",
                model = "test-model",
                provider = "ollama",
                baseUrl = baseUrl
            )

            val chunks = DirectChatService()
                .streamChat(conversation, userMessage = "hi", messageId = "message-1")
                .toList()

            chunks.filter { it.done } shouldHaveSize 1
            chunks.last().done shouldBe true
            chunks.joinToString("") { it.content } shouldBe "hello"
        } finally {
            server.stop(0)
        }
    }

    test("ollama stream honors downstream cancellation after first chunk") {
        val server = oneChunkHangingServer("""{"message":{"content":"first"},"done":false}""")
        server.start()
        try {
            val conversation = DirectChatConversation(
                id = "conversation-ollama-take",
                companyId = "company-1",
                title = "test",
                model = "test-model",
                provider = "ollama",
                baseUrl = "http://127.0.0.1:${server.address.port}"
            )

            val chunks = withTimeout(2_000) {
                DirectChatService()
                    .streamChat(conversation, userMessage = "hi", messageId = "message-1")
                    .take(1)
                    .toList()
            }

            chunks shouldHaveSize 1
            chunks.single().content shouldBe "first"
        } finally {
            server.stop(0)
        }
    }

    test("ollama stream reports an error for oversized provider lines before newline materialization") {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/api/chat") { exchange ->
            val body = """{"message":{"content":"${"x".repeat(80)}"},"done":false}"""
            val bytes = body.toByteArray()
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
        try {
            val conversation = DirectChatConversation(
                id = "conversation-ollama-large-line",
                companyId = "company-1",
                title = "test",
                model = "test-model",
                provider = "ollama",
                baseUrl = "http://127.0.0.1:${server.address.port}"
            )

            val chunks = DirectChatService(streamLineLimitChars = 32)
                .streamChat(conversation, userMessage = "hi", messageId = "message-1")
                .toList()

            chunks.last().done shouldBe true
            chunks.last().error shouldContain "stream line exceeded 32 character limit"
        } finally {
            server.stop(0)
        }
    }

    test("lmstudio stream honors downstream cancellation after first chunk") {
        val server = oneChunkHangingServer(
            """data: {"choices":[{"delta":{"content":"first"},"finish_reason":null}]}"""
        )
        server.start()
        try {
            val conversation = DirectChatConversation(
                id = "conversation-lmstudio-take",
                companyId = "company-1",
                title = "test",
                model = "test-model",
                provider = "lmstudio",
                baseUrl = "http://127.0.0.1:${server.address.port}"
            )

            val chunks = withTimeout(2_000) {
                DirectChatService()
                    .streamChat(conversation, userMessage = "hi", messageId = "message-1")
                    .take(1)
                    .toList()
            }

            chunks shouldHaveSize 1
            chunks.single().content shouldBe "first"
        } finally {
            server.stop(0)
        }
    }

    test("lmstudio stream reports an error when cumulative content exceeds the budget") {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/v1/chat/completions") { exchange ->
            val body = """
                data: {"choices":[{"delta":{"content":"abc"},"finish_reason":null}]}
                data: {"choices":[{"delta":{"content":"def"},"finish_reason":null}]}
                data: [DONE]
            """.trimIndent()
            val bytes = body.toByteArray()
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
        try {
            val conversation = DirectChatConversation(
                id = "conversation-lmstudio-content-budget",
                companyId = "company-1",
                title = "test",
                model = "test-model",
                provider = "lmstudio",
                baseUrl = "http://127.0.0.1:${server.address.port}"
            )

            val chunks = DirectChatService(streamContentLimitChars = 5)
                .streamChat(conversation, userMessage = "hi", messageId = "message-1")
                .toList()

            chunks.first().content shouldBe "abc"
            chunks.last().done shouldBe true
            chunks.last().error shouldContain "stream content exceeded 5 character limit"
        } finally {
            server.stop(0)
        }
    }

    test("claude-cli direct chat sends prompt through stdin instead of argv") {
        val scriptDir = Files.createTempDirectory("direct-chat-claude")
        val script = scriptDir.resolve("fake-claude")
        val argsFile = scriptDir.resolve("args.txt")
        val stdinFile = scriptDir.resolve("stdin.txt")
        Files.writeString(
            script,
            """
            #!/bin/sh
            printf '%s\n' "${'$'}@" > '${argsFile.toString().replace("'", "'\\''")}'
            cat > '${stdinFile.toString().replace("'", "'\\''")}'
            printf 'claude response'
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

        val conversation = DirectChatConversation(
            id = "conversation-claude",
            companyId = "company-1",
            title = "test",
            model = "claude",
            provider = "claude-cli"
        )

        val chunks = DirectChatService(claudeCommand = script.toString())
            .streamChat(conversation, userMessage = "hello from stdin", messageId = "message-1")
            .toList()

        chunks.last().done shouldBe true
        chunks.last().content shouldBe "claude response"
        argsFile.readText().trim() shouldBe "-p"
        stdinFile.readText() shouldContain "hello from stdin"
    }

    test("claude-cli direct chat cancellation kills descendant process and propagates cancellation") {
        coroutineScope {
            val scriptDir = Files.createTempDirectory("direct-chat-claude-cancel")
            val script = scriptDir.resolve("fake-claude")
            val childPidFile = scriptDir.resolve("child.pid")
            Files.writeString(
                script,
                """
                #!/bin/sh
                cat >/dev/null
                sleep 30 &
                child=${'$'}!
                printf '%s\n' "${'$'}child" > '${childPidFile.toString().replace("'", "'\\''")}'
                wait "${'$'}child"
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
            val conversation = DirectChatConversation(
                id = "conversation-claude-cancel",
                companyId = "company-1",
                title = "test",
                model = "claude",
                provider = "claude-cli"
            )
            var childPid: Long? = null
            val deferred = async {
                DirectChatService(claudeCommand = script.toString(), claudeTimeoutMillis = 30_000)
                    .streamChat(conversation, userMessage = "cancel this", messageId = "message-1")
                    .toList()
            }

            try {
                waitForFile(childPidFile)
                val pid = childPidFile.readText().trim().toLong()
                childPid = pid
                deferred.cancel()

                shouldThrow<CancellationException> {
                    deferred.await()
                }
                waitUntilNotAlive(pid).shouldBe(true)
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
    }
})

private suspend fun waitForFile(path: Path) {
    withTimeout(5_000) {
        while (!Files.exists(path)) {
            delay(25)
        }
    }
}

private suspend fun waitUntilNotAlive(pid: Long): Boolean {
    repeat(40) {
        if (!isProcessAlive(pid)) {
            return true
        }
        delay(100)
    }
    return !isProcessAlive(pid)
}

private fun isProcessAlive(pid: Long): Boolean =
    ProcessHandle.of(pid).map { it.isAlive }.orElse(false)

private fun oneChunkHangingServer(line: String): HttpServer {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.createContext("/") { exchange ->
        exchange.sendResponseHeaders(200, 0)
        try {
            exchange.responseBody.write((line + "\n").toByteArray())
            exchange.responseBody.flush()
            Thread.sleep(10_000)
        } catch (_: Exception) {
            // Client-side cancellation should close this stream.
        } finally {
            exchange.responseBody.close()
        }
    }
    return server
}
