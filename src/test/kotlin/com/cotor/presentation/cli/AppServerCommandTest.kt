package com.cotor.presentation.cli

import com.cotor.app.persistAppServerToken
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import io.kotest.matchers.string.shouldNotContain
import java.nio.file.Files

class AppServerCommandTest : FunSpec({
    test("app-server preserves configured bearer token") {
        resolveAppServerToken(" configured-token ") shouldBe "configured-token"
    }

    test("app-server reuses persisted bearer token before generating a new one") {
        val appHome = Files.createTempDirectory("cotor-app-server-token-reuse-test")
        try {
            persistAppServerToken("stored-token", appHome)

            resolveAppServerToken("", appHome) shouldBe "stored-token"
        } finally {
            appHome.toFile().deleteRecursively()
        }
    }

    test("app-server generates url-safe bearer token when none is configured") {
        val token = generateAppServerToken { bytes ->
            bytes.indices.forEach { index ->
                bytes[index] = index.toByte()
            }
        }

        token shouldNotBe ""
        token shouldNotContain "+"
        token shouldNotContain "/"
        token shouldNotContain "="
    }

    test("app-server persists effective bearer token for desktop clients") {
        val appHome = Files.createTempDirectory("cotor-app-server-token-test")
        try {
            val tokenPath = persistAppServerToken("secret-token", appHome)

            tokenPath.fileName.toString() shouldBe "app-server.token"
            Files.readString(tokenPath) shouldBe "secret-token"
        } finally {
            appHome.toFile().deleteRecursively()
        }
    }
})
