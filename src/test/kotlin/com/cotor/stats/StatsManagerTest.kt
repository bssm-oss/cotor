package com.cotor.stats

/**
 * File overview for StatsManagerTest.
 *
 * This file belongs to the test suite that documents expected behavior and protects against regressions.
 * It groups declarations around stats manager test so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import com.cotor.model.AggregatedResult
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.doubles.plusOrMinus
import io.kotest.matchers.nulls.shouldBeNull
import io.kotest.matchers.nulls.shouldNotBeNull
import io.kotest.matchers.shouldBe
import java.nio.file.Files
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class StatsManagerTest : FunSpec({

    test("getStatsDetails calculates correct stage-level statistics") {
        val dir = Files.createTempDirectory("stats-test")
        val manager = StatsManager(dir.toString())
        val result = AggregatedResult(1, 1, 0, 1000, emptyList(), "output", Instant.now())
        val stages1 = listOf(
            StageExecution("build", 500, ExecutionStatus.SUCCESS, 0),
            StageExecution("test", 500, ExecutionStatus.SUCCESS, 1)
        )
        val stages2 = listOf(
            StageExecution("build", 700, ExecutionStatus.SUCCESS, 0),
            StageExecution("test", 300, ExecutionStatus.FAILURE, 0)
        )

        manager.recordExecution("pipeline-a", result, stages1)
        manager.recordExecution("pipeline-a", result.copy(failureCount = 1, successCount = 0), stages2)

        val details = manager.getStatsDetails("pipeline-a")
        details.shouldNotBeNull()
        details.pipelineName shouldBe "pipeline-a"
        details.totalExecutions shouldBe 2
        details.stages.size shouldBe 2

        val buildStats = details.stages.first { it.stageName == "build" }
        buildStats.avgDuration shouldBe 600L
        buildStats.successRate shouldBe 100.0
        buildStats.avgRetries shouldBe 0.0

        val testStats = details.stages.first { it.stageName == "test" }
        testStats.avgDuration shouldBe 400L
        testStats.successRate shouldBe 50.0
        testStats.avgRetries.shouldBe(0.5 plusOrMinus 0.01)
    }

    test("clearStats removes stored statistics") {
        val dir = Files.createTempDirectory("stats-test")
        val manager = StatsManager(dir.toString())
        val result = AggregatedResult(
            totalAgents = 1,
            successCount = 1,
            failureCount = 0,
            totalDuration = 500,
            results = emptyList(),
            aggregatedOutput = "done",
            timestamp = Instant.now()
        )

        manager.recordExecution("pipeline-a", result, emptyList())
        manager.loadStats("pipeline-a").shouldNotBeNull()

        manager.clearStats("pipeline-a") shouldBe true
        manager.loadStats("pipeline-a").shouldBeNull()
    }

    test("recordExecution preserves concurrent writes for the same pipeline") {
        val dir = Files.createTempDirectory("stats-concurrency-test")
        val manager = StatsManager(dir.toString())
        val executor = Executors.newFixedThreadPool(8)
        val start = CountDownLatch(1)
        val done = CountDownLatch(20)

        try {
            repeat(20) {
                executor.submit {
                    start.await(5, TimeUnit.SECONDS)
                    manager.recordExecution(
                        pipelineName = "pipeline-a",
                        result = AggregatedResult(
                            totalAgents = 1,
                            successCount = 1,
                            failureCount = 0,
                            totalDuration = 100,
                            results = emptyList(),
                            aggregatedOutput = "done",
                            timestamp = Instant.now()
                        ),
                        stages = emptyList()
                    )
                    done.countDown()
                }
            }

            start.countDown()
            done.await(10, TimeUnit.SECONDS) shouldBe true
            manager.loadStats("pipeline-a")?.totalExecutions shouldBe 20
        } finally {
            executor.shutdownNow()
            executor.awaitTermination(5, TimeUnit.SECONDS)
        }
    }

    test("recordExecution caps stored execution history while preserving cumulative totals") {
        val dir = Files.createTempDirectory("stats-retention-test")
        val manager = StatsManager(dir.toString(), maxStoredExecutions = 3)

        repeat(5) { index ->
            manager.recordExecution(
                pipelineName = "pipeline-a",
                result = AggregatedResult(
                    totalAgents = 1,
                    successCount = 1,
                    failureCount = 0,
                    totalDuration = (index + 1) * 100L,
                    results = emptyList(),
                    aggregatedOutput = "done",
                    timestamp = Instant.now()
                ),
                stages = listOf(StageExecution("stage-$index", 10, ExecutionStatus.SUCCESS, 0))
            )
        }

        val stats = manager.loadStats("pipeline-a")
        stats.shouldNotBeNull()
        stats.totalExecutions shouldBe 5
        stats.totalSuccesses shouldBe 5
        stats.executions.size shouldBe 3
        stats.executions.map { it.totalDuration } shouldBe listOf(300L, 400L, 500L)

        val history = manager.getExecutionHistory("pipeline-a", 10)
        history.map { it.totalDuration } shouldBe listOf(300L, 400L, 500L)
    }
})
