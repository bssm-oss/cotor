package com.cotor.app

import kotlinx.serialization.Serializable

@Serializable
data class VideoPlanRequest(
    val companyId: String,
    val agentId: String,
    val issueId: String? = null,
    val prompt: String? = null,
    val projectPath: String? = null,
    val inputPath: String? = null,
    val outputPath: String? = null,
    val provider: String? = null
)

@Serializable
data class VideoPlanResult(
    val action: String,
    val status: String,
    val checks: List<CapabilitySimulationResult>,
    val command: List<String> = emptyList(),
    val message: String,
    val error: String? = null
)
