package com.cotor.app

import java.nio.file.Path
import kotlin.io.path.createDirectories
import kotlin.io.path.exists

internal class LocalPlaywrightDependencyResolver(
    private val commandAvailability: (String) -> Boolean,
    private val processRunner: LocalSkillProcessRunner,
    private val environment: () -> Map<String, String> = { System.getenv() }
) {
    suspend fun requireNodePath(
        runtimeDir: Path,
        timeoutSeconds: Int,
        label: String
    ): Path {
        require(commandAvailability("node")) {
            "$label requires node so Playwright can run locally."
        }
        runtimeDir.createDirectories()
        return withLocalSkillRuntimeMutationLock(runtimeDir) {
            existingNodePath(runtimeDir)
                ?: installIfExplicitlyAllowed(runtimeDir, timeoutSeconds, label)
                ?: error(playwrightSetupMessage(label))
        }
    }

    suspend fun prewarm(runtimeDir: Path, timeoutSeconds: Int) {
        if (!commandAvailability("node")) return
        runtimeDir.createDirectories()
        withLocalSkillRuntimeMutationLock(runtimeDir) {
            if (existingNodePath(runtimeDir) == null && allowRuntimeInstall()) {
                installIfExplicitlyAllowed(runtimeDir, timeoutSeconds, "Browser skill")
            }
        }
    }

    private fun existingNodePath(runtimeDir: Path): Path? {
        runtimeDir.resolve("node_modules").takeIf { it.hasPlaywrightPackage() }?.let { return it }
        configuredNodeModulesPath()?.takeIf { it.hasPlaywrightPackage() }?.let { return it }
        configuredNodeModulesPath()?.parent?.takeIf { it.hasPlaywrightPackage() }?.let { return it }
        return null
    }

    private suspend fun installIfExplicitlyAllowed(runtimeDir: Path, timeoutSeconds: Int, label: String): Path? {
        if (!allowRuntimeInstall()) return null
        require(commandAvailability("npm")) {
            "$label runtime Playwright install requires npm. Prebundle Playwright or set $NODE_PATH_ENV to a node_modules directory."
        }
        val installTimeoutSeconds = timeoutSeconds.coerceAtLeast(120).toLong()
        val result = processRunner.run(
            command = listOf(
                "npm",
                "install",
                "--silent",
                "--no-audit",
                "--no-fund",
                "--prefix",
                runtimeDir.toString(),
                "$PLAYWRIGHT_PACKAGE@$PLAYWRIGHT_VERSION"
            ),
            workingDirectory = runtimeDir,
            timeoutSeconds = installTimeoutSeconds,
            timeoutMessage = "Playwright dependency install timed out after ${installTimeoutSeconds}s.",
            environment = emptyMap()
        )
        val output = result.output.trim()
        if (result.exitCode != 0) {
            error(output.ifBlank { "Playwright dependency install failed with exit ${result.exitCode}." })
        }
        return runtimeDir.resolve("node_modules").takeIf { it.hasPlaywrightPackage() }
            ?: error("Playwright dependency install completed but node_modules/playwright was not created.")
    }

    private fun configuredNodeModulesPath(): Path? =
        environment()[NODE_PATH_ENV]
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?.let { Path.of(it).toAbsolutePath().normalize() }

    private fun allowRuntimeInstall(): Boolean =
        environment()[ALLOW_INSTALL_ENV]?.trim()?.equals("1") == true ||
            environment()[ALLOW_INSTALL_ENV]?.trim()?.equals("true", ignoreCase = true) == true

    private fun playwrightSetupMessage(label: String): String =
        "$label requires a preinstalled Playwright dependency. " +
            "Set $NODE_PATH_ENV to a node_modules directory containing playwright, " +
            "build the desktop bundle with COTOR_PREBUNDLE_PLAYWRIGHT=1, " +
            "or explicitly allow runtime npm install with $ALLOW_INSTALL_ENV=1."

    private fun Path.hasPlaywrightPackage(): Boolean =
        resolve(PLAYWRIGHT_PACKAGE).exists()

    private companion object {
        private const val PLAYWRIGHT_PACKAGE = "playwright"
        private const val PLAYWRIGHT_VERSION = "1.52.0"
        private const val NODE_PATH_ENV = "COTOR_BROWSER_SKILL_NODE_PATH"
        private const val ALLOW_INSTALL_ENV = "COTOR_BROWSER_SKILL_ALLOW_NPM_INSTALL"
    }
}
