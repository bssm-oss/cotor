package com.cotor.runtime.durable

import com.cotor.storage.writeTextAtomically
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.util.concurrent.ConcurrentHashMap
import kotlin.io.path.createDirectories
import kotlin.io.path.exists
import kotlin.io.path.readText

class DurableRuntimeStore(
    private val rootDir: Path = defaultDurableRuntimeRoot()
) {
    private val runLocks = ConcurrentHashMap<String, Any>()
    private val indexLock = Any()
    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private fun runsDir(): Path = rootDir.resolve("runs")
    private fun indexPath(): Path = rootDir.resolve("runs-index.json")

    init {
        runsDir().createDirectories()
    }

    fun listRuns(): List<DurableRunSnapshot> =
        Files.list(runsDir()).use { paths ->
            paths.toList()
                .filter { it.fileName.toString().endsWith(".json") }
                .mapNotNull { path ->
                    runCatching { json.decodeFromString<DurableRunSnapshot>(path.readText()) }.getOrNull()
                }
                .sortedByDescending { snapshot -> snapshot.updatedAt }
        }

    fun listRunSummaries(): List<DurableRunSummary> =
        synchronized(indexLock) {
            val runFiles = currentRunFiles()
            val index = loadValidatedIndex(runFiles) ?: rebuildIndex(runFiles)
            index.entries
                .map { it.summary }
                .sortedByDescending { summary -> summary.updatedAt }
        }

    fun loadRun(runId: String): DurableRunSnapshot? {
        val path = runPath(runId)
        if (!path.exists()) return null
        return runCatching { json.decodeFromString<DurableRunSnapshot>(path.readText()) }.getOrNull()
    }

    fun saveRun(snapshot: DurableRunSnapshot) {
        withRunLock(snapshot.runId) {
            writeRun(snapshot)
        }
    }

    fun updateRun(runId: String, update: (DurableRunSnapshot) -> DurableRunSnapshot): DurableRunSnapshot =
        withRunLock(runId) {
            val current = loadRunUnlocked(runId) ?: error("Unknown durable run: $runId")
            val updated = update(current)
            require(updated.runId == runId) {
                "Durable run update cannot change run id from '$runId' to '${updated.runId}'"
            }
            writeRun(updated)
            updated
        }

    fun replaceRun(snapshot: DurableRunSnapshot): DurableRunSnapshot =
        withRunLock(snapshot.runId) {
            writeRun(snapshot)
            snapshot
        }

    private fun <T> withRunLock(runId: String, block: () -> T): T {
        val lock = runLocks.computeIfAbsent(runId) { Any() }
        return synchronized(lock, block)
    }

    fun deleteRun(runId: String): Boolean =
        withRunLock(runId) {
            val deleted = runCatching { Files.deleteIfExists(runPath(runId)) }.getOrDefault(false)
            if (deleted) {
                removeRunFromIndex(runId)
            }
            deleted
        }

    private fun runPath(runId: String): Path = runsDir().resolve("$runId.json")

    private fun loadRunUnlocked(runId: String): DurableRunSnapshot? {
        val path = runPath(runId)
        if (!path.exists()) return null
        return runCatching { json.decodeFromString<DurableRunSnapshot>(path.readText()) }.getOrNull()
    }

    private fun writeRun(snapshot: DurableRunSnapshot) {
        val destination = runPath(snapshot.runId)
        writeTextAtomically(destination, json.encodeToString(snapshot))
        upsertIndexEntry(snapshot, destination)
    }

    private fun currentRunFiles(): Map<String, Path> =
        Files.list(runsDir()).use { paths ->
            paths.toList()
                .filter { path -> path.fileName.toString().endsWith(".json") }
                .associateBy { path -> path.fileName.toString().removeSuffix(".json") }
        }

    private fun loadValidatedIndex(runFiles: Map<String, Path>): DurableRunIndex? {
        val index = loadIndex() ?: return null
        val entriesByRunId = index.entries.associateBy { entry -> entry.summary.runId }
        if (entriesByRunId.keys != runFiles.keys) return null
        val allFilesMatch = runFiles.all { (runId, path) ->
            entriesByRunId[runId]?.runFileLastModifiedAt == lastModifiedAt(path)
        }
        return index.takeIf { allFilesMatch }
    }

    private fun rebuildIndex(runFiles: Map<String, Path>): DurableRunIndex {
        val entries = runFiles.values.mapNotNull { path ->
            runCatching {
                val snapshot = json.decodeFromString<DurableRunSnapshot>(path.readText())
                DurableRunIndexEntry(
                    summary = snapshot.toSummary(),
                    runFileLastModifiedAt = lastModifiedAt(path)
                )
            }.getOrNull()
        }.sortedByDescending { entry -> entry.summary.updatedAt }
        return DurableRunIndex(entries = entries).also(::writeIndex)
    }

    private fun upsertIndexEntry(snapshot: DurableRunSnapshot, runPath: Path) {
        synchronized(indexLock) {
            val currentEntries = loadIndex()?.entries.orEmpty()
            val entry = DurableRunIndexEntry(
                summary = snapshot.toSummary(),
                runFileLastModifiedAt = lastModifiedAt(runPath)
            )
            val entries = (currentEntries.filterNot { it.summary.runId == snapshot.runId } + entry)
                .sortedByDescending { it.summary.updatedAt }
            writeIndex(DurableRunIndex(entries = entries))
        }
    }

    private fun removeRunFromIndex(runId: String) {
        synchronized(indexLock) {
            val currentEntries = loadIndex()?.entries ?: return
            writeIndex(DurableRunIndex(entries = currentEntries.filterNot { it.summary.runId == runId }))
        }
    }

    private fun loadIndex(): DurableRunIndex? {
        val path = indexPath()
        if (!path.exists()) return null
        return runCatching { json.decodeFromString<DurableRunIndex>(path.readText()) }.getOrNull()
    }

    private fun writeIndex(index: DurableRunIndex) {
        writeTextAtomically(indexPath(), json.encodeToString(index))
    }

    private fun lastModifiedAt(path: Path): Long =
        runCatching { Files.getLastModifiedTime(path).toMillis() }.getOrDefault(0L)
}

@Serializable
private data class DurableRunIndex(
    val version: Int = 1,
    val entries: List<DurableRunIndexEntry> = emptyList()
)

@Serializable
private data class DurableRunIndexEntry(
    val summary: DurableRunSummary,
    val runFileLastModifiedAt: Long
)

private fun DurableRunSnapshot.toSummary(): DurableRunSummary {
    val companyIds = (
        checkpoints.mapNotNull { node -> node.metadata["companyId"] } +
            sideEffects.mapNotNull { effect -> effect.metadata["companyId"] }
        )
        .filter { it.isNotBlank() }
        .distinct()
        .sorted()
    return DurableRunSummary(
        runId = runId,
        pipelineName = pipelineName,
        configPath = configPath,
        replayMode = replayMode,
        sourceRunId = sourceRunId,
        sourceCheckpointId = sourceCheckpointId,
        status = status,
        createdAt = createdAt,
        updatedAt = updatedAt,
        completedAt = completedAt,
        importedLegacyCheckpoint = importedLegacyCheckpoint,
        checkpointCount = checkpoints.size,
        pendingApprovalCount = approvalPauses.count { pause -> pause.status == ApprovalPauseStatus.PENDING },
        companyIds = companyIds
    )
}

private fun defaultDurableRuntimeRoot(): Path {
    val overriddenHome = sequenceOf(
        System.getenv("COTOR_DESKTOP_APP_HOME"),
        System.getenv("COTOR_APP_HOME")
    )
        .mapNotNull { it?.trim()?.takeIf(String::isNotBlank) }
        .map { Paths.get(it).toAbsolutePath().normalize() }
        .firstOrNull()
    val appHome = overriddenHome
        ?: Paths.get(System.getProperty("user.home")).toAbsolutePath().normalize()
            .resolve("Library")
            .resolve("Application Support")
            .resolve("CotorDesktop")
    return appHome.resolve("runtime")
}
