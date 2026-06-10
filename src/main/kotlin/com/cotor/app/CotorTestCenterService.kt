package com.cotor.app

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

private const val TEST_CENTER_STATUS_PENDING = "PENDING"
private const val TEST_CENTER_STATUS_RUNNING = "RUNNING"
private const val TEST_CENTER_STATUS_PASSED = "PASSED"
private const val TEST_CENTER_STATUS_FAILED = "FAILED"
private const val TEST_CENTER_STATUS_SKIPPED = "SKIPPED"
private const val TEST_CENTER_OUTPUT_LIMIT = 40_000
private const val TEST_CENTER_STEP_TIMEOUT_MS = 20 * 60 * 1_000L

/**
 * Runs the desktop Test Center's local, predefined validation steps for a company.
 *
 * The service intentionally does not accept arbitrary commands from the client. It
 * detects known project test surfaces from the selected company root and executes
 * those local commands with bounded output and timeout handling.
 */
class CotorTestCenterService(
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
    private val now: () -> Long = { System.currentTimeMillis() },
    private val stepTimeoutMs: Long = TEST_CENTER_STEP_TIMEOUT_MS
) {
    private val sessions = ConcurrentHashMap<String, MutableTestCenterSession>()
    private val lock = Any()

    fun plan(company: Company, suiteId: String = DEFAULT_SUITE): TestCenterPlanRecord {
        val root = Path.of(company.rootPath).toAbsolutePath().normalize()
        return buildPlan(company.id, root, suiteId)
    }

    fun listSessions(companyId: String): List<TestCenterSessionRecord> =
        sessions.values
            .filter { it.companyId == companyId }
            .map { it.toRecord() }
            .sortedByDescending { it.createdAt }

    fun getSession(sessionId: String): TestCenterSessionRecord? =
        sessions[sessionId]?.toRecord()

    fun startSession(company: Company, suiteId: String = DEFAULT_SUITE): TestCenterSessionRecord {
        val root = Path.of(company.rootPath).toAbsolutePath().normalize()
        val plan = buildPlan(company.id, root, suiteId)
        val session = MutableTestCenterSession(
            id = UUID.randomUUID().toString(),
            companyId = company.id,
            rootPath = root.toString(),
            suiteId = plan.suiteId,
            status = TEST_CENTER_STATUS_PENDING,
            progress = 0.0,
            steps = plan.steps,
            createdAt = now(),
            summary = "Queued ${plan.steps.size} local validation step(s)."
        )
        sessions[session.id] = session
        scope.launch {
            runSession(session.id)
        }
        return session.toRecord()
    }

    fun shutdown() {
        scope.cancel()
    }

    private fun buildPlan(companyId: String, root: Path, requestedSuiteId: String): TestCenterPlanRecord {
        val warnings = mutableListOf<String>()
        val detectedSteps = if (Files.isDirectory(root)) {
            detectSteps(root, warnings)
        } else {
            warnings += "Company root does not exist or is not a directory: $root"
            emptyList()
        }
        val availableSuites = availableSuites(detectedSteps)
        val suiteId = normalizeSuiteId(requestedSuiteId, availableSuites)
        val selectedSteps = selectSuiteSteps(suiteId, detectedSteps)
            .ifEmpty {
                listOf(
                    TestCenterStepRecord(
                        id = "scan",
                        title = "Project scan",
                        detail = "No supported local test command was detected for this suite.",
                        command = "",
                        status = TEST_CENTER_STATUS_SKIPPED
                    )
                )
            }
        return TestCenterPlanRecord(
            companyId = companyId,
            rootPath = root.toString(),
            suiteId = suiteId,
            availableSuites = availableSuites,
            steps = selectedSteps,
            warnings = warnings,
            generatedAt = now()
        )
    }

    private fun detectSteps(root: Path, warnings: MutableList<String>): List<TestCenterStepRecord> {
        val steps = mutableListOf<TestCenterStepRecord>()
        val gradleWrapper = root.resolve("gradlew")
        if (Files.isRegularFile(gradleWrapper)) {
            steps += TestCenterStepRecord(
                id = "kotlin-gradle-test",
                title = "Kotlin test suite",
                detail = "Runs the repository Gradle tests with coverage report tasks disabled for faster desktop feedback.",
                command = "./gradlew",
                args = listOf("test", "-x", "jacocoTestReport", "-x", "jacocoTestCoverageVerification")
            )
        } else if (Files.isRegularFile(root.resolve("build.gradle.kts")) || Files.isRegularFile(root.resolve("build.gradle"))) {
            warnings += "Gradle build files are present, but no ./gradlew wrapper was found. Test Center skips system Gradle to keep runs reproducible."
        }

        val macosPackage = root.resolve("macos").resolve("Package.swift")
        if (Files.isRegularFile(macosPackage)) {
            steps += TestCenterStepRecord(
                id = "desktop-swift-build",
                title = "Desktop Swift build",
                detail = "Builds the native macOS desktop shell package.",
                command = "swift",
                args = listOf("build", "--package-path", "macos")
            )
        }

        val rootPackage = root.resolve("Package.swift")
        if (Files.isRegularFile(rootPackage) && !Files.isRegularFile(macosPackage)) {
            steps += TestCenterStepRecord(
                id = "swift-build",
                title = "Swift package build",
                detail = "Builds the Swift package at the company root.",
                command = "swift",
                args = listOf("build")
            )
        }

        return steps
    }

    private fun availableSuites(steps: List<TestCenterStepRecord>): List<String> {
        val suites = mutableListOf(DEFAULT_SUITE)
        if (steps.any { it.id.startsWith("kotlin-") }) suites += "kotlin"
        if (steps.any { it.id.startsWith("desktop-") || it.id.startsWith("swift-") }) suites += "desktop"
        if (steps.size > 1) suites += "full"
        return suites.distinct()
    }

    private fun normalizeSuiteId(requestedSuiteId: String, availableSuites: List<String>): String {
        val candidate = requestedSuiteId.trim().lowercase().ifBlank { DEFAULT_SUITE }
        return if (candidate in availableSuites) candidate else DEFAULT_SUITE
    }

    private fun selectSuiteSteps(suiteId: String, steps: List<TestCenterStepRecord>): List<TestCenterStepRecord> =
        when (suiteId) {
            "kotlin" -> steps.filter { it.id.startsWith("kotlin-") }
            "desktop" -> steps.filter { it.id.startsWith("desktop-") || it.id.startsWith("swift-") }
            "full" -> steps
            else -> steps
        }

    private suspend fun runSession(sessionId: String) {
        val original = sessions[sessionId] ?: return
        updateSession(sessionId) {
            status = TEST_CENTER_STATUS_RUNNING
            startedAt = now()
            summary = "Running local validation."
        }
        original.steps.forEach { step ->
            if (step.command.isBlank()) {
                updateStep(sessionId, step.id) {
                    copy(
                        status = TEST_CENTER_STATUS_SKIPPED,
                        startedAt = now(),
                        completedAt = now(),
                        durationMs = 0,
                        output = detail
                    )
                }
                updateProgress(sessionId)
                return@forEach
            }
            val startedAt = now()
            updateStep(sessionId, step.id) {
                copy(status = TEST_CENTER_STATUS_RUNNING, startedAt = startedAt)
            }
            val result = runCatching {
                runCommand(Path.of(original.rootPath), step.command, step.args)
            }.getOrElse { error ->
                CommandResult(
                    exitCode = -1,
                    output = null,
                    error = error.message ?: error.javaClass.simpleName
                )
            }
            val completedAt = now()
            updateStep(sessionId, step.id) {
                copy(
                    status = if (result.exitCode == 0) TEST_CENTER_STATUS_PASSED else TEST_CENTER_STATUS_FAILED,
                    completedAt = completedAt,
                    durationMs = completedAt - startedAt,
                    exitCode = result.exitCode,
                    output = result.output,
                    error = result.error
                )
            }
            updateProgress(sessionId)
        }
        updateSession(sessionId) {
            val finishedAt = now()
            val failedCount = steps.count { it.status == TEST_CENTER_STATUS_FAILED }
            val passedCount = steps.count { it.status == TEST_CENTER_STATUS_PASSED }
            val skippedCount = steps.count { it.status == TEST_CENTER_STATUS_SKIPPED }
            status = if (failedCount == 0) TEST_CENTER_STATUS_PASSED else TEST_CENTER_STATUS_FAILED
            completedAt = finishedAt
            durationMs = (startedAt ?: createdAt).let { finishedAt - it }
            progress = 1.0
            summary = "$passedCount passed, $failedCount failed, $skippedCount skipped."
        }
    }

    private suspend fun runCommand(root: Path, command: String, args: List<String>): CommandResult =
        coroutineScope {
            val output = StringBuilder()
            val process = withContext(Dispatchers.IO) {
                ProcessBuilder(listOf(command) + args)
                    .directory(root.toFile())
                    .redirectErrorStream(true)
                    .start()
            }
            val outputReader = async(Dispatchers.IO) {
                process.inputStream.bufferedReader().useLines { lines ->
                    lines.forEach { line ->
                        appendBounded(output, "$line\n")
                    }
                }
            }
            val exitCode = withTimeoutOrNull(stepTimeoutMs) {
                withContext(Dispatchers.IO) {
                    process.waitFor()
                }
            }
            if (exitCode == null) {
                process.destroyForcibly()
                outputReader.await()
                CommandResult(
                    exitCode = -1,
                    output = output.toString(),
                    error = "Timed out after ${stepTimeoutMs / 1_000} seconds."
                )
            } else {
                outputReader.await()
                CommandResult(
                    exitCode = exitCode,
                    output = output.toString().ifBlank { null },
                    error = null
                )
            }
        }

    private fun updateStep(
        sessionId: String,
        stepId: String,
        transform: TestCenterStepRecord.() -> TestCenterStepRecord
    ) {
        updateSession(sessionId) {
            steps = steps.map { step ->
                if (step.id == stepId) step.transform() else step
            }
        }
    }

    private fun updateProgress(sessionId: String) {
        updateSession(sessionId) {
            val done = steps.count { it.status in terminalStatuses }
            progress = if (steps.isEmpty()) 1.0 else done.toDouble() / steps.size.toDouble()
        }
    }

    private fun updateSession(sessionId: String, transform: MutableTestCenterSession.() -> Unit) {
        synchronized(lock) {
            sessions[sessionId]?.transform()
        }
    }

    private fun appendBounded(output: StringBuilder, text: String) {
        val overflow = output.length + text.length - TEST_CENTER_OUTPUT_LIMIT
        if (overflow > 0) {
            if (overflow >= output.length) {
                output.clear()
            } else {
                output.delete(0, overflow)
            }
        }
        output.append(text)
    }

    private data class MutableTestCenterSession(
        val id: String,
        val companyId: String,
        val rootPath: String,
        val suiteId: String,
        var status: String,
        var progress: Double,
        var steps: List<TestCenterStepRecord>,
        val createdAt: Long,
        var startedAt: Long? = null,
        var completedAt: Long? = null,
        var durationMs: Long? = null,
        var summary: String = "",
        var error: String? = null
    ) {
        fun toRecord(): TestCenterSessionRecord = TestCenterSessionRecord(
            id = id,
            companyId = companyId,
            rootPath = rootPath,
            suiteId = suiteId,
            status = status,
            progress = progress,
            steps = steps,
            createdAt = createdAt,
            startedAt = startedAt,
            completedAt = completedAt,
            durationMs = durationMs,
            summary = summary,
            error = error
        )
    }

    private data class CommandResult(
        val exitCode: Int,
        val output: String?,
        val error: String?
    )

    companion object {
        const val DEFAULT_SUITE = "baseline"
        private val terminalStatuses = setOf(
            TEST_CENTER_STATUS_PASSED,
            TEST_CENTER_STATUS_FAILED,
            TEST_CENTER_STATUS_SKIPPED
        )
    }
}
