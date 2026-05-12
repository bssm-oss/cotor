package com.cotor.reliability

/**
 * File overview for ProductionReliabilityBaselineTest.
 *
 * This file belongs to the test suite that documents expected behavior and protects against regressions.
 * It groups declarations around production reliability baseline test so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.nio.file.Files
import java.nio.file.Path

class ProductionReliabilityBaselineTest {

    @Test
    fun `docker image runs long-lived app server with health probe`() {
        val dockerfile = Files.readString(Path.of("Dockerfile"))

        assertTrue(dockerfile.contains("EXPOSE 8787"), "Dockerfile should expose app-server port 8787")
        assertTrue(
            dockerfile.contains("HEALTHCHECK") && dockerfile.contains("http://127.0.0.1:8787/health"),
            "Dockerfile should define a healthcheck against /health"
        )
        assertTrue(
            dockerfile.contains("CMD [\"app-server\", \"--host\", \"0.0.0.0\", \"--port\", \"8787\"]"),
            "Dockerfile should bind app-server to all container interfaces for published ports"
        )
        assertTrue(
            dockerfile.contains("COPY docker-entrypoint.sh /app/docker-entrypoint.sh") &&
                dockerfile.contains("ENTRYPOINT [\"/app/docker-entrypoint.sh\"]"),
            "Dockerfile should launch through the app-server entrypoint"
        )
    }

    @Test
    fun `docker entrypoint generates runtime token for non-loopback app server`() {
        val dockerfile = Files.readString(Path.of("Dockerfile"))
        val entrypoint = Files.readString(Path.of("docker-entrypoint.sh"))

        assertTrue(
            !dockerfile.contains("cotor-desktop-local-token") && !entrypoint.contains("cotor-desktop-local-token"),
            "Docker startup should not bake the desktop development token into the container"
        )
        assertTrue(
            entrypoint.contains("COTOR_APP_TOKEN") && entrypoint.contains("random_token"),
            "Entrypoint should generate a runtime token when one is not provided"
        )
        assertTrue(
            entrypoint.contains("! is_loopback_host \"\$host\"") &&
                entrypoint.contains("[ \"\$command_name\" = \"app-server\" ]"),
            "Entrypoint should only auto-generate tokens for non-loopback app-server binds"
        )
    }

    @Test
    fun `release workflow tracks master branch and publishes artifacts`() {
        val workflow = Files.readString(Path.of(".github/workflows/release.yml"))

        assertTrue(workflow.contains("- master"), "Release workflow should trigger on pushes to master")
        assertTrue(workflow.contains("build/release/cotor-"), "Release workflow should publish the shaded jar artifact")
        assertTrue(workflow.contains("shasum -a 256 \"build/release/cotor-"), "Release workflow should generate the shaded jar checksum")
        assertTrue(workflow.contains("build/release/Cotor-"), "Release workflow should publish the desktop DMG artifact")
    }

    @Test
    fun `app server exposes explicit health and readiness endpoints`() {
        val appServerSource = Files.readString(Path.of("src/main/kotlin/com/cotor/app/AppServer.kt"))

        assertTrue(appServerSource.contains("get(\"/health\")"), "App server should define /health endpoint")
        assertTrue(appServerSource.contains("get(\"/ready\")"), "App server should define /ready endpoint")
        assertTrue(
            appServerSource.contains("HealthResponse(ok = true, service = \"cotor-app-server\")"),
            "Health and readiness endpoints should report readiness payload"
        )
    }
}
