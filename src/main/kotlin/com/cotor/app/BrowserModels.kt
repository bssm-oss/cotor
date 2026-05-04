package com.cotor.app

import kotlinx.serialization.Serializable

@Serializable
data class BrowserSmokeRequest(
    val companyId: String,
    val agentId: String,
    val url: String,
    val screenshot: Boolean = false,
    val trace: Boolean = false,
    val record: Boolean = false,
    val interact: Boolean = false
)

@Serializable
data class BrowserSmokeResult(
    val url: String,
    val status: String,
    val checks: List<CapabilitySimulationResult>,
    val command: List<String> = emptyList(),
    val message: String,
    val error: String? = null
)
