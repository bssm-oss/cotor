package com.cotor.runtime.actions

import com.cotor.app.defaultDesktopAppHome
import com.cotor.storage.writeTextAtomically
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.createDirectories
import kotlin.io.path.exists
import kotlin.io.path.listDirectoryEntries
import kotlin.io.path.readText

class ActionStore(
    private val maxRecordsPerRun: Int = DEFAULT_MAX_RECORDS_PER_RUN,
    private val appHomeProvider: () -> Path = { defaultDesktopAppHome() }
) {
    private val lock = Any()
    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    init {
        require(maxRecordsPerRun > 0) { "maxRecordsPerRun must be positive" }
    }

    private fun actionsDir(): Path =
        appHomeProvider().resolve("runtime").resolve("actions")

    private fun indexFile(): Path =
        appHomeProvider().resolve("runtime").resolve("actions-index.json")

    fun listSnapshots(): List<ActionLogSnapshot> {
        val dir = actionsDir()
        if (!dir.exists()) {
            return emptyList()
        }
        return dir.listDirectoryEntries("*.json")
            .sortedBy { it.fileName.toString() }
            .mapNotNull { path ->
                runCatching {
                    json.decodeFromString(ActionLogSnapshot.serializer(), path.readText())
                }.getOrNull()
            }
    }

    fun listSummaries(): List<ActionLogSummary> {
        val dir = actionsDir()
        if (!dir.exists()) {
            return emptyList()
        }
        return synchronized(lock) {
            val actionFiles = currentActionFiles()
            val index = loadValidatedIndex(actionFiles) ?: rebuildIndex(actionFiles)
            index.entries
                .map { it.summary }
                .sortedBy { summary -> summary.runId }
        }
    }

    fun load(runId: String): ActionLogSnapshot? {
        return synchronized(lock) {
            val file = actionsDir().resolve("$runId.json")
            if (!file.exists()) {
                return@synchronized null
            }
            runCatching {
                json.decodeFromString(ActionLogSnapshot.serializer(), file.readText())
            }.getOrNull()
        }
    }

    fun append(runId: String, record: ActionExecutionRecord): ActionLogSnapshot {
        return synchronized(lock) {
            val current = load(runId) ?: ActionLogSnapshot(runId = runId)
            val updated = current.copy(
                records = (current.records + record).takeLast(maxRecordsPerRun),
                updatedAt = System.currentTimeMillis()
            )
            save(updated)
            updated
        }
    }

    fun replace(runId: String, recordId: String, transform: (ActionExecutionRecord) -> ActionExecutionRecord): ActionLogSnapshot {
        return synchronized(lock) {
            val current = load(runId) ?: ActionLogSnapshot(runId = runId)
            val updated = current.copy(
                records = current.records.map { record ->
                    if (record.id == recordId) transform(record) else record
                }.takeLast(maxRecordsPerRun),
                updatedAt = System.currentTimeMillis()
            )
            save(updated)
            updated
        }
    }

    private fun save(snapshot: ActionLogSnapshot) {
        synchronized(lock) {
            val dir = actionsDir()
            dir.createDirectories()
            val file = dir.resolve("${snapshot.runId}.json")
            writeTextAtomically(file, json.encodeToString(ActionLogSnapshot.serializer(), snapshot))
            upsertIndexEntry(snapshot, file)
        }
    }

    private fun currentActionFiles(): Map<String, Path> =
        actionsDir()
            .listDirectoryEntries("*.json")
            .associateBy { path -> path.fileName.toString().removeSuffix(".json") }

    private fun loadValidatedIndex(actionFiles: Map<String, Path>): ActionLogIndex? {
        val index = loadIndex() ?: return null
        val entriesByRunId = index.entries.associateBy { entry -> entry.summary.runId }
        if (entriesByRunId.keys != actionFiles.keys) return null
        val allFilesMatch = actionFiles.all { (runId, path) ->
            entriesByRunId[runId]?.fileLastModifiedAt == lastModifiedAt(path)
        }
        return index.takeIf { allFilesMatch }
    }

    private fun rebuildIndex(actionFiles: Map<String, Path>): ActionLogIndex {
        val entries = actionFiles.values.mapNotNull { path ->
            runCatching {
                val snapshot = json.decodeFromString(ActionLogSnapshot.serializer(), path.readText())
                ActionLogIndexEntry(
                    summary = snapshot.toSummary(),
                    fileLastModifiedAt = lastModifiedAt(path)
                )
            }.getOrNull()
        }.sortedBy { entry -> entry.summary.runId }
        return ActionLogIndex(entries = entries).also(::writeIndex)
    }

    private fun upsertIndexEntry(snapshot: ActionLogSnapshot, file: Path) {
        val currentEntries = loadIndex()?.entries.orEmpty()
        val entry = ActionLogIndexEntry(
            summary = snapshot.toSummary(),
            fileLastModifiedAt = lastModifiedAt(file)
        )
        val entries = (currentEntries.filterNot { it.summary.runId == snapshot.runId } + entry)
            .sortedBy { it.summary.runId }
        writeIndex(ActionLogIndex(entries = entries))
    }

    private fun loadIndex(): ActionLogIndex? {
        val file = indexFile()
        if (!file.exists()) return null
        return runCatching {
            json.decodeFromString(ActionLogIndex.serializer(), file.readText())
        }.getOrNull()
    }

    private fun writeIndex(index: ActionLogIndex) {
        writeTextAtomically(indexFile(), json.encodeToString(ActionLogIndex.serializer(), index))
    }

    private fun lastModifiedAt(path: Path): Long =
        runCatching { Files.getLastModifiedTime(path).toMillis() }.getOrDefault(0L)

    private companion object {
        const val DEFAULT_MAX_RECORDS_PER_RUN = 1_000
    }
}

@Serializable
private data class ActionLogIndex(
    val version: Int = 1,
    val entries: List<ActionLogIndexEntry> = emptyList()
)

@Serializable
private data class ActionLogIndexEntry(
    val summary: ActionLogSummary,
    val fileLastModifiedAt: Long
)

private fun ActionLogSnapshot.toSummary(): ActionLogSummary {
    val blockedByCompany = records
        .filter { record -> record.status == ActionStatus.DENIED || record.status == ActionStatus.WAITING_FOR_APPROVAL }
        .mapNotNull { record -> record.request.subject.companyId?.trim()?.takeIf { it.isNotBlank() } }
        .groupingBy { it }
        .eachCount()
    return ActionLogSummary(
        runId = runId,
        updatedAt = updatedAt,
        recordCount = records.size,
        blockedByCompany = blockedByCompany
    )
}
