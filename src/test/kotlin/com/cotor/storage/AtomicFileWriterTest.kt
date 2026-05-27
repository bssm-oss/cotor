package com.cotor.storage

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.nio.file.Files
import kotlin.io.path.exists
import kotlin.io.path.readText

class AtomicFileWriterTest : FunSpec({
    test("writeTextAtomically replaces existing content and leaves no temp files") {
        val dir = Files.createTempDirectory("atomic-file-writer")
        val target = dir.resolve("state.json")

        writeTextAtomically(target, "first")
        writeTextAtomically(target, "second")

        target.readText() shouldBe "second"
        Files.list(dir).use { entries ->
            entries.filter { it.fileName.toString().endsWith(".tmp") }.count() shouldBe 0
        }
    }

    test("writeTextAtomically creates missing parent directories") {
        val dir = Files.createTempDirectory("atomic-file-writer-parent")
        val target = dir.resolve("nested").resolve("state.json")

        writeTextAtomically(target, "payload")

        target.exists() shouldBe true
        target.readText() shouldBe "payload"
    }

    test("writeTextAtomically configures the temp file before replacing target") {
        val dir = Files.createTempDirectory("atomic-file-writer-configure")
        val target = dir.resolve("state.json")
        var configuredTempFile: java.nio.file.Path? = null

        writeTextAtomically(
            path = target,
            payload = "payload",
            configureTempFile = { tempFile ->
                configuredTempFile = tempFile
                tempFile.parent shouldBe dir
                tempFile.fileName.toString().endsWith(".tmp") shouldBe true
            }
        )

        target.readText() shouldBe "payload"
        configuredTempFile?.exists() shouldBe false
    }
})
