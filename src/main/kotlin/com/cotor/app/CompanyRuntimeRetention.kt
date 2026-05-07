package com.cotor.app

import java.nio.file.Files
import java.nio.file.Path
import java.util.Comparator
import java.util.Locale
import kotlin.io.path.exists
import kotlin.io.path.isDirectory

private const val DEFAULT_TERMINAL_WORKTREE_RETENTION_DAYS = 7
private const val DEFAULT_ORPHAN_WORKTREE_RETENTION_DAYS = 14
private const val MILLIS_PER_DAY = 24L * 60L * 60L * 1_000L

class CompanyRuntimeRetention(
    private val nowProvider: () -> Long = System::currentTimeMillis
) {
    fun preview(
        appHome: Path,
        state: DesktopAppState,
        companyId: String? = null,
        olderThanDays: Int? = null,
        allCompanies: Boolean = companyId == null
    ): RuntimeCleanupPreview {
        val now = nowProvider()
        val terminalRetentionDays = olderThanDays?.coerceAtLeast(0) ?: DEFAULT_TERMINAL_WORKTREE_RETENTION_DAYS
        val orphanRetentionDays = olderThanDays?.coerceAtLeast(0) ?: DEFAULT_ORPHAN_WORKTREE_RETENTION_DAYS
        val scope = RetentionScope.from(state, companyId, allCompanies)
        val worktreeCandidates = worktreeRoots(appHome, state, scope)
            .flatMap { root -> candidateWorktrees(root) }
            .distinctBy { it.toAbsolutePath().normalize().toString() }
            .mapNotNull { path ->
                classifyWorktree(
                    path = path,
                    state = state,
                    scope = scope,
                    now = now,
                    terminalRetentionDays = terminalRetentionDays,
                    orphanRetentionDays = orphanRetentionDays
                )
            }
        val processCandidates = staleProcessCandidates(state, scope, now)
        val candidates = (worktreeCandidates + processCandidates)
            .sortedWith(compareBy<RuntimeCleanupCandidate> { !it.eligible }.thenBy { it.kind }.thenBy { it.path ?: it.processId.toString() })
        return RuntimeCleanupPreview(
            companyId = companyId,
            allCompanies = scope.allCompanies,
            generatedAt = now,
            terminalRetentionDays = terminalRetentionDays,
            orphanRetentionDays = orphanRetentionDays,
            candidates = candidates
        )
    }

    fun deleteWorktree(path: String): String? {
        val root = runCatching { Path.of(path).toAbsolutePath().normalize() }.getOrElse { return it.message }
        if (!root.exists() || !root.isDirectory()) {
            return null
        }
        return runCatching {
            Files.walk(root).use { stream ->
                stream.sorted(Comparator.reverseOrder()).forEach(Files::deleteIfExists)
            }
        }.exceptionOrNull()?.message
    }

    private fun classifyWorktree(
        path: Path,
        state: DesktopAppState,
        scope: RetentionScope,
        now: Long,
        terminalRetentionDays: Int,
        orphanRetentionDays: Int
    ): RuntimeCleanupCandidate? {
        val normalized = path.toAbsolutePath().normalize().toString()
        val refs = referencesForPath(state, normalized, scope)
        if (!scope.includes(refs.companyId)) {
            return null
        }
        val modifiedAt = runCatching { Files.getLastModifiedTime(path).toMillis() }.getOrDefault(now)
        val ageDays = ((now - modifiedAt).coerceAtLeast(0L) / MILLIS_PER_DAY)
        val terminalRun = refs.terminalRuns.maxByOrNull { it.updatedAt }
        val classification: String
        val eligible: Boolean
        val reason: String
        when {
            refs.activeRuns.isNotEmpty() -> {
                classification = "active"
                eligible = false
                reason = "Referenced by ${refs.activeRuns.size} active run(s)."
            }
            refs.openIssues.isNotEmpty() -> {
                classification = "open-issue"
                eligible = false
                reason = "Referenced by ${refs.openIssues.size} open issue(s)."
            }
            refs.reviewItems.isNotEmpty() || refs.prLinked -> {
                classification = "review-linked"
                eligible = false
                reason = "Referenced by review or pull request metadata."
            }
            terminalRun != null -> {
                val runAgeDays = ((now - terminalRun.updatedAt).coerceAtLeast(0L) / MILLIS_PER_DAY)
                val stale = runAgeDays >= terminalRetentionDays
                classification = if (stale) "stale-terminal" else "recent-terminal"
                eligible = stale
                reason = if (stale) {
                    "Terminal run is $runAgeDays day(s) old."
                } else {
                    "Terminal run is only $runAgeDays day(s) old."
                }
                return candidate(
                    kind = "worktree",
                    classification = classification,
                    companyId = refs.companyId,
                    path = normalized,
                    processId = null,
                    ageDays = runAgeDays,
                    eligible = eligible,
                    reason = reason
                )
            }
            else -> {
                val stale = ageDays >= orphanRetentionDays
                classification = "unknown"
                eligible = stale
                reason = if (stale) {
                    "No state reference found and directory is $ageDays day(s) old."
                } else {
                    "No state reference found, but directory is only $ageDays day(s) old."
                }
            }
        }
        return candidate(
            kind = "worktree",
            classification = classification,
            companyId = refs.companyId,
            path = normalized,
            processId = null,
            ageDays = ageDays,
            eligible = eligible,
            reason = reason
        )
    }

    private fun staleProcessCandidates(
        state: DesktopAppState,
        scope: RetentionScope,
        now: Long
    ): List<RuntimeCleanupCandidate> {
        return state.runs
            .filter { it.status !in setOf(AgentRunStatus.RUNNING, AgentRunStatus.QUEUED) }
            .filter { scope.includes(companyIdForRun(state, it)) }
            .mapNotNull { run ->
                val processId = run.processId ?: return@mapNotNull null
                val handle = ProcessHandle.of(processId).orElse(null) ?: return@mapNotNull null
                if (!handle.isAlive) return@mapNotNull null
                val ageDays = ((now - run.updatedAt).coerceAtLeast(0L) / MILLIS_PER_DAY)
                candidate(
                    kind = "process",
                    classification = "stale-terminal",
                    companyId = companyIdForRun(state, run),
                    path = run.worktreePath.takeIf { it.isNotBlank() },
                    processId = processId,
                    ageDays = ageDays,
                    eligible = true,
                    reason = "Terminal run still has a live recorded process."
                )
            }
    }

    private fun worktreeRoots(appHome: Path, state: DesktopAppState, scope: RetentionScope): List<Path> {
        val roots = linkedSetOf<Path>()
        if (scope.allCompanies) {
            roots.add(appHome.resolve("worktrees"))
        }
        val scopedCompanies = state.companies
            .filter { scope.includes(it.id) }
        val scopedRepositoryIds = scopedCompanies.map { it.repositoryId }.toSet()
        scopedCompanies.mapNotNullTo(roots) { safePath(it.rootPath)?.resolve(".cotor")?.resolve("worktrees") }
        state.repositories
            .filter { scope.allCompanies || it.id in scopedRepositoryIds }
            .mapNotNullTo(roots) { safePath(it.localPath)?.resolve(".cotor")?.resolve("worktrees") }
        state.runs
            .filter { scope.includes(companyIdForRun(state, it)) }
            .mapNotNullTo(roots) { repositoryWorktreeRootFor(it.worktreePath) }
        state.issues
            .filter { scope.includes(it.companyId) }
            .mapNotNullTo(roots) { repositoryWorktreeRootFor(it.worktreePath) }
        state.reviewQueue
            .filter { scope.includes(it.companyId) }
            .mapNotNullTo(roots) { repositoryWorktreeRootFor(it.worktreePath) }
        return roots.map { it.toAbsolutePath().normalize() }.distinct()
    }

    private fun candidateWorktrees(root: Path): List<Path> {
        if (!root.exists() || !root.isDirectory()) return emptyList()
        val taskDirs = childDirectories(root)
        return taskDirs.flatMap { taskDir ->
            val agentDirs = childDirectories(taskDir)
            agentDirs.ifEmpty { listOf(taskDir) }
        }
    }

    private fun childDirectories(path: Path): List<Path> =
        runCatching {
            Files.list(path).use { stream ->
                stream.filter { Files.isDirectory(it) }.toList()
            }
        }.getOrDefault(emptyList())

    private fun referencesForPath(state: DesktopAppState, path: String, scope: RetentionScope): WorktreeReferences {
        val activeRuns = state.runs.filter {
            it.worktreePath.normalizedPath() == path &&
                it.status in setOf(AgentRunStatus.RUNNING, AgentRunStatus.QUEUED) &&
                scope.includes(companyIdForRun(state, it))
        }
        val terminalRuns = state.runs.filter {
            it.worktreePath.normalizedPath() == path &&
                it.status !in setOf(AgentRunStatus.RUNNING, AgentRunStatus.QUEUED) &&
                scope.includes(companyIdForRun(state, it))
        }
        val openIssues = state.issues.filter {
            it.worktreePath.normalizedPath() == path &&
                it.status !in setOf(IssueStatus.DONE, IssueStatus.CANCELED) &&
                scope.includes(it.companyId)
        }
        val reviewItems = state.reviewQueue.filter {
            it.worktreePath.normalizedPath() == path &&
                it.status !in setOf(ReviewQueueStatus.MERGED) &&
                scope.includes(it.companyId)
        }
        val prLinked = state.issues.any {
            it.worktreePath.normalizedPath() == path && it.pullRequestNumber != null && scope.includes(it.companyId)
        } || state.reviewQueue.any {
            it.worktreePath.normalizedPath() == path && it.pullRequestNumber != null && scope.includes(it.companyId)
        }
        val companyId = (
            activeRuns.mapNotNull { companyIdForRun(state, it) } +
                openIssues.map { it.companyId } +
                reviewItems.map { it.companyId } +
                terminalRuns.mapNotNull { companyIdForRun(state, it) }
            )
            .firstOrNull { it.isNotBlank() }
        return WorktreeReferences(activeRuns, terminalRuns, openIssues, reviewItems, prLinked, companyId)
    }

    private fun companyIdForRun(state: DesktopAppState, run: AgentRun): String? {
        val tasksById = state.tasks.associateBy { it.id }
        val issuesById = state.issues.associateBy { it.id }
        val issueId = tasksById[run.taskId]?.issueId
        return issueId?.let { issuesById[it]?.companyId }?.takeIf { it.isNotBlank() }
    }

    private fun repositoryWorktreeRootFor(path: String?): Path? {
        val normalized = path?.takeIf { it.isNotBlank() }?.let(::safePath) ?: return null
        val parts = normalized.toList()
        val cotorIndex = parts.indexOfFirst { it.toString() == ".cotor" }
        if (cotorIndex < 0 || cotorIndex + 1 >= parts.size || parts[cotorIndex + 1].toString() != "worktrees") {
            return null
        }
        return normalized.root?.resolve(parts.take(cotorIndex + 2).joinToString("/") { it.toString() })
            ?: Path.of(parts.take(cotorIndex + 2).joinToString("/"))
    }

    private fun safePath(raw: String?): Path? =
        raw?.takeIf { it.isNotBlank() }?.let { runCatching { Path.of(it).toAbsolutePath().normalize() }.getOrNull() }

    private fun String?.normalizedPath(): String? =
        safePath(this)?.toString()

    private fun candidate(
        kind: String,
        classification: String,
        companyId: String?,
        path: String?,
        processId: Long?,
        ageDays: Long?,
        eligible: Boolean,
        reason: String
    ): RuntimeCleanupCandidate =
        RuntimeCleanupCandidate(
            id = listOf(kind, path ?: processId.toString()).joinToString(":").lowercase(Locale.US),
            kind = kind,
            classification = classification,
            companyId = companyId,
            path = path,
            processId = processId,
            ageDays = ageDays,
            eligible = eligible,
            reason = reason
        )

    private data class WorktreeReferences(
        val activeRuns: List<AgentRun>,
        val terminalRuns: List<AgentRun>,
        val openIssues: List<CompanyIssue>,
        val reviewItems: List<ReviewQueueItem>,
        val prLinked: Boolean,
        val companyId: String?
    )

    private data class RetentionScope(
        val companyId: String?,
        val allCompanies: Boolean
    ) {
        fun includes(candidateCompanyId: String?): Boolean =
            allCompanies || companyId == null || candidateCompanyId == null || candidateCompanyId == companyId

        companion object {
            fun from(state: DesktopAppState, companyId: String?, allCompanies: Boolean): RetentionScope {
                val resolved = companyId?.takeIf { id -> state.companies.any { it.id == id } } ?: companyId
                return RetentionScope(companyId = resolved, allCompanies = allCompanies || resolved == null)
            }
        }
    }
}
