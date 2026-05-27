package com.cotor.a2a

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.nio.file.Files
import kotlin.io.path.readText

class A2aPersistenceTest : FunSpec({
    test("atomic text write replaces the target and cleans temporary files") {
        val dir = Files.createTempDirectory("a2a-atomic-write-test")
        val target = dir.resolve("sessions.json")

        writeA2aTextAtomically(target, "first")
        writeA2aTextAtomically(target, "second")

        target.readText() shouldBe "second"
        Files.list(dir).use { entries ->
            entries.filter { it.fileName.toString().endsWith(".tmp") }.count() shouldBe 0
        }
    }
})
