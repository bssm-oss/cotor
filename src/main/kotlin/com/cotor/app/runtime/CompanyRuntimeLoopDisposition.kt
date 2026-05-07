package com.cotor.app.runtime

internal data class CompanyRuntimeLoopFailureDisposition(
    val terminal: Boolean,
    val lastAction: String,
    val severity: String
)

internal object CompanyRuntimeLoopDisposition {
    fun failure(cause: Throwable, consecutiveFailures: Int, maxConsecutiveFailures: Int): CompanyRuntimeLoopFailureDisposition {
        val terminal = cause is Error || consecutiveFailures >= maxConsecutiveFailures
        return CompanyRuntimeLoopFailureDisposition(
            terminal = terminal,
            lastAction = if (terminal) "runtime-error" else "runtime-tick-retry",
            severity = if (terminal) "error" else "warning"
        )
    }
}
