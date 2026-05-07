package com.cotor.app

internal object CompanyMarketingDashboardProjection {
    fun policies(state: DesktopAppState, companyId: String? = null): List<MarketingDelegationPolicy> =
        state.marketingDelegationPolicies
            .filter { companyId == null || it.companyId == companyId }
            .sortedWith(
                compareBy<MarketingDelegationPolicy> { it.companyId }
                    .thenBy { it.agentId }
                    .thenBy { it.name.lowercase() }
            )

    fun runs(state: DesktopAppState, companyId: String? = null): List<MarketingRunRecord> =
        state.marketingRuns
            .filter { companyId == null || it.companyId == companyId }
            .sortedByDescending { it.createdAt }
}
