package com.cotor.presentation.cli

import java.nio.file.Path
import java.nio.file.Paths
import kotlin.io.path.exists
import kotlin.io.path.isDirectory

private const val DEFAULT_DESKTOP_HEALTH_URL = "http://127.0.0.1:8787/health"
private const val DEFAULT_DESKTOP_SMOKE_TIMEOUT_SECONDS = 45L
private const val DESKTOP_VERIFICATION_OUTPUT_LIMIT_CHARS = 64 * 1024

internal fun runInstalledDesktopAppVerification(
    layout: DesktopInstallLayout,
    environment: Map<String, String> = System.getenv(),
    homeDirectoryProvider: () -> Path = {
        desktopInstallHomeDirectory(environment)
    }
): DesktopScriptResult {
    if (layout.kind == DesktopInstallLayoutKind.SOURCE_CHECKOUT) {
        val sourceScript = layout.root.resolve("shell").resolve("test-installed-desktop-app.sh")
        if (sourceScript.exists()) {
            return runDesktopScript(layout.root, "test-installed-desktop-app.sh")
        }
    }

    val appPath = resolveInstalledDesktopAppPath(environment, homeDirectoryProvider)
        ?: return DesktopScriptResult(
            exitCode = 1,
            output = buildString {
                appendLine("Missing installed Cotor Desktop bundle.")
                appendLine("Checked: /Applications/$BUNDLED_DESKTOP_APP_NAME and ${homeDirectoryProvider().resolve("Applications").resolve(BUNDLED_DESKTOP_APP_NAME)}")
            }
        )

    val healthUrl = environment["COTOR_DESKTOP_HEALTH_URL"]
        ?.takeIf { it.isNotBlank() }
        ?: DEFAULT_DESKTOP_HEALTH_URL
    val timeoutSeconds = environment["COTOR_DESKTOP_SMOKE_TIMEOUT_SECONDS"]
        ?.toLongOrNull()
        ?.coerceAtLeast(1)
        ?: DEFAULT_DESKTOP_SMOKE_TIMEOUT_SECONDS

    val output = StringBuilder()
    output.appendLine("Verifying installed Cotor Desktop bundle")
    output.appendLine("  App:    $appPath")
    output.appendLine("  Health: $healthUrl")

    val codesign = runVerificationCommand(
        listOf("/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", appPath.toString()),
        timeoutSeconds = 30
    )
    output.append(codesign.output)
    if (codesign.exitCode != 0) {
        return DesktopScriptResult(codesign.exitCode, output.toString())
    }

    if (environment["COTOR_DESKTOP_SKIP_LAUNCH"] != "1") {
        if (environment["COTOR_DESKTOP_SKIP_QUIT"] != "1") {
            val quit = runVerificationCommand(
                listOf("/usr/bin/osascript", "-e", "tell application \"Cotor Desktop\" to quit"),
                timeoutSeconds = 10
            )
            if (quit.output.isNotBlank()) {
                output.append(quit.output)
            }
            Thread.sleep(1_000)
        }

        val launch = runVerificationCommand(
            listOf("/usr/bin/open", appPath.toString()),
            timeoutSeconds = 10
        )
        output.append(launch.output)
        if (launch.exitCode != 0) {
            return DesktopScriptResult(launch.exitCode, output.toString())
        }
    } else {
        output.appendLine("Skipping app launch because COTOR_DESKTOP_SKIP_LAUNCH=1.")
    }

    val deadline = System.nanoTime() + timeoutSeconds * 1_000_000_000L
    var lastProbe = ""
    while (System.nanoTime() < deadline) {
        val probe = runVerificationCommand(
            listOf("/usr/bin/curl", "-fsS", "--max-time", "2", healthUrl),
            timeoutSeconds = 3
        )
        if (probe.output.isNotBlank()) {
            lastProbe = probe.output.trim()
        }
        if (probe.exitCode == 0 && (lastProbe.contains("\"ok\":true") || lastProbe.contains("\"status\":\"ok\""))) {
            output.appendLine("Health response: $lastProbe")
            output.appendLine("Installed Cotor Desktop smoke check passed.")
            return DesktopScriptResult(0, output.toString())
        }
        Thread.sleep(1_000)
    }

    output.appendLine("Timed out waiting for installed Cotor Desktop health after ${timeoutSeconds}s.")
    if (lastProbe.isNotBlank()) {
        output.appendLine("Last health result: $lastProbe")
    }
    return DesktopScriptResult(1, output.toString())
}

internal fun resolveInstalledDesktopAppPath(
    environment: Map<String, String> = System.getenv(),
    homeDirectoryProvider: () -> Path = {
        desktopInstallHomeDirectory(environment)
    }
): Path? {
    environment["COTOR_DESKTOP_APP_PATH"]
        ?.takeIf { it.isNotBlank() }
        ?.let { Paths.get(it).toAbsolutePath().normalize() }
        ?.takeIf { it.isDirectory() }
        ?.let { return it }

    val roots = buildList {
        environment["COTOR_DESKTOP_INSTALL_ROOT"]
            ?.takeIf { it.isNotBlank() }
            ?.let { add(Paths.get(it).toAbsolutePath().normalize()) }
        add(Paths.get("/Applications"))
        add(homeDirectoryProvider().resolve("Applications"))
    }

    return roots
        .map { it.resolve(BUNDLED_DESKTOP_APP_NAME) }
        .firstOrNull { it.isDirectory() }
}

private fun runVerificationCommand(
    command: List<String>,
    timeoutSeconds: Long
): DesktopScriptResult =
    runDesktopCommand(
        command = command,
        timeoutSeconds = timeoutSeconds,
        outputLimitChars = DESKTOP_VERIFICATION_OUTPUT_LIMIT_CHARS,
        timeoutMessage = { effectiveTimeout ->
            "Desktop verification command timed out after ${effectiveTimeout}s: ${command.joinToString(" ")}"
        }
    )
