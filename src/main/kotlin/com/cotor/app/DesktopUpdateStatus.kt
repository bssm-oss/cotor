package com.cotor.app

import com.cotor.data.config.CotorProperties
import java.nio.file.Path
import java.nio.file.Paths
import java.util.concurrent.TimeUnit
import kotlin.io.path.exists
import kotlin.io.path.isDirectory

private const val COTOR_BREW_FORMULA = "bssm-oss/cotor/cotor"
private const val BUNDLED_DESKTOP_APP_NAME = "Cotor Desktop.app"
private const val UPDATE_STATUS_TIMEOUT_SECONDS = 8L
private const val UPDATE_STATUS_OUTPUT_LIMIT_CHARS = 16 * 1024

internal fun desktopUpdateStatusResponse(
    environment: Map<String, String> = System.getenv(),
    homeDirectoryProvider: () -> Path = {
        Paths.get(System.getProperty("user.home") ?: ".").toAbsolutePath().normalize()
    },
    commandRunner: (List<String>, Path?) -> UpdateStatusCommandResult = ::runUpdateStatusCommand
): DesktopUpdateStatusResponse {
    val health = appServerHealthResponse()
    val installedAppPath = resolveInstalledDesktopAppPath(environment, homeDirectoryProvider)
    val sourceCommit = resolveSourceCommit(commandRunner)
    val brewStatus = resolveBrewUpdateStatus(commandRunner)

    return DesktopUpdateStatusResponse(
        health = health,
        backendOwner = health.owner,
        currentVersion = CotorProperties.version,
        currentBuild = System.getProperty("cotor.build", CotorProperties.version),
        sourceCommit = sourceCommit,
        installedAppPath = installedAppPath?.toString(),
        brewFormula = COTOR_BREW_FORMULA,
        updateCommand = "cotor update --verify",
        updateAvailable = brewStatus.updateAvailable,
        latestVersion = brewStatus.latestVersion,
        latestCommit = null,
        checkedAtEpochMillis = System.currentTimeMillis(),
        status = brewStatus.status,
        message = brewStatus.message
    )
}

private data class BrewStatus(
    val updateAvailable: Boolean?,
    val latestVersion: String?,
    val status: String,
    val message: String
)

internal data class UpdateStatusCommandResult(
    val exitCode: Int,
    val output: String
)

private fun resolveBrewUpdateStatus(
    commandRunner: (List<String>, Path?) -> UpdateStatusCommandResult
): BrewStatus {
    val installed = commandRunner(listOf("/usr/bin/env", "brew", "list", "--versions", COTOR_BREW_FORMULA), null)
    if (installed.exitCode != 0) {
        return BrewStatus(
            updateAvailable = null,
            latestVersion = null,
            status = "UNKNOWN",
            message = "Homebrew formula is not installed or brew is unavailable."
        )
    }

    val outdated = commandRunner(listOf("/usr/bin/env", "brew", "outdated", "--formula", "--quiet", COTOR_BREW_FORMULA), null)
    val outdatedLines = outdated.output
        .lineSequence()
        .map { it.trim() }
        .filter { it.isNotEmpty() }
        .toList()
    if (outdatedLines.isNotEmpty()) {
        return BrewStatus(
            updateAvailable = true,
            latestVersion = null,
            status = "UPDATE_AVAILABLE",
            message = "A newer Homebrew formula is available. Run cotor update --verify."
        )
    }
    if (outdated.exitCode != 0) {
        return BrewStatus(
            updateAvailable = null,
            latestVersion = null,
            status = "UNKNOWN",
            message = "Could not check Homebrew update status."
        )
    }

    val installedVersion = installed.output.trim().ifBlank { COTOR_BREW_FORMULA }
    return BrewStatus(
        updateAvailable = false,
        latestVersion = null,
        status = "UP_TO_DATE",
        message = "Homebrew reports Cotor is up to date: $installedVersion"
    )
}

private fun resolveSourceCommit(
    commandRunner: (List<String>, Path?) -> UpdateStatusCommandResult
): String? {
    val cwd = Paths.get("").toAbsolutePath().normalize()
    if (!cwd.resolve(".git").exists()) {
        return null
    }
    val result = commandRunner(listOf("/usr/bin/env", "git", "rev-parse", "--short", "HEAD"), cwd)
    return result.output.trim().takeIf { result.exitCode == 0 && it.isNotBlank() }
}

private fun resolveInstalledDesktopAppPath(
    environment: Map<String, String>,
    homeDirectoryProvider: () -> Path
): Path? {
    environment["COTOR_DESKTOP_APP_PATH"]
        ?.takeIf { it.isNotBlank() }
        ?.let { Paths.get(it).toAbsolutePath().normalize() }
        ?.takeIf { it.isDirectory() }
        ?.let { return it }

    val candidates = buildList {
        environment["COTOR_DESKTOP_INSTALL_ROOT"]
            ?.takeIf { it.isNotBlank() }
            ?.let { add(Paths.get(it).toAbsolutePath().normalize().resolve(BUNDLED_DESKTOP_APP_NAME)) }
        add(Paths.get("/Applications").resolve(BUNDLED_DESKTOP_APP_NAME))
        add(homeDirectoryProvider().resolve("Applications").resolve(BUNDLED_DESKTOP_APP_NAME))
    }
    return candidates.firstOrNull { it.isDirectory() }
}

private fun runUpdateStatusCommand(command: List<String>, workingDirectory: Path?): UpdateStatusCommandResult {
    val process = runCatching {
        ProcessBuilder(command)
            .redirectErrorStream(true)
            .apply {
                workingDirectory?.let { directory(it.toFile()) }
            }
            .start()
    }.getOrElse { error ->
        return UpdateStatusCommandResult(127, error.message ?: error::class.simpleName.orEmpty())
    }

    val output = StringBuilder()
    val reader = Thread {
        runCatching {
            process.inputStream.bufferedReader().useLines { lines ->
                lines.forEach { line ->
                    if (output.length < UPDATE_STATUS_OUTPUT_LIMIT_CHARS) {
                        output.appendLine(line)
                    }
                }
            }
        }
    }
    reader.isDaemon = true
    reader.start()

    val finished = process.waitFor(UPDATE_STATUS_TIMEOUT_SECONDS, TimeUnit.SECONDS)
    if (!finished) {
        process.destroyForcibly()
        reader.join(500)
        return UpdateStatusCommandResult(124, "Command timed out: ${command.joinToString(" ")}")
    }
    reader.join(500)
    return UpdateStatusCommandResult(process.exitValue(), output.toString())
}
