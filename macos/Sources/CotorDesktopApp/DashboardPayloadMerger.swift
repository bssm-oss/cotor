import Foundation

enum DashboardPayloadMerger {
    static func applyingCompanySnapshot(
        current dashboard: DashboardPayload,
        snapshot: CompanyDashboardPayload,
        companyId: String,
        currentMarketingPolicies: [MarketingDelegationPolicyRecord],
        currentMarketingRuns: [MarketingRunRecord],
        currentSkillRuns: [SkillRunRecord]
    ) -> DashboardPayload {
        let currentCompanyIssueIDs = Set(dashboard.issues.filter { $0.companyId == companyId }.map(\.id))
        let mergedTasks = dashboard.tasks.filter { task in
            guard let issueId = task.issueId else { return true }
            return !currentCompanyIssueIDs.contains(issueId)
        } + snapshot.tasks
        let mergedCompanyAgentDefinitions = dashboard.companyAgentDefinitions.filter { $0.companyId != companyId } + snapshot.companyAgentDefinitions
        let mergedAgentCapabilityProfiles = dashboard.agentCapabilityProfiles.filter { $0.companyId != companyId } + snapshot.agentCapabilityProfiles
        let mergedProjectContexts = dashboard.projectContexts.filter { $0.companyId != companyId } + snapshot.projectContexts
        let mergedGoals = dashboard.goals.filter { $0.companyId != companyId } + snapshot.goals
        let mergedIssues = dashboard.issues.filter { $0.companyId != companyId } + snapshot.issues
        let mergedReviewQueue = dashboard.reviewQueue.filter { $0.companyId != companyId } + snapshot.reviewQueue
        let mergedOrgProfiles = dashboard.orgProfiles.filter { $0.companyId != companyId } + snapshot.orgProfiles
        let mergedWorkflowTopologies = dashboard.workflowTopologies.filter { $0.companyId != companyId } + snapshot.workflowTopologies
        let mergedGoalDecisions = dashboard.goalDecisions.filter { $0.companyId != companyId } + snapshot.goalDecisions
        let mergedRunningAgentSessions = dashboard.runningAgentSessions.filter { $0.companyId != companyId } + snapshot.runningAgentSessions
        let mergedActivity = dashboard.activity.filter { $0.companyId != companyId } + snapshot.activity
        let mergedCompanyRuntimes = dashboard.companyRuntimes.filter { $0.companyId != companyId } + [snapshot.runtime]
        let mergedContextEntries = dashboard.agentContextEntries.filter { $0.companyId != companyId } + snapshot.agentContextEntries
        let mergedAgentMessages = dashboard.agentMessages.filter { $0.companyId != companyId } + snapshot.agentMessages
        let mergedMarketingPolicies = currentMarketingPolicies.filter { $0.companyId != companyId } + snapshot.marketingDelegationPolicies
        let mergedMarketingRuns = currentMarketingRuns.filter { $0.companyId != companyId } + snapshot.marketingRuns
        let mergedSkillRuns = currentSkillRuns.filter { $0.companyId != companyId } + snapshot.skillRuns
        let mergedAgentPerformance = dashboard.agentPerformance.filter { performance in
            !snapshot.companyAgentDefinitions.contains { $0.id == performance.agentId }
        } + snapshot.agentPerformance
        let mergedBackendStatuses = mergeBackendStatuses(current: dashboard.backendStatuses, incoming: snapshot.backendStatuses)

        return DashboardPayload(
            repositories: dashboard.repositories,
            workspaces: dashboard.workspaces,
            tasks: mergedTasks.sorted { $0.updatedAt > $1.updatedAt },
            settings: dashboard.settings,
            companies: snapshot.companies.sorted { $0.updatedAt > $1.updatedAt },
            companyAgentDefinitions: mergedCompanyAgentDefinitions.sorted {
                if $0.displayOrder == $1.displayOrder {
                    return $0.title < $1.title
                }
                return $0.displayOrder < $1.displayOrder
            },
            agentCapabilityProfiles: mergedAgentCapabilityProfiles.sorted { $0.updatedAt > $1.updatedAt },
            projectContexts: mergedProjectContexts.sorted { $0.lastUpdatedAt > $1.lastUpdatedAt },
            goals: mergedGoals.sorted { $0.updatedAt > $1.updatedAt },
            issues: mergedIssues.sorted { $0.updatedAt > $1.updatedAt },
            reviewQueue: mergedReviewQueue.sorted { $0.updatedAt > $1.updatedAt },
            orgProfiles: mergedOrgProfiles.sorted { $0.roleName < $1.roleName },
            workflowTopologies: mergedWorkflowTopologies.sorted { $0.updatedAt > $1.updatedAt },
            goalDecisions: mergedGoalDecisions.sorted { $0.createdAt > $1.createdAt },
            runningAgentSessions: mergedRunningAgentSessions.sorted { $0.updatedAt > $1.updatedAt },
            backendStatuses: mergedBackendStatuses,
            opsMetrics: snapshot.opsMetrics,
            activity: mergedActivity.sorted { $0.createdAt > $1.createdAt },
            companyRuntimes: mergedCompanyRuntimes.sorted { ($0.lastTickAt ?? 0) > ($1.lastTickAt ?? 0) },
            agentContextEntries: mergedContextEntries.sorted { $0.createdAt > $1.createdAt },
            agentMessages: mergedAgentMessages.sorted { $0.createdAt > $1.createdAt },
            marketingDelegationPolicies: mergedMarketingPolicies.sorted { $0.name < $1.name },
            marketingRuns: mergedMarketingRuns.sorted { $0.createdAt > $1.createdAt },
            skillRuns: mergedSkillRuns.sorted { $0.updatedAt > $1.updatedAt },
            agentPerformance: mergedAgentPerformance
        )
    }

    private static func mergeBackendStatuses(
        current: [ExecutionBackendStatusPayload],
        incoming: [ExecutionBackendStatusPayload]
    ) -> [ExecutionBackendStatusPayload] {
        guard !incoming.isEmpty else { return current }
        let incomingKinds = Set(incoming.map(\.kind))
        return current.filter { !incomingKinds.contains($0.kind) } + incoming
    }
}
