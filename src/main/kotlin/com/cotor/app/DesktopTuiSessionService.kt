package com.cotor.app

/**
 * File overview for DesktopTuiSessionService.
 *
 * This file belongs to the app layer for the desktop shell and localhost app-server surface.
 * It groups declarations around desktop tui session service so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import com.cotor.data.config.ConfigRepository
import com.cotor.data.config.YamlParser
import com.cotor.data.process.destroyProcessTree
import com.cotor.model.AgentConfig
import com.cotor.model.CotorConfig
import com.cotor.storage.writeTextAtomically
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.slf4j.Logger
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.io.path.createDirectories
import kotlin.io.path.exists
import kotlin.io.path.setPosixFilePermissions

/**
 * Manages long-lived interactive TUI sessions for the native desktop shell.
 *
 * The CLI already has a real `cotor interactive` loop. This service runs that
 * loop inside a pseudo-terminal by delegating to macOS `script`, then exposes
 * the raw terminal stream as snapshot/delta APIs for the desktop terminal view.
 */
class DesktopTuiSessionService(
    private val stateStore: DesktopStateStore,
    private val configRepository: ConfigRepository,
    private val yamlParser: YamlParser,
    private val logger: Logger,
    private val ptyBridgeExecutable: String = "/usr/bin/python3"
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val sessions = ConcurrentHashMap<String, RuntimeSession>()
    private val failedSessions = ConcurrentHashMap<String, TuiSession>()
    private val workspaceSessions = ConcurrentHashMap<String, String>()

    suspend fun openSession(workspaceId: String, preferredAgent: String? = null): TuiSession {
        workspaceSessions[workspaceId]?.let { existingId ->
            val existing = sessions[existingId]
            if (existing != null && existing.process.isAlive && shouldReuse(existing.session, preferredAgent)) {
                return existing.snapshot()
            }
            val failed = failedSessions.remove(existingId)
            if (failed != null) {
                workspaceSessions.remove(workspaceId, existingId)
            }
            if (existing != null) {
                destroyProcessTree(existing.process, graceMillis = 1_500)
                sessions.remove(existingId)
                workspaceSessions.remove(workspaceId, existingId)
            }
        }

        val state = stateStore.load()
        val workspace = state.workspaces.firstOrNull { it.id == workspaceId }
            ?: throw IllegalArgumentException("Workspace not found: $workspaceId")
        val repository = state.repositories.firstOrNull { it.id == workspace.repositoryId }
            ?: throw IllegalArgumentException("Repository not found for workspace: ${workspace.repositoryId}")

        val now = System.currentTimeMillis()
        val runtimeRoot = stateStore.appHome().resolve("runtime").resolve("tui").resolve(UUID.randomUUID().toString())
        val sessionHome = runtimeRoot.resolve("home")
        val transcriptDir = runtimeRoot.resolve("transcript")
        val selectedAgent = resolveInteractiveAgent(
            repositoryRoot = Path.of(repository.localPath),
            preferredAgent = preferredAgent
        )
        val session = TuiSession(
            id = UUID.randomUUID().toString(),
            workspaceId = workspace.id,
            repositoryId = repository.id,
            repositoryPath = repository.localPath,
            agentName = selectedAgent.name,
            baseBranch = workspace.baseBranch,
            status = TuiSessionStatus.STARTING,
            transcript = "",
            createdAt = now,
            updatedAt = now
        )
        val isolatedConfigPath = runCatching {
            writeIsolatedConfig(runtimeRoot, selectedAgent)
        }.getOrElse { error ->
            if (error is CancellationException) throw error
            return rememberFailedTuiSession(session, listOf("desktop-tui-config"), error)
        }

        val ptyBridgePath = runCatching {
            materializePtyBridge(runtimeRoot)
        }.getOrElse { error ->
            if (error is CancellationException) throw error
            return rememberFailedTuiSession(session, listOf("desktop-tui-pty-bridge"), error)
        }
        val ptyCommand = buildPtyCommand(
            bridgePath = ptyBridgePath,
            configPath = isolatedConfigPath,
            activeAgent = selectedAgent.name,
            sessionHome = sessionHome,
            transcriptDir = transcriptDir
        )
        val process = runCatching {
            ProcessBuilder(ptyCommand)
            .directory(Path.of(repository.localPath).toFile())
            .apply {
                // Present a real terminal environment so JLine and Mordant can
                // enable interactive editing, ANSI styling, and prompt redraws.
                environment()["TERM"] = "xterm-256color"
                environment()["COTOR_DESKTOP_TUI"] = "1"
                environment()["PATH"] = buildDesktopCliPath(environment()["PATH"])
                // The interactive loop already prints user-facing failures, so
                // suppress backend stack traces that would otherwise flood xterm.
                environment()["COTOR_LOG_LEVEL"] = "ERROR"
            }
            .start()
        }.getOrElse { error ->
            if (error is CancellationException) throw error
            return rememberFailedTuiSession(session, ptyCommand, error)
        }

        val runtime = RuntimeSession(
            session = session.copy(processId = process.pid(), status = TuiSessionStatus.RUNNING),
            process = process,
            stdin = process.outputStream
        )

        sessions[runtime.session.id] = runtime
        workspaceSessions[workspace.id] = runtime.session.id

        startReader(runtime, process.inputStream)
        startReader(runtime, process.errorStream)
        watchProcess(runtime)

        return runtime.snapshot()
    }

    suspend fun getSession(sessionId: String): TuiSession {
        sessions[sessionId]?.let { return it.snapshot() }
        failedSessions[sessionId]?.let { return it }
        throw IllegalArgumentException("TUI session not found: $sessionId")
    }

    suspend fun listSessions(): List<TuiSession> =
        (sessions.values.map { it.snapshot() } + failedSessions.values)
            .sortedByDescending { it.updatedAt }

    suspend fun getDelta(sessionId: String, offset: Long): TuiSessionDelta {
        sessions[sessionId]?.let { return it.delta(offset) }
        failedSessions[sessionId]?.let { return failedSessionDelta(it, offset) }
        throw IllegalArgumentException("TUI session not found: $sessionId")
    }

    suspend fun sendInput(sessionId: String, input: String): TuiSession {
        failedSessions[sessionId]?.let {
            throw IllegalStateException("TUI session failed to start")
        }
        val session = sessions[sessionId] ?: throw IllegalArgumentException("TUI session not found: $sessionId")
        if (!session.process.isAlive) {
            throw IllegalStateException("TUI session is no longer running")
        }

        if (input.isEmpty()) {
            return session.snapshot()
        }

        session.mutex.withLock {
            session.stdin.write(input.toByteArray(StandardCharsets.UTF_8))
            session.stdin.flush()
        }

        return session.snapshot()
    }

    suspend fun terminateSession(sessionId: String): TuiSession {
        failedSessions.remove(sessionId)?.let { failed ->
            workspaceSessions.remove(failed.workspaceId, sessionId)
            return failed
        }
        val session = sessions[sessionId] ?: throw IllegalArgumentException("TUI session not found: $sessionId")
        terminateRuntimeSession(session)
        val exitCode = runCatching { session.process.exitValue() }.getOrDefault(0)
        session.updateStatus(TuiSessionStatus.EXITED, exitCode)
        sessions.remove(sessionId, session)
        workspaceSessions.remove(session.session.workspaceId, sessionId)
        return session.snapshot()
    }

    fun shutdown() {
        val activeSessions = sessions.values.toList()
        sessions.clear()
        failedSessions.clear()
        workspaceSessions.clear()
        activeSessions.forEach(::terminateRuntimeSession)
        scope.cancel()
    }

    private fun startReader(session: RuntimeSession, stream: InputStream) {
        scope.launch {
            runCatching {
                stream.use { input ->
                    val buffer = ByteArray(4096)
                    while (true) {
                        val count = input.read(buffer)
                        if (count == -1) {
                            break
                        }
                        session.append(String(buffer, 0, count, StandardCharsets.UTF_8).replace("\u0000", ""))
                    }
                }
            }.onFailure { error ->
                if (error is CancellationException) {
                    logger.debug("TUI session reader cancelled")
                } else if (error is IOException && !session.process.isAlive) {
                    logger.debug("TUI session reader closed after process exit")
                } else {
                    logger.warn("TUI session reader failed", error)
                }
            }
        }
    }

    private fun watchProcess(session: RuntimeSession) {
        scope.launch {
            val exitCode = runCatching { session.process.waitFor() }.getOrElse {
                logger.warn("TUI session watcher failed", it)
                -1
            }

            session.mutex.withLock {
                runCatching { session.stdin.close() }
            }

            val nextStatus = if (isExpectedTuiExit(exitCode)) TuiSessionStatus.EXITED else TuiSessionStatus.FAILED
            session.updateStatus(nextStatus, exitCode)
            sessions.remove(session.session.id, session)
            workspaceSessions.remove(session.session.workspaceId, session.session.id)
        }
    }

    private fun terminateRuntimeSession(session: RuntimeSession) {
        runCatching {
            session.mutex.tryLock().let { locked ->
                if (locked) {
                    try {
                        session.stdin.close()
                    } finally {
                        session.mutex.unlock()
                    }
                } else {
                    session.stdin.close()
                }
            }
        }

        val process = session.process
        if (process.isAlive) {
            destroyProcessTree(process, graceMillis = 1_500)
        }
    }

    private fun buildPtyCommand(
        bridgePath: Path,
        configPath: Path,
        activeAgent: String,
        sessionHome: Path,
        transcriptDir: Path
    ): List<String> {
        // The desktop shell needs a true PTY master, not a buffered wrapper.
        // A tiny Python bridge keeps keypresses and ANSI redraws much closer to
        // the raw terminal semantics expected by JLine.
        return listOf(ptyBridgeExecutable, bridgePath.toString(), "--") + buildCommand(
            configPath = configPath,
            activeAgent = activeAgent,
            sessionHome = sessionHome,
            transcriptDir = transcriptDir
        )
    }

    private fun buildCommand(
        configPath: Path,
        activeAgent: String,
        sessionHome: Path,
        transcriptDir: Path
    ): List<String> {
        val javaBinary = Path.of(System.getProperty("java.home"), "bin", "java").toString()
        val classpath = System.getProperty("java.class.path")
            ?.takeIf { it.isNotBlank() }
            ?: throw IllegalStateException("java.class.path is not available for TUI session launch")

        // Reuse the already running application classpath so the desktop server can
        // launch the exact same interactive command whether it was started by Gradle
        // during development or from the packaged app bundle in production.
        return listOf(
            javaBinary,
            "-Dfile.encoding=UTF-8",
            // Point only the child JVM at an empty HOME-equivalent so `interactive`
            // does not merge arbitrary `~/.cotor` overrides into the desktop TUI.
            "-Duser.home=${sessionHome.toAbsolutePath()}",
            "-cp",
            classpath,
            "com.cotor.MainKt",
            "interactive",
            "--config",
            configPath.toString(),
            "--mode",
            "single",
            "--agent",
            activeAgent,
            "--agents",
            activeAgent,
            "--save-dir",
            transcriptDir.toString()
        )
    }

    private suspend fun resolveInteractiveAgent(repositoryRoot: Path, preferredAgent: String?): AgentConfig {
        val configuredAgents = loadConfiguredAgents(repositoryRoot)
        val configuredByName = configuredAgents.associateBy { it.name.lowercase() }
        val preferred = preferredAgent?.trim()?.lowercase()?.takeIf { it.isNotBlank() }

        // Prefer the explicitly selected lead agent first, then fall back to the
        // desktop-safe roster order that biases toward the best-supported CLIs.
        val candidateNames = buildList {
            preferred?.let(::add)
            addAll(DEFAULT_TUI_AGENT_PRIORITY.filterNot { it == preferred })
        }

        candidateNames.forEach { candidate ->
            configuredByName[candidate]?.let { return it }
            resolveBuiltinInteractiveAgent(candidate)?.let { return it }
        }

        return configuredAgents.firstOrNull()
            ?: resolveBuiltinInteractiveAgent("echo")
            ?: throw IllegalStateException("No desktop-compatible interactive agent is available")
    }

    private suspend fun loadConfiguredAgents(repositoryRoot: Path): List<AgentConfig> {
        val configPath = supportedConfigPaths(repositoryRoot).firstOrNull { it.exists() } ?: return emptyList()
        return runCatching { configRepository.loadConfig(configPath).agents }
            .getOrElse { error ->
                logger.warn("Failed to load repository config for desktop TUI from {}", configPath, error)
                emptyList()
            }
    }

    private fun resolveBuiltinInteractiveAgent(name: String): AgentConfig? {
        if (!commandAvailability(name)) {
            return null
        }
        return BuiltinAgentCatalog.get(name)
    }

    private fun commandAvailability(agentName: String): Boolean {
        if (agentName.equals("echo", ignoreCase = true)) {
            return true
        }
        val executable = when (agentName.lowercase()) {
            "codex-exec", "codex-oauth" -> "codex"
            "cursor" -> "cursor-cli"
            else -> agentName.lowercase()
        }
        val path = buildDesktopCliPath(System.getenv("PATH"))
        return path.split(java.io.File.pathSeparator)
            .any { dir ->
                val file = java.io.File(dir, executable)
                file.exists() && file.canExecute()
            }
    }

    private fun buildDesktopCliPath(existingPath: String?): String {
        val preferredDirs = listOf(
            System.getenv("HOME")?.let { "$it/.local/bin" },
            System.getenv("HOME")?.let { "$it/.opencode/bin" },
            System.getenv("HOME")?.let { "$it/.cargo/bin" },
            System.getenv("HOME")?.let { "$it/bin" },
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            existingPath
        )

        return preferredDirs
            .flatMap { value ->
                value
                    ?.split(java.io.File.pathSeparator)
                    ?.filter { it.isNotBlank() }
                    ?: emptyList()
            }
            .distinct()
            .joinToString(java.io.File.pathSeparator)
    }

    private fun supportedConfigPaths(repositoryRoot: Path): List<Path> {
        return listOf(
            repositoryRoot.resolve("cotor.yaml"),
            repositoryRoot.resolve("cotor.yml")
        )
    }

    private fun writeIsolatedConfig(runtimeRoot: Path, agent: AgentConfig): Path {
        runtimeRoot.createDirectories()
        runtimeRoot.resolve("home").resolve(".cotor").createDirectories()
        runtimeRoot.resolve("transcript").createDirectories()

        // Only persist the chosen lead agent so the embedded TUI cannot accidentally
        // fan out into every globally registered CLI just because the machine has
        // extra `~/.cotor/agents/*.yaml` files.
        val isolatedConfig = CotorConfig(
            agents = listOf(agent),
            pipelines = emptyList()
        )
        val configPath = runtimeRoot.resolve("desktop-tui.yaml")
        writeTextAtomically(configPath, yamlParser.serialize(isolatedConfig))
        return configPath
    }

    private fun materializePtyBridge(runtimeRoot: Path): Path {
        val bridgeTarget = runtimeRoot.resolve("pty_bridge.py")
        if (bridgeTarget.exists()) {
            return bridgeTarget
        }

        val resource = javaClass.getResourceAsStream("/desktop/pty_bridge.py")
            ?: throw IllegalStateException("Missing PTY bridge resource: /desktop/pty_bridge.py")

        resource.use { input ->
            Files.copy(input, bridgeTarget, StandardCopyOption.REPLACE_EXISTING)
        }
        runCatching {
            bridgeTarget.setPosixFilePermissions(
                setOf(
                    java.nio.file.attribute.PosixFilePermission.OWNER_READ,
                    java.nio.file.attribute.PosixFilePermission.OWNER_WRITE,
                    java.nio.file.attribute.PosixFilePermission.OWNER_EXECUTE
                )
            )
        }
        return bridgeTarget
    }

    private fun shouldReuse(session: TuiSession, preferredAgent: String?): Boolean {
        val requested = preferredAgent?.trim()?.lowercase()?.takeIf { it.isNotBlank() } ?: return true
        return session.agentName.equals(requested, ignoreCase = true)
    }

    private fun rememberFailedTuiSession(session: TuiSession, command: List<String>, error: Throwable): TuiSession {
        val failed = failedTuiSession(session, command, error)
        failedSessions[failed.id] = failed
        workspaceSessions[failed.workspaceId] = failed.id
        logger.warn("Failed to start desktop TUI session {}", failed.id, error)
        return failed
    }

    private fun failedTuiSession(session: TuiSession, command: List<String>, error: Throwable): TuiSession {
        val now = System.currentTimeMillis()
        val executable = command.firstOrNull().orEmpty()
        val detail = error.message?.takeIf { it.isNotBlank() } ?: error::class.simpleName.orEmpty()
        val transcript = buildString {
            appendLine("Cotor desktop TUI failed to start.")
            appendLine("Command: $executable")
            append("Reason: $detail")
        }
        return session.copy(
            status = TuiSessionStatus.FAILED,
            transcript = transcript,
            transcriptStartOffset = 0,
            transcriptEndOffset = transcript.length.toLong(),
            exitCode = if (detail.contains("Permission denied", ignoreCase = true)) 126 else 127,
            updatedAt = now
        )
    }

    private fun failedSessionDelta(session: TuiSession, offset: Long): TuiSessionDelta {
        val endOffset = session.transcriptEndOffset
        val startOffset = session.transcriptStartOffset
        val mustReset = offset < startOffset || offset > endOffset
        val effectiveOffset = if (mustReset) startOffset else offset
        val relativeStart = (effectiveOffset - startOffset).toInt().coerceAtLeast(0)
        return TuiSessionDelta(
            sessionId = session.id,
            status = session.status,
            offset = effectiveOffset,
            nextOffset = endOffset,
            reset = mustReset,
            chunk = session.transcript.substring(relativeStart),
            exitCode = session.exitCode
        )
    }

    private class RuntimeSession(
        var session: TuiSession,
        val process: Process,
        val stdin: OutputStream
    ) {
        val mutex = Mutex()
        private val transcriptBuffer = StringBuilder(session.transcript)
        private var bufferStartOffset = session.transcriptStartOffset
        private var bufferEndOffset = session.transcriptEndOffset

        suspend fun append(text: String) {
            if (text.isEmpty()) {
                return
            }

            mutex.withLock {
                transcriptBuffer.append(text)
                bufferEndOffset += text.length
                if (transcriptBuffer.length > MAX_TRANSCRIPT_CHARS) {
                    val removed = transcriptBuffer.length - MAX_TRANSCRIPT_CHARS
                    transcriptBuffer.delete(0, removed)
                    bufferStartOffset += removed.toLong()
                }
                session = session.copy(
                    transcript = transcriptBuffer.toString(),
                    transcriptStartOffset = bufferStartOffset,
                    transcriptEndOffset = bufferEndOffset,
                    updatedAt = System.currentTimeMillis()
                )
            }
        }

        suspend fun snapshot(): TuiSession = mutex.withLock { session }

        suspend fun delta(offset: Long): TuiSessionDelta = mutex.withLock {
            val current = session
            val startOffset = bufferStartOffset
            val endOffset = bufferEndOffset
            val mustReset = offset < startOffset || offset > endOffset
            val effectiveOffset = if (mustReset) startOffset else offset
            val relativeStart = (effectiveOffset - startOffset).toInt().coerceAtLeast(0)
            val chunk = transcriptBuffer.substring(relativeStart)

            TuiSessionDelta(
                sessionId = current.id,
                status = current.status,
                offset = effectiveOffset,
                nextOffset = endOffset,
                reset = mustReset,
                chunk = chunk,
                exitCode = current.exitCode
            )
        }

        suspend fun updateStatus(status: TuiSessionStatus, exitCode: Int?) {
            mutex.withLock {
                session = session.copy(
                    status = status,
                    exitCode = exitCode,
                    updatedAt = System.currentTimeMillis()
                )
            }
        }
    }

    private companion object {
        private const val MAX_TRANSCRIPT_CHARS = 400_000
        private val DEFAULT_TUI_AGENT_PRIORITY = listOf(
            "codex",
            "claude",
            "gemini",
            "copilot",
            "qwen",
            "cursor",
            "opencode",
            "echo"
        )

        private fun isExpectedTuiExit(exitCode: Int): Boolean =
            exitCode == 0 || exitCode == 130 || exitCode == 143
    }
}
