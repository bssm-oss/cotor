package com.cotor.presentation.cli

import com.cotor.data.process.destroyProcessTree
import java.io.IOException
import java.nio.file.Path
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

internal const val DESKTOP_LIFECYCLE_COMMAND_TIMEOUT_SECONDS = 30L * 60L
internal const val DESKTOP_LIFECYCLE_OUTPUT_LIMIT_CHARS = 512 * 1024

internal fun runDesktopCommand(
    command: List<String>,
    workingDirectory: Path? = null,
    environment: Map<String, String> = emptyMap(),
    timeoutSeconds: Long = DESKTOP_LIFECYCLE_COMMAND_TIMEOUT_SECONDS,
    outputLimitChars: Int = DESKTOP_LIFECYCLE_OUTPUT_LIMIT_CHARS,
    timeoutMessage: (Long) -> String
): DesktopScriptResult {
    if (command.isEmpty()) {
        return DesktopScriptResult(exitCode = 127, output = "Missing desktop lifecycle command.\n")
    }
    val process = try {
        ProcessBuilder(command)
            .redirectErrorStream(true)
            .apply {
                workingDirectory?.let { directory(it.toFile()) }
                environment().putAll(environment)
            }
            .start()
    } catch (error: IOException) {
        return DesktopScriptResult(
            exitCode = 127,
            output = "Failed to start desktop lifecycle command `${command.joinToString(" ")}`: ${error.message ?: error::class.simpleName.orEmpty()}\n"
        )
    } catch (error: SecurityException) {
        return DesktopScriptResult(
            exitCode = 126,
            output = "Desktop lifecycle command was blocked `${command.joinToString(" ")}`: ${error.message ?: error::class.simpleName.orEmpty()}\n"
        )
    }

    runCatching { process.outputStream.close() }
    val output = BoundedDesktopCommandOutput(outputLimitChars)
    val outputReader = thread(
        start = true,
        isDaemon = true,
        name = "cotor-desktop-lifecycle-output"
    ) {
        runCatching {
            process.inputStream.bufferedReader().use { reader ->
                val buffer = CharArray(8192)
                while (true) {
                    val read = reader.read(buffer)
                    if (read == -1) break
                    output.append(buffer, read)
                }
            }
        }
    }

    val effectiveTimeout = timeoutSeconds.coerceAtLeast(1)
    val finished = try {
        process.waitFor(effectiveTimeout, TimeUnit.SECONDS)
    } catch (_: InterruptedException) {
        destroyProcessTree(process)
        runCatching { process.inputStream.close() }
        runCatching { outputReader.join(1_000) }
        Thread.currentThread().interrupt()
        return DesktopScriptResult(
            exitCode = 130,
            output = output.snapshotWithSuffix("Desktop lifecycle command interrupted.")
        )
    }
    if (!finished) {
        destroyProcessTree(process)
        outputReader.join(1_000)
        return DesktopScriptResult(
            exitCode = 124,
            output = output.snapshotWithSuffix(timeoutMessage(effectiveTimeout))
        )
    }

    outputReader.join(1_000)
    return DesktopScriptResult(exitCode = process.exitValue(), output = output.snapshot())
}

private class BoundedDesktopCommandOutput(
    private val limit: Int
) {
    private val builder = StringBuilder()
    private var truncated = false

    @Synchronized
    fun append(buffer: CharArray, length: Int) {
        if (limit <= 0 || length <= 0) {
            return
        }
        builder.append(buffer, 0, length)
        if (builder.length > limit) {
            builder.delete(0, builder.length - limit)
            truncated = true
        }
    }

    @Synchronized
    fun snapshot(): String {
        val content = builder.toString()
        return if (truncated) {
            "[desktop lifecycle output truncated to last $limit chars]\n$content"
        } else {
            content
        }
    }

    @Synchronized
    fun snapshotWithSuffix(suffix: String): String = buildString {
        val current = snapshot()
        append(current)
        if (current.isNotEmpty() && !current.endsWith("\n")) {
            appendLine()
        }
        appendLine(suffix.trimEnd())
    }
}
