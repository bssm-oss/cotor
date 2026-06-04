package com.cotor.app

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.UUID

internal class DesktopDirectChatService(
    private val stateStore: DesktopStateStore,
    private val stateMutex: Mutex,
    private val directChatService: DirectChatService = DirectChatService()
) {
    suspend fun createConversation(
        companyId: String,
        title: String,
        model: String,
        provider: String,
        baseUrl: String = "",
        systemPrompt: String = ""
    ): DirectChatConversation = stateMutex.withLock {
        val state = stateStore.load()
        val now = System.currentTimeMillis()
        val normalizedProvider = findDirectChatProvider(provider)?.id ?: provider
        val conversation = DirectChatConversation(
            id = UUID.randomUUID().toString(),
            companyId = companyId,
            title = title.trim().ifEmpty { model },
            model = model,
            provider = normalizedProvider,
            baseUrl = baseUrl,
            systemPrompt = systemPrompt,
            messages = emptyList(),
            createdAt = now,
            updatedAt = now
        )
        stateStore.save(
            state.copy(directChatConversations = state.directChatConversations + conversation)
        )
        conversation
    }

    suspend fun listConversations(companyId: String): List<DirectChatConversation> =
        stateStore.load().directChatConversations.filter { it.companyId == companyId }

    suspend fun getConversation(id: String): DirectChatConversation? =
        stateStore.load().directChatConversations.firstOrNull { it.id == id }

    suspend fun deleteConversation(id: String, companyId: String): Boolean =
        stateMutex.withLock {
            val state = stateStore.load()
            val target = state.directChatConversations.firstOrNull { it.id == id }
                ?: return@withLock false
            require(target.companyId == companyId) {
                "Conversation $id does not belong to company $companyId"
            }
            stateStore.save(
                state.copy(
                    directChatConversations = state.directChatConversations
                        .filterNot { it.id == id && it.companyId == companyId }
                )
            )
            true
        }

    fun streamMessage(
        conversationId: String,
        companyId: String,
        userMessage: String
    ): Flow<DirectChatStreamChunk> = flow {
        val conversation = getConversation(conversationId)
            ?: run {
                emit(
                    DirectChatStreamChunk(
                        conversationId = conversationId,
                        messageId = UUID.randomUUID().toString(),
                        content = "",
                        done = true,
                        error = "Conversation not found: $conversationId"
                    )
                )
                return@flow
            }

        if (conversation.companyId != companyId) {
            emit(
                DirectChatStreamChunk(
                    conversationId = conversationId,
                    messageId = UUID.randomUUID().toString(),
                    content = "",
                    done = true,
                    error = "Conversation $conversationId does not belong to company $companyId"
                )
            )
            return@flow
        }

        val userMsg = DirectChatMessage(
            id = UUID.randomUUID().toString(),
            role = "user",
            content = userMessage,
            createdAt = System.currentTimeMillis()
        )
        appendMessage(conversationId, userMsg)

        val assistantMessageId = UUID.randomUUID().toString()
        val contentBuilder = StringBuilder()
        var assistantSaved = false

        directChatService.streamChat(conversation, userMessage, assistantMessageId).collect { chunk ->
            emit(chunk)
            if (chunk.error != null) {
                return@collect
            }
            contentBuilder.append(chunk.content)
            if (chunk.done && !assistantSaved) {
                val assistantContent = contentBuilder.toString()
                if (assistantContent.isNotEmpty()) {
                    assistantSaved = true
                    appendMessage(
                        conversationId,
                        DirectChatMessage(
                            id = assistantMessageId,
                            role = "assistant",
                            content = assistantContent,
                            createdAt = System.currentTimeMillis()
                        )
                    )
                }
            }
        }
    }

    suspend fun listModels(baseUrl: String = "http://127.0.0.1:11434"): List<DirectChatAvailableModel> =
        withContext(Dispatchers.IO) {
            directChatService.listAvailableModels(baseUrl)
        }

    private suspend fun appendMessage(conversationId: String, message: DirectChatMessage) {
        stateMutex.withLock {
            val state = stateStore.load()
            val now = System.currentTimeMillis()
            stateStore.save(
                state.copy(
                    directChatConversations = state.directChatConversations.map { conversation ->
                        if (conversation.id == conversationId) {
                            conversation.copy(messages = conversation.messages + message, updatedAt = now)
                        } else {
                            conversation
                        }
                    }
                )
            )
        }
    }
}
