package com.cotor.data.process

import org.slf4j.Logger
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

internal class ProcessDescendantTracker(
    private val process: Process,
    private val pollMillis: Long = PROCESS_DESCENDANT_POLL_MILLIS
) {
    private val observedPids = ConcurrentHashMap.newKeySet<Long>()
    private val trackerThread: Thread

    init {
        recordDescendants()
        trackerThread = thread(
            start = true,
            isDaemon = true,
            name = "cotor-process-descendants-${process.pid()}"
        ) {
            while (!Thread.currentThread().isInterrupted && process.isAlive) {
                recordDescendants()
                try {
                    Thread.sleep(pollMillis)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
            }
            recordDescendants()
        }
    }

    fun stopAndSnapshot(): Set<Long> {
        trackerThread.interrupt()
        trackerThread.join(PROCESS_DESCENDANT_TRACKER_JOIN_MILLIS)
        recordDescendants()
        return observedPids.toSet()
    }

    private fun recordDescendants() {
        process.toHandle()
            .descendants()
            .forEach { handle -> observedPids += handle.pid() }
    }
}

internal fun destroyProcessTree(
    process: Process,
    graceMillis: Long = PROCESS_TREE_POLITE_JOIN_TIMEOUT_MS,
    logger: Logger? = null
) {
    val descendants = process.toHandle()
        .descendants()
        .toArray()
        .filterIsInstance<ProcessHandle>()
        .asReversed()
    terminateUnixChildren(process.pid(), force = false, logger = logger)
    descendants.forEach { handle ->
        if (handle.isAlive) {
            runCatching { handle.destroy() }
                .onFailure { logger?.debug("Failed to request descendant process ${handle.pid()} termination", it) }
        }
    }
    if (process.isAlive) {
        runCatching { process.destroy() }
            .onFailure { logger?.debug("Failed to request process ${process.pid()} termination", it) }
    }
    waitForProcessHandles(descendants, graceMillis)
    if (process.isAlive) {
        runCatching { process.waitFor(graceMillis, TimeUnit.MILLISECONDS) }
    }
    terminateUnixChildren(process.pid(), force = true, logger = logger)
    descendants.forEach { handle ->
        if (handle.isAlive) {
            runCatching { handle.destroyForcibly() }
                .onFailure { logger?.debug("Failed to destroy descendant process ${handle.pid()}", it) }
        }
    }
    if (process.isAlive) {
        runCatching { process.destroyForcibly() }
            .onFailure { logger?.debug("Failed to destroy process ${process.pid()}", it) }
    }
    waitForProcessHandles(descendants, PROCESS_TREE_JOIN_TIMEOUT_MS)
    runCatching { process.waitFor(PROCESS_TREE_JOIN_TIMEOUT_MS, TimeUnit.MILLISECONDS) }
}

internal fun cleanupSurvivingDescendants(
    process: Process,
    logger: Logger? = null,
    observedDescendantPids: Iterable<Long> = emptyList()
) {
    val descendants = (
        process.toHandle()
            .descendants()
            .toArray()
            .filterIsInstance<ProcessHandle>()
            .asReversed() + observedDescendantPids.mapNotNull { pid ->
            ProcessHandle.of(pid).orElse(null)
        }
        )
        .distinctBy { it.pid() }
        .filter { it.isAlive }
    if (descendants.isEmpty()) {
        return
    }
    descendants.forEach { handle ->
        runCatching { handle.destroyForcibly() }
            .onFailure { logger?.debug("Failed to clean up surviving descendant process ${handle.pid()}", it) }
    }
    waitForProcessHandles(descendants, PROCESS_TREE_JOIN_TIMEOUT_MS)
}

private fun terminateUnixChildren(parentPid: Long, force: Boolean, logger: Logger?) {
    val signal = if (force) "-KILL" else "-TERM"
    val pkill = ProcessBuilder("pkill", signal, "-P", parentPid.toString())
    runCatching {
        val process = pkill.start()
        process.waitFor(PROCESS_TREE_POLITE_JOIN_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        if (process.isAlive) {
            process.destroyForcibly()
        }
    }.onFailure {
        logger?.debug("Failed to request child process termination with pkill for parent pid=$parentPid", it)
    }
}

private fun waitForProcessHandles(handles: List<ProcessHandle>, timeoutMs: Long) {
    handles.forEach { handle ->
        runCatching { handle.onExit().get(timeoutMs, TimeUnit.MILLISECONDS) }
    }
}

private const val PROCESS_TREE_POLITE_JOIN_TIMEOUT_MS = 250L
private const val PROCESS_TREE_JOIN_TIMEOUT_MS = 500L
private const val PROCESS_DESCENDANT_POLL_MILLIS = 25L
private const val PROCESS_DESCENDANT_TRACKER_JOIN_MILLIS = 100L
