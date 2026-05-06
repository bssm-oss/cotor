package com.cotor.app

import java.nio.charset.StandardCharsets
import java.nio.file.Path
import java.util.UUID
import kotlin.io.path.exists

data class AutonomousDiscoveryScanResult(
    val signals: List<CompanyProblemSignal>,
    val changedCount: Int,
    val actionableSignal: CompanyProblemSignal?
)

class AutonomousDiscoveryService(
    private val signalCooldownMs: Long = 6L * 60L * 60L * 1000L,
    private val staleBlockedIssueMs: Long = 15L * 60L * 1000L,
    private val staleFollowUpGoalMs: Long = 24L * 60L * 60L * 1000L
) {
    fun scan(state: DesktopAppState, companyId: String, now: Long = System.currentTimeMillis()): AutonomousDiscoveryScanResult {
        val company = state.companies.firstOrNull { it.id == companyId }
            ?: return AutonomousDiscoveryScanResult(state.problemSignals, changedCount = 0, actionableSignal = null)
        val discovered = discoverSignals(state, company, now)
        val merged = mergeSignals(state.problemSignals, discovered, now)
        val actionable = selectActionableSignal(merged, companyId, state.goals, now)
        val changedCount = merged.count { signal ->
            val previous = state.problemSignals.firstOrNull { it.id == signal.id }
            previous == null || previous.updatedAt != signal.updatedAt || previous.status != signal.status
        }
        return AutonomousDiscoveryScanResult(merged, changedCount, actionable)
    }

    fun markTriaged(
        signals: List<CompanyProblemSignal>,
        signalId: String,
        triageGoalId: String,
        now: Long = System.currentTimeMillis()
    ): List<CompanyProblemSignal> =
        signals.map { signal ->
            if (signal.id == signalId) {
                signal.copy(
                    status = CompanyProblemSignalStatus.TRIAGED,
                    triageGoalId = triageGoalId,
                    cooldownUntil = now + signalCooldownMs,
                    updatedAt = now
                )
            } else {
                signal
            }
        }

    private fun discoverSignals(state: DesktopAppState, company: Company, now: Long): List<CompanyProblemSignal> {
        val companyIssues = state.issues.filter { it.companyId == company.id }
        val tasksByIssue = state.tasks.filter { it.issueId != null }.groupBy { it.issueId!! }
        val runsByTask = state.runs.groupBy { it.taskId }
        val reviewByIssue = state.reviewQueue.filter { it.companyId == company.id }.groupBy { it.issueId }
        val signals = mutableListOf<CompanyProblemSignal>()

        companyIssues
            .filter { it.status == IssueStatus.BLOCKED && !it.kind.equals("planning", ignoreCase = true) }
            .filter { now - it.updatedAt >= staleBlockedIssueMs }
            .forEach { issue ->
                signals += signal(
                    company = company,
                    kind = "stale-blocked-issue",
                    title = "Blocked issue needs autonomous triage",
                    detail = "Issue \"${issue.title}\" has stayed BLOCKED without fresh progress.",
                    severity = "high",
                    confidence = 0.85,
                    source = "runtime-watchdog",
                    dedupeParts = listOf(company.id, "blocked", issue.id),
                    issueId = issue.id,
                    goalId = issue.goalId,
                    now = now
                )
            }

        companyIssues.forEach { issue ->
            val issueTasks = tasksByIssue[issue.id].orEmpty()
            val failedTasks = issueTasks.filter { it.status == DesktopTaskStatus.FAILED }
            if (failedTasks.size >= 2) {
                val latestRun = failedTasks
                    .flatMap { task -> runsByTask[task.id].orEmpty() }
                    .maxByOrNull { it.updatedAt }
                signals += signal(
                    company = company,
                    kind = "repeated-execution-failure",
                    title = "Repeated execution failure",
                    detail = "Issue \"${issue.title}\" has ${failedTasks.size} failed task attempts. Latest error: ${latestRun?.error?.take(220) ?: "none"}",
                    severity = "high",
                    confidence = 0.9,
                    source = "runtime-watchdog",
                    dedupeParts = listOf(company.id, "failed-task", issue.id),
                    issueId = issue.id,
                    goalId = issue.goalId,
                    runId = latestRun?.id,
                    now = now
                )
            }
        }

        state.reviewQueue
            .filter { it.companyId == company.id && it.status in setOf(ReviewQueueStatus.FAILED_CHECKS, ReviewQueueStatus.CHANGES_REQUESTED) }
            .forEach { item ->
                val issue = companyIssues.firstOrNull { it.id == item.issueId }
                signals += signal(
                    company = company,
                    kind = "review-failure",
                    title = "Review failure needs remediation",
                    detail = "Review queue item for \"${issue?.title ?: item.issueId}\" is ${item.status}. ${item.checksSummary ?: item.qaFeedback ?: ""}".trim(),
                    severity = if (item.status == ReviewQueueStatus.FAILED_CHECKS) "high" else "medium",
                    confidence = 0.9,
                    source = "review-queue",
                    dedupeParts = listOf(company.id, "review", item.id),
                    issueId = item.issueId,
                    goalId = issue?.goalId,
                    reviewQueueItemId = item.id,
                    runId = item.runId,
                    now = now
                )
            }

        companyIssues
            .filter { it.status == IssueStatus.DONE }
            .filter { issue ->
                issue.acceptanceCriteria.isNotEmpty() &&
                    !issue.verificationStatus.equals("PASS", ignoreCase = true)
            }
            .forEach { issue ->
                signals += signal(
                    company = company,
                    kind = "verification-gap",
                    title = "Completed issue lacks strong verification",
                    detail = "Issue \"${issue.title}\" is DONE but verification did not record PASS.",
                    severity = "medium",
                    confidence = 0.7,
                    source = "verification-runtime",
                    dedupeParts = listOf(company.id, "verification", issue.id),
                    issueId = issue.id,
                    goalId = issue.goalId,
                    now = now
                )
            }

        state.companyRuntimes
            .filter { it.companyId == company.id }
            .filter { it.status == CompanyRuntimeStatus.ERROR || it.consecutiveFailures >= 3 || !it.lastError.isNullOrBlank() }
            .forEach { runtime ->
                signals += signal(
                    company = company,
                    kind = "runtime-health",
                    title = "Company runtime health needs attention",
                    detail = runtime.lastError ?: "Runtime has ${runtime.consecutiveFailures} consecutive failures.",
                    severity = "high",
                    confidence = 0.8,
                    source = "runtime-watchdog",
                    dedupeParts = listOf(company.id, "runtime", runtime.companyId ?: company.id),
                    now = now
                )
            }

        state.goals
            .filter {
                it.companyId == company.id &&
                    it.status == GoalStatus.ACTIVE &&
                    it.operatingPolicy.orEmpty().startsWith("auto-follow-up:") &&
                    now - it.updatedAt >= staleFollowUpGoalMs
            }
            .forEach { goal ->
                signals += signal(
                    company = company,
                    kind = "stale-follow-up",
                    title = "Follow-up goal is stale",
                    detail = "Follow-up goal \"${goal.title}\" has not settled within the expected operating window.",
                    severity = "medium",
                    confidence = 0.75,
                    source = "runtime-watchdog",
                    dedupeParts = listOf(company.id, "stale-follow-up", goal.id),
                    goalId = goal.id,
                    now = now
                )
            }

        val graphReport = Path.of(company.rootPath).resolve("graphify-out").resolve("GRAPH_REPORT.md")
        if (!graphReport.exists()) {
            signals += signal(
                company = company,
                kind = "graphify-map-missing",
                title = "Repository knowledge graph is missing",
                detail = "graphify-out/GRAPH_REPORT.md is not present for the company root, so architecture discovery is weaker.",
                severity = "low",
                confidence = 0.65,
                source = "graphify",
                dedupeParts = listOf(company.id, "graphify-missing"),
                now = now
            )
        }

        return signals.distinctBy { it.dedupeKey }
    }

    private fun mergeSignals(
        existing: List<CompanyProblemSignal>,
        discovered: List<CompanyProblemSignal>,
        now: Long
    ): List<CompanyProblemSignal> {
        val discoveredByKey = discovered.associateBy { it.dedupeKey }
        val mergedExisting = existing.map { signal ->
            val fresh = discoveredByKey[signal.dedupeKey] ?: return@map signal
            signal.copy(
                title = fresh.title,
                detail = fresh.detail,
                severity = fresh.severity,
                confidence = maxOf(signal.confidence, fresh.confidence),
                source = fresh.source,
                goalId = fresh.goalId ?: signal.goalId,
                issueId = fresh.issueId ?: signal.issueId,
                reviewQueueItemId = fresh.reviewQueueItemId ?: signal.reviewQueueItemId,
                runId = fresh.runId ?: signal.runId,
                lastSeenAt = now,
                updatedAt = now,
                status = if (signal.status == CompanyProblemSignalStatus.RESOLVED) CompanyProblemSignalStatus.OPEN else signal.status
            )
        }
        val existingKeys = existing.mapTo(linkedSetOf()) { it.dedupeKey }
        val additions = discovered.filter { it.dedupeKey !in existingKeys }
        return (mergedExisting + additions)
            .sortedWith(compareByDescending<CompanyProblemSignal> { severityRank(it.severity) }.thenByDescending { it.updatedAt })
            .take(200)
    }

    private fun selectActionableSignal(
        signals: List<CompanyProblemSignal>,
        companyId: String,
        goals: List<CompanyGoal>,
        now: Long
    ): CompanyProblemSignal? {
        val activeDiscoveryGoalPolicies = goals
            .filter { it.companyId == companyId && it.status == GoalStatus.ACTIVE }
            .mapNotNull { it.operatingPolicy }
            .filter { it.startsWith("auto-discovery:") }
            .toSet()
        return signals
            .filter { it.companyId == companyId && it.status == CompanyProblemSignalStatus.OPEN }
            .filter { it.confidence >= 0.6 }
            .filter { severityRank(it.severity) >= 2 }
            .filter { it.cooldownUntil == null || it.cooldownUntil <= now }
            .filter { "auto-discovery:${it.id}" !in activeDiscoveryGoalPolicies }
            .maxWithOrNull(compareBy<CompanyProblemSignal> { severityRank(it.severity) }.thenBy { it.firstSeenAt })
    }

    private fun signal(
        company: Company,
        kind: String,
        title: String,
        detail: String,
        severity: String,
        confidence: Double,
        source: String,
        dedupeParts: List<String>,
        goalId: String? = null,
        issueId: String? = null,
        reviewQueueItemId: String? = null,
        runId: String? = null,
        now: Long
    ): CompanyProblemSignal {
        val dedupeKey = dedupeParts.joinToString(":")
        return CompanyProblemSignal(
            id = UUID.nameUUIDFromBytes(dedupeKey.toByteArray(StandardCharsets.UTF_8)).toString(),
            companyId = company.id,
            projectContextId = null,
            kind = kind,
            title = title,
            detail = detail,
            severity = severity,
            confidence = confidence.coerceIn(0.0, 1.0),
            source = source,
            dedupeKey = dedupeKey,
            goalId = goalId,
            issueId = issueId,
            reviewQueueItemId = reviewQueueItemId,
            runId = runId,
            firstSeenAt = now,
            lastSeenAt = now,
            createdAt = now,
            updatedAt = now
        )
    }

    private fun severityRank(severity: String): Int = when (severity.lowercase()) {
        "critical" -> 4
        "high" -> 3
        "medium" -> 2
        "low" -> 1
        else -> 0
    }
}
