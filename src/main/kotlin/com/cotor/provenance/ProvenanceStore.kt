package com.cotor.provenance

import com.cotor.app.defaultDesktopAppHome
import com.cotor.storage.writeTextAtomically
import kotlinx.serialization.json.Json
import java.nio.file.Path
import kotlin.io.path.exists
import kotlin.io.path.readText

class ProvenanceStore(
    private val appHomeProvider: () -> Path = { defaultDesktopAppHome() }
) {
    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private fun graphFile(): Path =
        appHomeProvider().resolve("provenance").resolve("graph.json")

    fun load(): EvidenceGraph {
        val file = graphFile()
        if (!file.exists()) {
            return EvidenceGraph()
        }
        return runCatching {
            json.decodeFromString(EvidenceGraph.serializer(), file.readText())
        }.getOrDefault(EvidenceGraph())
    }

    fun save(graph: EvidenceGraph) {
        val file = graphFile()
        writeTextAtomically(file, json.encodeToString(EvidenceGraph.serializer(), graph))
    }
}
