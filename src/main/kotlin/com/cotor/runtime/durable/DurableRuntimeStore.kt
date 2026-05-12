package com.cotor.runtime.durable

import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.StandardCopyOption.ATOMIC_MOVE
import java.nio.file.StandardCopyOption.REPLACE_EXISTING
import java.util.concurrent.ConcurrentHashMap
import kotlin.io.path.createDirectories
import kotlin.io.path.exists
import kotlin.io.path.readText

class DurableRuntimeStore(
    private val rootDir: Path = defaultDurableRuntimeRoot()
) {
    private val runLocks = ConcurrentHashMap<String, Any>()
    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private fun runsDir(): Path = rootDir.resolve("runs")

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
            runCatching { Files.deleteIfExists(runPath(runId)) }.getOrDefault(false)
        }

    private fun runPath(runId: String): Path = runsDir().resolve("$runId.json")

    private fun loadRunUnlocked(runId: String): DurableRunSnapshot? {
        val path = runPath(runId)
        if (!path.exists()) return null
        return runCatching { json.decodeFromString<DurableRunSnapshot>(path.readText()) }.getOrNull()
    }

    private fun writeRun(snapshot: DurableRunSnapshot) {
        val destination = runPath(snapshot.runId)
        val temp = Files.createTempFile(runsDir(), "${snapshot.runId}.", ".tmp")
        Files.writeString(temp, json.encodeToString(snapshot))
        runCatching {
            Files.move(temp, destination, ATOMIC_MOVE, REPLACE_EXISTING)
        }.getOrElse {
            Files.move(temp, destination, REPLACE_EXISTING)
        }
    }
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
