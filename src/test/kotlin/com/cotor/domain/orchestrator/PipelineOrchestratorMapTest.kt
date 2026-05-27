package com.cotor.domain.orchestrator

/**
 * File overview for PipelineOrchestratorMapTest.
 *
 * This file belongs to the test suite that documents expected behavior and protects against regressions.
 * It groups declarations around pipeline orchestrator map test so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import com.cotor.analysis.ResultAnalyzer
import com.cotor.domain.aggregator.DefaultResultAggregator
import com.cotor.domain.executor.AgentExecutor
import com.cotor.event.EventBus
import com.cotor.model.*
import com.cotor.stats.StatsManager
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.slf4j.Logger
import java.util.concurrent.atomic.AtomicInteger

class PipelineOrchestratorMapTest {

    private val agentExecutor: AgentExecutor = mockk()
    private val resultAnalyzer: ResultAnalyzer = mockk(relaxed = true)
    private val resultAggregator: DefaultResultAggregator = DefaultResultAggregator(resultAnalyzer)
    private val eventBus: EventBus = mockk(relaxed = true)
    private val logger: Logger = mockk(relaxed = true)
    private val agentRegistry: com.cotor.data.registry.AgentRegistry = mockk(relaxed = true)
    private val outputValidator: com.cotor.validation.output.OutputValidator = mockk(relaxed = true)
    private val statsManager: StatsManager = mockk(relaxed = true)

    @Test
    fun `executePipeline with MAP execution mode should fan out and aggregate results`() = runBlocking {
        // Given
        val pipeline = Pipeline(
            name = "map-pipeline",
            executionMode = ExecutionMode.MAP,
            stages = listOf(
                PipelineStage(
                    id = "fanout-stage",
                    agent = AgentReference("test-agent"),
                    fanout = FanoutConfig(source = "items")
                )
            )
        )
        val orchestrator = DefaultPipelineOrchestrator(
            agentExecutor = agentExecutor,
            resultAggregator = resultAggregator,
            eventBus = eventBus,
            logger = logger,
            agentRegistry = agentRegistry,
            outputValidator = outputValidator,
            statsManager = statsManager
        )
        val items = listOf("item1", "item2", "item3")
        val pipelineContext = PipelineContext(
            pipelineId = "test-pipeline",
            pipelineName = "map-pipeline",
            totalStages = 1,
        )
        pipelineContext.sharedState["items"] = items

        coEvery { agentExecutor.executeAgent(any(), any(), any()) } returns AgentResult(
            agentName = "test-agent",
            isSuccess = true,
            output = "output",
            error = null,
            duration = 100,
            metadata = emptyMap()
        )

        coEvery { agentRegistry.getAgent(any()) } returns AgentConfig(
            name = "test-agent",
            pluginClass = "com.cotor.agent.TestAgent"
        )

        // When
        val result = orchestrator.executePipeline(pipeline, context = pipelineContext)

        // Then
        assertEquals(3, result.successCount)
        assertEquals(0, result.failureCount)
        assertEquals(3, result.results.size)
    }

    @Test
    fun `MAP execution honors maxConcurrentAgents`() = runBlocking {
        val trackingExecutor = TrackingAgentExecutor(delayMs = 50)
        coEvery { agentRegistry.getAgent(any()) } returns AgentConfig(
            name = "test-agent",
            pluginClass = "com.cotor.agent.TestAgent"
        )
        val orchestrator = DefaultPipelineOrchestrator(
            agentExecutor = trackingExecutor,
            resultAggregator = resultAggregator,
            eventBus = eventBus,
            logger = logger,
            agentRegistry = agentRegistry,
            outputValidator = outputValidator,
            statsManager = statsManager,
            performanceConfig = PerformanceConfig(maxConcurrentAgents = 2)
        )
        val pipeline = Pipeline(
            name = "bounded-map-pipeline",
            executionMode = ExecutionMode.MAP,
            stages = listOf(
                PipelineStage(
                    id = "fanout-stage",
                    agent = AgentReference("test-agent"),
                    fanout = FanoutConfig(source = "items")
                )
            )
        )
        val context = PipelineContext(
            pipelineId = "bounded-map",
            pipelineName = "bounded-map-pipeline",
            totalStages = 1
        )
        context.sharedState["items"] = (1..8).toList()

        val result = orchestrator.executePipeline(pipeline, context = context)

        assertEquals(8, result.results.size)
        assertTrue(trackingExecutor.maxActive.get() <= 2)
    }
}

private class TrackingAgentExecutor(
    private val delayMs: Long
) : AgentExecutor {
    private val active = AtomicInteger(0)
    val maxActive = AtomicInteger(0)

    override suspend fun executeAgent(
        agent: AgentConfig,
        input: String?,
        metadata: AgentExecutionMetadata
    ): AgentResult {
        val current = active.incrementAndGet()
        maxActive.updateAndGet { previous -> maxOf(previous, current) }
        return try {
            delay(delayMs)
            AgentResult(
                agentName = agent.name,
                isSuccess = true,
                output = "processed:$input",
                error = null,
                duration = delayMs,
                metadata = emptyMap()
            )
        } finally {
            active.decrementAndGet()
        }
    }

    override suspend fun executeWithRetry(
        agent: AgentConfig,
        input: String?,
        retryPolicy: RetryPolicy,
        metadata: AgentExecutionMetadata
    ): AgentResult = executeAgent(agent, input, metadata)
}
