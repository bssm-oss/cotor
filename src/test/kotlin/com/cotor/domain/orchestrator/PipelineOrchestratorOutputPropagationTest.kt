package com.cotor.domain.orchestrator

import com.cotor.analysis.ResultAnalyzer
import com.cotor.checkpoint.CheckpointManager
import com.cotor.data.registry.AgentRegistry
import com.cotor.domain.aggregator.DefaultResultAggregator
import com.cotor.domain.executor.AgentExecutor
import com.cotor.event.EventBus
import com.cotor.model.AgentConfig
import com.cotor.model.AgentExecutionMetadata
import com.cotor.model.AgentReference
import com.cotor.model.AgentResult
import com.cotor.model.ExecutionMode
import com.cotor.model.Pipeline
import com.cotor.model.PipelineStage
import com.cotor.model.ValidationResult
import com.cotor.stats.StatsManager
import com.cotor.validation.PipelineTemplateValidator
import com.cotor.validation.output.OutputValidator
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.slf4j.Logger
import java.util.concurrent.ConcurrentHashMap

class PipelineOrchestratorOutputPropagationTest {
    private val agentRegistry: AgentRegistry = mockk(relaxed = true)
    private val templateValidator: PipelineTemplateValidator = mockk(relaxed = true)

    @Test
    fun `sequential mode caps implicit previous output before next stage input`() = runBlocking {
        val largeOutput = "a".repeat(250_000)
        val inputs = ConcurrentHashMap<String, String?>()
        val orchestrator = orchestratorWithExecutor { stageId, input ->
            inputs[stageId] = input
            AgentResult(
                agentName = "agent",
                isSuccess = true,
                output = if (stageId == "source") largeOutput else "done",
                error = null,
                duration = 1,
                metadata = emptyMap()
            )
        }

        orchestrator.executePipeline(
            Pipeline(
                name = "sequential-propagation",
                executionMode = ExecutionMode.SEQUENTIAL,
                stages = listOf(
                    PipelineStage(id = "source", agent = AgentReference("agent"), input = "seed"),
                    PipelineStage(id = "sink", agent = AgentReference("agent"))
                )
            )
        )

        val sinkInput = inputs["sink"].orEmpty()
        assertTrue(sinkInput.length < largeOutput.length)
        assertTrue("cotor truncated" in sinkInput)
    }

    @Test
    fun `dag mode caps combined dependency outputs before dependent stage input`() = runBlocking {
        val largeOutput = "b".repeat(150_000)
        val inputs = ConcurrentHashMap<String, String?>()
        val orchestrator = orchestratorWithExecutor { stageId, input ->
            inputs[stageId] = input
            AgentResult(
                agentName = "agent",
                isSuccess = true,
                output = if (stageId.startsWith("source")) largeOutput else "done",
                error = null,
                duration = 1,
                metadata = emptyMap()
            )
        }

        orchestrator.executePipeline(
            Pipeline(
                name = "dag-propagation",
                executionMode = ExecutionMode.DAG,
                stages = listOf(
                    PipelineStage(id = "source-a", agent = AgentReference("agent"), input = "a"),
                    PipelineStage(id = "source-b", agent = AgentReference("agent"), input = "b"),
                    PipelineStage(id = "sink", agent = AgentReference("agent"), dependencies = listOf("source-a", "source-b"))
                )
            )
        )

        val sinkInput = inputs["sink"].orEmpty()
        assertTrue(sinkInput.length < largeOutput.length * 2)
        assertTrue("cotor truncated" in sinkInput)
    }

    private fun orchestratorWithExecutor(
        execute: (stageId: String, input: String?) -> AgentResult
    ): DefaultPipelineOrchestrator {
        val agentExecutor = mockk<AgentExecutor>()
        coEvery { agentRegistry.getAgent("agent") } returns AgentConfig("agent", "com.cotor.agent.TestAgent")
        coEvery { templateValidator.validate(any()) } returns ValidationResult.Success
        coEvery { agentExecutor.executeAgent(any(), any(), any()) } coAnswers {
            val input = secondArg<String?>()
            val metadata = thirdArg<AgentExecutionMetadata>()
            execute(metadata.stageId.orEmpty(), input)
        }
        return DefaultPipelineOrchestrator(
            agentExecutor = agentExecutor,
            resultAggregator = DefaultResultAggregator(mockk<ResultAnalyzer>(relaxed = true)),
            eventBus = mockk<EventBus>(relaxed = true),
            logger = mockk<Logger>(relaxed = true),
            agentRegistry = agentRegistry,
            outputValidator = mockk<OutputValidator>(relaxed = true),
            statsManager = mockk<StatsManager>(relaxed = true),
            checkpointManager = mockk<CheckpointManager>(relaxed = true),
            templateValidator = templateValidator
        )
    }
}
