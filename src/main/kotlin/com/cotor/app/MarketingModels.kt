package com.cotor.app

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class MarketingChannelAccount(
    val channel: String,
    val accountRef: String,
    val allowedDomains: List<String> = emptyList(),
    val secretRefs: List<String> = emptyList()
)

@Serializable
data class MarketingDelegationPolicy(
    val id: String = UUID.randomUUID().toString(),
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
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = createdAt
)

@Serializable
data class UpsertMarketingDelegationPolicyRequest(
    val id: String? = null,
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
    val maxRuntimeSeconds: Int = 900
)

@Serializable
data class MarketingRunRequest(
    val companyId: String,
    val agentId: String,
    val objective: String,
    val channels: List<String> = emptyList(),
    val delegationPolicyId: String? = null
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
    val id: String = UUID.randomUUID().toString(),
    val runId: String,
    val channel: String,
    val targetUrl: String,
    val inputSummary: String,
    val postedUrl: String? = null,
    val screenshotPath: String? = null,
    val utm: String? = null,
    val status: MarketingActionStatus,
    val idempotencyKey: String,
    val error: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = createdAt
)

@Serializable
data class MarketingRunRecord(
    val id: String = UUID.randomUUID().toString(),
    val companyId: String,
    val agentId: String,
    val objective: String,
    val channels: List<String>,
    val delegationPolicyId: String,
    val status: MarketingRunStatus = MarketingRunStatus.RUNNING,
    val actions: List<MarketingActionRecord> = emptyList(),
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = createdAt,
    val completedAt: Long? = null,
    val error: String? = null
)

@Serializable
data class MarketingBrowserCommand(
    val channel: String,
    val objective: String,
    val targetUrl: String,
    val inputSummary: String,
    val browserSessionRef: String? = null,
    val screenshotPath: String,
    val maxRuntimeSeconds: Int = 900
)

@Serializable
data class MarketingBrowserResult(
    val targetUrl: String,
    val postedUrl: String? = null,
    val screenshotPath: String? = null,
    val inputSummary: String
)

interface MarketingBrowserRunner {
    suspend fun execute(command: MarketingBrowserCommand): MarketingBrowserResult
}

fun defaultMarketingProhibitedActions(): List<String> = listOf(
    "paid-ad",
    "budget-change",
    "bulk-email",
    "direct-message",
    "payment",
    "credential-storage"
)
