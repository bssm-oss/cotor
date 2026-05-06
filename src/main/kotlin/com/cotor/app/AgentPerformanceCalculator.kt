package com.cotor.app

import kotlin.math.roundToInt
import kotlin.math.roundToLong

internal object AgentPerformanceCalculator {
    private const val RECENT_DELIVERY_WINDOW_MS = 14L * 24L * 60L * 60L * 1_000L

    fun compute(
        state: DesktopAppState,
        companyId: String?,
        orgProfiles: List<OrgAgentProfile>,
        scopedIssues: List<CompanyIssue>,
        scopedTasks: List<AgentTask>,
        scopedReviewQueue: List<ReviewQueueItem>
    ): List<AgentPerformanceSnapshot> {
        val subjects = subjects(state, orgProfiles, companyId)
        if (subjects.isEmpty()) return emptyList()

        val scopedIssueIds = scopedIssues.map { it.id }.toSet()
        val scopedTasksById = scopedTasks.associateBy { it.id }
        val allTasksById = state.tasks.associateBy { it.id }
        val issuesById = scopedIssues.associateBy { it.id }
        val subjectsById = subjects.associateBy { it.id }
        val issuesByAgent = scopedIssues.groupBy { it.assigneeProfileId.orEmpty() }
        val runsByAgent = subjects.associate { it.id to mutableListOf<AgentRun>() }.toMutableMap()
        val runAgentIds = mutableMapOf<String, String>()

        state.runs.forEach { run ->
            val task = scopedTasksById[run.taskId] ?: allTasksById[run.taskId]
            if (!belongsToScope(run, task, state, companyId, scopedIssueIds)) return@forEach

            val issue = task?.issueId?.let { issuesById[it] }
            val subject = issue?.assigneeProfileId?.let { subjectsById[it] }
                ?: run.agentId.takeIf { it.isNotBlank() }?.let { subjectsById[it] }
                ?: matchRun(run, subjects)

            if (subject != null) {
                runsByAgent.getOrPut(subject.id) { mutableListOf() } += run
                runAgentIds[run.id] = subject.id
            }
        }

        val runsById = state.runs.associateBy { it.id }
        val reviewsByAgent = subjects.associate { it.id to mutableListOf<ReviewQueueItem>() }.toMutableMap()
        scopedReviewQueue.forEach { item ->
            val issue = issuesById[item.issueId]
            val subject = issue?.assigneeProfileId?.let { subjectsById[it] }
                ?: runAgentIds[item.runId]?.let { subjectsById[it] }
                ?: runsById[item.runId]?.let { matchRun(it, subjects) }

            if (subject != null) {
                reviewsByAgent.getOrPut(subject.id) { mutableListOf() } += item
            }
        }

        val now = System.currentTimeMillis()
        return subjects.map { subject ->
            val assignedIssues = issuesByAgent[subject.id].orEmpty()
            val attributedRuns = runsByAgent[subject.id].orEmpty()
            val terminalRuns = attributedRuns.filter { it.status in terminalRunStatuses }
            val attributedReviews = reviewsByAgent[subject.id].orEmpty()
            val qaReviewedItems = attributedReviews.filter { !it.qaVerdict.isNullOrBlank() }

            val runSuccessRate = terminalRuns.takeIf { it.isNotEmpty() }?.let { runs ->
                runs.count { it.status == AgentRunStatus.COMPLETED }.toDouble() / runs.size.toDouble()
            }
            val qaPassRate = qaReviewedItems.takeIf { it.isNotEmpty() }?.let { reviews ->
                reviews.count { it.qaVerdict.equals("PASS", ignoreCase = true) }.toDouble() / reviews.size.toDouble()
            }
            val recentDeliveryRate = recentDeliveryRate(assignedIssues, now)
            val score = score(runSuccessRate, qaPassRate, recentDeliveryRate)

            AgentPerformanceSnapshot(
                agentId = subject.id,
                agentName = subject.agentName,
                roleName = subject.roleName,
                agentCli = subject.agentCli,
                model = subject.model,
                score = score,
                completedIssues = assignedIssues.count { it.status == IssueStatus.DONE },
                activeIssues = assignedIssues.count { it.status in activeIssueStatuses },
                blockedIssues = assignedIssues.count { it.status == IssueStatus.BLOCKED },
                runSuccessRate = runSuccessRate,
                qaPassRate = qaPassRate,
                reviewRejectionCount = attributedReviews.count { it.isRejection() },
                retryCount = terminalRuns.groupBy { run ->
                    scopedTasksById[run.taskId]?.issueId ?: allTasksById[run.taskId]?.issueId ?: run.taskId
                }.values.sumOf { attempts -> (attempts.size - 1).coerceAtLeast(0) },
                averageDurationMs = terminalRuns.mapNotNull { it.durationMs }
                    .takeIf { it.isNotEmpty() }
                    ?.let { durations -> durations.average().roundToLong() },
                estimatedCostCents = attributedRuns.mapNotNull { it.estimatedCostCents }
                    .takeIf { it.isNotEmpty() }
                    ?.sum(),
                lastActivityAt = listOfNotNull(
                    assignedIssues.maxOfOrNull { it.updatedAt },
                    attributedRuns.maxOfOrNull { it.updatedAt },
                    attributedReviews.maxOfOrNull { it.updatedAt }
                ).maxOrNull(),
                dataSufficiency = if (score == null) {
                    AgentPerformanceDataSufficiency.INSUFFICIENT_DATA
                } else {
                    AgentPerformanceDataSufficiency.SUFFICIENT
                }
            )
        }.sortedWith(
            compareByDescending<AgentPerformanceSnapshot> { it.score ?: -1 }
                .thenBy { it.roleName.lowercase() }
        )
    }

    private fun subjects(
        state: DesktopAppState,
        orgProfiles: List<OrgAgentProfile>,
        companyId: String?
    ): List<AgentPerformanceSubject> {
        val definitions = state.companyAgentDefinitions
            .filter { it.enabled && (companyId == null || it.companyId == companyId) }
            .sortedWith(
                compareBy<CompanyAgentDefinition> { it.companyId }
                    .thenBy { it.displayOrder }
                    .thenBy { it.title.lowercase() }
            )
        val profiles = orgProfiles.filter { it.enabled && (companyId == null || it.companyId == companyId) }
        val profilesById = profiles.associateBy { it.id }
        val definedSubjects = definitions.map { definition ->
            val profile = profilesById[definition.id]
            AgentPerformanceSubject(
                id = definition.id,
                companyId = definition.companyId,
                agentName = definition.title,
                roleName = profile?.roleName ?: definition.title,
                agentCli = definition.agentCli,
                model = definition.model,
                displayOrder = definition.displayOrder
            )
        }
        val definedIds = definitions.map { it.id }.toSet()
        val profileSubjects = profiles
            .filter { it.id !in definedIds }
            .mapIndexed { index, profile ->
                AgentPerformanceSubject(
                    id = profile.id,
                    companyId = profile.companyId,
                    agentName = profile.executionAgentName.ifBlank { profile.roleName },
                    roleName = profile.roleName,
                    agentCli = profile.executionAgentName,
                    model = null,
                    displayOrder = definitions.size + index
                )
            }
        return (definedSubjects + profileSubjects)
            .filter { it.companyId.isNotBlank() }
            .distinctBy { it.id }
    }

    private fun belongsToScope(
        run: AgentRun,
        task: AgentTask?,
        state: DesktopAppState,
        companyId: String?,
        scopedIssueIds: Set<String>
    ): Boolean {
        if (companyId == null) return true
        if (task?.issueId != null) return task.issueId in scopedIssueIds

        val company = state.companies.firstOrNull { it.id == companyId }
        if (company != null && run.repositoryId.isNotBlank() && run.repositoryId != company.repositoryId) {
            return false
        }

        return task == null || state.workspaces.firstOrNull { it.id == task.workspaceId }?.repositoryId == company?.repositoryId
    }

    private fun matchRun(run: AgentRun, subjects: List<AgentPerformanceSubject>): AgentPerformanceSubject? {
        val runAgentName = normalizedKey(run.agentName)
        if (runAgentName.isBlank()) return null
        val candidates = subjects.filter { subject ->
            runAgentName == normalizedKey(subject.agentName) ||
                runAgentName == normalizedKey(subject.roleName) ||
                runAgentName == normalizedKey(subject.agentCli)
        }
        return candidates.singleOrNull()
    }

    private fun recentDeliveryRate(issues: List<CompanyIssue>, now: Long): Double? {
        if (issues.isEmpty()) return null
        val windowStart = now - RECENT_DELIVERY_WINDOW_MS
        val recentIssues = issues.filter { it.updatedAt >= windowStart || it.createdAt >= windowStart }
        val basis = recentIssues.ifEmpty { issues }
        return basis.count { it.status == IssueStatus.DONE }.toDouble() / basis.size.toDouble()
    }

    private fun score(
        runSuccessRate: Double?,
        qaPassRate: Double?,
        recentDeliveryRate: Double?
    ): Int? {
        if (runSuccessRate == null || qaPassRate == null || recentDeliveryRate == null) return null
        return ((runSuccessRate * 45.0) + (qaPassRate * 35.0) + (recentDeliveryRate * 20.0))
            .roundToInt()
            .coerceIn(0, 100)
    }

    private fun normalizedKey(value: String): String =
        value.trim().lowercase().replace(Regex("[^a-z0-9가-힣]+"), "")

    private fun ReviewQueueItem.isRejection(): Boolean =
        status == ReviewQueueStatus.CHANGES_REQUESTED ||
            qaVerdict.equals("CHANGES_REQUESTED", ignoreCase = true) ||
            ceoVerdict.equals("CHANGES_REQUESTED", ignoreCase = true)

    private val terminalRunStatuses = setOf(
        AgentRunStatus.COMPLETED,
        AgentRunStatus.FAILED
    )

    private val activeIssueStatuses = setOf(
        IssueStatus.PLANNED,
        IssueStatus.DELEGATED,
        IssueStatus.IN_PROGRESS,
        IssueStatus.IN_REVIEW,
        IssueStatus.READY_FOR_CEO,
        IssueStatus.WAITING_FOR_APPROVAL
    )

    private data class AgentPerformanceSubject(
        val id: String,
        val companyId: String,
        val agentName: String,
        val roleName: String,
        val agentCli: String,
        val model: String?,
        val displayOrder: Int
    )
}
