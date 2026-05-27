package com.cotor.app

import com.cotor.data.process.ProcessDescendantTracker
import com.cotor.data.process.buildEffectivePath
import com.cotor.data.process.cleanupSurvivingDescendants
import com.cotor.data.process.destroyProcessTree
import com.cotor.data.process.resolveExecutablePath
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.IOException
import java.nio.file.Path
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

internal fun interface LocalSkillProcessRunner {
    suspend fun run(
        command: List<String>,
        workingDirectory: Path,
        timeoutSeconds: Long,
        timeoutMessage: String,
        environment: Map<String, String>
    ): LocalSkillProcessResult
}

internal val defaultLocalSkillProcessRunner = LocalSkillProcessRunner { command, workingDirectory, timeoutSeconds, timeoutMessage, environment ->
    runLocalSkillProcess(
        command = command,
        workingDirectory = workingDirectory,
        timeoutSeconds = timeoutSeconds,
        timeoutMessage = timeoutMessage,
        environment = environment
    )
}

internal data class LocalSkillProcessResult(
    val exitCode: Int,
    val output: String
)

internal fun runLocalSkillProcess(
    command: List<String>,
    workingDirectory: Path,
    timeoutSeconds: Long,
    timeoutMessage: String,
    environment: Map<String, String> = emptyMap(),
    outputLimitChars: Int = DEFAULT_LOCAL_SKILL_OUTPUT_LIMIT_CHARS
): LocalSkillProcessResult {
    require(command.isNotEmpty()) { "command is required" }
    require(timeoutSeconds > 0) { "timeoutSeconds must be positive" }
    val processEnvironment = System.getenv().toMutableMap().apply { putAll(environment) }
    val resolvedCommand = resolveLocalSkillCommand(command, processEnvironment)
    val process = try {
        ProcessBuilder(resolvedCommand)
            .directory(workingDirectory.toFile())
            .redirectErrorStream(true)
            .also { builder ->
                val builderEnvironment = builder.environment()
                builderEnvironment.putAll(environment)
                val resolvedExecutable = resolvedCommand.firstOrNull()
                    ?.let { runCatching { Path.of(it) }.getOrNull() }
                val effectivePath = buildEffectivePath(
                    inheritedPath = builderEnvironment["PATH"],
                    overridePath = environment["PATH"],
                    resolvedExecutable = resolvedExecutable
                )
                if (effectivePath.isNotBlank()) {
                    builderEnvironment["PATH"] = effectivePath
                }
            }
            .start()
    } catch (error: IOException) {
        return LocalSkillProcessResult(
            exitCode = localSkillStartFailureExitCode(error),
            output = localSkillStartFailureMessage(command, workingDirectory, error)
        )
    }
    val descendantTracker = ProcessDescendantTracker(process)
    val output = LocalSkillOutputBuffer(outputLimitChars.coerceAtLeast(0))
    val outputThread = thread(
        start = true,
        isDaemon = true,
        name = "cotor-local-skill-output-${process.pid()}"
    ) {
        process.inputStream.reader().use { reader ->
            val chunk = CharArray(4096)
            while (true) {
                val read = reader.read(chunk)
                if (read < 0) break
                output.append(chunk, 0, read)
            }
        }
    }

    try {
        val finished = process.waitFor(timeoutSeconds, TimeUnit.SECONDS)
        if (!finished) {
            destroyProcessTree(process)
            val observedDescendantPids = descendantTracker.stopAndSnapshot()
            cleanupSurvivingDescendants(process, observedDescendantPids = observedDescendantPids)
            outputThread.join(LOCAL_SKILL_OUTPUT_THREAD_JOIN_MILLIS)
            error(timeoutMessage)
        }
        val observedDescendantPids = descendantTracker.stopAndSnapshot()
        cleanupSurvivingDescendants(process, observedDescendantPids = observedDescendantPids)
        outputThread.join(LOCAL_SKILL_OUTPUT_THREAD_JOIN_MILLIS)
        return LocalSkillProcessResult(
            exitCode = process.exitValue(),
            output = output.snapshot()
        )
    } finally {
        descendantTracker.stopAndSnapshot()
        process.takeIf { it.isAlive }?.let(::destroyProcessTree)
    }
}

private fun resolveLocalSkillCommand(
    command: List<String>,
    environment: Map<String, String>
): List<String> {
    val executable = resolveExecutablePath(command.first(), environment = environment)?.toString() ?: command.first()
    return listOf(executable) + command.drop(1)
}

internal fun localCommandAvailable(command: String): Boolean {
    val executable = command.trim()
    if (executable.isBlank()) return false
    return runCatching {
        runLocalSkillProcess(
            command = listOf(executable, "--version"),
            workingDirectory = Path.of("").toAbsolutePath().normalize(),
            timeoutSeconds = 5,
            timeoutMessage = "$executable --version timed out after 5s.",
            outputLimitChars = 4_096
        ).exitCode == 0
    }.getOrDefault(false)
}

private val localSkillRuntimeMutationMutexes = ConcurrentHashMap<Path, Mutex>()

internal suspend fun <T> withLocalSkillRuntimeMutationLock(runtimeDir: Path, block: suspend () -> T): T {
    val lockKey = runtimeDir.toAbsolutePath().normalize()
    val mutex = localSkillRuntimeMutationMutexes.computeIfAbsent(lockKey) { Mutex() }
    return mutex.withLock { block() }
}

private fun localSkillStartFailureExitCode(error: IOException): Int {
    val message = error.message.orEmpty().lowercase()
    return if ("permission denied" in message) 126 else 127
}

private fun localSkillStartFailureMessage(command: List<String>, workingDirectory: Path, error: IOException): String {
    val executable = command.firstOrNull().orEmpty()
    val detail = error.message?.takeIf { it.isNotBlank() } ?: error::class.simpleName.orEmpty()
    return "Failed to start local skill process '$executable' in ${workingDirectory.toAbsolutePath().normalize()}: $detail"
}

private class LocalSkillOutputBuffer(private val maxChars: Int) {
    private val buffer = StringBuilder()
    private var truncatedChars: Long = 0

    @Synchronized
    fun append(chars: CharArray, offset: Int, length: Int) {
        if (maxChars == 0) {
            truncatedChars += length.toLong()
            return
        }
        buffer.append(chars, offset, length)
        val overflow = buffer.length - maxChars
        if (overflow > 0) {
            buffer.delete(0, overflow)
            truncatedChars += overflow.toLong()
        }
    }

    @Synchronized
    fun snapshot(): String {
        if (truncatedChars == 0L) {
            return buffer.toString()
        }
        return "[cotor truncated $truncatedChars chars from local skill output]\n$buffer"
    }
}

private const val DEFAULT_LOCAL_SKILL_OUTPUT_LIMIT_CHARS = 1_000_000
private const val LOCAL_SKILL_OUTPUT_THREAD_JOIN_MILLIS = 500L
