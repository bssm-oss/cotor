package com.cotor.chat

/**
 * File overview for ChatTranscriptWriter.
 *
 * This file belongs to the interactive chat layer used by the terminal-based assistant experience.
 * It groups declarations around chat transcript writer so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import com.cotor.storage.writeTextAtomically
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption.APPEND
import java.nio.file.StandardOpenOption.CREATE
import java.nio.file.StandardOpenOption.READ
import java.time.Instant
import kotlin.io.path.createDirectories
import kotlin.io.path.exists

class ChatTranscriptWriter(
    private val saveDir: Path
) {
    private val json = Json { ignoreUnknownKeys = true }
    private val jsonlFile = saveDir.resolve("session.jsonl")
    private val memoryFile = saveDir.resolve("MEMORY.md")

    fun ensureDir(): Path {
        saveDir.createDirectories()
        return saveDir
    }

    fun loadSessionMessages(): List<ChatMessage> {
        ensureDir()
        if (!jsonlFile.exists()) return emptyList()
        val messages = ArrayDeque<ChatMessage>()
        readUtf8Tail(jsonlFile, MAX_SESSION_JSONL_READ_BYTES)
            .lineSequence()
            .filter { it.isNotBlank() }
            .forEach { line ->
                val message = runCatching { json.decodeFromString<ChatMessage>(line) }.getOrNull()
                if (message != null) {
                    if (messages.size == MAX_LOADED_SESSION_MESSAGES) {
                        messages.removeFirst()
                    }
                    messages.addLast(message)
                }
            }
        return messages.toList()
    }

    fun writeJsonl(session: ChatSession) {
        ensureDir()
        val body = buildString {
            session.snapshot().forEach { msg ->
                appendLine(json.encodeToString(msg.compactForResume()))
            }
        }
        writeTextAtomically(jsonlFile, body)
    }

    fun clearJsonl() {
        ensureDir()
        writeTextAtomically(jsonlFile, "")
    }

    fun flushMemoryIfNeeded(session: ChatSession, flushThreshold: Int = 80, keepTail: Int = 30) {
        val snapshot = session.snapshot()
        if (snapshot.size <= flushThreshold) return

        val flushChunk = snapshot.dropLast(keepTail)
        if (flushChunk.isEmpty()) return

        val bullets = flushChunk
            .chunked(2)
            .map { pair ->
                pair.joinToString(" | ") {
                    val role = if (it.role == ChatRole.USER) "USER" else "ASSISTANT"
                    "$role:${it.content.replace("\n", " ").take(100)}"
                }
            }
            .take(20)

        val entry = buildString {
            appendLine("## Memory Flush ${Instant.now()}")
            bullets.forEach { appendLine("- $it") }
            appendLine()
        }

        val prefix = if (memoryFile.exists() && Files.size(memoryFile) > 0L) "\n" else ""
        Files.writeString(memoryFile, prefix + entry, StandardCharsets.UTF_8, CREATE, APPEND)

        session.compactHistory(keepHead = 4, keepTail = keepTail)
        writeJsonl(session)
    }

    fun searchMemory(query: String, limit: Int = 3): List<String> {
        if (!memoryFile.exists() || query.isBlank()) return emptyList()
        val tokens = query.lowercase().split(" ").filter { it.isNotBlank() }
        if (tokens.isEmpty()) return emptyList()

        return readUtf8Tail(memoryFile, MAX_MEMORY_SEARCH_READ_BYTES)
            .lineSequence()
            .filter { it.startsWith("-") }
            .map { it.removePrefix("-").trim() }
            .map { line ->
                val score = tokens.count { token -> line.lowercase().contains(token) }
                line to score
            }
            .filter { it.second > 0 }
            .sortedByDescending { it.second }
            .take(limit)
            .map { it.first }
            .toList()
    }

    fun writeMarkdown(
        session: ChatSession,
        headerLines: List<String> = emptyList()
    ) {
        ensureDir()
        val md = buildString {
            appendLine("# Cotor Interactive Session")
            appendLine()
            appendLine("- SavedAt: ${Instant.now()}")
            headerLines.forEach { appendLine("- $it") }
            appendLine()
            session.snapshot().forEach { msg ->
                when (msg.role) {
                    ChatRole.USER -> {
                        appendLine("## User")
                        appendLine()
                        appendLine(msg.content)
                        appendLine()
                    }
                    ChatRole.ASSISTANT -> {
                        appendLine("## Assistant")
                        appendLine()
                        appendLine(msg.content)
                        appendLine()
                    }
                }
            }
        }
        writeTextAtomically(saveDir.resolve("transcript.md"), md)
    }

    fun writeRawText(session: ChatSession) {
        ensureDir()
        val txt = buildString {
            session.snapshot().forEach { msg ->
                val prefix = when (msg.role) {
                    ChatRole.USER -> "USER"
                    ChatRole.ASSISTANT -> "ASSISTANT"
                }
                appendLine("[$prefix] ${msg.timestamp}")
                appendLine(msg.content)
                appendLine()
            }
        }
        writeTextAtomically(saveDir.resolve("transcript.txt"), txt)
    }

    private fun ChatMessage.compactForResume(): ChatMessage {
        if (content.length <= MAX_PERSISTED_MESSAGE_CHARS) return this
        return copy(
            content = content.take(MAX_PERSISTED_MESSAGE_CHARS) +
                "\n[cotor truncated persisted interactive message after $MAX_PERSISTED_MESSAGE_CHARS chars]"
        )
    }

    private fun readUtf8Tail(path: Path, maxBytes: Long): String {
        require(maxBytes > 0L) { "maxBytes must be positive" }
        val size = Files.size(path)
        val start = (size - maxBytes).coerceAtLeast(0L)
        val length = (size - start).toInt()
        val buffer = ByteBuffer.allocate(length)

        Files.newByteChannel(path, READ).use { channel ->
            channel.position(start)
            while (buffer.hasRemaining()) {
                if (channel.read(buffer) < 0) break
            }
        }

        buffer.flip()
        val decoder = StandardCharsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPLACE)
            .onUnmappableCharacter(CodingErrorAction.REPLACE)
        val text = decoder.decode(buffer).toString()
        return if (start > 0L) text.substringAfter('\n', "") else text
    }

    private companion object {
        const val MAX_SESSION_JSONL_READ_BYTES = 2_000_000L
        const val MAX_MEMORY_SEARCH_READ_BYTES = 1_000_000L
        const val MAX_LOADED_SESSION_MESSAGES = 5_000
        const val MAX_PERSISTED_MESSAGE_CHARS = 100_000
    }
}
