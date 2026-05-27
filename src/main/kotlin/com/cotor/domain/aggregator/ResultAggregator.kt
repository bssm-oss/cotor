package com.cotor.domain.aggregator

/**
 * File overview for ResultAggregator.
 *
 * This file belongs to the domain layer for orchestration, planning, aggregation, and runtime policies.
 * It groups declarations around result aggregator so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import com.cotor.analysis.ResultAnalyzer
import com.cotor.model.AgentResult
import com.cotor.model.AggregatedResult
import java.time.Instant

private const val AGGREGATED_OUTPUT_SEPARATOR = "\n---\n"
private const val MAX_AGGREGATED_OUTPUT_CHARS = 500_000

/**
 * Interface for aggregating agent results
 */
interface ResultAggregator {
    /**
     * Aggregate multiple agent results
     * @param results List of agent results to aggregate
     * @return AggregatedResult containing summary and merged output
     */
    fun aggregate(results: List<AgentResult>): AggregatedResult
}

/**
 * Default implementation of result aggregator
 */
class DefaultResultAggregator(
    private val resultAnalyzer: ResultAnalyzer
) : ResultAggregator {

    override fun aggregate(results: List<AgentResult>): AggregatedResult {
        val successCount = results.count { it.isSuccess }
        val failureCount = results.count { !it.isSuccess }
        val totalDuration = results.sumOf { it.duration }
        val analysis = resultAnalyzer.analyze(results)

        return AggregatedResult(
            totalAgents = results.size,
            successCount = successCount,
            failureCount = failureCount,
            totalDuration = totalDuration,
            results = results,
            aggregatedOutput = mergeOutputs(results),
            timestamp = Instant.now(),
            analysis = analysis
        )
    }

    private fun mergeOutputs(results: List<AgentResult>): String {
        val builder = StringBuilder()
        var hasOutput = false
        var truncatedChars = 0L

        for (result in results) {
            if (!result.isSuccess || result.output == null) continue
            val segment = "[${result.agentName}]\n${result.output}"
            val separator = if (hasOutput) AGGREGATED_OUTPUT_SEPARATOR else ""
            val segmentLength = separator.length + segment.length
            val remainingChars = MAX_AGGREGATED_OUTPUT_CHARS - builder.length

            if (remainingChars <= 0) {
                truncatedChars += segmentLength.toLong()
                hasOutput = true
                continue
            }

            if (segmentLength <= remainingChars) {
                builder.append(separator)
                builder.append(segment)
                hasOutput = true
                continue
            }

            val separatorChars = minOf(separator.length, remainingChars)
            if (separatorChars > 0) {
                builder.append(separator, 0, separatorChars)
            }
            val segmentChars = minOf(segment.length, remainingChars - separatorChars)
            if (segmentChars > 0) {
                builder.append(segment, 0, segmentChars)
            }
            truncatedChars += (segmentLength - separatorChars - segmentChars).toLong()
            hasOutput = true
        }

        if (truncatedChars > 0) {
            val marker = "\n[cotor truncated at least $truncatedChars chars from aggregated agent outputs]"
            val maxBodyLength = (MAX_AGGREGATED_OUTPUT_CHARS - marker.length).coerceAtLeast(0)
            if (builder.length > maxBodyLength) {
                builder.setLength(maxBodyLength)
            }
            builder.append(marker)
        }

        return builder.toString()
    }
}
