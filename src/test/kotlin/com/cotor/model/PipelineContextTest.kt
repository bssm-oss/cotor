package com.cotor.model

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PipelineContextTest {
    @Test
    fun `getAllOutputs preserves small outputs in execution order`() {
        val context = PipelineContext("pipeline-1", "test", totalStages = 2)

        context.addStageResult("first", agentResult(output = "one"))
        context.addStageResult("second", agentResult(output = "two"))

        assertEquals("one\n\n---\n\ntwo", context.getAllOutputs())
    }

    @Test
    fun `getAllOutputs caps large execution history output aggregation`() {
        val context = PipelineContext("pipeline-1", "test", totalStages = 2)
        val firstOutput = "a".repeat(180_000)
        val secondOutput = "b".repeat(80_000)

        context.addStageResult("first", agentResult(output = firstOutput))
        context.addStageResult("second", agentResult(output = secondOutput))

        val outputs = context.getAllOutputs()

        assertTrue(outputs.length <= 200_000)
        assertTrue(outputs.startsWith("a".repeat(1_000)))
        assertTrue("cotor truncated" in outputs)
    }

    @Test
    fun `getSuccessfulOutputs excludes failed outputs before applying aggregation cap`() {
        val context = PipelineContext("pipeline-1", "test", totalStages = 2)

        context.addStageResult("failed", agentResult(isSuccess = false, output = "f".repeat(220_000)))
        context.addStageResult("successful", agentResult(isSuccess = true, output = "s".repeat(220_000)))

        val outputs = context.getSuccessfulOutputs()

        assertTrue(outputs.length <= 200_000)
        assertTrue(outputs.startsWith("s".repeat(1_000)))
        assertFalse(outputs.startsWith("f"))
        assertTrue("cotor truncated" in outputs)
    }

    private fun agentResult(
        isSuccess: Boolean = true,
        output: String
    ): AgentResult {
        return AgentResult(
            agentName = "agent",
            isSuccess = isSuccess,
            output = output,
            error = null,
            duration = 1,
            metadata = emptyMap()
        )
    }
}
