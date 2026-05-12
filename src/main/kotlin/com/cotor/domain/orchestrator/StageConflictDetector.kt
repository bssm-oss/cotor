package com.cotor.domain.orchestrator

import com.cotor.context.TemplateEngine
import com.cotor.model.PipelineContext
import com.cotor.model.PipelineStage

class StageConflictDetector(
    private val templateEngine: TemplateEngine = TemplateEngine()
) {
    fun conflictSafeBatches(
        stages: List<PipelineStage>,
        context: PipelineContext
    ): List<List<PipelineStage>> {
        val batches = mutableListOf<MutableList<PipelineStage>>()
        val occupiedKeysByBatch = mutableListOf<MutableSet<String>>()

        stages.forEach { stage ->
            val keys = conflictKeys(stage, context)
            val index = occupiedKeysByBatch.indexOfFirst { occupied -> occupied.intersect(keys).isEmpty() }
            if (index >= 0) {
                batches[index] += stage
                occupiedKeysByBatch[index] += keys
            } else {
                batches += mutableListOf(stage)
                occupiedKeysByBatch += keys.toMutableSet()
            }
        }

        return batches
    }

    private fun conflictKeys(stage: PipelineStage, context: PipelineContext): Set<String> {
        val input = stage.input
            ?.let { runCatching { templateEngine.interpolate(it, context) }.getOrDefault(it) }
            .orEmpty()
        val pathKeys = pathPattern.findAll(input)
            .map { it.value.trim().removePrefix("./") }
            .filter { it.length > 2 }
            .map { "path:$it" }
            .toSet()
        val stageKey = "stage:${stage.id}"
        val dependencyKeys = stage.dependencies.map { "stage:$it" }.toSet()
        return pathKeys + dependencyKeys + stageKey
    }

    private companion object {
        private val pathPattern = Regex("""(?:^|\s)([\w./-]+\.(?:kt|kts|swift|ts|tsx|js|jsx|java|go|rs|py|yaml|yml|json|md))""")
    }
}
