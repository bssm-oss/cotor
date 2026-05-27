package com.cotor.presentation.cli

import com.cotor.data.process.destroyProcessTree
import java.io.IOException
import java.util.concurrent.TimeUnit

internal fun runDiscardingOutputProbe(
    command: List<String>,
    timeoutSeconds: Long
): Boolean {
    if (command.isEmpty()) {
        return false
    }
    val process = try {
        ProcessBuilder(command)
            .redirectOutput(ProcessBuilder.Redirect.DISCARD)
            .redirectError(ProcessBuilder.Redirect.DISCARD)
            .start()
    } catch (_: IOException) {
        return false
    } catch (_: SecurityException) {
        return false
    }

    return try {
        if (!process.waitFor(timeoutSeconds.coerceAtLeast(1), TimeUnit.SECONDS)) {
            destroyProcessTree(process)
            false
        } else {
            process.exitValue() == 0
        }
    } catch (_: InterruptedException) {
        Thread.currentThread().interrupt()
        destroyProcessTree(process)
        false
    } finally {
        runCatching { process.inputStream.close() }
        runCatching { process.errorStream.close() }
        runCatching { process.outputStream.close() }
    }
}
