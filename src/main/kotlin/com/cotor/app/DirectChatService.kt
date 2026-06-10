package com.cotor.app

/**
 * File overview for DirectChatService.
 *
 * This file belongs to the app layer for the desktop shell and localhost app-server surface.
 * It groups declarations around direct AI chat so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through direct multi-turn AI conversations.
 */

import com.cotor.data.http.sendBoundedText
import com.cotor.data.process.destroyProcessTree
import com.cotor.model.CodexDefaults
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.yield
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.InputStreamReader
import java.io.Reader
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.file.Files
import java.nio.file.Path
import java.nio.charset.StandardCharsets
import java.time.Duration
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

private val directChatHttpThreadCounter = AtomicInteger()
private val directChatHttpClient: HttpClient = HttpClient.newBuilder()
    .connectTimeout(Duration.ofSeconds(10))
    .executor(
        java.util.concurrent.ThreadPoolExecutor(
            0,
            16,
            60L,
            TimeUnit.SECONDS,
            java.util.concurrent.SynchronousQueue()
        ) { runnable ->
            Thread(runnable, "cotor-direct-chat-http-${directChatHttpThreadCounter.incrementAndGet()}").apply {
                isDaemon = true
            }
        }
    )
    .build()

private val directChatJson = Json { ignoreUnknownKeys = true }

private const val DEFAULT_DIRECT_CHAT_MODEL_LIST_RESPONSE_LIMIT_CHARS = 1_000_000
private const val DEFAULT_DIRECT_CHAT_STREAM_LINE_LIMIT_CHARS = 200_000
private const val DEFAULT_DIRECT_CHAT_STREAM_CONTENT_LIMIT_CHARS = 1_000_000

class DirectChatService(
    private val codexCommand: String = "codex",
    private val codexTimeoutMillis: Long = TimeUnit.MINUTES.toMillis(5),
    private val codexOutputLimitChars: Int = 1_000_000,
    private val codexEnvironment: Map<String, String> = System.getenv(),
    private val modelListResponseLimitChars: Int = DEFAULT_DIRECT_CHAT_MODEL_LIST_RESPONSE_LIMIT_CHARS,
    private val streamLineLimitChars: Int = DEFAULT_DIRECT_CHAT_STREAM_LINE_LIMIT_CHARS,
    private val streamContentLimitChars: Int = DEFAULT_DIRECT_CHAT_STREAM_CONTENT_LIMIT_CHARS
) {

    private fun validateAndNormalizeBaseUrl(raw: String, defaultBase: String): String {
        if (raw.isBlank()) return defaultBase
        val uri = URI.create(raw)
        val scheme = uri.scheme?.lowercase()
        require(scheme == "http" || scheme == "https") {
            "Only http/https schemes are allowed, got: $scheme"
        }
        val host = uri.host?.lowercase()
        require(host in setOf("127.0.0.1", "localhost", "::1")) {
            "Only localhost connections are allowed, got: $host"
        }
        return raw.trimEnd('/')
    }

    fun listAvailableModels(baseUrl: String = "http://127.0.0.1:11434"): List<DirectChatAvailableModel> {
        val effectiveBase = validateAndNormalizeBaseUrl(baseUrl, "http://127.0.0.1:11434")
        return try {
            val request = HttpRequest.newBuilder()
                .uri(URI.create("$effectiveBase/api/tags"))
                .timeout(Duration.ofSeconds(5))
                .GET()
                .build()
            val response = directChatHttpClient.sendBoundedText(request, modelListResponseLimitChars)
            if (response.statusCode != 200 || response.truncated) return emptyList()
            val body = directChatJson.parseToJsonElement(response.body).jsonObject
            val modelsArray = body["models"]?.jsonArray ?: return emptyList()
            modelsArray.mapNotNull { element ->
                val name = element.jsonObject["name"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                DirectChatAvailableModel(
                    id = name,
                    provider = "ollama",
                    displayName = name
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun streamChat(
        conversation: DirectChatConversation,
        userMessage: String,
        messageId: String
    ): Flow<DirectChatStreamChunk> = flow {
        val provider = findDirectChatProvider(conversation.provider)
        val providerId = provider?.id ?: conversation.provider
        val defaultBase = provider?.defaultBaseUrl.orEmpty()
        val effectiveBase = if (defaultBase.isBlank()) {
            defaultBase
        } else {
            validateAndNormalizeBaseUrl(conversation.baseUrl, defaultBase)
        }

        when (providerId) {
            "ollama" -> streamOllama(conversation, userMessage, messageId, effectiveBase)
                .collect { emit(it) }
            "lmstudio" -> streamLmStudio(conversation, userMessage, messageId, effectiveBase)
                .collect { emit(it) }
            "codex-oauth" -> streamCodexOAuth(conversation, userMessage, messageId)
                .collect { emit(it) }
            else -> emit(
                DirectChatStreamChunk(
                    conversationId = conversation.id,
                    messageId = messageId,
                    content = "",
                    done = true,
                    error = "Unknown provider: ${conversation.provider}"
                )
            )
        }
    }

    private fun streamOllama(
        conversation: DirectChatConversation,
        userMessage: String,
        messageId: String,
        baseUrl: String
    ): Flow<DirectChatStreamChunk> = flow {
        val messages = buildOllamaMessages(conversation, userMessage)
        val bodyJson = buildString {
            append("{")
            append("\"model\":${jsonString(conversation.model)},")
            append("\"stream\":true,")
            append("\"messages\":[")
            messages.forEachIndexed { idx, (role, content) ->
                if (idx > 0) append(",")
                append("{\"role\":${jsonString(role)},\"content\":${jsonString(content)}}")
            }
            append("]}")
        }

        try {
            val request = HttpRequest.newBuilder()
                .uri(URI.create("$baseUrl/api/chat"))
                .timeout(Duration.ofMinutes(10))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(bodyJson))
                .build()

            val response = withContext(Dispatchers.IO) {
                directChatHttpClient.send(request, HttpResponse.BodyHandlers.ofInputStream())
            }
            if (response.statusCode() !in 200..299) {
                error("Ollama request failed with HTTP ${response.statusCode()}")
            }
            var doneSent = false
            var emittedContentChars = 0
            response.body().use { stream ->
                val reader = BoundedDirectChatLineReader(
                    reader = InputStreamReader(stream, StandardCharsets.UTF_8),
                    lineLimitChars = streamLineLimitChars,
                    provider = "Ollama"
                )
                while (true) {
                    val line = withContext(Dispatchers.IO) { reader.readLine() } ?: break
                    if (line.isBlank()) continue
                    val parsedChunk = try {
                        val parsed = directChatJson.parseToJsonElement(line).jsonObject
                        val done = parsed["done"]?.jsonPrimitive?.booleanOrNull == true
                        val content = parsed["message"]?.jsonObject?.get("content")
                            ?.jsonPrimitive?.contentOrNull ?: ""
                        content to done
                    } catch (e: CancellationException) {
                        throw e
                    } catch (_: Exception) {
                        // skip malformed lines
                        null
                    } ?: continue

                    val (content, done) = parsedChunk
                    emittedContentChars = updatedStreamContentChars("Ollama", emittedContentChars, content)
                    emit(
                        DirectChatStreamChunk(
                            conversationId = conversation.id,
                            messageId = messageId,
                            content = content,
                            done = done
                        )
                    )
                    if (done) {
                        doneSent = true
                        break
                    }
                }
            }
            // ensure done=true is emitted if the stream ended without an explicit done
            if (!doneSent) {
                emit(
                    DirectChatStreamChunk(
                        conversationId = conversation.id,
                        messageId = messageId,
                        content = "",
                        done = true
                    )
                )
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emit(
                DirectChatStreamChunk(
                    conversationId = conversation.id,
                    messageId = messageId,
                    content = "",
                    done = true,
                    error = e.message ?: "Ollama request failed"
                )
            )
        }
    }

    private fun streamLmStudio(
        conversation: DirectChatConversation,
        userMessage: String,
        messageId: String,
        baseUrl: String
    ): Flow<DirectChatStreamChunk> = flow {
        val messages = buildOllamaMessages(conversation, userMessage)
        val bodyJson = buildString {
            append("{")
            append("\"model\":${jsonString(conversation.model)},")
            append("\"stream\":true,")
            append("\"messages\":[")
            messages.forEachIndexed { idx, (role, content) ->
                if (idx > 0) append(",")
                append("{\"role\":${jsonString(role)},\"content\":${jsonString(content)}}")
            }
            append("]}")
        }

        try {
            val request = HttpRequest.newBuilder()
                .uri(URI.create("$baseUrl/v1/chat/completions"))
                .timeout(Duration.ofMinutes(10))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(bodyJson))
                .build()

            val response = withContext(Dispatchers.IO) {
                directChatHttpClient.send(request, HttpResponse.BodyHandlers.ofInputStream())
            }
            if (response.statusCode() !in 200..299) {
                error("LM Studio request failed with HTTP ${response.statusCode()}")
            }
            var doneSent = false
            var emittedContentChars = 0
            response.body().use { stream ->
                val reader = BoundedDirectChatLineReader(
                    reader = InputStreamReader(stream, StandardCharsets.UTF_8),
                    lineLimitChars = streamLineLimitChars,
                    provider = "LM Studio"
                )
                while (true) {
                    val line = withContext(Dispatchers.IO) { reader.readLine() } ?: break
                    if (line.isBlank()) continue
                    if (!line.startsWith("data:")) continue
                    val data = line.removePrefix("data:").trim()
                    if (data == "[DONE]") {
                        if (!doneSent) {
                            doneSent = true
                            emit(
                                DirectChatStreamChunk(
                                    conversationId = conversation.id,
                                    messageId = messageId,
                                    content = "",
                                    done = true
                                )
                            )
                        }
                        break
                    }
                    val parsedChunk = try {
                        val parsed = directChatJson.parseToJsonElement(data).jsonObject
                        val finishReason = parsed["choices"]?.jsonArray
                            ?.firstOrNull()?.jsonObject?.get("finish_reason")
                            ?.jsonPrimitive?.contentOrNull
                        val content = parsed["choices"]?.jsonArray
                            ?.firstOrNull()?.jsonObject?.get("delta")
                            ?.jsonObject?.get("content")
                            ?.jsonPrimitive?.contentOrNull ?: ""
                        val done = finishReason != null && finishReason != "null"
                        content to done
                    } catch (e: CancellationException) {
                        throw e
                    } catch (_: Exception) {
                        // skip malformed SSE lines
                        null
                    } ?: continue

                    val (content, done) = parsedChunk
                    emittedContentChars = updatedStreamContentChars("LM Studio", emittedContentChars, content)
                    emit(
                        DirectChatStreamChunk(
                            conversationId = conversation.id,
                            messageId = messageId,
                            content = content,
                            done = done
                        )
                    )
                    if (done) {
                        doneSent = true
                        break
                    }
                }
            }
            if (!doneSent) {
                emit(
                    DirectChatStreamChunk(
                        conversationId = conversation.id,
                        messageId = messageId,
                        content = "",
                        done = true
                    )
                )
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emit(
                DirectChatStreamChunk(
                    conversationId = conversation.id,
                    messageId = messageId,
                    content = "",
                    done = true,
                    error = e.message ?: "LM Studio request failed"
                )
            )
        }
    }

    private fun streamCodexOAuth(
        conversation: DirectChatConversation,
        userMessage: String,
        messageId: String
    ): Flow<DirectChatStreamChunk> = flow {
        val prompt = buildCliChatPrompt(conversation, userMessage)
        val outputFile = withContext(Dispatchers.IO) {
            Files.createTempFile("cotor-direct-chat-codex-", ".txt")
        }
        try {
            val output = withContext(Dispatchers.IO) {
                coroutineScope {
                    var process: Process? = null
                    try {
                        val model = CodexDefaults.normalizeModel(conversation.model)
                            ?: CodexDefaults.DEFAULT_MODEL
                        process = ProcessBuilder(
                            codexCommand,
                            "exec",
                            "--skip-git-repo-check",
                            "--sandbox",
                            "read-only",
                            "--output-last-message",
                            outputFile.toString(),
                            "-c",
                            "mcp_servers={}",
                            "--model",
                            model,
                            "-"
                        )
                            .redirectErrorStream(true)
                            .also { builder ->
                                builder.environment().putAll(codexEnvironment)
                                builder.environment()["CODEX_HOME"] = effectiveCodexOAuthHome(codexEnvironment).toString()
                            }
                            .start()
                        // Read and wait concurrently so killing the process unblocks the read.
                        val readJob = async(Dispatchers.IO) {
                            val sb = StringBuilder()
                            process.inputStream.bufferedReader().use { reader ->
                                val buf = CharArray(8192)
                                var read: Int
                                while (reader.read(buf).also { read = it } != -1) {
                                    sb.append(buf, 0, read)
                                    if (sb.length > codexOutputLimitChars) {
                                        destroyProcessTree(process)
                                        error("codex-oauth output exceeded $codexOutputLimitChars character limit")
                                    }
                                }
                            }
                            sb.toString()
                        }
                        val writeJob = async(Dispatchers.IO) {
                            process.outputStream.bufferedWriter().use { writer ->
                                writer.write(prompt)
                                writer.flush()
                            }
                        }
                        val finished = withTimeoutOrNull(codexTimeoutMillis.coerceAtLeast(1)) {
                            while (!process.waitFor(50, TimeUnit.MILLISECONDS)) {
                                yield()
                            }
                            true
                        } == true
                        if (!finished) {
                            destroyProcessTree(process)
                            readJob.cancel()
                            writeJob.cancel()
                            error("codex-oauth timed out after ${codexTimeoutMillis}ms")
                        }
                        writeJob.await()
                        val stdout = readJob.await()
                        val exitCode = process.exitValue()
                        val finalText = readBoundedUtf8Text(outputFile, codexOutputLimitChars).trim()
                        if (exitCode != 0 && finalText.isBlank()) {
                            error(stdout.ifBlank { "codex-oauth failed with exit $exitCode" })
                        }
                        finalText.ifBlank { stdout }
                    } finally {
                        process?.takeIf { it.isAlive }?.let(::destroyProcessTree)
                    }
                }
            }
            emit(
                DirectChatStreamChunk(
                    conversationId = conversation.id,
                    messageId = messageId,
                    content = output,
                    done = true
                )
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emit(
                DirectChatStreamChunk(
                    conversationId = conversation.id,
                    messageId = messageId,
                    content = "",
                    done = true,
                    error = e.message ?: "codex-oauth execution failed"
                )
            )
        } finally {
            withContext(Dispatchers.IO) {
                runCatching { Files.deleteIfExists(outputFile) }
            }
        }
    }

    private fun updatedStreamContentChars(provider: String, current: Int, content: String): Int {
        val limit = streamContentLimitChars.coerceAtLeast(1)
        val next = current + content.length
        require(next <= limit) {
            "$provider stream content exceeded $limit character limit"
        }
        return next
    }

    private class BoundedDirectChatLineReader(
        private val reader: Reader,
        lineLimitChars: Int,
        private val provider: String
    ) {
        private val limit = lineLimitChars.coerceAtLeast(1)
        private val buffer = CharArray(8_192)
        private var offset = 0
        private var length = 0

        fun readLine(): String? {
            val line = StringBuilder()
            var sawAny = false

            while (true) {
                if (offset >= length) {
                    length = reader.read(buffer)
                    offset = 0
                    if (length < 0) {
                        return if (sawAny) line.toString() else null
                    }
                }

                val ch = buffer[offset++]
                sawAny = true
                when (ch) {
                    '\n' -> return line.toString()
                    '\r' -> Unit
                    else -> {
                        require(line.length < limit) {
                            "$provider stream line exceeded $limit character limit"
                        }
                        line.append(ch)
                    }
                }
            }
        }
    }

    private fun buildOllamaMessages(
        conversation: DirectChatConversation,
        userMessage: String
    ): List<Pair<String, String>> {
        val result = mutableListOf<Pair<String, String>>()
        if (conversation.systemPrompt.isNotBlank()) {
            result += "system" to conversation.systemPrompt
        }
        conversation.messages.takeLast(40).forEach { msg ->
            result += msg.role to msg.content
        }
        result += "user" to userMessage
        return result
    }

    private fun buildCliChatPrompt(
        conversation: DirectChatConversation,
        userMessage: String
    ): String = buildString {
        if (conversation.systemPrompt.isNotBlank()) {
            append("System: ${conversation.systemPrompt}\n\n")
        }
        conversation.messages.takeLast(40).forEach { msg ->
            val label = if (msg.role == "user") "Human" else "Assistant"
            append("$label: ${msg.content}\n\n")
        }
        append("Human: $userMessage\n\nAssistant:")
    }

    private fun managedCodexOAuthHome(environment: Map<String, String>): Path {
        environment["COTOR_CODEX_OAUTH_HOME"]?.trim()?.takeIf { it.isNotBlank() }?.let {
            return Path.of(it)
        }
        val home = environment["HOME"]?.trim()?.takeIf { it.isNotBlank() }
            ?: System.getProperty("user.home")
        return Path.of(home).resolve(".cotor").resolve("auth").resolve("codex-oauth")
    }

    private fun nativeCodexHome(environment: Map<String, String>): Path? {
        environment["CODEX_HOME"]?.trim()?.takeIf { it.isNotBlank() }?.let {
            return Path.of(it)
        }
        return environment["HOME"]?.trim()?.takeIf { it.isNotBlank() }
            ?.let { Path.of(it).resolve(".codex") }
    }

    private fun effectiveCodexOAuthHome(environment: Map<String, String>): Path {
        val managed = managedCodexOAuthHome(environment)
        val native = nativeCodexHome(environment)
        val managedAuth = managed.resolve("auth.json")
        val nativeAuth = native?.resolve("auth.json")
        return when {
            nativeAuth != null && Files.exists(nativeAuth) && Files.exists(managedAuth) -> {
                val managedUpdatedAt = Files.getLastModifiedTime(managedAuth).toMillis()
                val nativeUpdatedAt = Files.getLastModifiedTime(nativeAuth).toMillis()
                if (nativeUpdatedAt > managedUpdatedAt) native else managed
            }
            nativeAuth != null && Files.exists(nativeAuth) -> native
            else -> managed
        }
    }

    private fun readBoundedUtf8Text(path: Path, maxChars: Int): String {
        if (!Files.exists(path)) return ""
        val limit = maxChars.coerceAtLeast(1)
        Files.newBufferedReader(path, StandardCharsets.UTF_8).use { reader ->
            val buffer = CharArray(limit)
            var offset = 0
            while (offset < limit) {
                val read = reader.read(buffer, offset, limit - offset)
                if (read < 0) return String(buffer, 0, offset)
                offset += read
            }
            val truncated = reader.read() >= 0
            return if (truncated) {
                String(buffer, 0, offset) + "\n[cotor truncated direct chat output after $limit chars]"
            } else {
                String(buffer, 0, offset)
            }
        }
    }

    private fun jsonString(value: String): String {
        val sb = StringBuilder("\"")
        for (ch in value) {
            when {
                ch == '"' -> sb.append("\\\"")
                ch == '\\' -> sb.append("\\\\")
                ch == '\n' -> sb.append("\\n")
                ch == '\r' -> sb.append("\\r")
                ch == '\t' -> sb.append("\\t")
                ch.code < 0x20 -> sb.append("\\u%04x".format(ch.code))
                else -> sb.append(ch)
            }
        }
        sb.append("\"")
        return sb.toString()
    }
}
