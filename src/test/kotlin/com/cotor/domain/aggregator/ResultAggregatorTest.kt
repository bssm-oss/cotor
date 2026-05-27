package com.cotor.domain.aggregator

/**
 * File overview for ResultAggregatorTest.
 *
 * This file belongs to the test suite that documents expected behavior and protects against regressions.
 * It groups declarations around result aggregator test so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import com.cotor.analysis.ResultAnalyzer
import com.cotor.model.AgentResult
import com.cotor.model.ResultAnalysis
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import io.kotest.matchers.string.shouldStartWith

class ResultAggregatorTest : FunSpec({

    val stubAnalysis = ResultAnalysis(
        hasConsensus = true,
        consensusScore = 0.9,
        bestAgent = "claude",
        bestSummary = "ok",
        disagreements = emptyList(),
        recommendations = emptyList()
    )

    val analyzer = object : ResultAnalyzer {
        override fun analyze(results: List<AgentResult>) = stubAnalysis
    }

    val aggregator = DefaultResultAggregator(analyzer)

    test("includes analysis summary in aggregated result") {
        val aggregated = aggregator.aggregate(
            listOf(
                AgentResult("claude", true, "a", null, 10, emptyMap()),
                AgentResult("gemini", false, null, "err", 10, emptyMap())
            )
        )

        aggregated.analysis shouldBe stubAnalysis
        aggregated.successCount shouldBe 1
        aggregated.failureCount shouldBe 1
    }

    test("preserves small successful outputs with agent headers") {
        val aggregated = aggregator.aggregate(
            listOf(
                AgentResult("claude", true, "alpha", null, 10, emptyMap()),
                AgentResult("gemini", true, "beta", null, 10, emptyMap()),
                AgentResult("copilot", false, "ignored", "err", 10, emptyMap())
            )
        )

        aggregated.aggregatedOutput shouldBe "[claude]\nalpha\n---\n[gemini]\nbeta"
    }

    test("caps oversized aggregated output") {
        val aggregated = aggregator.aggregate(
            listOf(
                AgentResult("claude", true, "a".repeat(450_000), null, 10, emptyMap()),
                AgentResult("gemini", true, "b".repeat(200_000), null, 10, emptyMap())
            )
        )

        aggregated.aggregatedOutput.length shouldBe 500_000
        aggregated.aggregatedOutput shouldStartWith "[claude]\n"
        aggregated.aggregatedOutput shouldContain "cotor truncated"
    }
})
