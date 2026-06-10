package com.cotor.app

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContain
import io.kotest.matchers.shouldBe
import kotlinx.coroutines.delay
import java.nio.file.Files
import kotlin.io.path.writeText

class CotorTestCenterServiceTest : FunSpec({
    test("builds a local validation plan from detected project test surfaces") {
        val root = Files.createTempDirectory("cotor-test-center-plan")
        val gradlew = root.resolve("gradlew")
        gradlew.writeText("#!/bin/sh\nexit 0\n")
        gradlew.toFile().setExecutable(true)
        Files.createDirectories(root.resolve("macos"))
        root.resolve("macos").resolve("Package.swift").writeText("// swift package placeholder\n")

        val service = CotorTestCenterService()
        try {
            val plan = service.plan(testCompany(root.toString()), "full")

            plan.suiteId shouldBe "full"
            plan.availableSuites shouldContain "kotlin"
            plan.availableSuites shouldContain "desktop"
            plan.steps.map { it.id } shouldContain "kotlin-gradle-test"
            plan.steps.map { it.id } shouldContain "desktop-swift-build"
        } finally {
            service.shutdown()
        }
    }

    test("runs detected commands and records a completed session") {
        val root = Files.createTempDirectory("cotor-test-center-run")
        val gradlew = root.resolve("gradlew")
        gradlew.writeText("#!/bin/sh\necho test-center-ok\nexit 0\n")
        gradlew.toFile().setExecutable(true)

        val service = CotorTestCenterService(stepTimeoutMs = 5_000)
        try {
            val session = service.startSession(testCompany(root.toString()), "kotlin")
            val completed = waitForSession(service, session.id)

            completed.status shouldBe "PASSED"
            completed.progress shouldBe 1.0
            completed.steps.single().status shouldBe "PASSED"
            completed.steps.single().output?.contains("test-center-ok") shouldBe true
        } finally {
            service.shutdown()
        }
    }
})

private fun testCompany(rootPath: String): Company =
    Company(
        id = "company-test",
        name = "Test Company",
        rootPath = rootPath,
        repositoryId = "repo-test",
        defaultBaseBranch = "main",
        createdAt = 1,
        updatedAt = 1
    )

private suspend fun waitForSession(service: CotorTestCenterService, sessionId: String): TestCenterSessionRecord {
    repeat(50) {
        val session = service.getSession(sessionId)
        if (session != null && session.status !in setOf("PENDING", "RUNNING")) {
            return session
        }
        delay(100)
    }
    error("Test Center session did not complete")
}
