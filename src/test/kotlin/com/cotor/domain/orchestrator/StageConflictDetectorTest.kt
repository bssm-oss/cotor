package com.cotor.domain.orchestrator

import com.cotor.model.PipelineContext
import com.cotor.model.PipelineStage
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContainExactly
import io.kotest.matchers.shouldBe

class StageConflictDetectorTest : FunSpec({
    test("separates parallel stages that target the same file") {
        val detector = StageConflictDetector()
        val context = PipelineContext("pipeline-1", "parallel", totalStages = 3)
        val stages = listOf(
            PipelineStage(id = "a", input = "edit src/main/kotlin/Foo.kt"),
            PipelineStage(id = "b", input = "also edit src/main/kotlin/Foo.kt"),
            PipelineStage(id = "c", input = "edit src/main/kotlin/Bar.kt")
        )

        val batches = detector.conflictSafeBatches(stages, context)

        batches.size shouldBe 2
        batches[0].map { it.id }.shouldContainExactly("a", "c")
        batches[1].map { it.id }.shouldContainExactly("b")
    }

    test("separates dependent parallel stages even when prerequisite has path keys") {
        val detector = StageConflictDetector()
        val context = PipelineContext("pipeline-1", "parallel", totalStages = 2)
        val stages = listOf(
            PipelineStage(id = "prepare", input = "edit src/main/kotlin/Foo.kt"),
            PipelineStage(id = "publish", input = "publish result", dependencies = listOf("prepare"))
        )

        val batches = detector.conflictSafeBatches(stages, context)

        batches.size shouldBe 2
        batches[0].map { it.id }.shouldContainExactly("prepare")
        batches[1].map { it.id }.shouldContainExactly("publish")
    }
})
