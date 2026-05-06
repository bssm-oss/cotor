package com.cotor.app

import kotlinx.serialization.Serializable

@Serializable
data class MarketingChannelAccount(
    val channel: String,
    val accountRef: String? = null,
    val allowedDomains: List<String> = emptyList(),
    val secretRefs: List<String> = emptyList()
)

@Serializable
data class MarketingDelegationPolicy(
    val id: String,
    val companyId: String,
    val agentId: String,
    val name: String = "Owned+Social",
    val allowedDomains: List<String> = emptyList(),
    val channelAccounts: List<MarketingChannelAccount> = emptyList(),
    val dailyPostLimit: Int = 1,
    val forbiddenTerms: List<String> = emptyList(),
    val brandTone: String? = null,
    val prohibitedActions: List<String> = defaultMarketingProhibitedActions(),
    val secretRefs: List<String> = emptyList(),
    val browserSessionRef: String? = null,
    val maxRuntimeSeconds: Int = 900,
    val createdAt: Long,
    val updatedAt: Long
)

@Serializable
data class UpsertMarketingDelegationPolicyRequest(
    val id: String? = null,
    val companyId: String,
    val agentId: String,
    val name: String? = null,
    val allowedDomains: List<String> = emptyList(),
    val channelAccounts: List<MarketingChannelAccount> = emptyList(),
    val dailyPostLimit: Int = 1,
    val forbiddenTerms: List<String> = emptyList(),
    val brandTone: String? = null,
    val prohibitedActions: List<String> = defaultMarketingProhibitedActions(),
    val secretRefs: List<String> = emptyList(),
    val browserSessionRef: String? = null,
    val maxRuntimeSeconds: Int = 900
)

@Serializable
data class MarketingRunRequest(
    val companyId: String,
    val agentId: String,
    val objective: String,
    val channels: List<String> = emptyList(),
    val delegationPolicyId: String
)

@Serializable
enum class MarketingRunStatus {
    RUNNING,
    COMPLETED,
    DENIED,
    FAILED
}

@Serializable
enum class MarketingActionStatus {
    SUCCEEDED,
    DENIED,
    SKIPPED,
    FAILED
}

@Serializable
data class MarketingActionRecord(
    val id: String,
    val channel: String,
    val action: String,
    val targetUrl: String,
    val inputSummary: String,
    val postedUrl: String? = null,
    val screenshotPath: String? = null,
    val utm: String? = null,
    val status: MarketingActionStatus,
    val idempotencyKey: String,
    val createdAt: Long,
    val updatedAt: Long,
    val error: String? = null
)

@Serializable
data class MarketingRunRecord(
    val id: String,
    val companyId: String,
    val agentId: String,
    val objective: String,
    val channels: List<String>,
    val delegationPolicyId: String,
    val status: MarketingRunStatus,
    val checks: List<CapabilitySimulationResult> = emptyList(),
    val actions: List<MarketingActionRecord> = emptyList(),
    val message: String? = null,
    val error: String? = null,
    val createdAt: Long,
    val updatedAt: Long,
    val completedAt: Long? = null
)

@Serializable
data class MarketingBrowserCommand(
    val runId: String,
    val actionId: String,
    val channel: String,
    val objective: String,
    val targetUrl: String,
    val brandTone: String? = null,
    val browserSessionRef: String? = null,
    val secretRefs: List<String> = emptyList(),
    val screenshotPath: String,
    val idempotencyKey: String
)

@Serializable
data class MarketingBrowserResult(
    val postedUrl: String? = null,
    val screenshotPath: String? = null,
    val inputSummary: String,
    val outputSummary: String? = null
)

interface MarketingBrowserRunner {
    suspend fun execute(command: MarketingBrowserCommand, timeoutSeconds: Int): MarketingBrowserResult
}

fun defaultMarketingProhibitedActions(): List<String> = listOf(
    "paid-ad",
    "budget-change",
    "bulk-email",
    "direct-message",
    "payment",
    "credential-storage"
)

