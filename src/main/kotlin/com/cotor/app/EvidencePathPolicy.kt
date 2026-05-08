package com.cotor.app

import java.nio.file.Path

/**
 * Keeps evidence file lookups inside roots that the desktop state already owns.
 */
internal object EvidencePathPolicy {
    fun requireAllowedFilePath(path: String, state: DesktopAppState): Path {
        val requested = canonicalize(Path.of(path))
        val roots = evidenceRoots(state)
        require(roots.isNotEmpty()) { "No configured company, repository, or worktree roots are available for evidence lookup" }
        require(roots.any { requested.startsWith(it) }) {
            "Evidence file path must stay inside a configured company, repository, or worktree root"
        }
        return requested
    }

    private fun evidenceRoots(state: DesktopAppState): List<Path> {
        val companyRoots = state.companies.mapNotNull { it.rootPath.takeIf(String::isNotBlank) }
        val repositoryRoots = state.repositories.mapNotNull { it.localPath.takeIf(String::isNotBlank) }
        val worktreeRoots = state.runs.mapNotNull { it.worktreePath.takeIf(String::isNotBlank) }
        return (companyRoots + repositoryRoots + worktreeRoots)
            .map { canonicalize(Path.of(it)) }
            .distinct()
    }

    private fun canonicalize(path: Path): Path =
        runCatching { path.toRealPath() }
            .getOrElse { path.toAbsolutePath().normalize() }
}
