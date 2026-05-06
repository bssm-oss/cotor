package com.cotor.app

internal object AgentPerformanceCalculator {
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

        val issueIds = scopedIssues.map { it.id }.toSet()
        val issuesById = scopedIssues.associateBy { it.id }
        val tasksById = scopedTasks.associateBy { it.id }
        val taskIds = tasksById.keys
        val subjectsById = subjects.associateBy { it.id }
        val issuesByAgent = scopedIssues.groupBy { it.assigneeProfileId.orEmpty() }
        val runsByAgent = subjects.associate { it.id to mutableListOf<AgentRun>() }.toMutableMap()
        val runAgentIds = mutableMapOf<String, String>()

        state.runs.forEach { run ->
            val task = tasksById[run.taskId] ?: state.tasks.firstOrNull { it.id == run.taskId }
            if (companyId != null && task?.issueId != null && task.issueId !in issueIds) return@forEach
            if (companyId != null && task == null && run.taskId !in taskIds && run.agentId.isBlank()) return@forEach
            val issue = task?.issueId?.let { issuesById[it] }
            val subject = issue?.assigneeProfileId?.let { subjectsById[it] }
                ?: run.agentId.takeIf { it.isNotBlank() }?.let { subjectsById[it] }
                ?: matchRun(run, subjects)
            if (subject != null) {
                runsByAgent.getOrPut(subject.id) { mutableListOf() } += run
                runAgentIds[run.id] = subject.id
            }
        }

        val reviewsByAgent = subjects.associate { it.id to mutableListOf<ReviewQueueItem>() }.toMutableMap()
        val runsById = state.runs.associateBy { it.id }
        scopedReviewQueue.forEach { item ->
            val issue = issuesById[item.issueId]
            val subject = issue?.assigneeProfileId?.let { subjectsById[it] }
                ?: runAgentIds[item.runId]?.let { subjectsById[it] }
                ?: runsById[item.runId]?.let { matchRun(it, subjects) }
            if (subject != null) {
                reviewsByAgent.getOrPut(subject.id) { mutableListOf() } += item
            }
        }

        return subjects.map { subject ->
            val assignedIssues = issuesByAgent[subject.id].orEmpty()
            val attributedRuns = runsByAgent[subject.id].orEmpty()
            val terminalRuns = attributedRuns.filter { it.status == AgentRunStatus.COMPLETED || it.status == AgentRunStatus.FAILED }
            val attributedReviews = reviewsByAgent[subject.id].orEmpty()
            val qaReviewedItems = attributedReviews.filter { !it.qaVerdict.isNullOrBlank() }
            val runSuccessRate = terminalRuns.takeIf { it.isNotEmpty() }
                ?.let { runs -> runs.count { it.status == AgentRunStatus.COMPLETED }.toDouble() / runs.size.toDouble() }
            val qaPassRate = qaReviewedItems.takeIf { it.isNotEmpty() }
                ?.let { reviews -> reviews.count { it.qaVerdict.equals("PASS", ignoreCase = true) }.toDouble() / reviews.size.toDouble() }
            val sufficient = runSuccessRate != null || assignedIssues.size >= 3 || attributedRuns.size >= 3
            val score = if (sufficient) {
                val runScore = ((runSuccessRate ?: 0.0) * 70.0).toInt()
                val qaScore = ((qaPassRate ?: 1.0) * 20.0).toInt()
                (runScore + qaScore + assignedIssues.count { it.status == IssueStatus.DONE } * 2).coerceIn(0, 100)
            } else {
                null
            }
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
                retryCount = terminalRuns.groupBy { run -> tasksById[run.taskId]?.issueId ?: run.taskId }
                    .values
                    .sumOf { attempts -> (attempts.size - 1).coerceAtLeast(0) },
                averageDurationMs = terminalRuns.mapNotNull { it.durationMs }.takeIf { it.isNotEmpty() }?.let { it.average().toLong() },
                estimatedCostCents = attributedRuns.mapNotNull { it.estimatedCostCents }.takeIf { it.isNotEmpty() }?.sum(),
                lastActivityAt = listOfNotNull(
                    assignedIssues.maxOfOrNull { it.updatedAt },
                    attributedRuns.maxOfOrNull { it.updatedAt },
                    attributedReviews.maxOfOrNull { it.updatedAt }
                ).maxOrNull(),
                dataSufficiency = if (sufficient) {
                    AgentPerformanceDataSufficiency.SUFFICIENT
                } else {
                    AgentPerformanceDataSufficiency.INSUFFICIENT_DATA
                }
            )
        }.sortedWith(compareByDescending<AgentPerformanceSnapshot> { it.score ?: -1 }.thenBy { it.roleName.lowercase() })
    }

    private fun subjects(
        state: DesktopAppState,
        orgProfiles: List<OrgAgentProfile>,
        companyId: String?
    ): List<AgentPerformanceSubject> {
        val definitions = state.companyAgentDefinitions
            .filter { it.enabled && (companyId == null || it.companyId == companyId) }
            .sortedWith(compareBy<CompanyAgentDefinition> { it.displayOrder }.thenBy { it.title.lowercase() })
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
                    agentName = profile.roleName,
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

    private fun normalizedKey(value: String): String =
        value.trim().lowercase().replace(Regex("[^a-z0-9가-힣]+"), "")

    private fun ReviewQueueItem.isRejection(): Boolean =
        status == ReviewQueueStatus.CHANGES_REQUESTED ||
            qaVerdict.equals("CHANGES_REQUESTED", ignoreCase = true) ||
            ceoVerdict.equals("CHANGES_REQUESTED", ignoreCase = true)

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
