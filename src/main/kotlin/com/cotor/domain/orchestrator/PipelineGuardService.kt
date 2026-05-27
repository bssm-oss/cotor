package com.cotor.domain.orchestrator

import com.cotor.model.AgentResult
import com.cotor.model.FailureCategory
import com.cotor.model.PipelineContext
import com.cotor.model.PipelineStage

enum class PipelineGuardSeverity {
    WARNING,
    BLOCKING
}

data class PipelineGuardFinding(
    val code: String,
    val severity: PipelineGuardSeverity,
    val message: String
)

data class PipelineGuardResult(
    val confidenceScore: Int,
    val findings: List<PipelineGuardFinding>
) {
    val blockingFindings: List<PipelineGuardFinding>
        get() = findings.filter { it.severity == PipelineGuardSeverity.BLOCKING }
}

private const val MAX_PIPELINE_GUARD_SCAN_CHARS = 200_000
private const val MAX_SECRET_ASSIGNMENT_WINDOWS_PER_KEYWORD = 2_048
private const val SECRET_ASSIGNMENT_WINDOW_CHARS = 256

private data class GuardTextSample(
    val text: String,
    val truncated: Boolean
)

private val secretAssignmentKeywords = listOf("apiKey", "api_key", "api-key", "secret", "password", "token")
private val hardcodedSecretPattern = Regex("""(?i)(api[_-]?key|secret|password|token)\s*=\s*["'][^"']{8,}["']""")

class PipelineGuardService {
    fun evaluate(
        stage: PipelineStage,
        result: AgentResult,
        context: PipelineContext
    ): PipelineGuardResult {
        val sample = result.guardTextSample()
        val text = sample.text
        val lower = text.lowercase()
        val findings = buildList {
            if (sample.truncated) {
                add(
                    PipelineGuardFinding(
                        code = "GUARD_SCAN_TRUNCATED",
                        severity = PipelineGuardSeverity.WARNING,
                        message = "Agent output was sampled before pipeline guard checks because it exceeded $MAX_PIPELINE_GUARD_SCAN_CHARS characters"
                    )
                )
            }
            detectUncertainty(lower)?.let(::add)
            detectFakeData(lower)?.let(::add)
            detectRiskyPatterns(result)?.let(::add)
            detectMissingVerification(stage, result, lower)?.let(::add)
            detectWorktreeHygiene(result, context)?.let(::add)
        }
        val confidencePenalty = findings.fold(0) { total, finding ->
            total + when (finding.severity) {
                PipelineGuardSeverity.BLOCKING -> 45
                PipelineGuardSeverity.WARNING -> 12
            }
        }
        val confidence = (100 - confidencePenalty).coerceIn(0, 100)
        return PipelineGuardResult(confidence, findings)
    }

    fun apply(
        stage: PipelineStage,
        result: AgentResult,
        context: PipelineContext
    ): AgentResult {
        val guardResult = evaluate(stage, result, context)
        val findingSummary = guardResult.findings.joinToString(" | ") { "${it.severity}:${it.code}:${it.message}" }
        val metadata = result.metadata + mapOf(
            "pipelineGuardStatus" to if (guardResult.blockingFindings.isEmpty()) "PASS" else "BLOCK",
            "pipelineGuardConfidence" to guardResult.confidenceScore.toString(),
            "pipelineGuardFindings" to findingSummary,
            "pipelineGuardBlockingCount" to guardResult.blockingFindings.size.toString()
        )
        if (guardResult.blockingFindings.isEmpty()) {
            return result.copy(metadata = metadata)
        }

        val message = guardResult.blockingFindings.joinToString("; ") { it.message }
        return result.copy(
            isSuccess = false,
            error = listOfNotNull(result.error, "Pipeline guard blocked stage ${stage.id}: $message").joinToString("\n"),
            metadata = metadata + ("failureCategory" to FailureCategory.VALIDATION_FAILED.name)
        )
    }

    private fun detectUncertainty(lower: String): PipelineGuardFinding? {
        val patterns = listOf("not tested", "untested", "maybe", "probably", "workaround", "i think", "i assume")
        val matched = patterns.firstOrNull { lower.contains(it) } ?: return null
        return PipelineGuardFinding(
            code = "UNCERTAINTY",
            severity = PipelineGuardSeverity.WARNING,
            message = "Agent output contains uncertainty marker '$matched'"
        )
    }

    private fun detectFakeData(lower: String): PipelineGuardFinding? {
        val patterns = listOf("faker.", "math.random(", "mock data", "dummy data", "placeholder data")
        val matched = patterns.firstOrNull { lower.contains(it) } ?: return null
        return PipelineGuardFinding(
            code = "FAKE_DATA",
            severity = PipelineGuardSeverity.WARNING,
            message = "Agent output mentions fake or placeholder data marker '$matched'"
        )
    }

    private fun detectRiskyPatterns(result: AgentResult): PipelineGuardFinding? {
        val hasHardcodedSecret = listOfNotNull(result.output, result.error)
            .any { it.hasHardcodedSecretAssignment() }
        if (!hasHardcodedSecret) return null
        return PipelineGuardFinding(
            code = "HARDCODED_SECRET",
            severity = PipelineGuardSeverity.BLOCKING,
            message = "Agent output appears to include a hardcoded secret assignment"
        )
    }

    private fun detectMissingVerification(
        stage: PipelineStage,
        result: AgentResult,
        lower: String
    ): PipelineGuardFinding? {
        if (!result.isSuccess) return null
        if (stage.validation != null) return null
        val verificationMarkers = listOf("test", "gradle", "swift build", "typecheck", "lint", "verified", "passed")
        if (verificationMarkers.any { lower.contains(it) }) return null
        return PipelineGuardFinding(
            code = "MISSING_VERIFICATION",
            severity = PipelineGuardSeverity.WARNING,
            message = "Successful stage did not report test, build, lint, or verification evidence"
        )
    }

    private fun detectWorktreeHygiene(
        result: AgentResult,
        context: PipelineContext
    ): PipelineGuardFinding? {
        val worktree = result.metadata["worktreePath"] ?: context.metadata["worktreePath"]?.toString()
        val repoRoot = result.metadata["repositoryRoot"] ?: context.metadata["repositoryRoot"]?.toString()
        if (worktree.isNullOrBlank() || repoRoot.isNullOrBlank()) return null
        if (worktree == repoRoot) {
            return PipelineGuardFinding(
                code = "SHARED_REPO_WRITE",
                severity = PipelineGuardSeverity.WARNING,
                message = "Stage appears to have run in the shared repository root instead of an isolated worktree"
            )
        }
        return null
    }

    private fun String.hasHardcodedSecretAssignment(): Boolean {
        for (keyword in secretAssignmentKeywords) {
            var startIndex = 0
            var scannedWindows = 0
            while (scannedWindows < MAX_SECRET_ASSIGNMENT_WINDOWS_PER_KEYWORD) {
                val keywordIndex = indexOf(keyword, startIndex = startIndex, ignoreCase = true)
                if (keywordIndex < 0) break

                val windowEnd = (keywordIndex + SECRET_ASSIGNMENT_WINDOW_CHARS).coerceAtMost(length)
                if (hardcodedSecretPattern.containsMatchIn(substring(keywordIndex, windowEnd))) {
                    return true
                }

                scannedWindows++
                startIndex = keywordIndex + keyword.length
            }
        }
        return false
    }

    private fun AgentResult.guardTextSample(): GuardTextSample {
        val parts = listOfNotNull(output, error)
        if (parts.isEmpty()) return GuardTextSample("", truncated = false)

        val perPartBudget = (MAX_PIPELINE_GUARD_SCAN_CHARS / parts.size).coerceAtLeast(1)
        var truncated = false
        val sampled = parts.joinToString("\n") { part ->
            val sample = part.sampleForGuardScan(perPartBudget)
            truncated = truncated || sample.truncated
            sample.text
        }
        return GuardTextSample(sampled, truncated)
    }

    private fun String.sampleForGuardScan(maxChars: Int): GuardTextSample {
        if (length <= maxChars) return GuardTextSample(this, truncated = false)

        val marker = "\n[cotor guard scan omitted middle]\n"
        val bodyBudget = (maxChars - marker.length).coerceAtLeast(0)
        val headChars = bodyBudget / 2
        val tailChars = bodyBudget - headChars
        val sampled = buildString {
            append(take(headChars))
            append(marker)
            append(takeLast(tailChars))
        }
        return GuardTextSample(sampled, truncated = true)
    }
}
