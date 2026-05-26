package com.cotor.app

/**
 * File overview for DirectChatService.
 *
 * This file belongs to the app layer for the desktop shell and localhost app-server surface.
 * It groups declarations around direct AI chat so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through direct multi-turn AI conversations.
 */

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration
import java.util.concurrent.atomic.AtomicInteger

private val directChatHttpThreadCounter = AtomicInteger()
private val directChatHttpClient: HttpClient = HttpClient.newBuilder()
    .connectTimeout(Duration.ofSeconds(10))
    .executor(
        java.util.concurrent.Executors.newCachedThreadPool { runnable ->
            Thread(runnable, "cotor-direct-chat-http-${directChatHttpThreadCounter.incrementAndGet()}").apply {
                isDaemon = true
            }
        }
    )
    .build()

private val directChatJson = Json { ignoreUnknownKeys = true }

class DirectChatService {

    fun listAvailableModels(baseUrl: String = "http://127.0.0.1:11434"): List<DirectChatAvailableModel> {
        val effectiveBase = baseUrl.trimEnd('/')
        return try {
            val request = HttpRequest.newBuilder()
                .uri(URI.create("$effectiveBase/api/tags"))
                .timeout(Duration.ofSeconds(5))
                .GET()
                .build()
            val response = directChatHttpClient.send(request, HttpResponse.BodyHandlers.ofString())
            if (response.statusCode() != 200) return emptyList()
            val body = directChatJson.parseToJsonElement(response.body()).jsonObject
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
        val provider = conversation.provider
        val effectiveBase = conversation.baseUrl.trimEnd('/').ifBlank {
            when (provider) {
                "ollama" -> "http://127.0.0.1:11434"
                "lmstudio" -> "http://127.0.0.1:1234"
                else -> ""
            }
        }

        when (provider) {
            "ollama" -> streamOllama(conversation, userMessage, messageId, effectiveBase)
                .collect { emit(it) }
            "lmstudio" -> streamLmStudio(conversation, userMessage, messageId, effectiveBase)
                .collect { emit(it) }
            "claude-cli" -> streamClaudeCli(conversation, userMessage, messageId)
                .collect { emit(it) }
            else -> emit(
                DirectChatStreamChunk(
                    conversationId = conversation.id,
                    messageId = messageId,
                    content = "",
                    done = true,
                    error = "Unknown provider: $provider"
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
                directChatHttpClient.send(request, HttpResponse.BodyHandlers.ofLines())
            }
            val iterator = response.body().iterator()
            while (withContext(Dispatchers.IO) { iterator.hasNext() }) {
                val line = withContext(Dispatchers.IO) { iterator.next() }
                if (line.isBlank()) continue
                try {
                    val parsed = directChatJson.parseToJsonElement(line).jsonObject
                    val done = parsed["done"]?.jsonPrimitive?.contentOrNull == "true"
                    val content = parsed["message"]?.jsonObject?.get("content")
                        ?.jsonPrimitive?.contentOrNull ?: ""
                    emit(
                        DirectChatStreamChunk(
                            conversationId = conversation.id,
                            messageId = messageId,
                            content = content,
                            done = done
                        )
                    )
                    if (done) break
                } catch (_: Exception) {
                    // skip malformed lines
                }
            }
            // ensure done=true is emitted if the stream ended without an explicit done
            emit(
                DirectChatStreamChunk(
                    conversationId = conversation.id,
                    messageId = messageId,
                    content = "",
                    done = true
                )
            )
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
                directChatHttpClient.send(request, HttpResponse.BodyHandlers.ofLines())
            }
            var doneSent = false
            val iterator = response.body().iterator()
            while (withContext(Dispatchers.IO) { iterator.hasNext() }) {
                val line = withContext(Dispatchers.IO) { iterator.next() }
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
                try {
                    val parsed = directChatJson.parseToJsonElement(data).jsonObject
                    val finishReason = parsed["choices"]?.jsonArray
                        ?.firstOrNull()?.jsonObject?.get("finish_reason")
                        ?.jsonPrimitive?.contentOrNull
                    val content = parsed["choices"]?.jsonArray
                        ?.firstOrNull()?.jsonObject?.get("delta")
                        ?.jsonObject?.get("content")
                        ?.jsonPrimitive?.contentOrNull ?: ""
                    val done = finishReason != null && finishReason != "null"
                    emit(
                        DirectChatStreamChunk(
                            conversationId = conversation.id,
                            messageId = messageId,
                            content = content,
                            done = done
                        )
                    )
                    if (done) { doneSent = true; break }
                } catch (_: Exception) {
                    // skip malformed SSE lines
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

    private fun streamClaudeCli(
        conversation: DirectChatConversation,
        userMessage: String,
        messageId: String
    ): Flow<DirectChatStreamChunk> = flow {
        val prompt = buildClaudeCliPrompt(conversation, userMessage)
        try {
            val output = withContext(Dispatchers.IO) {
                val process = ProcessBuilder("claude", "-p", prompt)
                    .redirectErrorStream(true)
                    .start()
                val text = process.inputStream.bufferedReader().readText()
                process.waitFor()
                text
            }
            emit(
                DirectChatStreamChunk(
                    conversationId = conversation.id,
                    messageId = messageId,
                    content = output,
                    done = true
                )
            )
        } catch (e: Exception) {
            emit(
                DirectChatStreamChunk(
                    conversationId = conversation.id,
                    messageId = messageId,
                    content = "",
                    done = true,
                    error = e.message ?: "claude-cli execution failed"
                )
            )
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
        conversation.messages.forEach { msg ->
            result += msg.role to msg.content
        }
        result += "user" to userMessage
        return result
    }

    private fun buildClaudeCliPrompt(
        conversation: DirectChatConversation,
        userMessage: String
    ): String = buildString {
        if (conversation.systemPrompt.isNotBlank()) {
            append("System: ${conversation.systemPrompt}\n\n")
        }
        conversation.messages.forEach { msg ->
            val label = if (msg.role == "user") "Human" else "Assistant"
            append("$label: ${msg.content}\n\n")
        }
        append("Human: $userMessage\n\nAssistant:")
    }

    private fun jsonString(value: String): String {
        val escaped = value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
        return "\"$escaped\""
    }
}
