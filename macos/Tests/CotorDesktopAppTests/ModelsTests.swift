import Foundation
import Testing
@testable import CotorDesktopApp

struct ModelsTests {
    @Test
    func desktopApiUrlBuilderKeepsQueryOutOfPath() throws {
        let url = try DesktopAPI.makeURL(
            baseURL: URL(string: "http://127.0.0.1:8787")!,
            path: "api/app/marketing/policies",
            query: [URLQueryItem(name: "companyId", value: "company-1")]
        )

        #expect(url.absoluteString == "http://127.0.0.1:8787/api/app/marketing/policies?companyId=company-1")
        #expect(!url.path.contains("?"))
    }

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
    func companyRuntimeSnapshotDecodesSchedulerAndAttentionFields() throws {
        let json = """
        {
          "companyId": "company-1",
          "status": "RUNNING",
          "tickIntervalSeconds": 60,
          "activeGoalCount": 1,
          "activeIssueCount": 2,
          "autonomyEnabledGoalCount": 1,
          "backendKind": "LOCAL_COTOR",
          "backendHealth": "healthy",
          "backendLifecycleState": "RUNNING",
          "todaySpentCents": 3,
          "monthSpentCents": 9,
          "consecutiveFailures": 2,
          "adaptiveTickMs": 15000,
          "resumableRunCount": 1,
          "waitingApprovalCount": 1,
          "blockedByPolicyCount": 2,
          "blockedByCiCount": 3,
          "quarantinedRunCount": 4,
          "resumableRunIds": ["run-1"],
          "pendingApprovalRunIds": ["run-2"],
          "pendingIssueIds": ["issue-1"],
          "blockedIssueIds": ["issue-2"],
          "reviewQueueAttentionIds": ["review-1"],
          "lastReconciliationAt": 12345
        }
        """.data(using: .utf8)!

        let runtime = try JSONDecoder().decode(CompanyRuntimeSnapshotRecord.self, from: json)

        #expect(runtime.consecutiveFailures == 2)
        #expect(runtime.adaptiveTickMs == 15000)
        #expect(runtime.resumableRunIds == ["run-1"])
        #expect(runtime.pendingIssueIds == ["issue-1"])
        #expect(runtime.blockedIssueIds == ["issue-2"])
        #expect(runtime.lastReconciliationAt == 12345)
    }

    @Test
    func dashboardPayloadRejectsMalformedCompanyRuntimeFields() {
        let json = """
        {
          "companyRuntimes": [
            {
              "status": 42
            }
          ]
        }
        """.data(using: .utf8)!

        #expect(throws: Error.self) {
            _ = try JSONDecoder().decode(DashboardPayload.self, from: json)
        }
    }

    @Test
    func dashboardEmptyStartsWithoutCompanyData() {
        let dashboard = DashboardPayload.empty

        #expect(dashboard.companies.isEmpty)
        #expect(dashboard.companyAgentDefinitions.isEmpty)
        #expect(dashboard.issues.isEmpty)
        #expect(dashboard.reviewQueue.isEmpty)
        #expect(dashboard.settings.availableAgents.isEmpty)
        #expect(dashboard.agentPerformance.isEmpty)
        #expect(dashboard.marketingDelegationPolicies.isEmpty)
        #expect(dashboard.marketingRuns.isEmpty)
    }

    @Test
    func dashboardPayloadsDecodeMissingOptionalArraysAsEmpty() throws {
        let companyDashboard = try JSONDecoder().decode(CompanyDashboardPayload.self, from: Data("{}".utf8))
        let dashboard = try JSONDecoder().decode(DashboardPayload.self, from: Data("{}".utf8))

        #expect(companyDashboard.agentPerformance.isEmpty)
        #expect(dashboard.agentPerformance.isEmpty)
        #expect(companyDashboard.marketingDelegationPolicies.isEmpty)
        #expect(companyDashboard.marketingRuns.isEmpty)
        #expect(dashboard.marketingDelegationPolicies.isEmpty)
        #expect(dashboard.marketingRuns.isEmpty)
    }

    @Test
    func dashboardPayloadsDecodeMarketingStateFromDashboardContract() throws {
        let data = Data("""
        {
          "marketingDelegationPolicies": [
            {
              "id": "policy-1",
              "companyId": "company-1",
              "agentId": "agent-1",
              "name": "Owned",
              "allowedDomains": ["example.com"],
              "channelAccounts": [],
              "dailyPostLimit": 1,
              "forbiddenTerms": [],
              "brandTone": "direct",
              "prohibitedActions": ["paid-ad"],
              "secretRefs": [],
              "browserSessionRef": null,
              "maxRuntimeSeconds": 900,
              "createdAt": 1,
              "updatedAt": 2
            }
          ],
          "marketingRuns": [
            {
              "id": "run-1",
              "companyId": "company-1",
              "agentId": "agent-1",
              "objective": "post",
              "channels": ["web"],
              "delegationPolicyId": "policy-1",
              "status": "COMPLETED",
              "actions": [
                {
                  "id": "action-1",
                  "runId": "run-1",
                  "channel": "web",
                  "targetUrl": "http://127.0.0.1:8787/health",
                  "inputSummary": "web: no editable field; no publish button",
                  "postedUrl": "http://127.0.0.1:8787/health?utm_source=cotor",
                  "screenshotPath": "/tmp/cotor-marketing.png",
                  "utm": "utm_source=cotor",
                  "status": "SUCCEEDED",
                  "idempotencyKey": "key-1",
                  "error": null,
                  "createdAt": 1,
                  "updatedAt": 2
                }
              ],
              "message": "done",
              "error": null,
              "createdAt": 1,
              "updatedAt": 2,
              "completedAt": 3
            }
          ]
        }
        """.utf8)
        let dashboard = try JSONDecoder().decode(DashboardPayload.self, from: data)

        #expect(dashboard.marketingDelegationPolicies.map(\.id) == ["policy-1"])
        #expect(dashboard.marketingRuns.map(\.id) == ["run-1"])
        #expect(dashboard.marketingRuns.first?.actions.first?.runId == "run-1")
        #expect(dashboard.marketingRuns.first?.actions.first?.action == "web")
    }

    @Test
    func marketingActionDecodesLegacyRecordsWithoutActionField() throws {
        let data = Data("""
        {
          "id": "action-1",
          "channel": "web",
          "targetUrl": "http://127.0.0.1:58973",
          "inputSummary": "web form",
          "postedUrl": "http://127.0.0.1:58973/published",
          "screenshotPath": null,
          "utm": null,
          "status": "SUCCEEDED",
          "idempotencyKey": "key",
          "createdAt": 1,
          "updatedAt": 2,
          "error": null
        }
        """.utf8)

        let action = try JSONDecoder().decode(MarketingActionRecord.self, from: data)

        #expect(action.action == "web")
        #expect(action.channel == "web")
    }

    @Test
    func companyEventLineDecoderDropsMalformedLineAndKeepsValidEventsDecodable() throws {
        let invalid = DesktopAPI.decodeCompanyEventLine("{not-json")
        let heartbeat = DesktopAPI.decodeCompanyEventLine("   \n")
        let valid = DesktopAPI.decodeCompanyEventLine("""
        {
          "event": {
            "id": "event-1",
            "companyId": "company-1",
            "type": "runtime.tick",
            "title": "Tick",
            "detail": null,
            "goalId": null,
            "issueId": null,
            "runId": null,
            "createdAt": 1
          },
          "dashboard": null,
          "companyDashboard": null
        }
        """)

        #expect(invalid == nil)
        #expect(heartbeat == nil)
        #expect(try #require(valid).event.companyId == "company-1")
    }

    @Test
    func desktopAPIUsesOnlyConfiguredOrRuntimeToken() throws {
        #expect(DesktopAPI.configuredAppToken(processEnvironment: [:]) == nil)
        #expect(DesktopAPI.configuredAppToken(processEnvironment: ["COTOR_APP_TOKEN": " configured-token "]) == "configured-token")

        let appHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("cotor-desktop-token-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: appHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: appHome) }

        #expect(DesktopAPI.readRuntimeAppToken(appHome: appHome) == nil)
        let tokenURL = try #require(DesktopAPI.writeRuntimeAppToken("runtime-token", appHome: appHome))

        #expect(tokenURL.lastPathComponent == "app-server.token")
        #expect(DesktopAPI.readRuntimeAppToken(appHome: appHome) == "runtime-token")
    }

    @Test
    func desktopAPIEncodesDynamicPathSegments() throws {
        let api = DesktopAPI(baseURL: try #require(URL(string: "http://127.0.0.1:8787")), token: "token")
        let url = try api.makeURL(pathSegments: ["api", "app", "companies", "company/a?b#c", "dashboard"])

        #expect(url.absoluteString == "http://127.0.0.1:8787/api/app/companies/company%2Fa%3Fb%23c/dashboard")
    }

    @Test
    func desktopAPIPreservesConfiguredBasePathWhenBuildingRoutes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DesktopAPICapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var capturedPath: String?
        DesktopAPICapturingURLProtocol.requestHandler = { request in
            capturedPath = request.url?.path
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"ok":true}"#.utf8))
        }
        defer { DesktopAPICapturingURLProtocol.requestHandler = nil }
        let api = DesktopAPI(
            baseURL: try #require(URL(string: "http://127.0.0.1:8787/prefix")),
            token: nil,
            session: session
        )

        let ok = try await api.health()

        #expect(ok)
        #expect(capturedPath == "/prefix/api/app/health")
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
    func companyAgentDefinitionDecodesMissingMentorAsNil() throws {
        let data = """
        {
          "id": "agent-builder",
          "companyId": "company",
          "title": "Builder",
          "agentCli": "opencode",
          "model": "opencode/deepseek-v4-flash-free",
          "roleSummary": "implementation",
          "specialties": ["implementation"],
          "collaborationInstructions": null,
          "preferredCollaboratorIds": [],
          "memoryNotes": null,
          "enabled": true,
          "displayOrder": 0,
          "createdAt": 1,
          "updatedAt": 2
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CompanyAgentDefinitionRecord.self, from: data)

        #expect(decoded.mentorAgentId == nil)
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
    func companyDailyReportDecodesSummaryItemsAndCost() throws {
        let data = """
        {
          "id": "company-1-2026-05-05",
          "companyId": "company-1",
          "date": "2026-05-05",
          "generatedAt": 10,
          "periodStart": 1,
          "periodEnd": 2,
          "summary": "1 completed · 0 blocked",
          "highlights": [],
          "completedItems": [
            {
              "id": "issue-1",
              "title": "Ship README change",
              "detail": "Merged PR #7",
              "issueId": "issue-1",
              "goalId": "goal-1",
              "runId": "run-1",
              "pullRequestUrl": "https://github.com/acme/repo/pull/7",
              "status": "DONE",
              "severity": "success",
              "timestamp": 2
            }
          ],
          "pullRequests": [],
          "reviewItems": [],
          "blockedItems": [],
          "autoRecoveredItems": [],
          "recommendedNextActions": [],
          "costSummary": {
            "estimatedRunCostCents": 42,
            "todaySpentCents": 100,
            "monthSpentCents": 200,
            "dailyBudgetCents": 500,
            "monthlyBudgetCents": 2000,
            "budgetPaused": false
          },
          "activityCount": 1
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CompanyDailyReportRecord.self, from: data)

        #expect(decoded.date == "2026-05-05")
        #expect(decoded.completedItems.first?.pullRequestUrl?.contains("/pull/7") == true)
        #expect(decoded.costSummary.estimatedRunCostCents == 42)
        #expect(decoded.activityCount == 1)
    }

    @Test
    func operatorCommandPayloadsRenderModeResponsesAndPendingApprovals() throws {
        let request = OperatorCommandRequestPayload(
            message: "모든 에이전트 opencode deepseek",
            automationMode: "AGENT_APPROVED",
            confirmFullAuto: false,
            confirmStaffing: false
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
    func operatorChatMapsRawModesAndStatusesForDisplay() {
        #expect(operatorAutomationModeDisplayName("FULL_AUTO", language: .korean) == "완전 자동")
        #expect(operatorAutomationModeDisplayName("AGENT_APPROVED", language: .korean) == "내부 승인")
        #expect(operatorAutomationModeDisplayName("ASK_ME", language: .korean) == "확인 후 실행")
        #expect(operatorActionStatusDisplayName("USER_CONFIRMATION_REQUIRED", language: .korean) == "확인 필요")
        #expect(operatorActionStatusDisplayName("AGENT_APPROVAL_REQUESTED", language: .korean) == "내부 승인 대기")
    }

    @Test
    func operatorChatSanitizesMachineSummaryText() {
        let sanitized = sanitizeOperatorUserText(
            "FULL_AUTO changed: DONE runtime=stopped, backend=healthy, status=AGENT_APPROVAL_REQUESTED",
            language: .korean
        )

        #expect(sanitized.contains("완전 자동"))
        #expect(sanitized.contains("runtime=") == false)
        #expect(sanitized.contains("backend=") == false)
        #expect(sanitized.contains("FULL_AUTO") == false)
        #expect(sanitized.contains("AGENT_APPROVAL_REQUESTED") == false)
    }

    @Test
    func operatorChatMessageKeepsAssistantCommandsWithUserFacingLabels() {
        let command = OperatorChatCommand(
            title: "완전 자동 켜기",
            prompt: "완전 자동으로 바꿔줘",
            kind: .confirmFullAuto
        )
        let message = OperatorChatMessage(role: .assistant, text: "켜려면 확인하세요.", commands: [command])

        #expect(message.role == .assistant)
        #expect(message.commands.first?.kind == .confirmFullAuto)
        #expect(message.commands.first?.title == "완전 자동 켜기")
    }

    @Test
    func operatorChatMessagesPreserveTimelineRoles() {
        let messages = [
            OperatorChatMessage(role: .user, text: "상태 확인"),
            OperatorChatMessage(role: .assistant, text: "정상입니다."),
            OperatorChatMessage(role: .system, text: "연결 상태 변경")
        ]

        #expect(messages.map(\.role) == [.user, .assistant, .system])
        #expect(messages.map(\.text) == ["상태 확인", "정상입니다.", "연결 상태 변경"])
    }

    @Test
    func operatorChatResponseDecodesAnswerSources() throws {
        let json = """
        {
          "message": "Builder가 현재 가장 좋은 에이전트입니다.",
          "automationMode": "AGENT_APPROVED",
          "actions": [],
          "pendingApprovals": [],
          "blockedActions": [],
          "summary": {
            "runtimeStatus": "STOPPED",
            "backendHealth": "healthy",
            "activeAgentCount": 0,
            "blockedIssueCount": 0,
            "reviewQueueCount": 0,
            "pendingApprovalCount": 0,
            "budgetPaused": false
          },
          "answerSources": [
            {
              "type": "agent-performance",
              "title": "Builder · Builder",
              "detail": "score=91",
              "refId": "agent-builder"
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(OperatorChatResponsePayload.self, from: json)

        #expect(response.message.contains("Builder"))
        #expect(response.summary?.runtimeStatus == "STOPPED")
        #expect(response.answerSources.first?.type == "agent-performance")
        #expect(response.answerSources.first?.refId == "agent-builder")
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

    @Test
    func appServerConfigLoopbackURLIsAllowed() {
        let fallback = URL(string: "http://127.0.0.1:8787")!
        let (url, _) = DesktopAPI.validatedAppServerConfiguration(
            envURL: "http://127.0.0.1:9000",
            envAllowRemote: nil,
            envToken: nil,
            fallbackURL: fallback,
            appToken: "token"
        )
        #expect(url.absoluteString == "http://127.0.0.1:9000")
    }

    @Test
    func appServerConfigLocalhostURLIsAllowed() {
        let fallback = URL(string: "http://127.0.0.1:8787")!
        let (url, _) = DesktopAPI.validatedAppServerConfiguration(
            envURL: "http://localhost:8787",
            envAllowRemote: nil,
            envToken: nil,
            fallbackURL: fallback,
            appToken: "token"
        )
        #expect(url.host == "localhost")
    }

    @Test
    func appServerConfigRemoteURLWithoutFlagFallsBackToLoopback() {
        let fallback = URL(string: "http://127.0.0.1:8787")!
        let (url, _) = DesktopAPI.validatedAppServerConfiguration(
            envURL: "https://remote.cotor.io:8787",
            envAllowRemote: nil,
            envToken: "some-token",
            fallbackURL: fallback,
            appToken: "app-token"
        )
        #expect(url.absoluteString == fallback.absoluteString)
    }

    @Test
    func appServerConfigDeceptiveLoopbackHostFallsBackToLoopback() {
        let fallback = URL(string: "http://127.0.0.1:8787")!
        let (url, _) = DesktopAPI.validatedAppServerConfiguration(
            envURL: "http://localhost.evil.test:8787",
            envAllowRemote: nil,
            envToken: "some-token",
            fallbackURL: fallback,
            appToken: "app-token"
        )
        #expect(url.absoluteString == fallback.absoluteString)
    }

    @Test
    func appServerConfigNonHttpLoopbackURLFallsBackToLoopback() {
        let fallback = URL(string: "http://127.0.0.1:8787")!
        let (url, _) = DesktopAPI.validatedAppServerConfiguration(
            envURL: "ftp://localhost:8787",
            envAllowRemote: nil,
            envToken: "some-token",
            fallbackURL: fallback,
            appToken: "app-token"
        )
        #expect(url.absoluteString == fallback.absoluteString)
    }

    @Test
    func appServerConfigRemoteURLWithFlagAndTokenIsAllowed() {
        let fallback = URL(string: "http://127.0.0.1:8787")!
        let (url, token) = DesktopAPI.validatedAppServerConfiguration(
            envURL: "https://remote.cotor.io:8787",
            envAllowRemote: "1",
            envToken: "explicit-token",
            fallbackURL: fallback,
            appToken: "app-token"
        )
        #expect(url.absoluteString == "https://remote.cotor.io:8787")
        #expect(token == "explicit-token")
    }

    @Test
    func appServerConfigRemoteURLWithFlagButNoTokenFallsBackToLoopback() {
        let fallback = URL(string: "http://127.0.0.1:8787")!
        let (url, _) = DesktopAPI.validatedAppServerConfiguration(
            envURL: "https://remote.cotor.io:8787",
            envAllowRemote: "1",
            envToken: nil,
            fallbackURL: fallback,
            appToken: "app-token"
        )
        #expect(url.absoluteString == fallback.absoluteString)
    }

    @Test
    func appServerConfigNilEnvURLFallsBackToLoopback() {
        let fallback = URL(string: "http://127.0.0.1:8787")!
        let (url, _) = DesktopAPI.validatedAppServerConfiguration(
            envURL: nil,
            envAllowRemote: nil,
            envToken: nil,
            fallbackURL: fallback,
            appToken: "token"
        )
        #expect(url.absoluteString == fallback.absoluteString)
    }
}

final class DesktopAPICapturingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (response, data) = try Self.requestHandler?(request) ?? {
                let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }()
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
