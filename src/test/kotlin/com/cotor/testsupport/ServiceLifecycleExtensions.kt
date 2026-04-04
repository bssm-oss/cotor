package com.cotor.testsupport

import com.cotor.app.DesktopAppService
import kotlinx.coroutines.runBlocking

/**
 * Shared test helper for DesktopAppService lifecycle management.
 *
 * Runtime-oriented tests create background jobs and event loops. This registry
 * makes teardown explicit so those jobs do not keep the JVM alive after tests.
 */
class DesktopAppServiceRegistry {
    private val services = linkedSetOf<DesktopAppService>()

    @Synchronized
    fun register(service: DesktopAppService): DesktopAppService {
        services += service
        return service
    }

    @Synchronized
    fun shutdownAll() {
        val snapshot = services.toList().asReversed()
        services.clear()
        snapshot.forEach { service ->
            runCatching { runBlocking { service.shutdown() } }
        }
    }
}
