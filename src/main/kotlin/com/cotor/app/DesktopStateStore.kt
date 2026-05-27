package com.cotor.app

/**
 * File overview for DesktopStateStore.
 *
 * This file belongs to the app layer for the desktop shell and localhost app-server surface.
 * It groups declarations around desktop state store so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import com.cotor.app.persistence.StateRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import java.nio.channels.FileChannel
import java.nio.channels.OverlappingFileLockException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.nio.file.attribute.PosixFilePermission
import java.security.MessageDigest
import java.sql.Connection
import java.sql.DriverManager
import java.util.concurrent.ConcurrentHashMap
import kotlin.io.path.createDirectories
import kotlin.io.path.exists
import kotlin.io.path.readText
import kotlin.io.path.writeText

/**
 * Persists the lightweight desktop state into Application Support.
 *
 * The store is intentionally forgiving: if the JSON file becomes unreadable we
 * fall back to an empty state instead of blocking the whole desktop app from booting.
 */
class DesktopStateStore(
    private val appHomeProvider: () -> Path = { defaultDesktopAppHome() },
) : StateRepository<DesktopAppState> {
    companion object {
        private const val MAX_PERSISTED_RESOLVED_ISSUES = 20
        private const val MAX_PERSISTED_TASK_PROMPT_CHARS = 512
        private const val MAX_PERSISTED_RUN_OUTPUT_CHARS = 4000
        private const val MAX_STATE_LOAD_LOG_BYTES = 1L * 1024L * 1024L
        private const val STATE_LOAD_LOG_DEDUP_WINDOW_MS = 30_000L
        private const val STATE_LOCK_TIMEOUT_MS = 3_000L
        private const val STATE_LOCK_RETRY_DELAY_MS = 50L
        private const val MAX_TAIL_TRIM_RECOVERY_CHARS = 512

        @Volatile
        private var lastStateLoadLogMessage: String? = null

        @Volatile
        private var lastStateLoadLogAt: Long = 0L

        private val processStateFileLocks = ConcurrentHashMap<String, Mutex>()
    }

    private data class CachedState(
        val state: DesktopAppState,
        val lastModifiedAtMillis: Long,
        val sizeInBytes: Long
    )

    private data class SqliteCachedState(
        val state: DesktopAppState,
        val revision: Long
    )

    private class StateCollection<T>(
        val name: String,
        private val serializer: KSerializer<T>,
        private val read: (DesktopAppState) -> T,
        private val write: (DesktopAppState, T) -> DesktopAppState
    ) {
        fun encode(state: DesktopAppState, json: Json): String =
            json.encodeToString(serializer, read(state))

        fun apply(state: DesktopAppState, payload: String, json: Json): DesktopAppState =
            write(state, json.decodeFromString(serializer, payload))
    }

    private val json = Json {
        ignoreUnknownKeys = true
        prettyPrint = true
        isLenient = true
        coerceInputValues = true
        encodeDefaults = true
    }

    private val stateCollections: List<StateCollection<*>> = listOf(
        StateCollection("companies", ListSerializer(Company.serializer()), DesktopAppState::companies) { state, value -> state.copy(companies = value) },
        StateCollection("companyAgentDefinitions", ListSerializer(CompanyAgentDefinition.serializer()), DesktopAppState::companyAgentDefinitions) { state, value -> state.copy(companyAgentDefinitions = value) },
        StateCollection("agentCapabilityProfiles", ListSerializer(AgentCapabilityProfile.serializer()), DesktopAppState::agentCapabilityProfiles) { state, value -> state.copy(agentCapabilityProfiles = value) },
        StateCollection("projectContexts", ListSerializer(CompanyProjectContext.serializer()), DesktopAppState::projectContexts) { state, value -> state.copy(projectContexts = value) },
        StateCollection("repositories", ListSerializer(ManagedRepository.serializer()), DesktopAppState::repositories) { state, value -> state.copy(repositories = value) },
        StateCollection("workspaces", ListSerializer(Workspace.serializer()), DesktopAppState::workspaces) { state, value -> state.copy(workspaces = value) },
        StateCollection("tasks", ListSerializer(AgentTask.serializer()), DesktopAppState::tasks) { state, value -> state.copy(tasks = value) },
        StateCollection("runs", ListSerializer(AgentRun.serializer()), DesktopAppState::runs) { state, value -> state.copy(runs = value) },
        StateCollection("goals", ListSerializer(CompanyGoal.serializer()), DesktopAppState::goals) { state, value -> state.copy(goals = value) },
        StateCollection("issues", ListSerializer(CompanyIssue.serializer()), DesktopAppState::issues) { state, value -> state.copy(issues = value) },
        StateCollection("issueDependencies", ListSerializer(IssueDependency.serializer()), DesktopAppState::issueDependencies) { state, value -> state.copy(issueDependencies = value) },
        StateCollection("orgProfiles", ListSerializer(OrgAgentProfile.serializer()), DesktopAppState::orgProfiles) { state, value -> state.copy(orgProfiles = value) },
        StateCollection("workflowTopologies", ListSerializer(WorkflowTopologySnapshot.serializer()), DesktopAppState::workflowTopologies) { state, value -> state.copy(workflowTopologies = value) },
        StateCollection("goalDecisions", ListSerializer(GoalOrchestrationDecision.serializer()), DesktopAppState::goalDecisions) { state, value -> state.copy(goalDecisions = value) },
        StateCollection("reviewQueue", ListSerializer(ReviewQueueItem.serializer()), DesktopAppState::reviewQueue) { state, value -> state.copy(reviewQueue = value) },
        StateCollection("companyActivity", ListSerializer(CompanyActivityItem.serializer()), DesktopAppState::companyActivity) { state, value -> state.copy(companyActivity = value) },
        StateCollection("opsMetrics", OpsMetricSnapshot.serializer(), DesktopAppState::opsMetrics) { state, value -> state.copy(opsMetrics = value) },
        StateCollection("signals", ListSerializer(OpsSignal.serializer()), DesktopAppState::signals) { state, value -> state.copy(signals = value) },
        StateCollection("backendSettings", DesktopBackendSettings.serializer(), DesktopAppState::backendSettings) { state, value -> state.copy(backendSettings = value) },
        StateCollection("linearSettings", DesktopLinearSettings.serializer(), DesktopAppState::linearSettings) { state, value -> state.copy(linearSettings = value) },
        StateCollection("runtime", CompanyRuntimeSnapshot.serializer(), DesktopAppState::runtime) { state, value -> state.copy(runtime = value) },
        StateCollection("companyRuntimes", ListSerializer(CompanyRuntimeSnapshot.serializer()), DesktopAppState::companyRuntimes) { state, value -> state.copy(companyRuntimes = value) },
        StateCollection("workflowPipelines", ListSerializer(WorkflowPipelineDefinition.serializer()), DesktopAppState::workflowPipelines) { state, value -> state.copy(workflowPipelines = value) },
        StateCollection("agentContextEntries", ListSerializer(AgentContextEntry.serializer()), DesktopAppState::agentContextEntries) { state, value -> state.copy(agentContextEntries = value) },
        StateCollection("agentMessages", ListSerializer(AgentMessage.serializer()), DesktopAppState::agentMessages) { state, value -> state.copy(agentMessages = value) },
        StateCollection("marketingDelegationPolicies", ListSerializer(MarketingDelegationPolicy.serializer()), DesktopAppState::marketingDelegationPolicies) { state, value -> state.copy(marketingDelegationPolicies = value) },
        StateCollection("marketingRuns", ListSerializer(MarketingRunRecord.serializer()), DesktopAppState::marketingRuns) { state, value -> state.copy(marketingRuns = value) },
        StateCollection("skillRuns", ListSerializer(SkillRunRecord.serializer()), DesktopAppState::skillRuns) { state, value -> state.copy(skillRuns = value) },
        StateCollection("companyRuntimeWorkItems", ListSerializer(CompanyRuntimeWorkItem.serializer()), DesktopAppState::companyRuntimeWorkItems) { state, value -> state.copy(companyRuntimeWorkItems = value) },
        StateCollection("problemSignals", ListSerializer(CompanyProblemSignal.serializer()), DesktopAppState::problemSignals) { state, value -> state.copy(problemSignals = value) }
    )

    // A single process can finish multiple background runs nearly at once, so writes
    // need to be serialized even though the backing file is small.
    private val mutex = Mutex()

    @Volatile
    private var cachedState: CachedState? = null

    @Volatile
    private var cachedSqliteState: SqliteCachedState? = null

    fun appHome(): Path = appHomeProvider()

    fun managedReposRoot(): Path = appHome().resolve("ManagedRepos")

    override suspend fun load(): DesktopAppState =
        if (useJsonBackend()) {
            loadJson()
        } else {
            loadSqlite()
        }

    private suspend fun loadJson(): DesktopAppState = withContext(Dispatchers.IO) {
        val stateFile = stateFile()
        if (!stateFile.exists()) {
            return@withContext withStateFileLock {
                cleanupStateTempFiles(stateFile.parent)
                DesktopAppState()
            }
        }
        val backupFile = backupStateFile()
        currentFingerprint(stateFile)?.let { fingerprint ->
            cachedState
                ?.takeIf {
                    it.lastModifiedAtMillis == fingerprint.first &&
                        it.sizeInBytes == fingerprint.second
                }
                ?.let { return@withContext it.state }
        }

        withStateFileLock {
            cleanupStateTempFiles(stateFile.parent)
            currentFingerprint(stateFile)?.let { fingerprint ->
                cachedState
                    ?.takeIf {
                        it.lastModifiedAtMillis == fingerprint.first &&
                            it.sizeInBytes == fingerprint.second
                    }
                    ?.let { return@withStateFileLock it.state }
            }
            val raw = runCatching { stateFile.readText() }.getOrElse { return@withStateFileLock DesktopAppState() }
            decodeState(raw)?.also { decoded ->
                val compacted = normalizeStateForPersistence(decoded)
                if (raw != json.encodeToString(DesktopAppState.serializer(), compacted)) {
                    saveJsonLocked(compacted)
                } else {
                    updateCache(stateFile, compacted)
                }
                return@withStateFileLock compacted
            } ?: DesktopAppState()
            if (backupFile.exists()) {
                val backupRaw = runCatching { backupFile.readText() }.getOrNull()
                decodeState(backupRaw.orEmpty())?.also { recovered ->
                    val compacted = normalizeStateForPersistence(recovered)
                    saveJsonLocked(compacted)
                    return@withStateFileLock compacted
                }
            }
            DesktopAppState()
        }
    }

    override suspend fun save(state: DesktopAppState) {
        if (useJsonBackend()) {
            saveJson(state)
        } else {
            saveSqlite(state)
        }
    }

    private suspend fun saveJson(state: DesktopAppState) {
        mutex.withLock {
            withContext(Dispatchers.IO) {
                withStateFileLock {
                    saveJsonLocked(state)
                }
            }
        }
    }

    private fun stateFile(): Path = appHome().resolve("state.json")

    private fun backupStateFile(): Path = appHome().resolve("state.json.bak")

    private fun sqliteStateFile(): Path = appHome().resolve("state.sqlite")

    private fun lockFile(): Path = appHome().resolve("state.lock")

    private fun lockMetadataFile(): Path = appHome().resolve("state.lock.json")

    private fun saveJsonLocked(state: DesktopAppState) {
        val file = stateFile()
        val backupFile = backupStateFile()
        // Always create the parent directories before the first write so the
        // app can start from a completely clean machine state.
        file.parent?.createDirectories()
        managedReposRoot().createDirectories()
        val compactedState = normalizeStateForPersistence(state)
        val payload = json.encodeToString(DesktopAppState.serializer(), compactedState)
        cleanupStateTempFiles(file.parent)
        val tempFile = Files.createTempFile(file.parent, "${file.fileName}.", ".tmp")
        tempFile.writeText(payload)
        enforceOwnerOnlyPermissions(tempFile)
        moveWithAtomicFallback(tempFile, file)
        enforceOwnerOnlyPermissions(file)
        val backupTempFile = Files.createTempFile(backupFile.parent, "${backupFile.fileName}.", ".tmp")
        backupTempFile.writeText(payload)
        enforceOwnerOnlyPermissions(backupTempFile)
        moveWithAtomicFallback(backupTempFile, backupFile)
        enforceOwnerOnlyPermissions(backupFile)
        updateCache(file, compactedState)
    }

    private suspend fun loadSqlite(): DesktopAppState = withContext(Dispatchers.IO) {
        withStateFileLock {
            cleanupStateTempFiles(appHome())
            sqliteConnection().use { connection ->
                ensureSqliteSchema(connection)
                migrateJsonStateIfNeeded(connection)
                val revision = sqliteRevision(connection)
                cachedSqliteState?.takeIf { it.revision == revision }?.let { return@withStateFileLock it.state }
                val state = loadSqliteState(connection)
                cachedSqliteState = SqliteCachedState(state, revision)
                state
            }
        }
    }

    private suspend fun saveSqlite(state: DesktopAppState) {
        mutex.withLock {
            withContext(Dispatchers.IO) {
                withStateFileLock {
                    cleanupStateTempFiles(appHome())
                    sqliteConnection().use { connection ->
                        ensureSqliteSchema(connection)
                        saveSqliteState(connection, state)
                    }
                }
            }
        }
    }

    private fun sqliteConnection(): Connection {
        val file = sqliteStateFile()
        file.parent?.createDirectories()
        managedReposRoot().createDirectories()
        val connection = DriverManager.getConnection("jdbc:sqlite:${file.toAbsolutePath().normalize()}")
        connection.createStatement().use { statement ->
            statement.execute("PRAGMA busy_timeout = 3000")
            statement.execute("PRAGMA journal_mode = WAL")
            statement.execute("PRAGMA synchronous = NORMAL")
        }
        return connection
    }

    private fun ensureSqliteSchema(connection: Connection) {
        connection.createStatement().use { statement ->
            statement.execute(
                """
                CREATE TABLE IF NOT EXISTS state_collections (
                    name TEXT PRIMARY KEY,
                    payload TEXT NOT NULL,
                    payload_sha256 TEXT NOT NULL,
                    updated_at INTEGER NOT NULL
                )
                """.trimIndent()
            )
            statement.execute(
                """
                CREATE TABLE IF NOT EXISTS state_meta (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                )
                """.trimIndent()
            )
        }
        if (sqliteMeta(connection, "schema_version") == null) {
            setSqliteMeta(connection, "schema_version", "1")
        }
    }

    private fun migrateJsonStateIfNeeded(connection: Connection) {
        if (sqliteCollectionCount(connection) > 0L) {
            return
        }
        val migrated = readJsonStateForMigration() ?: return
        saveSqliteState(connection, migrated)
        setSqliteMeta(connection, "migrated_from_json_at", System.currentTimeMillis().toString())
    }

    private fun readJsonStateForMigration(): DesktopAppState? {
        val primary = stateFile()
        if (primary.exists()) {
            val raw = runCatching { primary.readText() }.getOrNull()
            decodeState(raw.orEmpty())?.let { return normalizeStateForPersistence(it) }
        }
        val backup = backupStateFile()
        if (backup.exists()) {
            val raw = runCatching { backup.readText() }.getOrNull()
            decodeState(raw.orEmpty())?.let { return normalizeStateForPersistence(it) }
        }
        return null
    }

    private fun loadSqliteState(connection: Connection): DesktopAppState {
        val rows = mutableMapOf<String, String>()
        connection.prepareStatement("SELECT name, payload FROM state_collections").use { statement ->
            statement.executeQuery().use { result ->
                while (result.next()) {
                    rows[result.getString("name")] = result.getString("payload")
                }
            }
        }
        if (rows.isEmpty()) {
            return DesktopAppState()
        }
        val decoded = stateCollections.fold(DesktopAppState()) { state, collection ->
            val payload = rows[collection.name] ?: return@fold state
            runCatching { collection.apply(state, payload, json) }
                .onFailure { error ->
                    appendStateLoadLog(
                        "Recovered SQLite state without invalid collection ${collection.name}: " +
                            (error.message ?: error::class.simpleName.orEmpty())
                    )
                }
                .getOrDefault(state)
        }
        return normalizeStateForPersistence(decoded)
    }

    private fun saveSqliteState(connection: Connection, state: DesktopAppState) {
        val compactedState = normalizeStateForPersistence(state)
        val existingHashes = sqliteCollectionHashes(connection)
        val now = System.currentTimeMillis()
        var changed = false
        connection.autoCommit = false
        try {
            stateCollections.forEach { collection ->
                val payload = collection.encode(compactedState, json)
                val hash = sha256(payload)
                if (existingHashes[collection.name] == hash) {
                    return@forEach
                }
                connection.prepareStatement(
                    """
                    INSERT INTO state_collections(name, payload, payload_sha256, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(name) DO UPDATE SET
                        payload = excluded.payload,
                        payload_sha256 = excluded.payload_sha256,
                        updated_at = excluded.updated_at
                    """.trimIndent()
                ).use { statement ->
                    statement.setString(1, collection.name)
                    statement.setString(2, payload)
                    statement.setString(3, hash)
                    statement.setLong(4, now)
                    statement.executeUpdate()
                }
                changed = true
            }
            val currentRevision = sqliteRevision(connection)
            val nextRevision = if (changed || currentRevision == 0L) {
                currentRevision + 1L
            } else {
                currentRevision
            }
            if (nextRevision != currentRevision) {
                setSqliteMeta(connection, "revision", nextRevision.toString())
            }
            connection.commit()
            cachedSqliteState = SqliteCachedState(compactedState, nextRevision)
        } catch (error: Throwable) {
            runCatching { connection.rollback() }
            throw error
        } finally {
            connection.autoCommit = true
        }
    }

    private fun sqliteCollectionCount(connection: Connection): Long =
        connection.prepareStatement("SELECT COUNT(*) FROM state_collections").use { statement ->
            statement.executeQuery().use { result ->
                if (result.next()) result.getLong(1) else 0L
            }
        }

    private fun sqliteCollectionHashes(connection: Connection): Map<String, String> {
        val hashes = mutableMapOf<String, String>()
        connection.prepareStatement("SELECT name, payload_sha256 FROM state_collections").use { statement ->
            statement.executeQuery().use { result ->
                while (result.next()) {
                    hashes[result.getString("name")] = result.getString("payload_sha256")
                }
            }
        }
        return hashes
    }

    private fun sqliteRevision(connection: Connection): Long =
        sqliteMeta(connection, "revision")?.toLongOrNull() ?: 0L

    private fun sqliteMeta(connection: Connection, key: String): String? =
        connection.prepareStatement("SELECT value FROM state_meta WHERE key = ?").use { statement ->
            statement.setString(1, key)
            statement.executeQuery().use { result ->
                if (result.next()) result.getString(1) else null
            }
        }

    private fun setSqliteMeta(connection: Connection, key: String, value: String) {
        connection.prepareStatement(
            """
            INSERT INTO state_meta(key, value)
            VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """.trimIndent()
        ).use { statement ->
            statement.setString(1, key)
            statement.setString(2, value)
            statement.executeUpdate()
        }
    }

    private fun sha256(value: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    private fun useJsonBackend(): Boolean {
        val configured = System.getenv("COTOR_DESKTOP_STATE_BACKEND")
            ?: System.getProperty("cotor.desktop.state.backend")
        return configured.equals("json", ignoreCase = true)
    }

    private fun cleanupStateTempFiles(directory: Path?) {
        if (directory == null) {
            return
        }
        stateTempFilesToClean(directory).forEach { tempFile ->
            runCatching { Files.deleteIfExists(tempFile) }
        }
    }

    private fun decodeStateOrNull(raw: String): DesktopAppState? {
        val strictDecode = runCatching { json.decodeFromString<DesktopAppState>(raw) }
        strictDecode.getOrNull()?.let { return it }
        return decodeStateLenient(raw, strictDecode.exceptionOrNull())
    }

    private fun decodeState(raw: String): DesktopAppState? {
        decodeStateOrNull(raw)?.let { return it }
        var candidate = raw.trimEnd()
        var trimsRemaining = MAX_TAIL_TRIM_RECOVERY_CHARS
        while (candidate.isNotEmpty() && trimsRemaining > 0) {
            candidate = candidate.dropLast(1).trimEnd()
            trimsRemaining -= 1
            decodeStateOrNull(candidate)?.let { return it }
        }
        return null
    }

    private fun decodeStateLenient(raw: String, strictError: Throwable?): DesktopAppState? = runCatching {
        val root = json.parseToJsonElement(raw).jsonObject
        val skippedEntries = mutableListOf<String>()
        fun <T> decodeList(name: String, serializer: KSerializer<T>): List<T> =
            root[name]
                ?.jsonArray
                ?.mapIndexedNotNull { index, element ->
                    runCatching { json.decodeFromJsonElement(serializer, element) }
                        .onFailure { error ->
                            skippedEntries += "$name[$index]: ${error.message ?: error::class.simpleName.orEmpty()}"
                        }
                        .getOrNull()
                }
                ?: emptyList()
        fun <T> decodeObject(name: String, serializer: KSerializer<T>, defaultValue: T): T =
            root[name]
                ?.let { element ->
                    runCatching { json.decodeFromJsonElement(serializer, element) }
                        .onFailure { error ->
                            skippedEntries += "$name: ${error.message ?: error::class.simpleName.orEmpty()}"
                        }
                        .getOrNull()
                }
                ?: defaultValue

        val recovered = DesktopAppState(
            companies = decodeList("companies", Company.serializer()),
            companyAgentDefinitions = decodeList("companyAgentDefinitions", CompanyAgentDefinition.serializer()),
            agentCapabilityProfiles = decodeList("agentCapabilityProfiles", AgentCapabilityProfile.serializer()),
            projectContexts = decodeList("projectContexts", CompanyProjectContext.serializer()),
            repositories = decodeList("repositories", ManagedRepository.serializer()),
            workspaces = decodeList("workspaces", Workspace.serializer()),
            tasks = decodeList("tasks", AgentTask.serializer()),
            runs = decodeList("runs", AgentRun.serializer()),
            goals = decodeList("goals", CompanyGoal.serializer()),
            issues = decodeList("issues", CompanyIssue.serializer()),
            issueDependencies = decodeList("issueDependencies", IssueDependency.serializer()),
            orgProfiles = decodeList("orgProfiles", OrgAgentProfile.serializer()),
            workflowPipelines = decodeList("workflowPipelines", WorkflowPipelineDefinition.serializer()),
            workflowTopologies = decodeList("workflowTopologies", WorkflowTopologySnapshot.serializer()),
            goalDecisions = decodeList("goalDecisions", GoalOrchestrationDecision.serializer()),
            reviewQueue = decodeList("reviewQueue", ReviewQueueItem.serializer()),
            companyActivity = decodeList("companyActivity", CompanyActivityItem.serializer()),
            agentContextEntries = decodeList("agentContextEntries", AgentContextEntry.serializer()),
            agentMessages = decodeList("agentMessages", AgentMessage.serializer()),
            marketingDelegationPolicies = decodeList("marketingDelegationPolicies", MarketingDelegationPolicy.serializer()),
            marketingRuns = decodeList("marketingRuns", MarketingRunRecord.serializer()),
            skillRuns = decodeList("skillRuns", SkillRunRecord.serializer()),
            opsMetrics = decodeObject("opsMetrics", OpsMetricSnapshot.serializer(), OpsMetricSnapshot()),
            signals = decodeList("signals", OpsSignal.serializer()),
            backendSettings = decodeObject("backendSettings", DesktopBackendSettings.serializer(), DesktopBackendSettings()),
            linearSettings = decodeObject("linearSettings", DesktopLinearSettings.serializer(), DesktopLinearSettings()),
            runtime = decodeObject("runtime", CompanyRuntimeSnapshot.serializer(), CompanyRuntimeSnapshot()),
            companyRuntimes = decodeList("companyRuntimes", CompanyRuntimeSnapshot.serializer())
        )
        val summary = buildString {
            append("Recovered state with lenient decode")
            strictError?.message?.takeIf { it.isNotBlank() }?.let {
                append(" | strict=")
                append(it)
            }
            if (skippedEntries.isNotEmpty()) {
                append(" | skipped=")
                append(skippedEntries.take(20).joinToString("; "))
                if (skippedEntries.size > 20) {
                    append(" (+")
                    append(skippedEntries.size - 20)
                    append(" more)")
                }
            }
        }
        appendStateLoadLog(summary)
        recovered
    }.onFailure { error ->
        appendStateLoadLog(
            "Failed lenient state decode" +
                (strictError?.message?.let { " | strict=$it" } ?: "") +
                " | lenient=${error.message ?: error::class.simpleName.orEmpty()}"
        )
    }.getOrNull()

    private fun appendStateLoadLog(message: String) {
        runCatching {
            val now = System.currentTimeMillis()
            synchronized(DesktopStateStore::class.java) {
                if (message == lastStateLoadLogMessage && now - lastStateLoadLogAt < STATE_LOAD_LOG_DEDUP_WINDOW_MS) {
                    return@runCatching
                }
                lastStateLoadLogMessage = message
                lastStateLoadLogAt = now
            }
            val runtimeDir = appHome().resolve("runtime").resolve("backend")
            runtimeDir.createDirectories()
            val logFile = runtimeDir.resolve("state-load.log")
            if (logFile.exists() && Files.size(logFile) >= MAX_STATE_LOAD_LOG_BYTES) {
                Files.move(
                    logFile,
                    logFile.resolveSibling("${logFile.fileName}.1"),
                    StandardCopyOption.REPLACE_EXISTING
                )
            }
            Files.writeString(
                logFile,
                "[$now] $message\n",
                StandardOpenOption.CREATE,
                StandardOpenOption.APPEND
            )
        }
    }

    private suspend fun <T> withStateFileLock(block: () -> T): T {
        val lockPath = lockFile()
        val metadataPath = lockMetadataFile()
        lockPath.parent?.createDirectories()
        metadataPath.parent?.createDirectories()
        val processLock = processStateFileLocks.getOrPut(lockPath.toAbsolutePath().normalize().toString()) { Mutex() }
        return processLock.withLock {
            try {
                FileChannel.open(
                    lockPath,
                    StandardOpenOption.CREATE,
                    StandardOpenOption.WRITE
                ).use { channel ->
                    val deadline = System.currentTimeMillis() + STATE_LOCK_TIMEOUT_MS
                    while (true) {
                        val lock = channel.tryLock()
                        if (lock != null) {
                            return@use lock.use {
                                writeLockMetadata(metadataPath)
                                try {
                                    block()
                                } finally {
                                    clearLockMetadata(metadataPath)
                                }
                            }
                        }
                        if (System.currentTimeMillis() >= deadline) {
                            val holder = runCatching { metadataPath.readText() }.getOrNull()?.trim()
                            error(
                                buildString {
                                    append("state.lock acquisition timed out after ")
                                    append(STATE_LOCK_TIMEOUT_MS)
                                    append("ms; path=")
                                    append(lockPath)
                                    if (!holder.isNullOrBlank()) {
                                        append("; holder=")
                                        append(holder)
                                    }
                                }
                            )
                        }
                        delay(STATE_LOCK_RETRY_DELAY_MS)
                    }
                    error("Unreachable")
                }
            } catch (_: OverlappingFileLockException) {
                // The process-level coroutine mutex above serializes same-JVM
                // access. The file-channel lock still protects cross-process use
                // whenever the JVM can acquire it.
                block()
            }
        }
    }

    private fun moveWithAtomicFallback(source: Path, target: Path) {
        try {
            Files.move(
                source,
                target,
                StandardCopyOption.REPLACE_EXISTING,
                StandardCopyOption.ATOMIC_MOVE
            )
        } catch (error: Exception) {
            appendStateLoadLog(
                "ATOMIC_MOVE failed for ${target.fileName}: ${error.message ?: error::class.simpleName.orEmpty()}; falling back to non-atomic replace"
            )
            Files.move(
                source,
                target,
                StandardCopyOption.REPLACE_EXISTING
            )
        }
    }

    private fun writeLockMetadata(metadataPath: Path) {
        val now = System.currentTimeMillis()
        val pid = runCatching { ProcessHandle.current().pid() }.getOrDefault(-1L)
        val payload = """
            {"pid":$pid,"lockedAt":$now,"appHome":"${appHome().toString().replace("\"", "\\\"")}"}
        """.trimIndent()
        metadataPath.writeText(payload)
        enforceOwnerOnlyPermissions(metadataPath)
    }

    private fun clearLockMetadata(metadataPath: Path) {
        runCatching { Files.deleteIfExists(metadataPath) }
    }

    private fun enforceOwnerOnlyPermissions(path: Path) {
        runCatching {
            Files.setPosixFilePermissions(
                path,
                setOf(
                    PosixFilePermission.OWNER_READ,
                    PosixFilePermission.OWNER_WRITE
                )
            )
        }
    }

    private fun currentFingerprint(file: Path): Pair<Long, Long>? =
        if (!file.exists()) {
            null
        } else {
            Files.getLastModifiedTime(file).toMillis() to Files.size(file)
        }

    private fun updateCache(file: Path, state: DesktopAppState) {
        currentFingerprint(file)?.let { fingerprint ->
            cachedState = CachedState(
                state = state,
                lastModifiedAtMillis = fingerprint.first,
                sizeInBytes = fingerprint.second
            )
        }
    }

    private fun normalizeStateForPersistence(state: DesktopAppState): DesktopAppState =
        compactStateForPersistence(pruneDanglingCompanyReferences(normalizeLegacyCompanyRuntimeState(state)))

    private fun pruneDanglingCompanyReferences(state: DesktopAppState): DesktopAppState {
        val companyIds = state.companies.mapTo(linkedSetOf()) { it.id }
        val projectContextIds = state.projectContexts
            .filter { it.companyId in companyIds }
            .mapTo(linkedSetOf()) { it.id }
        val goals = state.goals
            .filter { goal -> goal.companyId in companyIds }
            .map { goal ->
                if (goal.projectContextId != null && goal.projectContextId !in projectContextIds) {
                    goal.copy(projectContextId = null)
                } else {
                    goal
                }
            }
        val goalIds = goals.mapTo(linkedSetOf()) { it.id }
        val issues = state.issues
            .filter { issue ->
                issue.companyId in companyIds &&
                    issue.goalId in goalIds
            }
            .map { issue ->
                if (issue.projectContextId != null && issue.projectContextId !in projectContextIds) {
                    issue.copy(projectContextId = null)
                } else {
                    issue
                }
            }
        val issueIds = issues.mapTo(linkedSetOf()) { it.id }
        val issuesById = issues.associateBy { it.id }
        val normalizedReviewQueue = state.reviewQueue.map { item ->
            val issue = issuesById[item.issueId]
            if (issue != null && item.companyId.isBlank()) {
                item.copy(
                    companyId = issue.companyId,
                    projectContextId = item.projectContextId ?: issue.projectContextId
                )
            } else {
                item
            }
        }
        val reviewQueueIds = normalizedReviewQueue
            .filter { it.companyId in companyIds && it.issueId in issueIds }
            .mapTo(linkedSetOf()) { it.id }
        val runIds = state.runs.mapTo(linkedSetOf()) { it.id }
        val taskIds = state.tasks.mapTo(linkedSetOf()) { it.id }
        val agentIds = state.companyAgentDefinitions
            .filter { it.companyId in companyIds }
            .mapTo(linkedSetOf()) { it.id }

        fun validGoalRef(goalId: String?): Boolean = goalId == null || goalId in goalIds
        fun validIssueRef(issueId: String?): Boolean = issueId == null || issueId in issueIds
        fun validProjectRef(projectContextId: String?): Boolean =
            projectContextId == null || projectContextId in projectContextIds

        val runtime = state.runtime.takeIf { it.companyId == null || it.companyId in companyIds }
            ?: CompanyRuntimeSnapshot()

        return state.copy(
            projectContexts = state.projectContexts.filter { it.companyId in companyIds },
            companyAgentDefinitions = state.companyAgentDefinitions.filter { it.companyId in companyIds },
            agentCapabilityProfiles = state.agentCapabilityProfiles.filter { it.companyId in companyIds },
            goals = goals,
            issues = issues,
            issueDependencies = state.issueDependencies.filter {
                it.issueId in issueIds && it.dependsOnIssueId in issueIds
            },
            orgProfiles = state.orgProfiles.filter { it.companyId in companyIds },
            workflowTopologies = state.workflowTopologies.filter { it.companyId in companyIds },
            goalDecisions = state.goalDecisions.mapNotNull { decision ->
                if (
                    decision.companyId !in companyIds ||
                    !validGoalRef(decision.goalId) ||
                    !validIssueRef(decision.issueId)
                ) {
                    null
                } else {
                    decision.copy(createdIssues = decision.createdIssues.filter { it in issueIds })
                }
            },
            reviewQueue = normalizedReviewQueue.filter {
                it.companyId in companyIds && it.issueId in issueIds
            },
            companyActivity = state.companyActivity.filter {
                it.companyId in companyIds &&
                    validProjectRef(it.projectContextId) &&
                    validGoalRef(it.goalId) &&
                    validIssueRef(it.issueId)
            },
            signals = state.signals.filter {
                (it.companyId == null || it.companyId in companyIds) &&
                    validProjectRef(it.projectContextId) &&
                    validGoalRef(it.goalId) &&
                    validIssueRef(it.issueId)
            },
            runtime = runtime,
            companyRuntimes = state.companyRuntimes.filter { it.companyId in companyIds },
            workflowPipelines = state.workflowPipelines.filter { it.companyId in companyIds },
            agentContextEntries = state.agentContextEntries.filter {
                it.companyId in companyIds &&
                    validGoalRef(it.goalId) &&
                    validIssueRef(it.issueId)
            },
            agentMessages = state.agentMessages.filter {
                it.companyId in companyIds &&
                    validGoalRef(it.goalId) &&
                    validIssueRef(it.issueId)
            },
            marketingDelegationPolicies = state.marketingDelegationPolicies.filter {
                it.companyId in companyIds && it.agentId in agentIds
            },
            marketingRuns = state.marketingRuns.filter {
                it.companyId in companyIds && it.agentId in agentIds
            },
            skillRuns = state.skillRuns.filter {
                it.companyId in companyIds && it.agentId in agentIds
            },
            companyRuntimeWorkItems = state.companyRuntimeWorkItems.filter {
                it.companyId in companyIds &&
                    validGoalRef(it.goalId) &&
                    it.issueId in issueIds &&
                    (it.activeTaskId == null || it.activeTaskId in taskIds)
            },
            problemSignals = state.problemSignals.filter {
                it.companyId in companyIds &&
                    validProjectRef(it.projectContextId) &&
                    validGoalRef(it.goalId) &&
                    validIssueRef(it.issueId) &&
                    validGoalRef(it.triageGoalId) &&
                    (it.reviewQueueItemId == null || it.reviewQueueItemId in reviewQueueIds) &&
                    (it.runId == null || it.runId in runIds)
            }
        )
    }

    private fun compactStateForPersistence(state: DesktopAppState): DesktopAppState =
        state.run {
            val unresolvedIssueIds = issues
                .filter { it.status != IssueStatus.DONE && it.status != IssueStatus.CANCELED }
                .mapTo(linkedSetOf()) { it.id }
            val recentResolvedIssueIds = issues
                .filter { it.status == IssueStatus.DONE || it.status == IssueStatus.CANCELED }
                .sortedByDescending { it.updatedAt }
                .take(MAX_PERSISTED_RESOLVED_ISSUES)
                .mapTo(linkedSetOf()) { it.id }
            val latestRetainedTaskIds = tasks
                .filter { task -> task.issueId != null && task.issueId in recentResolvedIssueIds }
                .groupBy { it.issueId!! }
                .values
                .mapNotNull { issueTasks -> issueTasks.maxByOrNull { it.updatedAt }?.id }
                .toSet()
            val retainedTasks = tasks.filter { task ->
                task.issueId == null ||
                    task.status == DesktopTaskStatus.RUNNING ||
                    task.status == DesktopTaskStatus.QUEUED ||
                    task.issueId in unresolvedIssueIds ||
                    task.id in latestRetainedTaskIds
            }
            val retainedTaskIds = retainedTasks.mapTo(linkedSetOf()) { it.id }
            val unresolvedTaskIds = retainedTasks
                .filter { task ->
                    task.issueId in unresolvedIssueIds ||
                        task.status == DesktopTaskStatus.RUNNING ||
                        task.status == DesktopTaskStatus.QUEUED
                }
                .mapTo(linkedSetOf()) { it.id }
            val retainedRuns = runs
                .groupBy { it.taskId }
                .flatMap { (taskId, taskRuns) ->
                    if (taskId !in retainedTaskIds) {
                        emptyList()
                    } else {
                        val task = retainedTasks.firstOrNull { it.id == taskId }
                        if (task?.issueId in unresolvedIssueIds || task?.status == DesktopTaskStatus.RUNNING || task?.status == DesktopTaskStatus.QUEUED) {
                            taskRuns
                        } else {
                            listOfNotNull(taskRuns.maxByOrNull { it.updatedAt })
                        }
                    }
                }
            val retainedReviewQueueIssueIds = linkedSetOf<String>().also {
                it += unresolvedIssueIds
                it += recentResolvedIssueIds
            }
            copy(
                tasks = retainedTasks.map { compactTaskForPersistence(it, unresolvedIssueIds) },
                runs = retainedRuns.map { compactRunForPersistence(it, unresolvedTaskIds) },
                reviewQueue = reviewQueue.filter { it.issueId in retainedReviewQueueIssueIds },
                companyActivity = companyActivity.sortedByDescending { it.createdAt }.take(200),
                signals = signals.sortedByDescending { it.createdAt }.take(150),
                goalDecisions = goalDecisions.sortedByDescending { it.createdAt }.take(150),
                marketingRuns = marketingRuns.sortedByDescending { it.createdAt }.take(200),
                skillRuns = skillRuns.sortedByDescending { it.updatedAt }.take(200),
                problemSignals = problemSignals.sortedByDescending { it.updatedAt }.take(200)
            )
        }

    private fun normalizeLegacyCompanyRuntimeState(state: DesktopAppState): DesktopAppState =
        state.copy(
            runtime = state.runtime.withNormalizedStopIntent(),
            companyRuntimes = state.companyRuntimes.map { runtime ->
                runtime.withNormalizedStopIntent()
            }
        )

    private fun compactTaskForPersistence(task: AgentTask, unresolvedIssueIds: Set<String>): AgentTask {
        if (
            task.status == DesktopTaskStatus.RUNNING ||
            task.status == DesktopTaskStatus.QUEUED ||
            task.issueId in unresolvedIssueIds
        ) {
            return task
        }
        return task.copy(
            prompt = compactRequiredText(task.prompt, MAX_PERSISTED_TASK_PROMPT_CHARS),
            plan = null
        )
    }

    private fun compactRunForPersistence(run: AgentRun, unresolvedTaskIds: Set<String>): AgentRun =
        if (
            run.taskId in unresolvedTaskIds ||
            run.status == AgentRunStatus.RUNNING ||
            run.status == AgentRunStatus.QUEUED
        ) {
            run
        } else {
            run.copy(output = compactText(run.output, MAX_PERSISTED_RUN_OUTPUT_CHARS))
        }

    private fun compactText(value: String?, maxChars: Int): String? {
        val text = value ?: return null
        if (text.length <= maxChars) {
            return text
        }
        val omittedChars = text.length - maxChars
        return buildString {
            append(text.take(maxChars))
            append("\n\n[compacted ")
            append(omittedChars)
            append(" chars]")
        }
    }

    private fun compactRequiredText(value: String, maxChars: Int): String =
        compactText(value, maxChars) ?: value
}

internal fun stateTempFilesToClean(
    directory: Path,
    nowMillis: Long = System.currentTimeMillis(),
    minAgeMillis: Long = 60_000L
): List<Path> {
    if (!directory.exists()) {
        return emptyList()
    }
    val stream = Files.list(directory)
    return try {
        stream
            .filter { Files.isRegularFile(it) }
            .filter { STATE_TEMP_FILE_REGEX.matches(it.fileName.toString()) }
            .filter { tempFile ->
                val modifiedAt = runCatching { Files.getLastModifiedTime(tempFile).toMillis() }.getOrDefault(nowMillis)
                nowMillis - modifiedAt >= minAgeMillis
            }
            .toList()
            .sortedBy { it.fileName.toString() }
    } finally {
        stream.close()
    }
}

private val STATE_TEMP_FILE_REGEX = Regex("""state\.json(?:\.bak)?\.[^.]+\.tmp""")

/**
 * Desktop data lives under the conventional macOS Application Support location
 * so it behaves like a native app instead of leaving metadata in arbitrary repos.
 */
fun defaultDesktopAppHome(): Path {
    val overriddenHome = sequenceOf(
        System.getProperty("cotor.desktop.app.home"),
        System.getenv("COTOR_DESKTOP_APP_HOME"),
        System.getenv("COTOR_APP_HOME")
    )
        .mapNotNull { it?.trim()?.takeIf(String::isNotBlank) }
        .map { java.nio.file.Paths.get(it).toAbsolutePath().normalize() }
        .firstOrNull()
    if (overriddenHome != null) {
        return overriddenHome
    }
    val userHome = java.nio.file.Paths.get(System.getProperty("user.home")).toAbsolutePath().normalize()
    return userHome
        .resolve("Library")
        .resolve("Application Support")
        .resolve("CotorDesktop")
}
