package com.cotor.presentation.cli

/**
 * File overview for AppServerCommand.
 *
 * This file belongs to the CLI presentation layer for interactive and command-driven flows.
 * It groups declarations around app server command so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import com.cotor.app.AppServer
import com.cotor.app.appServerTokenPath
import com.cotor.app.defaultDesktopAppHome
import com.cotor.app.readPersistedAppServerToken
import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.parameters.options.default
import com.github.ajalt.clikt.parameters.options.option
import com.github.ajalt.clikt.parameters.types.int
import java.nio.file.Path
import java.security.SecureRandom
import java.util.Base64

/**
 * CLI entrypoint used by the native macOS shell.
 *
 * This keeps desktop orchestration in the same distributable as the rest of Cotor
 * instead of requiring a second bespoke backend binary.
 */
class AppServerCommand : CliktCommand(
    name = "app-server",
    help = "Launch the local API server used by the Cotor macOS desktop app"
) {
    private val host by option("--host", help = "Host interface to bind the app server to")
        .default(System.getenv("COTOR_APP_HOST") ?: "127.0.0.1")
    private val port by option("--port", "-p", help = "Port to run the app server on").int().default(8787)
    private val token by option("--token", help = "Optional bearer token required by the desktop app")
        .default(System.getenv("COTOR_APP_TOKEN").orEmpty())
    private val controlToken by option("--control-token", help = "Optional bearer token required by MCP control tools")
        .default(System.getenv("COTOR_APP_CONTROL_TOKEN").orEmpty())

    override fun run() {
        val appHome = defaultDesktopAppHome()
        val storedToken = readPersistedAppServerToken(appHome)
        val effectiveToken = resolveAppServerToken(token, appHome)
        if (token.isBlank() && storedToken == null) {
            val tokenPath = appServerTokenPath(appHome)
            println("[cotor-app-server] generated bearer token at $tokenPath")
        }
        AppServer().start(
            host = host,
            port = port,
            token = effectiveToken,
            controlToken = controlToken.ifBlank { null }
        )
    }
}

private val appServerTokenRandom = SecureRandom()

internal fun resolveAppServerToken(configuredToken: String, appHome: Path = defaultDesktopAppHome()): String {
    return configuredToken.trim().takeIf { it.isNotBlank() }
        ?: readPersistedAppServerToken(appHome)
        ?: generateAppServerToken()
}

internal fun generateAppServerToken(randomBytes: (ByteArray) -> Unit = appServerTokenRandom::nextBytes): String {
    val bytes = ByteArray(32)
    randomBytes(bytes)
    return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
}
