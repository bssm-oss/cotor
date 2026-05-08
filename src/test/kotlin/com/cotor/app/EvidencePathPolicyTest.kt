package com.cotor.app

import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import java.nio.file.Files

class EvidencePathPolicyTest : FunSpec({
    test("allows evidence files inside configured company repository and worktree roots") {
        val root = Files.createTempDirectory("cotor-evidence-root")
        val file = Files.createDirectories(root.resolve("src")).resolve("Main.kt")
        Files.writeString(file, "fun main() = Unit\n")
        val state = DesktopAppState(
            companies = listOf(
                Company(
                    id = "company-1",
                    name = "Evidence Co",
                    rootPath = root.toString(),
                    repositoryId = "repo-1",
                    defaultBaseBranch = "master",
                    createdAt = 1,
                    updatedAt = 1
                )
            )
        )

        EvidencePathPolicy.requireAllowedFilePath(file.toString(), state) shouldBe file.toRealPath()
    }

    test("rejects traversal outside configured roots") {
        val root = Files.createTempDirectory("cotor-evidence-root")
        val outside = Files.createTempFile("cotor-evidence-outside", ".txt")
        val state = DesktopAppState(
            repositories = listOf(
                ManagedRepository(
                    id = "repo-1",
                    name = "repo",
                    localPath = root.toString(),
                    sourceKind = RepositorySourceKind.LOCAL,
                    defaultBranch = "master",
                    createdAt = 1,
                    updatedAt = 1
                )
            )
        )

        shouldThrow<IllegalArgumentException> {
            EvidencePathPolicy.requireAllowedFilePath(outside.toString(), state)
        }.message shouldContain "must stay inside"
    }
})
