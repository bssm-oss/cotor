package com.cotor.app

import org.slf4j.LoggerFactory
import java.net.URI

/**
 * Centralizes loopback-vs-remote validation for app-server URLs.
 *
 * Remote connections are only allowed when the operator has explicitly set
 * COTOR_ALLOW_REMOTE_APP_SERVER=1 **and** provided a COTOR_APP_TOKEN, so that
 * accidental env-var misconfiguration cannot silently route agent traffic to an
 * untrusted host.
 */
object DesktopEndpointPolicy {
    private val logger = LoggerFactory.getLogger(DesktopEndpointPolicy::class.java)

    private val LOOPBACK_HOSTS = setOf("127.0.0.1", "localhost", "::1", "[::1]")
    private val ALLOWED_SCHEMES = setOf("http", "https")

    fun isLoopback(url: String): Boolean {
        val uri = runCatching { URI(url.trim()) }.getOrNull() ?: return false
        val scheme = uri.scheme?.lowercase() ?: return false
        val host = uri.host?.lowercase() ?: return false
        return scheme in ALLOWED_SCHEMES && host in LOOPBACK_HOSTS && uri.rawUserInfo == null
    }

    fun remoteAllowed(
        envAllowRemote: String? = System.getenv("COTOR_ALLOW_REMOTE_APP_SERVER"),
        envToken: String? = System.getenv("COTOR_APP_TOKEN")
    ): Boolean {
        val flag = envAllowRemote == "1"
        val token = !envToken.isNullOrBlank()
        return flag && token
    }

    /**
     * Returns the validated a2a endpoint URL.
     * Falls back to the default loopback address when the env-var value is
     * remote and the remote-allow flag+token are not both set.
     */
    fun resolveA2aEndpoint(
        envUrl: String? = System.getenv("COTOR_APP_SERVER_URL"),
        envAllowRemote: String? = System.getenv("COTOR_ALLOW_REMOTE_APP_SERVER"),
        envToken: String? = System.getenv("COTOR_APP_TOKEN")
    ): String {
        val base = envUrl?.takeIf { it.isNotBlank() }?.trim()?.removeSuffix("/")
            ?: return DEFAULT_LOOPBACK_A2A
        return if (isLoopback(base) || remoteAllowed(envAllowRemote, envToken)) {
            "$base/api/a2a"
        } else {
            logger.warn(
                "COTOR_APP_SERVER_URL points to a non-loopback host ({}). " +
                    "Set COTOR_ALLOW_REMOTE_APP_SERVER=1 and COTOR_APP_TOKEN to allow remote connections. " +
                    "Falling back to default loopback endpoint.",
                base
            )
            DEFAULT_LOOPBACK_A2A
        }
    }

    const val DEFAULT_LOOPBACK = "http://127.0.0.1:8787"
    const val DEFAULT_LOOPBACK_A2A = "$DEFAULT_LOOPBACK/api/a2a"
}
