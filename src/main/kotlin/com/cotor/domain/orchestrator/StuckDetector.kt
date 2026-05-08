package com.cotor.domain.orchestrator

import com.cotor.model.AgentResult

enum class StuckSignal {
    SAME_ERROR,
    REVISION_LOOP,
    SAME_OUTPUT
}

class StuckDetector(
    private val sameErrorRepeat: Int = 2,
    private val revisionLoop: Int = 4,
    private val sameOutputRepeat: Int = 3
) {
    private val errorFingerprints = mutableListOf<String>()
    private val outputFingerprints = mutableListOf<String>()
    private var revisions = 0

    fun record(result: AgentResult): StuckSignal? {
        revisions += 1

        result.error?.fingerprint()?.takeIf { it.isNotBlank() }?.let { error ->
            errorFingerprints += error
            if (errorFingerprints.takeLast(sameErrorRepeat).size == sameErrorRepeat &&
                errorFingerprints.takeLast(sameErrorRepeat).distinct().size == 1
            ) {
                return StuckSignal.SAME_ERROR
            }
        }

        result.output?.fingerprint()?.takeIf { it.isNotBlank() }?.let { output ->
            outputFingerprints += output
            if (outputFingerprints.takeLast(sameOutputRepeat).size == sameOutputRepeat &&
                outputFingerprints.takeLast(sameOutputRepeat).distinct().size == 1
            ) {
                return StuckSignal.SAME_OUTPUT
            }
        }

        return if (revisions >= revisionLoop) StuckSignal.REVISION_LOOP else null
    }

    private fun String.fingerprint(): String =
        lowercase()
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .take(12)
            .joinToString("\n")
}
