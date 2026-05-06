import Foundation
import Testing
@testable import CotorDesktopApp

struct ModelsTests {
    @Test
    func companySidebarDisclosureStateStartsCollapsed() {
        var state = CompanySidebarDisclosureState()

        #expect(state.isCompanyDraftExpanded == false)
        #expect(state.isAdvancedSettingsExpanded == false)

        state.isCompanyDraftExpanded = true
        #expect(state.isCompanyDraftExpanded)

        state.isAdvancedSettingsExpanded = true
        #expect(state.isAdvancedSettingsExpanded)
    }

    @Test
    func companyRuntimeSnapshotDetectsManualStop() {
        let runtime = CompanyRuntimeSnapshotRecord(
            companyId: "company-1",
            status: "STOPPED",
            tickIntervalSeconds: 60,
            activeGoalCount: 0,
            activeIssueCount: 0,
            autonomyEnabledGoalCount: 0,
            lastStartedAt: nil,
            lastStoppedAt: 10,
            manuallyStoppedAt: 10,
            lastTickAt: nil,
            lastAction: "runtime-stopped",
            lastError: nil,
            backendKind: "LOCAL_COTOR",
            backendHealth: "stopped",
            backendMessage: "Stopped",
            backendLifecycleState: "STOPPED",
            backendPid: nil,
            backendPort: nil,
            todaySpentCents: 0,
            monthSpentCents: 0,
            budgetPausedAt: nil,
            budgetResetDate: nil
        )

        #expect(runtime.isManuallyStopped)
        #expect(!runtime.isBudgetPaused)
    }

    @Test
    func companyRuntimeSnapshotDetectsBudgetPause() {
        let runtime = CompanyRuntimeSnapshotRecord(
            companyId: "company-1",
            status: "RUNNING",
            tickIntervalSeconds: 60,
            activeGoalCount: 1,
            activeIssueCount: 2,
            autonomyEnabledGoalCount: 1,
            lastStartedAt: 10,
            lastStoppedAt: nil,
            manuallyStoppedAt: nil,
            lastTickAt: 20,
            lastAction: "running",
            lastError: nil,
            backendKind: "LOCAL_COTOR",
            backendHealth: "healthy",
            backendMessage: "Running",
            backendLifecycleState: "RUNNING",
            backendPid: 42,
            backendPort: 8787,
            todaySpentCents: 100,
            monthSpentCents: 200,
            budgetPausedAt: 30,
            budgetResetDate: "2026-04-03"
        )

        #expect(!runtime.isManuallyStopped)
        #expect(runtime.isBudgetPaused)
    }

    @Test
    func dashboardEmptyStartsWithoutCompanyData() {
        let dashboard = DashboardPayload.empty

        #expect(dashboard.companies.isEmpty)
        #expect(dashboard.companyAgentDefinitions.isEmpty)
        #expect(dashboard.issues.isEmpty)
        #expect(dashboard.reviewQueue.isEmpty)
        #expect(dashboard.settings.availableAgents.isEmpty)
    }

    @Test
    func desktopSettingsDecodesMissingAgentModelFieldsAsEmpty() throws {
        let encoded = try JSONEncoder().encode(DashboardPayload.empty.settings)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "availableAgentModels")
        object.removeValue(forKey: "defaultAgentModels")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(DesktopSettingsPayload.self, from: legacyData)

        #expect(decoded.availableAgentModels.isEmpty)
        #expect(decoded.defaultAgentModels.isEmpty)
    }

    @Test
    func agentCapabilitySettingDecodesMissingChannelAllowlistAsEmpty() throws {
        let data = """
        {
          "enabled": true,
          "mode": "AUTO",
          "domainAllowlist": ["cms.example.com"],
          "skillAllowlist": ["marketing-operator"],
          "requiresEvidence": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AgentCapabilitySettingRecord.self, from: data)

        #expect(decoded.mode == "AUTO")
        #expect(decoded.domainAllowlist == ["cms.example.com"])
        #expect(decoded.channelAllowlist.isEmpty)
        #expect(decoded.skillAllowlist == ["marketing-operator"])
    }

    @Test
    func companyRecordDecodesMissingOperatorModeAsLegacyState() throws {
        let data = """
        {
          "id": "company-1",
          "name": "Legacy",
          "rootPath": "/tmp/legacy",
          "repositoryId": "repo-1",
          "defaultBaseBranch": "main",
          "backendKind": "LOCAL_COTOR",
          "linearSyncEnabled": false,
          "autonomyEnabled": true,
          "dailyBudgetCents": null,
          "monthlyBudgetCents": null,
          "createdAt": 1,
          "updatedAt": 2
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CompanyRecord.self, from: data)

        #expect(decoded.operatorAutomationMode == nil)
    }

    @Test
    func operatorCommandPayloadsRenderModeResponsesAndPendingApprovals() throws {
        let request = OperatorCommandRequestPayload(
            message: "모든 에이전트 opencode deepseek",
            automationMode: "AGENT_APPROVED",
            confirmFullAuto: false
        )
        let requestData = try JSONEncoder().encode(request)
        let decodedRequest = try JSONDecoder().decode(OperatorCommandRequestPayload.self, from: requestData)

        let response = OperatorCommandResponsePayload(
            message: "1 action routed for internal approval.",
            automationMode: "AGENT_APPROVED",
            actions: [],
            pendingApprovals: [
                OperatorCommandActionPayload(
                    type: "agent-approval",
                    title: "Approve blocked issue retry",
                    detail: "Routed to CEO.",
                    status: "AGENT_APPROVAL_REQUESTED"
                )
            ],
            blockedActions: [],
            summary: OperatorCompanySummaryPayload(
                runtimeStatus: "RUNNING",
                backendHealth: "healthy",
                activeAgentCount: 2,
                blockedIssueCount: 1,
                reviewQueueCount: 3,
                pendingApprovalCount: 1,
                budgetPaused: false
            )
        )
        let responseData = try JSONEncoder().encode(response)
        let decodedResponse = try JSONDecoder().decode(OperatorCommandResponsePayload.self, from: responseData)

        #expect(decodedRequest.automationMode == "AGENT_APPROVED")
        #expect(decodedResponse.automationMode == "AGENT_APPROVED")
        #expect(decodedResponse.pendingApprovals.first?.status == "AGENT_APPROVAL_REQUESTED")
        #expect(decodedResponse.summary?.pendingApprovalCount == 1)
    }

    @Test
    func batchUpdatePayloadEncodesSelectedFields() throws {
        let payload = BatchUpdateCompanyAgentsPayload(
            agentIds: ["agent-1", "agent-2"],
            agentCli: "codex-oauth",
            model: "gpt-5.4",
            specialties: ["qa", "review"],
            enabled: false
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(BatchUpdateCompanyAgentsPayload.self, from: data)

        #expect(decoded.agentIds == ["agent-1", "agent-2"])
        #expect(decoded.agentCli == "codex-oauth")
        #expect(decoded.model == "gpt-5.4")
        #expect(decoded.specialties == ["qa", "review"])
        #expect(decoded.enabled == false)
    }
}
