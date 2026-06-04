package com.cotor.app

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

internal class CompanyEventStreamService(
    private val scope: CoroutineScope,
    private val snapshotProvider: suspend (String) -> CompanyDashboardResponse?,
    private val replayCapacity: Int,
    streamBufferCapacity: Int
) {
    private val sequence = AtomicLong(0L)
    private val replayLock = Any()
    private val replayBuffers = ConcurrentHashMap<String, ArrayDeque<CompanyEventEnvelope>>()
    private val requests = Channel<PublishRequest>(Channel.UNLIMITED)
    private val stream = MutableSharedFlow<CompanyEventEnvelope>(
        replay = replayCapacity,
        extraBufferCapacity = streamBufferCapacity,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )

    init {
        scope.launch {
            for (request in requests) {
                runCatching { publishRequest(request) }
            }
        }
    }

    fun clearReplay() {
        synchronized(replayLock) {
            replayBuffers.clear()
        }
    }

    fun publish(
        companyId: String,
        type: String,
        title: String,
        detail: String? = null,
        goalId: String? = null,
        issueId: String? = null,
        runId: String? = null
    ) {
        val request = PublishRequest(
            companyId = companyId,
            type = type,
            title = title,
            detail = detail,
            goalId = goalId,
            issueId = issueId,
            runId = runId
        )
        val result = requests.trySend(request)
        if (!result.isSuccess) {
            scope.launch {
                runCatching { requests.send(request) }
            }
        }
    }

    fun events(companyId: String, cursor: String? = null): Flow<CompanyEventEnvelope> = flow {
        var lastSequence = cursor?.toLongOrNull()
        val initialSequence = lastSequence
        if (initialSequence != null) {
            if (hasGap(companyId, initialSequence)) {
                gapSnapshot(companyId, initialSequence)?.let { gap ->
                    emit(gap)
                    lastSequence = gap.sequence ?: lastSequence
                }
            } else {
                replayedEvents(companyId, initialSequence).forEach { envelope ->
                    emit(envelope)
                    envelope.sequence?.let { lastSequence = it }
                }
            }
        }
        stream
            .filter { envelope ->
                val cursorSequence = lastSequence
                envelope.event.companyId == companyId &&
                    (envelope.sequence == null || cursorSequence == null || envelope.sequence > cursorSequence)
            }
            .collect { envelope ->
                val envelopeSequence = envelope.sequence
                val beforeEnvelopeSequence = lastSequence
                if (envelopeSequence != null && beforeEnvelopeSequence != null && envelopeSequence > beforeEnvelopeSequence + 1) {
                    gapSnapshot(companyId, beforeEnvelopeSequence)?.let { gap ->
                        emit(gap)
                        lastSequence = gap.sequence ?: lastSequence
                    }
                }
                val cursorSequence = lastSequence
                if (envelopeSequence == null || cursorSequence == null || envelopeSequence > cursorSequence) {
                    emit(envelope)
                    if (envelopeSequence != null) {
                        lastSequence = envelopeSequence
                    }
                }
            }
    }

    suspend fun gapSnapshot(companyId: String, afterSequence: Long?): CompanyEventEnvelope? {
        val latestSequence = latestSequence(companyId) ?: return null
        if (afterSequence != null && afterSequence >= latestSequence) {
            return null
        }
        val snapshot = snapshotProvider(companyId)
        return CompanyEventEnvelope(
            event = CompanyEvent(
                id = UUID.randomUUID().toString(),
                companyId = companyId,
                type = "stream.gap",
                title = "Recovered company event stream",
                detail = "Event stream resumed from a stale cursor; the included dashboard snapshot is authoritative.",
                createdAt = System.currentTimeMillis()
            ),
            companyDashboard = snapshot,
            sequence = latestSequence,
            cursor = latestSequence.toString(),
            gapDetected = true
        )
    }

    private suspend fun publishRequest(request: PublishRequest) {
        val nextSequence = sequence.incrementAndGet()
        val snapshot = snapshotProvider(request.companyId)
        val envelope = CompanyEventEnvelope(
            event = CompanyEvent(
                id = UUID.randomUUID().toString(),
                companyId = request.companyId,
                type = request.type,
                title = request.title,
                detail = request.detail,
                goalId = request.goalId,
                issueId = request.issueId,
                runId = request.runId,
                createdAt = request.requestedAt
            ),
            companyDashboard = snapshot,
            sequence = nextSequence,
            cursor = nextSequence.toString()
        )
        remember(envelope)
        stream.emit(envelope)
    }

    private fun remember(envelope: CompanyEventEnvelope) {
        synchronized(replayLock) {
            val buffer = replayBuffers.computeIfAbsent(envelope.event.companyId) { ArrayDeque() }
            buffer.addLast(envelope)
            while (buffer.size > replayCapacity) {
                buffer.removeFirst()
            }
        }
    }

    private fun replayedEvents(companyId: String, afterSequence: Long): List<CompanyEventEnvelope> =
        synchronized(replayLock) {
            replayBuffers[companyId]
                ?.filter { (it.sequence ?: Long.MIN_VALUE) > afterSequence }
                .orEmpty()
        }

    private fun hasGap(companyId: String, afterSequence: Long): Boolean =
        synchronized(replayLock) {
            val buffer = replayBuffers[companyId] ?: return@synchronized false
            val latest = buffer.lastOrNull()?.sequence ?: return@synchronized false
            val oldest = buffer.firstOrNull()?.sequence ?: return@synchronized false
            afterSequence < latest && afterSequence < oldest - 1
        }

    private fun latestSequence(companyId: String): Long? =
        synchronized(replayLock) {
            replayBuffers[companyId]?.lastOrNull()?.sequence
        }

    private data class PublishRequest(
        val companyId: String,
        val type: String,
        val title: String,
        val detail: String? = null,
        val goalId: String? = null,
        val issueId: String? = null,
        val runId: String? = null,
        val requestedAt: Long = System.currentTimeMillis()
    )
}
