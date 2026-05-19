package com.cotor.app

import com.cotor.verification.VerificationBundle
import com.cotor.verification.VerificationBundleService
import com.cotor.verification.VerificationOutcomeStatus

data class CompanyVerificationDecision(
    val passed: Boolean,
    val status: String,
    val summary: String,
    val bundle: VerificationBundle
)

class CompanyVerifierService(
    private val verificationBundleService: VerificationBundleService = VerificationBundleService()
) {
    fun verifyIssueCompletion(
        state: DesktopAppState,
        issue: CompanyIssue,
        primaryRun: AgentRun?
    ): CompanyVerificationDecision {
        val queueItem = state.reviewQueue
            .filter { it.issueId == issue.id }
            .maxByOrNull { it.updatedAt }
        val ignoreReviewVerdicts = shouldIgnoreReviewVerdictsForCompletion(issue)
        val issueForVerification = issue.copy(
            status = IssueStatus.DONE,
            durableRunId = primaryRun?.id ?: issue.durableRunId,
            qaVerdict = if (ignoreReviewVerdicts) null else issue.qaVerdict,
            qaFeedback = if (ignoreReviewVerdicts) null else issue.qaFeedback,
            ceoVerdict = if (ignoreReviewVerdicts) null else issue.ceoVerdict,
            ceoFeedback = if (ignoreReviewVerdicts) null else issue.ceoFeedback
        )
        val bundle = verificationBundleService.buildForIssue(state, issueForVerification, queueItem)
        val missingExecutionEvidence = requiresExecutionEvidence(issue) &&
            primaryRun?.output.isNullOrBlank() &&
            primaryRun?.publish == null &&
            issue.durableRunId.isNullOrBlank()
        val passed = when {
            missingExecutionEvidence -> false
            bundle.outcome.status in setOf(VerificationOutcomeStatus.FAIL, VerificationOutcomeStatus.BLOCKED) -> false
            else -> true
        }
        val summary = when {
            missingExecutionEvidence ->
                "Verification blocked completion because no execution output, publish metadata, or durable run evidence was recorded."
            else -> bundle.outcome.summary
        }
        return CompanyVerificationDecision(
            passed = passed,
            status = if (passed) "PASS" else "FAIL",
            summary = summary,
            bundle = bundle
        )
    }

    private fun requiresExecutionEvidence(issue: CompanyIssue): Boolean {
        if (issue.kind.equals("planning", ignoreCase = true)) return false
        if (issue.kind.equals("review", ignoreCase = true)) return false
        if (issue.kind.equals("approval", ignoreCase = true)) return false
        if (issue.codeProducing == false || issue.executionIntent == ExecutionIntent.VALIDATION_ONLY) return false
        return issue.acceptanceCriteria.isNotEmpty() || issue.codeProducing == true || issue.kind.equals("implementation", ignoreCase = true)
    }

    private fun shouldIgnoreReviewVerdictsForCompletion(issue: CompanyIssue): Boolean {
        if (!issue.kind.equals("execution", ignoreCase = true)) return false
        return issue.codeProducing == false ||
            issue.executionIntent in setOf(ExecutionIntent.VALIDATION_ONLY, ExecutionIntent.PR_REUSE_HANDOFF)
    }
}
