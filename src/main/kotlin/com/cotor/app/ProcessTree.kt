package com.cotor.app

import java.util.concurrent.TimeUnit

internal fun destroyProcessTree(process: Process, graceMillis: Long = 500) {
    val descendants = process.toHandle().descendants().toList().asReversed()
    descendants.forEach { handle ->
        runCatching { handle.destroy() }
    }
    runCatching { process.destroy() }
    val exited = runCatching { process.waitFor(graceMillis, TimeUnit.MILLISECONDS) }.getOrDefault(false)
    if (!exited) {
        descendants.forEach { handle ->
            runCatching {
                if (handle.isAlive) {
                    handle.destroyForcibly()
                }
            }
        }
        runCatching {
            if (process.isAlive) {
                process.destroyForcibly()
            }
        }
    }
}
