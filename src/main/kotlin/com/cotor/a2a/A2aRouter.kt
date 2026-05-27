package com.cotor.a2a

import com.cotor.app.DesktopAppService
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put
import java.net.URI
import java.nio.file.InvalidPathException
import java.nio.file.Path
import java.util.UUID

private const val MAX_A2A_ARTIFACT_KIND_CHARS = 64
private const val MAX_A2A_ARTIFACT_LABEL_CHARS = 512
private const val MAX_A2A_ARTIFACT_URL_CHARS = 2_048
private const val MAX_A2A_ARTIFACT_PATH_CHARS = 4_096
private const val MAX_A2A_ARTIFACT_REF_CHARS = 128
private val A2A_ARTIFACT_KIND_REGEX = Regex("[a-z][a-z0-9._-]{0,63}")
private val A2A_ARTIFACT_REF_REGEX = Regex("[A-Za-z0-9._:/@-]{1,128}")

class A2aRouter(
    private val desktopService: DesktopAppService,
    private val sessionStore: A2aSessionStore = A2aSessionStore(persistenceStore = A2aSessionPersistenceStore()),
    private val dedupeStore: A2aDedupeStore = A2aDedupeStore(persistenceStore = A2aDedupePersistenceStore()),
    private val artifactStore: A2aArtifactStore = A2aArtifactStore()
) {
    private val json = Json {
        encodeDefaults = true
        ignoreUnknownKeys = true
    }

    fun openSession(request: A2aHelloRequest, now: Long = System.currentTimeMillis()): A2aWelcomeResponse {
        val session = sessionStore.open(request, now)
        return A2aWelcomeResponse(
            sessionId = session.id,
            heartbeatIntervalMs = sessionStore.heartbeatIntervalMs(),
            serverTs = now
        )
    }

    fun heartbeat(sessionId: String, now: Long = System.currentTimeMillis()): A2aHeartbeatResponse {
        val session = sessionStore.touch(sessionId, now)
        return A2aHeartbeatResponse(
            sessionId = session.id,
            serverTs = now
        )
    }

    suspend fun postMessage(envelope: A2aEnvelope, now: Long = System.currentTimeMillis()): A2aAckResponse {
        val normalizedEnvelope = envelope.normalizedForRouting()
        validateEnvelope(normalizedEnvelope, now)
        validateSenderTenant(normalizedEnvelope, now)
        val freshAck = A2aAck(
            messageId = normalizedEnvelope.id,
            dedupeStatus = "accepted",
            serverTs = now
        )
        val dedupeScope = "${normalizedEnvelope.tenant.companyId}:${normalizedEnvelope.dedupeKey}"
        val (accepted, ack) = dedupeStore.remember(dedupeScope, freshAck)
        if (!accepted) {
            return A2aAckResponse(
                ack = ack.copy(dedupeStatus = "already_processed")
            )
        }
        if (normalizedEnvelope.type == "sync.snapshot.request") {
            enqueueSnapshotResponse(normalizedEnvelope, now)
            return A2aAckResponse(ack = ack)
        }
        persistInternalMessage(normalizedEnvelope)
        recipientsFor(normalizedEnvelope).forEach { session ->
            sessionStore.enqueue(session.id, normalizedEnvelope, now)
        }
        return A2aAckResponse(ack = ack)
    }

    fun pullMessages(sessionId: String, after: Long?, limit: Int, now: Long = System.currentTimeMillis()): A2aPullResponse {
        require(limit > 0) { "limit must be positive" }
        require(sessionStore.session(sessionId) != null) { "Unknown session: $sessionId" }
        val messages = sessionStore.pull(sessionId, after, limit.coerceAtMost(100), now)
        return A2aPullResponse(
            messages = messages,
            nextCursor = messages.lastOrNull()?.cursor
        )
    }

    fun acknowledgeMessages(request: A2aAckMessagesRequest, now: Long = System.currentTimeMillis()): A2aAckMessagesResponse {
        require(request.throughCursor > 0) { "throughCursor must be positive" }
        require(sessionStore.session(request.sessionId) != null) { "Unknown session: ${request.sessionId}" }
        val (removedCount, pendingCount) = sessionStore.acknowledge(request.sessionId, request.throughCursor, now)
        return A2aAckMessagesResponse(
            sessionId = request.sessionId,
            removedCount = removedCount,
            pendingCount = pendingCount,
            serverTs = now
        )
    }

    suspend fun snapshot(request: A2aSnapshotRequest, now: Long = System.currentTimeMillis()): A2aSnapshotResponse {
        val dashboard = desktopService.companyDashboardReadOnly(request.tenant.companyId)
        val snapshot = buildJsonObject {
            put("companyId", request.tenant.companyId)
            put("serverTs", now)
            put("dashboard", json.encodeToJsonElement(dashboard))
        }
        return A2aSnapshotResponse(serverTs = now, snapshot = snapshot)
    }

    fun registerArtifact(request: A2aArtifactRegistrationRequest, now: Long = System.currentTimeMillis()): A2aArtifactRegistrationResponse {
        val tenant = normalizeArtifactTenant(request.tenant)
        val artifact = A2aArtifactRegistration(
            id = UUID.randomUUID().toString(),
            tenant = tenant,
            kind = normalizeArtifactKind(request.kind),
            label = normalizeArtifactLabel(request.label),
            url = normalizeArtifactUrl(request.url),
            localPath = normalizeArtifactLocalPath(request.localPath),
            issueId = normalizeArtifactReference(request.issueId, "issueId"),
            taskId = normalizeArtifactReference(request.taskId, "taskId"),
            runId = normalizeArtifactReference(request.runId, "runId"),
            createdAt = now
        )
        artifactStore.append(artifact)
        return A2aArtifactRegistrationResponse(artifact = artifact)
    }

    fun listArtifacts(
        tenant: A2aTenant,
        issueId: String? = null,
        taskId: String? = null,
        runId: String? = null
    ): A2aArtifactListResponse {
        val filtered = artifactStore.list(tenant, issueId, taskId, runId)
        return A2aArtifactListResponse(artifacts = filtered)
    }

    internal fun artifactCount(): Int = artifactStore.count()

    private fun normalizeArtifactTenant(tenant: A2aTenant): A2aTenant {
        val companyId = tenant.companyId.trim()
        require(companyId.isNotBlank()) { "tenant.companyId is required" }
        require(companyId.length <= MAX_A2A_ARTIFACT_REF_CHARS) { "tenant.companyId is too long" }
        require(A2A_ARTIFACT_REF_REGEX.matches(companyId)) { "tenant.companyId contains unsupported characters" }
        return tenant.copy(
            companyId = companyId,
            projectContextId = normalizeArtifactReference(tenant.projectContextId, "tenant.projectContextId")
        )
    }

    private fun normalizeArtifactKind(kind: String): String {
        val normalized = kind.trim().lowercase()
        require(normalized.isNotBlank()) { "kind is required" }
        require(normalized.length <= MAX_A2A_ARTIFACT_KIND_CHARS) { "kind is too long" }
        require(A2A_ARTIFACT_KIND_REGEX.matches(normalized)) {
            "kind must be a lowercase token containing only letters, digits, dot, underscore, or hyphen"
        }
        return normalized
    }

    private fun normalizeArtifactLabel(label: String): String {
        val normalized = label.trim()
        require(normalized.isNotBlank()) { "label is required" }
        require(normalized.length <= MAX_A2A_ARTIFACT_LABEL_CHARS) { "label is too long" }
        require(!normalized.contains('\u0000')) { "label contains unsupported characters" }
        return normalized
    }

    private fun normalizeArtifactUrl(url: String?): String? {
        val normalized = url?.trim()?.takeIf { it.isNotBlank() } ?: return null
        require(normalized.length <= MAX_A2A_ARTIFACT_URL_CHARS) { "url is too long" }
        require(!normalized.contains('\u0000')) { "url contains unsupported characters" }
        val uri = runCatching { URI(normalized).normalize() }
            .getOrElse { throw IllegalArgumentException("url must be a valid URI") }
        val scheme = uri.scheme?.lowercase()
        require(scheme == "http" || scheme == "https") { "url must use http or https" }
        require(!uri.host.isNullOrBlank()) { "url must include a host" }
        require(uri.userInfo == null) { "url must not include credentials" }
        return uri.toString()
    }

    private fun normalizeArtifactLocalPath(localPath: String?): String? {
        val normalized = localPath?.trim()?.takeIf { it.isNotBlank() } ?: return null
        require(normalized.length <= MAX_A2A_ARTIFACT_PATH_CHARS) { "localPath is too long" }
        require(!normalized.contains('\u0000')) { "localPath contains unsupported characters" }
        val path = try {
            Path.of(normalized).normalize()
        } catch (_: InvalidPathException) {
            throw IllegalArgumentException("localPath must be a valid path")
        }
        if (!path.isAbsolute) {
            require(path.none { it.toString() == ".." }) { "localPath must not escape its base directory" }
        }
        return path.toString()
    }

    private fun normalizeArtifactReference(value: String?, label: String): String? {
        val normalized = value?.trim()?.takeIf { it.isNotBlank() } ?: return null
        require(normalized.length <= MAX_A2A_ARTIFACT_REF_CHARS) { "$label is too long" }
        require(A2A_ARTIFACT_REF_REGEX.matches(normalized)) { "$label contains unsupported characters" }
        return normalized
    }

    private fun validateEnvelope(envelope: A2aEnvelope, now: Long) {
        require(envelope.v == "a2a.v1") { "Unsupported protocol version: ${envelope.v}" }
        require(envelope.id.isNotBlank()) { "message id is required" }
        require(envelope.type in SUPPORTED_MESSAGE_TYPES) { "Unsupported message type: ${envelope.type}" }
        require(envelope.dedupeKey.isNotBlank()) { "dedupeKey is required" }
        require(envelope.ttlMs > 0) { "ttlMs must be positive" }
        require(envelope.from.agentId.trim().isNotBlank()) { "from.agentId is required" }
        require(envelope.tenant.companyId.trim().isNotBlank()) { "tenant.companyId is required" }
        if (envelope.ts + envelope.ttlMs < now) {
            error("expired_message")
        }
    }

    private fun validateSenderTenant(envelope: A2aEnvelope, now: Long) {
        val senderAgentId = envelope.from.agentId.trim()
        val knownSessions = sessionStore.sessionsForAgent(senderAgentId, now)
        if (knownSessions.none { it.tenant == envelope.tenant }) {
            throw IllegalArgumentException("from.agentId requires an active session for tenant.companyId ${envelope.tenant.companyId}")
        }
    }

    private suspend fun persistInternalMessage(envelope: A2aEnvelope) {
        val issueId = envelope.correlation?.issueId
        val goalId = envelope.correlation?.goalId
        val body = envelope.body as? JsonObject
        val title = body?.get("title")?.toString()?.trim('"')
            ?: body?.get("label")?.toString()?.trim('"')
            ?: envelope.type
        val content = body?.get("content")?.toString()?.trim('"')
            ?: body?.get("message")?.toString()?.trim('"')
            ?: title
        when (envelope.type) {
            "task.assign" -> {
                desktopService.ingestA2aTaskAssignment(
                    companyId = envelope.tenant.companyId,
                    fromAgentName = envelope.from.roleName ?: envelope.from.agentId,
                    toAgentName = envelope.to.firstOrNull()?.let { it.roleName ?: it.agentId },
                    title = title,
                    content = content,
                    issueId = issueId,
                    goalId = goalId
                )
            }
            "task.accept" -> {
                desktopService.ingestAgentNote(
                    companyId = envelope.tenant.companyId,
                    agentName = envelope.from.roleName ?: envelope.from.agentId,
                    title = title,
                    content = content,
                    issueId = issueId,
                    goalId = goalId,
                    visibility = "goal"
                )
            }
            "message.note" -> {
                desktopService.ingestAgentNote(
                    companyId = envelope.tenant.companyId,
                    agentName = envelope.from.roleName ?: envelope.from.agentId,
                    title = title,
                    content = content,
                    issueId = issueId,
                    goalId = goalId,
                    visibility = "goal"
                )
            }
            "message.warning" -> {
                desktopService.ingestAgentWarning(
                    companyId = envelope.tenant.companyId,
                    agentName = envelope.from.roleName ?: envelope.from.agentId,
                    title = title,
                    content = content,
                    issueId = issueId,
                    goalId = goalId
                )
            }
            "message.handoff" -> {
                desktopService.ingestAgentHandoff(
                    companyId = envelope.tenant.companyId,
                    fromAgentName = envelope.from.roleName ?: envelope.from.agentId,
                    toAgentName = envelope.to.firstOrNull()?.let { it.roleName ?: it.agentId },
                    title = title,
                    content = content,
                    issueId = issueId,
                    goalId = goalId
                )
            }
            "message.escalation" -> {
                desktopService.ingestAgentEscalation(
                    companyId = envelope.tenant.companyId,
                    fromAgentName = envelope.from.roleName ?: envelope.from.agentId,
                    toAgentName = envelope.to.firstOrNull()?.let { it.roleName ?: it.agentId },
                    title = title,
                    content = content,
                    issueId = issueId,
                    goalId = goalId
                )
            }
            "message.feedback" -> {
                desktopService.ingestAgentFeedback(
                    companyId = envelope.tenant.companyId,
                    fromAgentName = envelope.from.roleName ?: envelope.from.agentId,
                    toAgentName = envelope.to.firstOrNull()?.let { it.roleName ?: it.agentId },
                    title = title,
                    content = content,
                    issueId = issueId,
                    goalId = goalId
                )
            }
            "review.verdict" -> {
                val queueItemId = envelope.correlation?.reviewQueueItemId
                    ?: body?.get("queueItemId")?.toString()?.trim('"')
                    ?: throw IllegalArgumentException("review.verdict requires correlation.reviewQueueItemId or body.queueItemId")
                val stage = body?.get("stage")?.toString()?.trim('"')
                    ?: throw IllegalArgumentException("review.verdict requires body.stage")
                val verdict = body["verdict"]?.toString()?.trim('"')
                    ?: throw IllegalArgumentException("review.verdict requires body.verdict")
                val feedback = body["feedback"]?.toString()?.trim('"')
                desktopService.ingestA2aReviewVerdict(
                    companyId = envelope.tenant.companyId,
                    queueItemId = queueItemId,
                    stage = stage,
                    verdict = verdict,
                    feedback = feedback
                )
            }
            "review.request" -> {
                val reviewIssueId = envelope.correlation?.issueId
                    ?: body?.get("issueId")?.toString()?.trim('"')
                    ?: throw IllegalArgumentException("review.request requires correlation.issueId or body.issueId")
                val taskId = envelope.correlation?.taskId
                    ?: body?.get("taskId")?.toString()?.trim('"')
                val runId = envelope.correlation?.runId
                    ?: body?.get("runId")?.toString()?.trim('"')
                desktopService.ingestA2aReviewRequest(
                    companyId = envelope.tenant.companyId,
                    issueId = reviewIssueId,
                    taskId = taskId,
                    runId = runId
                )
            }
            "run.update" -> {
                val runId = envelope.correlation?.runId
                    ?: body?.get("runId")?.toString()?.trim('"')
                    ?: throw IllegalArgumentException("run.update requires correlation.runId or body.runId")
                val status = body?.get("status")?.toString()?.trim('"')
                    ?: throw IllegalArgumentException("run.update requires body.status")
                val output = body?.get("output")?.toString()?.trim('"')
                val error = body?.get("error")?.toString()?.trim('"')
                val processId = body?.get("processId")?.toString()?.trim('"')?.toLongOrNull()
                val durationMs = body?.get("durationMs")?.toString()?.trim('"')?.toLongOrNull()
                desktopService.ingestA2aRunUpdate(
                    companyId = envelope.tenant.companyId,
                    runId = runId,
                    status = status,
                    output = output,
                    error = error,
                    processId = processId,
                    durationMs = durationMs
                )
            }
        }
    }

    private fun recipientsFor(envelope: A2aEnvelope): List<A2aSession> {
        val tenantSessions = sessionStore.sessionsForTenant(envelope.tenant)
        if (envelope.to.isEmpty()) {
            return tenantSessions.filterNot { it.agentId == envelope.from.agentId }
        }
        return tenantSessions.filter { session ->
            envelope.to.any { target ->
                target.agentId.equals(session.agentId, ignoreCase = true) ||
                    (
                        !target.executionAgentName.isNullOrBlank() &&
                            target.executionAgentName.equals(session.executionAgentName, ignoreCase = true)
                        )
            }
        }
    }

    private suspend fun enqueueSnapshotResponse(requestEnvelope: A2aEnvelope, now: Long) {
        val snapshot = snapshot(A2aSnapshotRequest(tenant = requestEnvelope.tenant), now)
        val responseEnvelope = A2aEnvelope(
            v = "a2a.v1",
            id = UUID.randomUUID().toString(),
            type = "sync.snapshot.response",
            ts = now,
            tenant = requestEnvelope.tenant,
            from = A2aParty(
                agentId = "cotor-app-server",
                roleName = "Cotor App Server",
                executionAgentName = "app-server"
            ),
            to = listOf(requestEnvelope.from),
            correlation = requestEnvelope.correlation,
            causation = A2aCausation(messageId = requestEnvelope.id),
            dedupeKey = "${requestEnvelope.dedupeKey}:snapshot-response",
            ttlMs = requestEnvelope.ttlMs,
            body = snapshot.snapshot
        )
        requesterSessionsFor(requestEnvelope).forEach { session ->
            sessionStore.enqueue(session.id, responseEnvelope, now)
        }
    }

    private fun requesterSessionsFor(envelope: A2aEnvelope): List<A2aSession> {
        return sessionStore.sessionsForTenant(envelope.tenant).filter { session ->
            session.agentId.equals(envelope.from.agentId, ignoreCase = true) ||
                (
                    !session.executionAgentName.isNullOrBlank() &&
                        !envelope.from.executionAgentName.isNullOrBlank() &&
                        session.executionAgentName.equals(envelope.from.executionAgentName, ignoreCase = true)
                    )
        }
    }

    companion object {
        val SUPPORTED_MESSAGE_TYPES = setOf(
            "task.assign",
            "task.accept",
            "run.update",
            "review.request",
            "review.verdict",
            "message.note",
            "message.warning",
            "message.handoff",
            "message.feedback",
            "message.escalation",
            "sync.snapshot.request",
            "sync.snapshot.response"
        )
    }
}

private fun A2aEnvelope.normalizedForRouting(): A2aEnvelope =
    copy(
        id = id.trim(),
        type = type.trim(),
        tenant = tenant.normalized(),
        from = from.normalized(),
        to = to.map { it.normalized() },
        dedupeKey = dedupeKey.trim()
    )

private fun A2aTenant.normalized(): A2aTenant =
    copy(
        companyId = companyId.trim(),
        projectContextId = projectContextId?.trim()?.takeIf { it.isNotBlank() }
    )

private fun A2aParty.normalized(): A2aParty =
    copy(
        agentId = agentId.trim(),
        roleName = roleName?.trim()?.takeIf { it.isNotBlank() },
        executionAgentName = executionAgentName?.trim()?.takeIf { it.isNotBlank() }
    )
