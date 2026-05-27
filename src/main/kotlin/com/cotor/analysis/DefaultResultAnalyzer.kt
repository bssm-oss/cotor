package com.cotor.analysis

/**
 * File overview for DefaultResultAnalyzer.
 *
 * This file belongs to the analysis layer that summarizes and compares agent results.
 * It groups declarations around default result analyzer so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import com.cotor.model.AgentResult
import com.cotor.model.ResultAnalysis
import kotlin.math.min

private const val MAX_ANALYZED_OUTPUT_CHARS = 100_000
private const val MAX_OUTPUT_LENGTH_CONFIDENCE_BONUS = 1.0

/**
 * Heuristic analyzer that compares agent outputs using token-based similarity
 * and metadata hints (validationScore) to highlight best candidates.
 */
class DefaultResultAnalyzer : ResultAnalyzer {
    override fun analyze(results: List<AgentResult>): ResultAnalysis? {
        if (results.isEmpty()) return null
        if (results.size == 1) {
            val single = results.first()
            return ResultAnalysis(
                hasConsensus = true,
                consensusScore = 1.0,
                bestAgent = single.agentName,
                bestSummary = single.output?.take(200),
                disagreements = emptyList(),
                recommendations = emptyList()
            )
        }

        val comparable = results.filter { it.output?.isNotBlank() == true }
        if (comparable.isEmpty()) {
            return ResultAnalysis(
                hasConsensus = false,
                consensusScore = 0.0,
                bestAgent = null,
                bestSummary = null,
                disagreements = listOf("All agents returned empty output."),
                recommendations = listOf("Re-run pipeline with verbose mode to inspect failures.")
            )
        }

        val pairSimilarities = mutableListOf<Double>()
        val disagreements = mutableListOf<String>()
        for (i in 0 until comparable.lastIndex) {
            for (j in i + 1 until comparable.size) {
                val left = comparable[i]
                val right = comparable[j]
                val score = similarity(left.analysisOutput(), right.analysisOutput())
                pairSimilarities += score
                if (score < 0.4) {
                    disagreements += "Low agreement between ${left.agentName} and ${right.agentName} (${percent(score)})."
                }
            }
        }

        val consensusScore = if (pairSimilarities.isEmpty()) 1.0 else pairSimilarities.average()
        val hasConsensus = consensusScore >= 0.7 || comparable.size == 1

        val best = comparable.maxByOrNull { extractConfidence(it) }
        val recommendations = mutableListOf<String>()
        if (!hasConsensus) {
            recommendations += "Review outputs manually or keep the highest scoring agent (${best?.agentName ?: "unknown"})."
        }
        if (disagreements.isEmpty() && !hasConsensus) {
            recommendations += "Consider tightening stage validation to align agent outputs."
        }

        return ResultAnalysis(
            hasConsensus = hasConsensus,
            consensusScore = min(consensusScore, 1.0),
            bestAgent = best?.agentName,
            bestSummary = best?.output?.take(200),
            disagreements = disagreements,
            recommendations = recommendations
        )
    }

    private fun extractConfidence(result: AgentResult): Double {
        val validationScore = result.metadata["validationScore"]?.toDoubleOrNull() ?: 0.0
        val outputBonus = ((result.output?.length ?: 0).coerceAtMost(MAX_ANALYZED_OUTPUT_CHARS) / 2000.0)
            .coerceAtMost(MAX_OUTPUT_LENGTH_CONFIDENCE_BONUS)
        return validationScore + outputBonus
    }

    private fun AgentResult.analysisOutput(): String =
        output?.take(MAX_ANALYZED_OUTPUT_CHARS).orEmpty()

    private fun similarity(left: String, right: String): Double {
        val leftTokens = tokenize(left)
        val rightTokens = tokenize(right)
        if (leftTokens.isEmpty() || rightTokens.isEmpty()) return 0.0

        val intersection = leftTokens.intersect(rightTokens)
        val union = leftTokens.union(rightTokens)
        return intersection.size.toDouble() / union.size.toDouble()
    }

    private fun tokenize(text: String): Set<String> {
        return text
            .lowercase()
            .replace("[^a-z0-9 ]".toRegex(), " ")
            .split(" ")
            .mapNotNull { token -> token.trim().takeIf { it.length > 2 } }
            .toSet()
    }

    private fun percent(score: Double): String = "${(score * 100).toInt()}%"
}
