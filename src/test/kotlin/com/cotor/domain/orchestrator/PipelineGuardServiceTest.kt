package com.cotor.domain.orchestrator

import com.cotor.model.AgentResult
import com.cotor.model.PipelineContext
import com.cotor.model.PipelineStage
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.booleans.shouldBeFalse
import io.kotest.matchers.booleans.shouldBeTrue
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain

class PipelineGuardServiceTest : FunSpec({
    val service = PipelineGuardService()
    val context = PipelineContext(pipelineId = "pipeline-1", pipelineName = "guards", totalStages = 1)

    test("adds warning metadata for uncertainty and missing verification evidence") {
        val guarded = service.apply(
            stage = PipelineStage(id = "draft"),
            result = AgentResult(
                agentName = "worker",
                isSuccess = true,
                output = "Implemented the change, but maybe incomplete.",
                error = null,
                duration = 10,
                metadata = emptyMap()
            ),
            context = context
        )

        guarded.isSuccess.shouldBeTrue()
        guarded.metadata["pipelineGuardStatus"] shouldBe "PASS"
        guarded.metadata["pipelineGuardFindings"] shouldContain "UNCERTAINTY"
        guarded.metadata["pipelineGuardFindings"] shouldContain "MISSING_VERIFICATION"
    }

    test("blocks hardcoded secret shaped output before reviewer stages consume it") {
        val guarded = service.apply(
            stage = PipelineStage(id = "draft"),
            result = AgentResult(
                agentName = "worker",
                isSuccess = true,
                output = "val apiKey = \"sk-this-should-not-ship\"",
                error = null,
                duration = 10,
                metadata = emptyMap()
            ),
            context = context
        )

        guarded.isSuccess.shouldBeFalse()
        guarded.metadata["pipelineGuardStatus"] shouldBe "BLOCK"
        guarded.metadata["failureCategory"] shouldBe "VALIDATION_FAILED"
        guarded.error shouldContain "Pipeline guard blocked"
    }
})
