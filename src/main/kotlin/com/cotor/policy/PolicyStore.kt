package com.cotor.policy

import com.cotor.app.defaultDesktopAppHome
import com.cotor.storage.writeTextAtomically
import kotlinx.serialization.json.Json
import java.nio.file.Path
import kotlin.io.path.createDirectories
import kotlin.io.path.exists
import kotlin.io.path.listDirectoryEntries
import kotlin.io.path.readText

class PolicyStore(
    private val appHomeProvider: () -> Path = { defaultDesktopAppHome() }
) {
    private val lock = Any()
    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private fun policiesDir(): Path = appHomeProvider().resolve("policies")

    private fun auditFile(): Path = policiesDir().resolve("audit.json")

    fun listDocuments(): List<PolicyDocument> {
        val dir = policiesDir()
        if (!dir.exists()) {
            return emptyList()
        }
        return dir.listDirectoryEntries("*.policy.json")
            .sortedBy { it.fileName.toString() }
            .mapNotNull { path ->
                runCatching { json.decodeFromString(PolicyDocument.serializer(), path.readText()) }.getOrNull()
            }
    }

    fun loadDocument(path: Path): PolicyDocument =
        json.decodeFromString(PolicyDocument.serializer(), path.readText())

    fun saveDocument(document: PolicyDocument) {
        val dir = policiesDir()
        dir.createDirectories()
        writeTextAtomically(
            dir.resolve("${document.name}.policy.json"),
            json.encodeToString(PolicyDocument.serializer(), document)
        )
    }

    fun appendDecision(decision: PolicyDecision) {
        synchronized(lock) {
            val current = loadAudit()
            val updated = current.copy(
                decisions = (current.decisions + decision).takeLast(500),
                updatedAt = System.currentTimeMillis()
            )
            val dir = policiesDir()
            dir.createDirectories()
            writeTextAtomically(auditFile(), json.encodeToString(PolicyAuditLog.serializer(), updated))
        }
    }

    fun loadAudit(): PolicyAuditLog {
        return synchronized(lock) {
            val file = auditFile()
            if (!file.exists()) {
                return@synchronized PolicyAuditLog()
            }
            runCatching {
                json.decodeFromString(PolicyAuditLog.serializer(), file.readText())
            }.getOrDefault(PolicyAuditLog())
        }
    }

    fun defaultPermissiveProfile(): PolicyDocument =
        PolicyDocument(
            name = "default",
            defaultEffect = PolicyEffect.ALLOW,
            rules = emptyList()
        )
}
