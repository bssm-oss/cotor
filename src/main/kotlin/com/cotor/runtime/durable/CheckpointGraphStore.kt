package com.cotor.runtime.durable

class CheckpointGraphStore(
    private val store: DurableRuntimeStore
) {
    fun upsertRun(snapshot: DurableRunSnapshot): DurableRunSnapshot {
        return store.replaceRun(snapshot)
    }

    fun appendCheckpoint(
        runId: String,
        checkpoint: CheckpointNode,
        status: DurableRunStatus? = null,
        sourceCheckpointId: String? = null
    ): DurableRunSnapshot {
        return store.updateRun(runId) { current ->
            val normalizedCheckpoint = checkpoint.copy(
                ordinal = (current.checkpoints.maxOfOrNull { it.ordinal } ?: 0) + 1,
                parentId = current.latestCheckpoint?.id
            )
            current.copy(
                status = status ?: current.status,
                sourceCheckpointId = sourceCheckpointId ?: current.sourceCheckpointId,
                updatedAt = normalizedCheckpoint.createdAt,
                checkpoints = current.checkpoints + normalizedCheckpoint
            )
        }
    }

    fun updateStatus(
        runId: String,
        status: DurableRunStatus,
        timestamp: Long = System.currentTimeMillis()
    ): DurableRunSnapshot {
        return store.updateRun(runId) { current ->
            current.copy(
                status = status,
                updatedAt = timestamp,
                completedAt = if (status == DurableRunStatus.COMPLETED || status == DurableRunStatus.FAILED) {
                    timestamp
                } else {
                    current.completedAt
                }
            )
        }
    }
}
