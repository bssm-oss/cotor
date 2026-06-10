import Foundation
import Testing
@testable import CotorDesktopApp

@MainActor
struct DesktopStoreTests {
    @Test
    func defaultAgentSelectionUsesGemma4Only() {
        let store = DesktopStore()

        #expect(store.agentSelection == Set(["gemma4"]))
    }

    @Test
    func expectedCompanyEventStreamInterruptionsDoNotRepresentOfflineState() {
        #expect(isExpectedCompanyEventStreamInterruption(URLError(.networkConnectionLost)))
        #expect(isExpectedCompanyEventStreamInterruption(URLError(.timedOut)))
        #expect(isExpectedCompanyEventStreamInterruption(URLError(.cancelled)))
        #expect(!isExpectedCompanyEventStreamInterruption(URLError(.cannotConnectToHost)))
    }

    @Test
    func companyEventStreamHeartbeatIsRecognizedAsKeepaliveOnly() {
        let envelope = CompanyEventEnvelopePayload(
            event: CompanyEventRecord(
                id: "heartbeat-1",
                companyId: "company",
                type: "stream.heartbeat",
                title: "Stream heartbeat",
                detail: nil,
                goalId: nil,
                issueId: nil,
                runId: nil,
                createdAt: 1
            ),
            dashboard: nil,
            companyDashboard: nil,
            sequence: nil,
            cursor: nil,
            gapDetected: nil
        )

        #expect(isCompanyEventStreamHeartbeat(envelope))
    }

    @Test
    func selectedCompanyAgentPerformanceFiltersAndCountsScoreableAgents() {
        let store = DesktopStore()
        store.selectedCompanyID = "company"
        let visibleAgent = agentDefinition(id: "agent-builder", title: "Builder", roleSummary: "Build work")
        let hiddenAgent = CompanyAgentDefinitionRecord(
            id: "agent-hidden",
            companyId: "other-company",
            title: "Other",
            agentCli: "opencode",
            model: nil,
            roleSummary: "Other company",
            specialties: [],
            collaborationInstructions: nil,
            preferredCollaboratorIds: [],
            mentorAgentId: nil,
            memoryNotes: nil,
            enabled: true,
            displayOrder: 0,
            createdAt: 0,
            updatedAt: 0
        )

        store.dashboard = DashboardPayload(
            repositories: [],
            workspaces: [],
            tasks: [],
            settings: DashboardPayload.empty.settings,
            companies: [],
            companyAgentDefinitions: [visibleAgent, hiddenAgent],
            agentCapabilityProfiles: [],
            projectContexts: [],
            goals: [],
            issues: [],
            reviewQueue: [],
            orgProfiles: [],
            workflowTopologies: [],
            goalDecisions: [],
            runningAgentSessions: [],
            backendStatuses: [],
            opsMetrics: DashboardPayload.empty.opsMetrics,
            activity: [],
            companyRuntimes: [],
            agentContextEntries: [],
            agentMessages: [],
            agentPerformance: [
                AgentPerformanceSnapshotRecord(
                    agentId: visibleAgent.id,
                    agentName: "Builder",
                    roleName: "Builder",
                    agentCli: "opencode",
                    model: "ollama/gemma4:12b",
                    score: 91,
                    completedIssues: 3,
                    activeIssues: 1,
                    blockedIssues: 0,
                    runSuccessRate: 0.9,
                    qaPassRate: 0.8,
                    reviewRejectionCount: 0,
                    retryCount: 1,
                    averageDurationMs: 90_000,
                    estimatedCostCents: 42,
                    lastActivityAt: 100,
                    dataSufficiency: "SUFFICIENT"
                ),
                AgentPerformanceSnapshotRecord(
                    agentId: hiddenAgent.id,
                    agentName: "Other",
                    roleName: "Other",
                    agentCli: "opencode",
                    model: nil,
                    score: nil,
                    completedIssues: 0,
                    activeIssues: 0,
                    blockedIssues: 0,
                    runSuccessRate: nil,
                    qaPassRate: nil,
                    reviewRejectionCount: 0,
                    retryCount: 0,
                    averageDurationMs: nil,
                    estimatedCostCents: nil,
                    lastActivityAt: nil,
                    dataSufficiency: "INSUFFICIENT_DATA"
                )
            ]
        )

        #expect(store.agentPerformance.map(\.agentId) == [visibleAgent.id])
        #expect(store.scoreableAgentPerformanceCount == 1)
    }

    @Test
    func bootstrapRetriesEmptySuccessfulDashboardBeforeSettling() {
        let store = DesktopStore()

        store.isOffline = false
        store.dashboard = DashboardPayload.empty

        #expect(store.shouldRetryBootstrapAfterRefresh(attempt: 0, maxAttempts: 4))
        #expect(!store.shouldRetryBootstrapAfterRefresh(attempt: 3, maxAttempts: 4))

        store.dashboard = DashboardPayload(
            repositories: [],
            workspaces: [],
            tasks: [],
            settings: DashboardPayload.empty.settings,
            companies: [company(id: "company", repositoryId: "repo", name: "Company")],
            companyAgentDefinitions: [],
            agentCapabilityProfiles: [],
            projectContexts: [],
            goals: [],
            issues: [],
            reviewQueue: [],
            orgProfiles: [],
            workflowTopologies: [],
            goalDecisions: [],
            runningAgentSessions: [],
            backendStatuses: [],
            opsMetrics: DashboardPayload.empty.opsMetrics,
            activity: [],
            companyRuntimes: [],
            agentContextEntries: [],
            agentMessages: [],
            agentPerformance: []
        )

        #expect(!store.shouldRetryBootstrapAfterRefresh(attempt: 0, maxAttempts: 4))

        store.isOffline = true

        #expect(store.shouldRetryBootstrapAfterRefresh(attempt: 0, maxAttempts: 4))
    }

    @Test
    func fullAutoOperatorChatRequestAddsConfirmationToTimeline() async {
        let store = DesktopStore()

        await store.submitOperatorChatMessage("완전 자동으로 바꿔줘")

        #expect(store.operatorChatMessages.map(\.role) == [.user, .assistant])
        #expect(store.operatorChatMessages.first?.text == "완전 자동으로 바꿔줘")
        #expect(store.operatorChatMessages.last?.commands.map(\.kind) == [.confirmFullAuto, .cancelConfirmation])
        #expect(store.isSendingOperatorChatMessage == false)
    }

    @Test
    func askMeHrStaffingChatRequestAddsConfirmationToTimeline() async {
        let store = DesktopStore()
        store.language = .korean
        store.selectedCompanyID = "company"
        store.dashboard = DashboardPayload(
            repositories: [],
            workspaces: [],
            tasks: [],
            settings: DashboardPayload.empty.settings,
            companies: [company(id: "company", repositoryId: "repo", name: "Test Company", operatorAutomationMode: "ASK_ME")],
            companyAgentDefinitions: [],
            agentCapabilityProfiles: [],
            projectContexts: [],
            goals: [],
            issues: [],
            reviewQueue: [],
            orgProfiles: [],
            workflowTopologies: [],
            goalDecisions: [],
            runningAgentSessions: [],
            backendStatuses: [],
            opsMetrics: DashboardPayload.empty.opsMetrics,
            activity: [],
            companyRuntimes: [],
            agentContextEntries: [],
            agentMessages: [],
            agentPerformance: []
        )

        await store.submitOperatorChatMessage("팀 보강해")

        #expect(store.operatorChatMessages.map(\.role) == [.user, .assistant])
        #expect(store.operatorChatMessages.last?.commands.map(\.kind) == [.confirmHrStaffing, .cancelConfirmation])
        #expect(store.operatorChatMessages.last?.text.contains("HR 매니저") == true)
        #expect(store.isSendingOperatorChatMessage == false)
    }

    @Test
    func operatorSuggestedCommandsExposeHrStaffingAndMentorActions() {
        let store = DesktopStore()
        store.language = .korean

        let commands = store.operatorSuggestedCommands()
        let titles = commands.map(\.title)
        let prompts = commands.map(\.prompt).joined(separator: "\n")

        #expect(titles.contains("팀 보강"))
        #expect(titles.contains("사수 지정"))
        #expect(prompts.contains("HR 매니저"))
        #expect(prompts.contains("사수"))
    }

    @Test
    func orgProfileShiftSelectionAndClearWorkAcrossRanges() {
        let store = DesktopStore()
        store.dashboard = DashboardPayload(
            repositories: [],
            workspaces: [],
            tasks: [],
            settings: DashboardPayload.empty.settings,
            companies: [],
            companyAgentDefinitions: [],
            agentCapabilityProfiles: [],
            projectContexts: [],
            goals: [],
            issues: [],
            reviewQueue: [],
            orgProfiles: [
                OrgAgentProfileRecord(id: "a", companyId: "company", roleName: "CEO", executionAgentName: "opencode", capabilities: ["planning"], linearAssigneeId: nil, reviewerPolicy: nil, mergeAuthority: true, enabled: true),
                OrgAgentProfileRecord(id: "b", companyId: "company", roleName: "Builder", executionAgentName: "opencode", capabilities: ["implementation"], linearAssigneeId: nil, reviewerPolicy: nil, mergeAuthority: false, enabled: true),
                OrgAgentProfileRecord(id: "c", companyId: "company", roleName: "QA", executionAgentName: "opencode", capabilities: ["qa"], linearAssigneeId: nil, reviewerPolicy: "review-queue", mergeAuthority: false, enabled: true),
            ],
            workflowTopologies: [],
            goalDecisions: [],
            runningAgentSessions: [],
            backendStatuses: [],
            opsMetrics: DashboardPayload.empty.opsMetrics,
            activity: [],
            companyRuntimes: [],
            agentContextEntries: [],
            agentMessages: [],
            agentPerformance: []
        )

        store.toggleOrgProfileSelection(id: "a", shiftKey: false)
        #expect(store.selectedOrgProfileIDs == Set(["a"]))

        store.toggleOrgProfileSelection(id: "c", shiftKey: true)
        #expect(store.selectedOrgProfileIDs == Set(["a", "c"]))

        store.clearOrgProfileSelection()
        #expect(store.selectedOrgProfileIDs.isEmpty)
    }

    @Test
    func companyAgentSelectionIsAdditiveAndOrgProfilesResolveToBatchEditableAgents() {
        let store = DesktopStore()
        store.selectedCompanyID = "company"
        store.dashboard = DashboardPayload(
            repositories: [],
            workspaces: [],
            tasks: [],
            settings: DashboardPayload.empty.settings,
            companies: [
                CompanyRecord(
                    id: "company",
                    name: "Test Company",
                    rootPath: "/tmp/company",
                    repositoryId: "repo",
                    defaultBaseBranch: "master",
                    backendKind: "LOCAL_COTOR",
                    linearSyncEnabled: false,
                    linearConfigOverride: nil,
                    autonomyEnabled: true,
                    dailyBudgetCents: nil,
                    monthlyBudgetCents: nil,
                    createdAt: 0,
                    updatedAt: 0,
                    operatorAutomationMode: "AGENT_APPROVED"
                )
            ],
            companyAgentDefinitions: [
                CompanyAgentDefinitionRecord(
                    id: "agent-qa",
                    companyId: "company",
                    title: "QA",
                    agentCli: "opencode",
                    model: "opencode/qwen3.6-plus-free",
                    roleSummary: "review",
                    specialties: ["qa", "review"],
                    collaborationInstructions: nil,
                    preferredCollaboratorIds: [],
                    mentorAgentId: nil,
                    memoryNotes: nil,
                    enabled: true,
                    displayOrder: 0,
                    createdAt: 0,
                    updatedAt: 0
                ),
                CompanyAgentDefinitionRecord(
                    id: "agent-builder",
                    companyId: "company",
                    title: "Builder",
                    agentCli: "opencode",
                    model: "opencode/qwen3.6-plus-free",
                    roleSummary: "implementation",
                    specialties: ["build"],
                    collaborationInstructions: nil,
                    preferredCollaboratorIds: [],
                    mentorAgentId: nil,
                    memoryNotes: nil,
                    enabled: true,
                    displayOrder: 1,
                    createdAt: 0,
                    updatedAt: 0
                ),
            ],
            agentCapabilityProfiles: [],
            projectContexts: [],
            goals: [],
            issues: [],
            reviewQueue: [],
            orgProfiles: [
                OrgAgentProfileRecord(id: "profile-qa", companyId: "company", roleName: "QA", executionAgentName: "opencode", capabilities: ["qa"], linearAssigneeId: nil, reviewerPolicy: "review-queue", mergeAuthority: false, enabled: true),
                OrgAgentProfileRecord(id: "profile-builder", companyId: "company", roleName: "Builder", executionAgentName: "opencode", capabilities: ["build"], linearAssigneeId: nil, reviewerPolicy: nil, mergeAuthority: false, enabled: true),
            ],
            workflowTopologies: [],
            goalDecisions: [],
            runningAgentSessions: [],
            backendStatuses: [],
            opsMetrics: DashboardPayload.empty.opsMetrics,
            activity: [],
            companyRuntimes: [],
            agentContextEntries: [],
            agentMessages: [],
            agentPerformance: []
        )

        store.toggleCompanyAgentSelection(id: "agent-qa", shiftKey: false)
        store.toggleCompanyAgentSelection(id: "agent-builder", shiftKey: false)
        #expect(store.selectedCompanyAgentDefinitionIDs == Set(["agent-qa", "agent-builder"]))

        store.clearCompanyAgentSelection()
        store.toggleOrgProfileSelection(id: "profile-qa", shiftKey: false)

        #expect(store.selectedBatchEditableAgents.map(\.id) == ["agent-qa"])
    }

    @Test
    func agentCliSelectionResetsModelToProviderDefault() {
        let store = DesktopStore()
        let baseSettings = DashboardPayload.empty.settings
        store.dashboard = DashboardPayload(
            repositories: [],
            workspaces: [],
            tasks: [],
            settings: DesktopSettingsPayload(
                appHome: baseSettings.appHome,
                managedReposRoot: baseSettings.managedReposRoot,
                availableAgents: ["opencode", "codex"],
                availableCliAgents: ["opencode", "codex", "gemma4", "ollama", "lmstudio"],
                availableAgentModels: [
                    "opencode": ["ollama/gemma4:12b", "opencode/big-pickle", "opencode/deepseek-v4-flash-free"],
                    "codex": ["openai/gpt-5.5"],
                    "gemma4": ["gemma4:12b"],
                    "ollama": ["gemma4:12b"],
                    "lmstudio": ["gemma4:12b"]
                ],
                defaultAgentModels: [
                    "opencode": "ollama/gemma4:12b",
                    "codex": "openai/gpt-5.5",
                    "gemma4": "gemma4:12b",
                    "ollama": "gemma4:12b",
                    "lmstudio": "gemma4:12b"
                ],
                recentCompanies: baseSettings.recentCompanies,
                defaultLaunchMode: baseSettings.defaultLaunchMode,
                backendSettings: baseSettings.backendSettings,
                githubPublishStatus: baseSettings.githubPublishStatus,
                linearSettings: baseSettings.linearSettings,
                backendStatuses: baseSettings.backendStatuses,
                shortcuts: baseSettings.shortcuts
            ),
            companies: [],
            companyAgentDefinitions: [],
            agentCapabilityProfiles: [],
            projectContexts: [],
            goals: [],
            issues: [],
            reviewQueue: [],
            orgProfiles: [],
            workflowTopologies: [],
            goalDecisions: [],
            runningAgentSessions: [],
            backendStatuses: [],
            opsMetrics: DashboardPayload.empty.opsMetrics,
            activity: [],
            companyRuntimes: [],
            agentContextEntries: [],
            agentMessages: [],
            agentPerformance: []
        )

        store.selectNewCompanyAgentCli("opencode")
        #expect(store.newCompanyAgentModel == "ollama/gemma4:12b")

        store.selectNewCompanyAgentCli("codex")
        #expect(store.newCompanyAgentModel == "openai/gpt-5.5")

        store.selectNewCompanyAgentCli("gemma4")
        #expect(store.newCompanyAgentModel == "gemma4:12b")

        store.selectNewCompanyAgentCli("lmstudio")
        #expect(store.newCompanyAgentModel == "gemma4:12b")
    }

    @Test
    func emptyAgentDraftCliResolvesToVisiblePreferredCli() {
        let store = DesktopStore()
        let baseSettings = DashboardPayload.empty.settings
        store.dashboard = DashboardPayload(
            repositories: [],
            workspaces: [],
            tasks: [],
            settings: DesktopSettingsPayload(
                appHome: baseSettings.appHome,
                managedReposRoot: baseSettings.managedReposRoot,
                availableAgents: ["opencode"],
                availableCliAgents: ["opencode"],
                availableAgentModels: [
                    "opencode": ["ollama/gemma4:12b"]
                ],
                defaultAgentModels: [
                    "opencode": "ollama/gemma4:12b"
                ],
                recentCompanies: baseSettings.recentCompanies,
                defaultLaunchMode: baseSettings.defaultLaunchMode,
                backendSettings: baseSettings.backendSettings,
                githubPublishStatus: baseSettings.githubPublishStatus,
                linearSettings: baseSettings.linearSettings,
                backendStatuses: baseSettings.backendStatuses,
                shortcuts: baseSettings.shortcuts
            ),
            companies: [],
            companyAgentDefinitions: [],
            agentCapabilityProfiles: [],
            projectContexts: [],
            goals: [],
            issues: [],
            reviewQueue: [],
            orgProfiles: [],
            workflowTopologies: [],
            goalDecisions: [],
            runningAgentSessions: [],
            backendStatuses: [],
            opsMetrics: DashboardPayload.empty.opsMetrics,
            activity: [],
            companyRuntimes: [],
            agentContextEntries: [],
            agentMessages: [],
            agentPerformance: []
        )

        store.newCompanyAgentCli = ""

        #expect(store.resolvedNewCompanyAgentCli == "opencode")
        #expect(store.newCompanyAgentModelOptions == ["ollama/gemma4:12b"])
    }

    @Test
    func localAgentSelectionPinsGemma4DefaultEvenWhenAliasIsNotDiscovered() {
        let store = DesktopStore()
        let baseSettings = DashboardPayload.empty.settings
        store.dashboard = DashboardPayload(
            repositories: [],
            workspaces: [],
            tasks: [],
            settings: DesktopSettingsPayload(
                appHome: baseSettings.appHome,
                managedReposRoot: baseSettings.managedReposRoot,
                availableAgents: ["codex", "gemma4", "lmstudio"],
                availableCliAgents: ["codex", "gemma4", "lmstudio"],
                availableAgentModels: [
                    "codex": ["openai/gpt-5.5"]
                ],
                defaultAgentModels: [
                    "codex": "openai/gpt-5.5",
                    "gemma4": "gemma4:12b",
                    "lmstudio": "gemma4:12b"
                ],
                recentCompanies: baseSettings.recentCompanies,
                defaultLaunchMode: baseSettings.defaultLaunchMode,
                backendSettings: baseSettings.backendSettings,
                githubPublishStatus: baseSettings.githubPublishStatus,
                linearSettings: baseSettings.linearSettings,
                backendStatuses: baseSettings.backendStatuses,
                shortcuts: baseSettings.shortcuts
            ),
            companies: [],
            companyAgentDefinitions: [],
            agentCapabilityProfiles: [],
            projectContexts: [],
            goals: [],
            issues: [],
            reviewQueue: [],
            orgProfiles: [],
            workflowTopologies: [],
            goalDecisions: [],
            runningAgentSessions: [],
            backendStatuses: [],
            opsMetrics: DashboardPayload.empty.opsMetrics,
            activity: [],
            companyRuntimes: [],
            agentContextEntries: [],
            agentMessages: [],
            agentPerformance: []
        )

        store.selectNewCompanyAgentCli("codex")
        #expect(store.newCompanyAgentModel == "openai/gpt-5.5")

        store.selectNewCompanyAgentCli("gemma4")
        #expect(store.newCompanyAgentModel == "gemma4:12b")

        store.selectNewCompanyAgentCli("lmstudio")
        #expect(store.newCompanyAgentModel == "gemma4:12b")
    }

    @Test
    func localAgentSelectionKeepsGemma4DefaultAheadOfDiscoveredFallback() {
        let store = DesktopStore()
        let baseSettings = DashboardPayload.empty.settings
        store.dashboard = DashboardPayload(
            repositories: [],
            workspaces: [],
            tasks: [],
            settings: DesktopSettingsPayload(
                appHome: baseSettings.appHome,
                managedReposRoot: baseSettings.managedReposRoot,
                availableAgents: ["gemma4"],
                availableCliAgents: ["gemma4"],
                availableAgentModels: [
                    "gemma4": ["google/gemma-4-31b-it"]
                ],
                defaultAgentModels: [
                    "gemma4": "gemma4:12b"
                ],
                recentCompanies: baseSettings.recentCompanies,
                defaultLaunchMode: baseSettings.defaultLaunchMode,
                backendSettings: baseSettings.backendSettings,
                githubPublishStatus: baseSettings.githubPublishStatus,
                linearSettings: baseSettings.linearSettings,
                backendStatuses: baseSettings.backendStatuses,
                shortcuts: baseSettings.shortcuts
            ),
            companies: [],
            companyAgentDefinitions: [],
            agentCapabilityProfiles: [],
            projectContexts: [],
            goals: [],
            issues: [],
            reviewQueue: [],
            orgProfiles: [],
            workflowTopologies: [],
            goalDecisions: [],
            runningAgentSessions: [],
            backendStatuses: [],
            opsMetrics: DashboardPayload.empty.opsMetrics,
            activity: [],
            companyRuntimes: [],
            agentContextEntries: [],
            agentMessages: [],
            agentPerformance: []
        )

        store.selectNewCompanyAgentCli("gemma4")
        #expect(store.newCompanyAgentModel == "gemma4:12b")
    }

    @Test
    func activeGitHubConnectionReadyRequiresGhAndOrigin() {
        let store = DesktopStore()
        let baseSettings = DashboardPayload.empty.settings
        store.dashboard = DashboardPayload(
            repositories: [],
            workspaces: [],
            tasks: [],
            settings: DesktopSettingsPayload(
                appHome: baseSettings.appHome,
                managedReposRoot: baseSettings.managedReposRoot,
                availableAgents: baseSettings.availableAgents,
                availableCliAgents: baseSettings.availableCliAgents,
                recentCompanies: baseSettings.recentCompanies,
                defaultLaunchMode: baseSettings.defaultLaunchMode,
                backendSettings: baseSettings.backendSettings,
                githubPublishStatus: GitHubPublishStatusPayload(
                    policy: "REQUIRE_GITHUB_PR",
                    ghInstalled: true,
                    ghAuthenticated: true,
                    originConfigured: false,
                    originUrl: nil,
                    bootstrapAvailable: false,
                    repositoryPath: "/tmp/cotor",
                    companyId: "company",
                    companyName: "Test Company",
                    message: "origin missing"
                ),
                linearSettings: baseSettings.linearSettings,
                backendStatuses: baseSettings.backendStatuses,
                shortcuts: baseSettings.shortcuts
            ),
            companies: [],
            companyAgentDefinitions: [],
            agentCapabilityProfiles: [],
            projectContexts: [],
            goals: [],
            issues: [],
            reviewQueue: [],
            orgProfiles: [],
            workflowTopologies: [],
            goalDecisions: [],
            runningAgentSessions: [],
            backendStatuses: [],
            opsMetrics: DashboardPayload.empty.opsMetrics,
            activity: [],
            companyRuntimes: [],
            agentContextEntries: [],
            agentMessages: [],
            agentPerformance: []
        )

        #expect(store.activeGitHubConnectionReady == false)
        #expect(store.activeGitHubConnectionNeedsSetup == true)

        store.selectedCompanyGitHubStatus = GitHubPublishStatusPayload(
            policy: "REQUIRE_GITHUB_PR",
            ghInstalled: true,
            ghAuthenticated: true,
            originConfigured: true,
            originUrl: "https://github.com/example/cotor.git",
            bootstrapAvailable: false,
            repositoryPath: "/tmp/cotor",
            companyId: "company",
            companyName: "Test Company",
            message: "ready"
        )

        #expect(store.activeGitHubConnectionReady == true)
        #expect(store.activeGitHubConnectionNeedsSetup == false)
    }

    @Test
    func batchEditAgentSelectionDoesNotImplyModelOverride() {
        let payload = OrgProfileBatchEditPayloadDraft.build(
            batchAgent: " codex ",
            batchModel: OrgProfileBatchEditPayloadDraft.modelAfterAgentSelection(),
            batchCapabilities: "",
            batchEnabled: nil
        )

        #expect(payload.agentCli == "codex")
        #expect(payload.model == nil)
        #expect(payload.specialties == nil)
        #expect(payload.enabled == nil)
    }

    @Test
    func batchEditPayloadKeepsExplicitModelAndCapabilities() {
        let payload = OrgProfileBatchEditPayloadDraft.build(
            batchAgent: "opencode",
            batchModel: " ollama/gemma4:12b ",
            batchCapabilities: "qa, review, , deploy",
            batchEnabled: false
        )

        #expect(payload.agentCli == "opencode")
        #expect(payload.model == "ollama/gemma4:12b")
        #expect(payload.specialties == ["qa", "review", "deploy"])
        #expect(payload.enabled == false)
    }

    @Test
    func codexArgumentParserPreservesQuotedArguments() {
        let args = parseCodexArguments("app-server --host 127.0.0.1 --label \"local dev server\" --note 'quoted value'")

        #expect(args == ["app-server", "--host", "127.0.0.1", "--label", "local dev server", "--note", "quoted value"])
    }

    @Test
    func codexArgumentParserSupportsEscapedWhitespace() {
        let args = parseCodexArguments("app-server --name local\\ server --port {port}")

        #expect(args == ["app-server", "--name", "local server", "--port", "{port}"])
    }

    @Test
    func shellModeDefaultsToCompanyAndCanSwitchToTui() {
        let store = DesktopStore()

        #expect(store.shellMode == .company)

        store.setShellMode(.tui)
        #expect(store.shellMode == .tui)

        store.setShellMode(.company)
        #expect(store.shellMode == .company)
    }

    @Test
    func chatGoalProposalUsesFirstMeaningfulLineAsTitle() {
        let store = DesktopStore()

        let proposal = store.chatGoalProposal(from: "Goal: Stabilize company chat control\nWire explicit confirmation into the desktop rail.")

        #expect(proposal == ChatGoalProposal(
            title: "Stabilize company chat control",
            description: "Goal: Stabilize company chat control\nWire explicit confirmation into the desktop rail."
        ))
    }

    @Test
    func chatGoalProposalStripsBulletPrefixes() {
        let store = DesktopStore()

        let proposal = store.chatGoalProposal(from: "- Goal: Ship approval-first goal creation\nKeep issue and review actions preview-only.")

        #expect(proposal?.title == "Ship approval-first goal creation")
    }

    @Test
    func chatGoalProposalStripsSlashGoalCommand() {
        let store = DesktopStore()

        let proposal = store.chatGoalProposal(from: "/goal Stabilize the company runtime\nKeep the work scoped to app-server startup.")

        #expect(proposal == ChatGoalProposal(
            title: "Stabilize the company runtime",
            description: "Stabilize the company runtime\nKeep the work scoped to app-server startup."
        ))
    }

    @Test
    func chatGoalProposalStripsListPrefixedSlashGoalCommand() {
        let store = DesktopStore()

        let proposal = store.chatGoalProposal(from: "- /goal Stabilize the company runtime")

        #expect(proposal == ChatGoalProposal(
            title: "Stabilize the company runtime",
            description: "Stabilize the company runtime"
        ))
    }

    @Test
    func listPrefixedSlashGoalCommandRoutesThroughChatGoalCreation() async throws {
        let host = "desktop-goal.test"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DesktopStoreCapturingURLProtocol.self]
        let api = DesktopAPI(
            baseURL: URL(string: "http://\(host)")!,
            token: "test-token",
            session: URLSession(configuration: configuration)
        )
        let store = DesktopStore(api: api)
        let company = company(id: "company", repositoryId: "repo", name: "Company")
        store.selectedCompanyID = company.id
        store.dashboard = DashboardPayload(
            repositories: [],
            workspaces: [],
            tasks: [],
            settings: DashboardPayload.empty.settings,
            companies: [company],
            companyAgentDefinitions: [],
            agentCapabilityProfiles: [],
            projectContexts: [],
            goals: [],
            issues: [],
            reviewQueue: [],
            orgProfiles: [],
            workflowTopologies: [],
            goalDecisions: [],
            runningAgentSessions: [],
            backendStatuses: [],
            opsMetrics: DashboardPayload.empty.opsMetrics,
            activity: [],
            companyRuntimes: [],
            agentContextEntries: [],
            agentMessages: [],
            agentPerformance: []
        )

        let capturedPayloads = Locked<[CreateGoalPayload]>([])
        let createdGoal = goal(
            id: "goal",
            companyId: company.id,
            title: "Stabilize the company runtime",
            status: "ACTIVE"
        )
        let dashboardAfterCreate = DashboardPayload(
            repositories: [],
            workspaces: [],
            tasks: [],
            settings: DashboardPayload.empty.settings,
            companies: [company],
            companyAgentDefinitions: [],
            agentCapabilityProfiles: [],
            projectContexts: [],
            goals: [createdGoal],
            issues: [],
            reviewQueue: [],
            orgProfiles: [],
            workflowTopologies: [],
            goalDecisions: [],
            runningAgentSessions: [],
            backendStatuses: [],
            opsMetrics: DashboardPayload.empty.opsMetrics,
            activity: [],
            companyRuntimes: [],
            agentContextEntries: [],
            agentMessages: [],
            agentPerformance: []
        )
        DesktopStoreCapturingURLProtocol.setRequestHandler(forHost: host) { request in
            let encoder = JSONEncoder()
            let path = request.url?.path ?? ""
            let data: Data
            if path == "/api/app/companies/company/goals", request.httpMethod == "POST" {
                let body = try #require(requestBodyData(from: request))
                let payload = try JSONDecoder().decode(CreateGoalPayload.self, from: body)
                capturedPayloads.withLock { $0.append(payload) }
                data = try encoder.encode(createdGoal)
            } else if path == "/api/app/dashboard" {
                data = try encoder.encode(dashboardAfterCreate)
            } else if path == "/api/app/skills" {
                data = try encoder.encode([SkillCatalogEntryRecord]())
            } else {
                data = Data("{}".utf8)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }
        defer { DesktopStoreCapturingURLProtocol.removeRequestHandler(forHost: host) }

        await store.submitOperatorChatMessage("- /goal Stabilize the company runtime")

        #expect(capturedPayloads.withLock { $0.map(\.title) } == ["Stabilize the company runtime"])
        #expect(store.operatorChatMessages.last?.text == "Created goal: Stabilize the company runtime")
        #expect(store.selectedGoalID == "goal")
    }

    @Test
    func chatGoalProposalStripsKoreanSlashGoalCommand() {
        let store = DesktopStore()

        let proposal = store.chatGoalProposal(from: "/목표 마케팅 스킬 첫 실행 안정화")

        #expect(proposal?.title == "마케팅 스킬 첫 실행 안정화")
        #expect(proposal?.description == "마케팅 스킬 첫 실행 안정화")
    }

    @Test
    func chatCompanyRequestProposalTurnsVagueDraftIntoCeoIntake() {
        let store = DesktopStore()

        let proposal = store.chatCompanyRequestProposal(from: "앱이 좀 알아서 다 잘되게 해줘\n채팅만으로 회사가 일을 나눠서 처리했으면 해.")

        #expect(proposal?.title == "앱이 좀 알아서 다 잘되게 해줘")
        #expect(proposal?.request.contains("채팅만으로 회사가 일을 나눠서 처리") == true)
        #expect(proposal?.ceoBrief.contains("CEO") == true)
    }

    @Test
    func chatReviewProposalDefaultsQaDraftToPass() {
        let store = DesktopStore()

        let proposal = store.chatReviewProposal(from: "QA looks good. Regression coverage passed.", kind: "qa")

        #expect(proposal == ChatReviewProposal(stage: .qa, verdict: "PASS", feedback: "QA looks good. Regression coverage passed."))
    }

    @Test
    func chatReviewProposalMapsChangeRequests() {
        let store = DesktopStore()

        let proposal = store.chatReviewProposal(from: "Request changes before CEO approval.", kind: "ceo")

        #expect(proposal == ChatReviewProposal(stage: .ceo, verdict: "CHANGES_REQUESTED", feedback: "Request changes before CEO approval."))
    }

    @Test
    func chatIssueProposalUsesSelectedGoalAndFirstMeaningfulLine() {
        let store = DesktopStore()
        store.selectedGoalID = "goal-1"

        let proposal = store.chatIssueProposal(from: "Issue: Wire the chat rail to real issue creation\nUse the current goal as the parent.")

        #expect(proposal == ChatIssueProposal(
            goalId: "goal-1",
            title: "Wire the chat rail to real issue creation",
            description: "Issue: Wire the chat rail to real issue creation\nUse the current goal as the parent."
        ))
    }

    @Test
    func chatMergeProposalRecognizesExplicitMergeRequest() {
        let store = DesktopStore()

        let proposal = store.chatMergeProposal(from: "Approve and merge this PR now.")

        #expect(proposal == ChatMergeProposal(summary: "Approve and merge this PR now."))
    }

    @Test
    func chatRuntimeProposalRecognizesStartRequest() {
        let store = DesktopStore()

        let proposal = store.chatRuntimeProposal(from: "Start runtime for this company.")

        #expect(proposal == ChatRuntimeProposal(action: .start, summary: "Start runtime for this company."))
    }

    @Test
    func chatAgentProposalCreatesQaAgentFromStaffingRequest() {
        let store = DesktopStore()
        store.dashboard = DashboardPayload(
            repositories: DashboardPayload.empty.repositories,
            workspaces: DashboardPayload.empty.workspaces,
            tasks: DashboardPayload.empty.tasks,
            settings: DesktopSettingsPayload(
                appHome: "/tmp",
                managedReposRoot: "/tmp",
                availableAgents: ["opencode"],
                availableCliAgents: [],
                recentCompanies: [],
                defaultLaunchMode: "company",
                backendSettings: DashboardPayload.empty.settings.backendSettings,
                githubPublishStatus: DashboardPayload.empty.settings.githubPublishStatus,
                linearSettings: DashboardPayload.empty.settings.linearSettings,
                backendStatuses: DashboardPayload.empty.settings.backendStatuses,
                shortcuts: DashboardPayload.empty.settings.shortcuts
            ),
            companies: DashboardPayload.empty.companies,
            companyAgentDefinitions: DashboardPayload.empty.companyAgentDefinitions,
            agentCapabilityProfiles: DashboardPayload.empty.agentCapabilityProfiles,
            projectContexts: DashboardPayload.empty.projectContexts,
            goals: DashboardPayload.empty.goals,
            issues: DashboardPayload.empty.issues,
            reviewQueue: DashboardPayload.empty.reviewQueue,
            orgProfiles: DashboardPayload.empty.orgProfiles,
            workflowTopologies: DashboardPayload.empty.workflowTopologies,
            goalDecisions: DashboardPayload.empty.goalDecisions,
            runningAgentSessions: DashboardPayload.empty.runningAgentSessions,
            backendStatuses: DashboardPayload.empty.backendStatuses,
            opsMetrics: DashboardPayload.empty.opsMetrics,
            activity: DashboardPayload.empty.activity,
            companyRuntimes: DashboardPayload.empty.companyRuntimes,
            agentContextEntries: DashboardPayload.empty.agentContextEntries,
            agentMessages: DashboardPayload.empty.agentMessages,
            agentPerformance: DashboardPayload.empty.agentPerformance
        )

        let proposal = store.chatAgentProposal(from: "Create a QA agent for this company.")

        #expect(proposal?.title == "QA Agent")
        #expect(proposal?.specialties == ["qa", "review", "verification"])
        #expect(proposal?.agentCli == "opencode")
    }

    @Test
    func chatBackendProposalRecognizesRestartRequest() {
        let store = DesktopStore()

        let proposal = store.chatBackendProposal(from: "Restart backend for this company.")

        #expect(proposal == ChatBackendProposal(action: .restart, summary: "Restart backend for this company."))
    }

    @Test
    func chatExecutionProposalRecognizesRunIssueRequest() {
        let store = DesktopStore()

        let proposal = store.chatExecutionProposal(from: "Run this issue now.")

        #expect(proposal == ChatExecutionProposal(summary: "Run this issue now."))
    }

    @Test
    func graphifyOperatorChatRunsRepositorySkillInsteadOfSelectedIssue() async throws {
        let host = "desktop-operator-skill.test"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DesktopStoreCapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let api = DesktopAPI(
            baseURL: URL(string: "http://\(host)")!,
            token: "test-token",
            session: session
        )
        let store = DesktopStore(api: api)
        let company = company(id: "company", repositoryId: "repo", name: "Company")
        let selectedIssue = issue(
            id: "issue",
            companyId: company.id,
            goalId: "goal",
            workspaceId: "workspace",
            status: "PLANNED"
        )
        let agent = agentDefinition(id: "agent-builder", title: "Builder", roleSummary: "repository analysis")
        let graphifySkill = skillEntry(
            name: "graphify",
            displayName: "Repository Mapper",
            requiredCapabilities: ["KNOWLEDGE_GRAPH_READ"]
        )
        store.selectedCompanyID = company.id
        store.selectedIssueID = selectedIssue.id
        store.availableSkills = [graphifySkill]
        store.dashboard = DashboardPayload(
            repositories: [],
            workspaces: [],
            tasks: [],
            settings: DashboardPayload.empty.settings,
            companies: [company],
            companyAgentDefinitions: [agent],
            agentCapabilityProfiles: [
                capabilityProfile(agentId: agent.id, settings: [
                    "SKILL_RUN": AgentCapabilitySettingRecord(
                        enabled: true,
                        mode: "AUTO",
                        skillAllowlist: ["graphify"]
                    ),
                    "KNOWLEDGE_GRAPH_READ": AgentCapabilitySettingRecord(enabled: true, mode: "READ_ONLY")
                ])
            ],
            projectContexts: [],
            goals: [goal(id: "goal", companyId: company.id, title: "Map repository", status: "ACTIVE")],
            issues: [selectedIssue],
            reviewQueue: [],
            orgProfiles: [],
            workflowTopologies: [],
            goalDecisions: [],
            runningAgentSessions: [],
            backendStatuses: [],
            opsMetrics: DashboardPayload.empty.opsMetrics,
            activity: [],
            companyRuntimes: [],
            agentContextEntries: [],
            agentMessages: [],
            agentPerformance: []
        )

        let skillRunRequests = Locked<[SkillRunRequestPayload]>([])
        let issueRunPaths = Locked<[String]>([])
        let skillResult = SkillRunResultRecord(
            skill: "graphify",
            status: "COMPLETED",
            capability: CapabilitySimulationResultRecord(
                action: "skill.run",
                capability: "SKILL_RUN",
                mode: "AUTO",
                allowed: true,
                requiresApproval: false,
                reason: "delegated"
            ),
            runId: "run-graphify",
            actions: ["graphify"],
            evidence: [
                SkillRunEvidenceRecord(
                    type: "file",
                    path: "graphify-out/GRAPH_REPORT.md",
                    url: nil,
                    title: "Graph report",
                    detail: "Repository graph updated."
                )
            ],
            summary: "Graphify returned repository map evidence.",
            output: nil,
            error: nil
        )
        DesktopStoreCapturingURLProtocol.setRequestHandler(forHost: host) { request in
            let encoder = JSONEncoder()
            let path = request.url?.path ?? ""
            let data: Data
            switch (request.httpMethod ?? "GET", path) {
            case ("POST", "/api/app/skills/graphify/run"):
                let body = try #require(requestBodyData(from: request))
                let payload = try JSONDecoder().decode(SkillRunRequestPayload.self, from: body)
                skillRunRequests.withLock { $0.append(payload) }
                data = try encoder.encode(skillResult)
            case ("POST", "/api/app/companies/company/issues/issue/run"):
                issueRunPaths.withLock { $0.append(path) }
                data = try encoder.encode(selectedIssue)
            case ("GET", "/api/app/companies/company/dashboard"):
                data = Data("{}".utf8)
            case ("GET", "/api/app/skills"),
                 ("GET", "/api/app/marketing/policies"),
                 ("GET", "/api/app/marketing/runs"),
                 ("GET", "/api/app/companies/company/reports"),
                 ("GET", "/api/app/companies/company/problem-signals"):
                data = Data("[]".utf8)
            default:
                data = Data("{}".utf8)
            }
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }
        defer { DesktopStoreCapturingURLProtocol.removeRequestHandler(forHost: host) }

        await store.submitOperatorChatMessage("graphify 실행해서 리포지토리 구조 알려줘")

        #expect(skillRunRequests.withLock { $0.map(\.agentId) } == [agent.id])
        #expect(skillRunRequests.withLock { $0.map(\.companyId) } == [company.id])
        #expect(skillRunRequests.withLock { $0.map(\.input) } == ["graphify 실행해서 리포지토리 구조 알려줘"])
        #expect(issueRunPaths.withLock { $0.isEmpty })
        #expect(store.operatorChatMessages.last?.text == "Graphify returned repository map evidence.")
    }

    @Test
    func browserSmokeSkillDefaultsToAppHealthURLWhenRunFromUI() async throws {
        let host = "desktop-browser-skill.test"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DesktopStoreCapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let api = DesktopAPI(
            baseURL: try #require(URL(string: "http://\(host)")),
            token: "test-token",
            session: session
        )
        let store = DesktopStore(api: api)
        store.selectedCompanyID = "company"

        let skillRunRequests = Locked<[SkillRunRequestPayload]>([])
        let skillResult = SkillRunResultRecord(
            skill: "browser-smoke",
            status: "COMPLETED",
            capability: CapabilitySimulationResultRecord(
                action: "skill.run",
                capability: "SKILL_RUN",
                mode: "AUTO",
                allowed: true,
                requiresApproval: false,
                reason: "delegated"
            ),
            runId: "run-browser-smoke",
            actions: ["browser-smoke"],
            evidence: [
                SkillRunEvidenceRecord(
                    type: "url",
                    path: nil,
                    url: "http://\(host)/health",
                    title: "Final URL",
                    detail: "Cotor app-server"
                )
            ],
            summary: "Visited http://\(host)/health (0 console error(s)).",
            output: nil,
            error: nil
        )

        DesktopStoreCapturingURLProtocol.setRequestHandler(forHost: host) { request in
            let encoder = JSONEncoder()
            let path = request.url?.path ?? ""
            let data: Data
            switch (request.httpMethod ?? "GET", path) {
            case ("POST", "/api/app/skills/browser-smoke/run"):
                let body = try #require(requestBodyData(from: request))
                let payload = try JSONDecoder().decode(SkillRunRequestPayload.self, from: body)
                skillRunRequests.withLock { $0.append(payload) }
                data = try encoder.encode(skillResult)
            case ("GET", "/api/app/companies/company/dashboard"):
                data = Data("{}".utf8)
            case ("GET", "/api/app/skills"),
                 ("GET", "/api/app/marketing/policies"),
                 ("GET", "/api/app/marketing/runs"),
                 ("GET", "/api/app/companies/company/reports"),
                 ("GET", "/api/app/companies/company/problem-signals"):
                data = Data("[]".utf8)
            default:
                data = Data("{}".utf8)
            }
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }
        defer { DesktopStoreCapturingURLProtocol.removeRequestHandler(forHost: host) }

        let result = await store.runSkill(skillName: "browser-smoke", agentId: "agent-builder")

        #expect(result?.status == "COMPLETED")
        let payloads = skillRunRequests.withLock { $0 }
        #expect(payloads.count == 1)
        #expect(payloads.first?.companyId == "company")
        #expect(payloads.first?.agentId == "agent-builder")
        #expect(payloads.first?.parameters["url"] == "http://\(host)/health")
    }

    @Test
    func marketingSkillsStayOptInAndPolicyFormLoadsForOperator() {
        let store = DesktopStore()
        store.availableSkills = [
            SkillCatalogEntryRecord(
                name: "repository-mapper",
                displayName: "Repository Mapper",
                description: "Map repository structure.",
                requiredCapabilities: ["GRAPH_READ"],
                localOnly: true,
                dangerous: false
            ),
            SkillCatalogEntryRecord(
                name: "marketing-operator",
                displayName: "Marketing Operator",
                description: "Operate delegated owned and social channels.",
                requiredCapabilities: ["BROWSER_READ", "WEB_PUBLISH"],
                localOnly: true,
                dangerous: true
            ),
            SkillCatalogEntryRecord(
                name: "social-publisher",
                displayName: "Social Publisher",
                description: "Publish organic social posts.",
                requiredCapabilities: ["SOCIAL_POST_CREATE"],
                localOnly: true,
                dangerous: true
            )
        ]
        let agent = CompanyAgentDefinitionRecord(
            id: "agent-marketing",
            companyId: "company",
            title: "Marketing Operator",
            agentCli: "opencode",
            model: "opencode/deepseek-v4-flash-free",
            roleSummary: "owned and social publishing",
            specialties: ["marketing"],
            collaborationInstructions: nil,
            preferredCollaboratorIds: [],
            mentorAgentId: nil,
            memoryNotes: nil,
            enabled: true,
            displayOrder: 1,
            createdAt: 1,
            updatedAt: 1
        )
        store.dashboard = DashboardPayload(
            repositories: [],
            workspaces: [],
            tasks: [],
            settings: DashboardPayload.empty.settings,
            companies: [],
            companyAgentDefinitions: [agent],
            agentCapabilityProfiles: [
                AgentCapabilityProfileRecord(
                    companyId: "company",
                    agentId: "agent-marketing",
                    settings: [
                        "SKILL_RUN": AgentCapabilitySettingRecord(
                            enabled: true,
                            mode: "AUTO",
                            skillAllowlist: ["marketing-operator", "social-publisher"]
                        )
                    ],
                    updatedAt: 1
                )
            ],
            projectContexts: [],
            goals: [],
            issues: [],
            reviewQueue: [],
            orgProfiles: [],
            workflowTopologies: [],
            goalDecisions: [],
            runningAgentSessions: [],
            backendStatuses: [],
            opsMetrics: DashboardPayload.empty.opsMetrics,
            activity: [],
            companyRuntimes: [],
            agentContextEntries: [],
            agentMessages: [],
            agentPerformance: []
        )
        store.marketingDelegationPolicies = [
            MarketingDelegationPolicyRecord(
                id: "policy-1",
                companyId: "company",
                agentId: "agent-marketing",
                name: "Owned+Social",
                allowedDomains: ["cms.example.com"],
                channelAccounts: [
                    MarketingChannelAccountRecord(channel: "web", accountRef: "web", allowedDomains: ["cms.example.com"], secretRefs: []),
                    MarketingChannelAccountRecord(channel: "linkedin", accountRef: "linkedin", allowedDomains: ["linkedin.com"], secretRefs: [])
                ],
                dailyPostLimit: 2,
                forbiddenTerms: ["unapproved"],
                brandTone: "Helpful and precise",
                prohibitedActions: ["paid-ad", "bulk-email"],
                secretRefs: ["secret://cms/session"],
                browserSessionRef: "profile://marketing",
                maxRuntimeSeconds: 600,
                createdAt: 1,
                updatedAt: 2
            )
        ]
        store.marketingRuns = [
            MarketingRunRecord(
                id: "run-old",
                companyId: "company",
                agentId: "agent-marketing",
                objective: "Old update",
                channels: ["web"],
                delegationPolicyId: "policy-1",
                status: "COMPLETED",
                actions: [],
                message: nil,
                error: nil,
                createdAt: 1,
                updatedAt: 1,
                completedAt: 1
            ),
            MarketingRunRecord(
                id: "run-new",
                companyId: "company",
                agentId: "agent-marketing",
                objective: "New update",
                channels: ["linkedin"],
                delegationPolicyId: "policy-1",
                status: "COMPLETED",
                actions: [],
                message: nil,
                error: nil,
                createdAt: 2,
                updatedAt: 3,
                completedAt: 3
            )
        ]

        #expect(store.defaultCompanyAgentSkillIDs == Set(["repository-mapper"]))

        store.beginEditingCompanyAgent(agent)

        #expect(store.isMarketingOperatorSelected)
        #expect(store.marketingPolicyAllowedDomains == "cms.example.com")
        #expect(store.marketingPolicyChannels == "web, linkedin")
        #expect(store.marketingPolicyDailyPostLimit == "2")
        #expect(store.marketingPolicyBrandTone == "Helpful and precise")
        #expect(store.marketingPolicyConnectionSummary.contains("Session/secret refs configured"))
        #expect(store.recentMarketingRunsForEditedAgent.map(\.id) == ["run-new", "run-old"])
    }

    @Test
    func agentSkillCardShowsSelectedSkillAllowlist() {
        let agent = agentDefinition(id: "agent-builder", title: "Builder", roleSummary: "implementation")
        let profile = capabilityProfile(agentId: agent.id, settings: [
            "SKILL_RUN": AgentCapabilitySettingRecord(
                enabled: true,
                mode: "AUTO",
                skillAllowlist: ["graphify", "browser-smoke"]
            )
        ])
        let card = AgentSkillCardRecord(
            agent: agent,
            profile: profile,
            skillCatalog: [
                skillEntry(name: "graphify", displayName: "Repository Mapper", requiredCapabilities: ["SKILL_RUN", "KNOWLEDGE_GRAPH_READ"]),
                skillEntry(name: "browser-smoke", displayName: "Browser Tester", requiredCapabilities: ["SKILL_RUN", "BROWSER_READ"]),
            ]
        )

        #expect(card.selectedSkills.map(\.displayName) == ["Browser Tester", "Repository Mapper"])
        #expect(card.capabilityScopes.contains(.browserQA))
        #expect(card.capabilityScopes.contains(.repositoryMap))
        #expect(card.policyChips.contains(.auto))
    }

    @Test
    func agentSkillCardToleratesDuplicateSkillCatalogEntries() {
        let agent = agentDefinition(id: "agent-builder", title: "Builder", roleSummary: "implementation")
        let profile = capabilityProfile(agentId: agent.id, settings: [
            "SKILL_RUN": AgentCapabilitySettingRecord(
                enabled: true,
                mode: "AUTO",
                skillAllowlist: ["graphify"]
            )
        ])
        let card = AgentSkillCardRecord(
            agent: agent,
            profile: profile,
            skillCatalog: [
                skillEntry(name: "graphify", displayName: "Repository Mapper", requiredCapabilities: ["KNOWLEDGE_GRAPH_READ"]),
                skillEntry(name: "graphify", displayName: "Duplicate Mapper", requiredCapabilities: ["KNOWLEDGE_GRAPH_READ"]),
            ]
        )

        #expect(card.selectedSkills.map(\.displayName) == ["Repository Mapper"])
        #expect(card.capabilityScopes.contains(.repositoryMap))
    }

    @Test
    func agentSkillCardDerivesMarketingVideoBrowserAndRepositoryScopes() {
        let agent = agentDefinition(id: "agent-operator", title: "Operator", roleSummary: "marketing and video workflows")
        let profile = capabilityProfile(agentId: agent.id, settings: [
            "SKILL_RUN": AgentCapabilitySettingRecord(
                enabled: true,
                mode: "APPROVAL_REQUIRED",
                skillAllowlist: ["graphify", "browser-smoke", "marketing-operator", "video-plan"]
            ),
            "WEB_PUBLISH": AgentCapabilitySettingRecord(enabled: true, mode: "APPROVAL_REQUIRED"),
            "VIDEO_UPLOAD": AgentCapabilitySettingRecord(enabled: true, mode: "APPROVAL_REQUIRED"),
        ])
        let card = AgentSkillCardRecord(
            agent: agent,
            profile: profile,
            skillCatalog: [
                skillEntry(name: "graphify", displayName: "Repository Mapper", requiredCapabilities: ["KNOWLEDGE_GRAPH_READ"]),
                skillEntry(name: "browser-smoke", displayName: "Browser Tester", requiredCapabilities: ["BROWSER_SCREENSHOT"]),
                skillEntry(name: "marketing-operator", displayName: "Marketing Operator", requiredCapabilities: ["WEB_PUBLISH", "SOCIAL_POST_CREATE"]),
                skillEntry(name: "video-plan", displayName: "Video Builder", requiredCapabilities: ["VIDEO_SCRIPT_WRITE"]),
            ]
        )
        let scopes = Set(card.capabilityScopes)

        #expect(scopes.isSuperset(of: [.repositoryMap, .browserQA, .marketing, .video, .videoUpload]))
        #expect(card.policyChips.contains(.approvalRequired))
    }

    @Test
    func agentSkillCardSurvivesEmptySkillCatalogWithSpecialtiesAndCapabilities() {
        let agent = agentDefinition(
            id: "agent-qa",
            title: "QA",
            roleSummary: "review verification",
            specialties: ["qa", "verification"]
        )
        let profile = capabilityProfile(agentId: agent.id, settings: [
            "BROWSER_READ": AgentCapabilitySettingRecord(enabled: true, mode: "READ_ONLY"),
            "KNOWLEDGE_GRAPH_READ": AgentCapabilitySettingRecord(enabled: true, mode: "READ_ONLY"),
            "TEST_RUN": AgentCapabilitySettingRecord(enabled: true, mode: "AUTO"),
        ])
        let card = AgentSkillCardRecord(agent: agent, profile: profile, skillCatalog: [])
        let scopes = Set(card.capabilityScopes)

        #expect(card.selectedSkills.isEmpty)
        #expect(scopes.isSuperset(of: [.browserQA, .repositoryMap, .buildTest, .qaReview]))
        #expect(card.policyChips.contains(.readOnly))
        #expect(card.policyChips.contains(.auto))
    }

    @Test
    func agentSkillCardMarksDisabledAgent() {
        let agent = agentDefinition(id: "agent-paused", title: "Paused QA", roleSummary: "qa", enabled: false)
        let profile = capabilityProfile(agentId: agent.id, settings: [
            "SKILL_RUN": AgentCapabilitySettingRecord(enabled: false, mode: "DISABLED")
        ])
        let card = AgentSkillCardRecord(agent: agent, profile: profile, skillCatalog: [])

        #expect(!card.enabled)
        #expect(!card.policyChips.contains(.disabled))
        #expect(!card.hasDisabledCapabilities)
        #expect(card.capabilityScopes.contains(.qaReview))
    }

    @Test
    func agentSkillCardShowsHasDisabledCapabilitiesForEnabledAgentWithRestrictedCapability() {
        let agent = agentDefinition(id: "agent-restricted", title: "Restricted", roleSummary: "marketing")
        let profile = capabilityProfile(agentId: agent.id, settings: [
            "SKILL_RUN": AgentCapabilitySettingRecord(
                enabled: true,
                mode: "AUTO",
                skillAllowlist: ["marketing-operator"]
            ),
            "WEB_PUBLISH": AgentCapabilitySettingRecord(enabled: true, mode: "DISABLED"),
        ])
        let card = AgentSkillCardRecord(
            agent: agent,
            profile: profile,
            skillCatalog: [
                skillEntry(name: "marketing-operator", displayName: "Marketing Operator", requiredCapabilities: ["WEB_PUBLISH"])
            ]
        )

        #expect(card.enabled)
        #expect(!card.policyChips.contains(.disabled))
        #expect(card.hasDisabledCapabilities)
    }

    @Test
    func chatDelegationProposalRecognizesDelegateIssueRequest() {
        let store = DesktopStore()

        let proposal = store.chatDelegationProposal(from: "Delegate this issue to the company roster.")

        #expect(proposal == ChatDelegationProposal(summary: "Delegate this issue to the company roster."))
    }

    @Test
    func chatGoalDecompositionProposalRecognizesGoalBreakdownRequest() {
        let store = DesktopStore()

        let proposal = store.chatGoalDecompositionProposal(from: "Break this goal into issues.")

        #expect(proposal == ChatGoalDecompositionProposal(summary: "Break this goal into issues."))
    }

    @Test
    func chatGoalAutonomyProposalRecognizesAutonomyToggleRequest() {
        let store = DesktopStore()

        let proposal = store.chatGoalAutonomyProposal(from: "Enable autonomy for this goal.")

        #expect(proposal == ChatGoalAutonomyProposal(mode: .enable, summary: "Enable autonomy for this goal."))
    }

    @Test
    func staleCompanyAsyncResponsesDoNotOverwriteSelectedCompanyState() async throws {
        let host = "desktop-stale-company.test"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DesktopStoreCapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        DesktopStoreCapturingURLProtocol.setRequestHandler(forHost: host) { request in
            let path = request.url?.path ?? ""
            if path.contains("/github/status") {
                Thread.sleep(forTimeInterval: 0.1)
            }
            let body: String
            switch path {
            case "/api/app/companies/company-a/github/status":
                body = """
                {
                  "policy": "REQUIRE_GITHUB_PR",
                  "ghInstalled": true,
                  "ghAuthenticated": true,
                  "originConfigured": true,
                  "originUrl": "https://github.com/example/a.git",
                  "bootstrapAvailable": true,
                  "repositoryPath": "/tmp/a",
                  "companyId": "company-a",
                  "companyName": "Company A",
                  "message": "ready"
                }
                """
            case "/api/app/companies/company-a/reports":
                body = """
                [{
                  "id": "report-a",
                  "companyId": "company-a",
                  "date": "2026-05-12",
                  "generatedAt": 1,
                  "periodStart": 0,
                  "periodEnd": 1,
                  "summary": "Company A report",
                  "completedCount": 0,
                  "blockedCount": 0,
                  "qaPassedCount": 0,
                  "changesRequestedCount": 0,
                  "pullRequestCount": 0,
                  "estimatedRunCostCents": 0,
                  "activityCount": 0
                }]
                """
            case "/api/app/companies/company-a/problem-signals":
                body = """
                [{
                  "id": "signal-a",
                  "companyId": "company-a",
                  "kind": "risk",
                  "title": "Company A signal",
                  "detail": "stale response",
                  "severity": "warning",
                  "confidence": 0.9,
                  "source": "test",
                  "dedupeKey": "signal-a",
                  "status": "OPEN",
                  "goalId": null,
                  "issueId": null,
                  "reviewQueueItemId": null,
                  "runId": null,
                  "triageGoalId": null,
                  "cooldownUntil": null,
                  "firstSeenAt": 1,
                  "lastSeenAt": 1,
                  "updatedAt": 1
                }]
                """
            default:
                body = "{}"
            }
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }
        defer { DesktopStoreCapturingURLProtocol.removeRequestHandler(forHost: host) }
        let store = DesktopStore(
            api: DesktopAPI(
                baseURL: try #require(URL(string: "http://\(host)")),
                token: nil,
                session: session
            )
        )
        store.dashboard = scopedSelectionDashboard()
        store.selectedCompanyID = "company-a"

        let githubStatusTask = Task { await store.refreshSelectedCompanyGitHubStatus() }
        try await Task.sleep(nanoseconds: 20_000_000)
        store.selectedCompanyID = "company-b"
        await githubStatusTask.value

        #expect(store.selectedCompanyGitHubStatus == nil)
        #expect(store.companyGitHubStatusMessage == nil)

        await store.refreshCompanyReports(companyId: "company-a")
        #expect(store.companyReports.isEmpty)
        #expect(store.selectedCompanyReportDate == nil)
        #expect(store.selectedCompanyReport == nil)

        await store.refreshCompanyProblemSignals(companyId: "company-a")
        #expect(store.companyProblemSignals.isEmpty)
    }

    @Test
    func selectedIssueTaskAndMetricsStayScopedToSelectedCompany() {
        let store = DesktopStore()
        store.dashboard = scopedSelectionDashboard()
        store.selectedCompanyID = "company-a"
        store.selectedRepositoryID = "repo-a"
        store.selectedWorkspaceID = "workspace-a"
        store.selectedGoalID = "goal-b"
        store.selectedIssueID = "issue-b"
        store.selectedTaskID = "task-b"

        #expect(store.selectedGoal == nil)
        #expect(store.selectedIssue == nil)
        #expect(store.selectedTask == nil)
        #expect(store.selectedReviewQueueItem == nil)

        let metrics = store.scopedOpsMetrics(companyID: "company-a")
        #expect(metrics.openGoals == 1)
        #expect(metrics.activeIssues == 1)
        #expect(metrics.blockedIssues == 0)
        #expect(metrics.readyToMergeCount == 0)
    }

    @Test
    func emptySkillAllowlistProducesNoRunnableSkills() {
        let agent = agentDefinition(id: "agent-builder", title: "Builder", roleSummary: "implementation")
        let profile = capabilityProfile(agentId: agent.id, settings: [
            "SKILL_RUN": AgentCapabilitySettingRecord(
                enabled: true,
                mode: "AUTO",
                skillAllowlist: []
            )
        ])
        let card = AgentSkillCardRecord(
            agent: agent,
            profile: profile,
            skillCatalog: [
                skillEntry(name: "graphify", displayName: "Repository Mapper", requiredCapabilities: ["KNOWLEDGE_GRAPH_READ", "KNOWLEDGE_GRAPH_WRITE"])
            ]
        )

        #expect(card.selectedSkills.isEmpty)
        #expect(card.runnableSkills.isEmpty)
        #expect(card.primaryRunnableSkill == nil)
    }

    @Test
    func delegatedAutoSkillWithSatisfiedCapabilitiesIsRunnable() {
        let agent = agentDefinition(id: "agent-builder", title: "Builder", roleSummary: "implementation")
        let profile = capabilityProfile(agentId: agent.id, settings: [
            "SKILL_RUN": AgentCapabilitySettingRecord(
                enabled: true,
                mode: "AUTO",
                skillAllowlist: ["graphify"]
            ),
            "KNOWLEDGE_GRAPH_READ": AgentCapabilitySettingRecord(enabled: true, mode: "AUTO"),
            "KNOWLEDGE_GRAPH_WRITE": AgentCapabilitySettingRecord(enabled: true, mode: "AUTO")
        ])
        let card = AgentSkillCardRecord(
            agent: agent,
            profile: profile,
            skillCatalog: [
                skillEntry(name: "graphify", displayName: "Repository Mapper", requiredCapabilities: ["KNOWLEDGE_GRAPH_READ", "KNOWLEDGE_GRAPH_WRITE"])
            ]
        )

        #expect(card.runnableSkills.map(\.id) == ["graphify"])
        #expect(card.primaryRunnableSkill?.id == "graphify")
        #expect(card.blockedSkillReasons.isEmpty)
    }

    @Test
    func delegatedAutoReadOnlySkillWithReadCapabilityIsRunnable() {
        let agent = agentDefinition(id: "agent-builder", title: "Builder", roleSummary: "implementation")
        let profile = capabilityProfile(agentId: agent.id, settings: [
            "SKILL_RUN": AgentCapabilitySettingRecord(
                enabled: true,
                mode: "AUTO",
                skillAllowlist: ["analytics-reporter"]
            ),
            "MARKETING_ANALYTICS_READ": AgentCapabilitySettingRecord(enabled: true, mode: "READ_ONLY")
        ])
        let card = AgentSkillCardRecord(
            agent: agent,
            profile: profile,
            skillCatalog: [
                skillEntry(name: "analytics-reporter", displayName: "Analytics Reporter", requiredCapabilities: ["MARKETING_ANALYTICS_READ"])
            ]
        )

        #expect(card.runnableSkills.map(\.id) == ["analytics-reporter"])
        #expect(card.primaryRunnableSkill?.id == "analytics-reporter")
        #expect(card.blockedSkillReasons.isEmpty)
        #expect(card.policyChips.contains(.readOnly))
    }

    @Test
    func graphifyWithoutWriteCapabilityIsNotRunnable() {
        let agent = agentDefinition(id: "agent-builder", title: "Builder", roleSummary: "implementation")
        let profile = capabilityProfile(agentId: agent.id, settings: [
            "SKILL_RUN": AgentCapabilitySettingRecord(
                enabled: true,
                mode: "AUTO",
                skillAllowlist: ["graphify"]
            ),
            "KNOWLEDGE_GRAPH_READ": AgentCapabilitySettingRecord(enabled: true, mode: "READ_ONLY"),
            "KNOWLEDGE_GRAPH_WRITE": AgentCapabilitySettingRecord(enabled: true, mode: "APPROVAL_REQUIRED")
        ])
        let card = AgentSkillCardRecord(
            agent: agent,
            profile: profile,
            skillCatalog: [
                skillEntry(name: "graphify", displayName: "Repository Mapper", requiredCapabilities: ["KNOWLEDGE_GRAPH_READ", "KNOWLEDGE_GRAPH_WRITE"])
            ]
        )

        #expect(card.runnableSkills.isEmpty)
        #expect(card.primaryRunnableSkill == nil)
        #expect(card.blockedSkillReasons["graphify"] == "capability_KNOWLEDGE_GRAPH_WRITE_not_runnable")
    }

    @Test
    func approvalRequiredSkillRunBlocksAllSelectedSkillsFromRunnable() {
        let agent = agentDefinition(id: "agent-operator", title: "Operator", roleSummary: "marketing")
        let profile = capabilityProfile(agentId: agent.id, settings: [
            "SKILL_RUN": AgentCapabilitySettingRecord(
                enabled: true,
                mode: "APPROVAL_REQUIRED",
                skillAllowlist: ["marketing-operator"]
            )
        ])
        let card = AgentSkillCardRecord(
            agent: agent,
            profile: profile,
            skillCatalog: [
                skillEntry(name: "marketing-operator", displayName: "Marketing Operator", requiredCapabilities: ["WEB_PUBLISH"])
            ]
        )

        #expect(card.selectedSkills.map(\.id) == ["marketing-operator"])
        #expect(card.runnableSkills.isEmpty)
        #expect(card.primaryRunnableSkill == nil)
        #expect(card.blockedSkillReasons["marketing-operator"] == "approval_required")
    }

    @Test
    func skillBlockedByCapabilityNotAutoShowsCapabilityReason() {
        let agent = agentDefinition(id: "agent-op", title: "Operator", roleSummary: "marketing")
        let profile = capabilityProfile(agentId: agent.id, settings: [
            "SKILL_RUN": AgentCapabilitySettingRecord(enabled: true, mode: "AUTO", skillAllowlist: ["browser-smoke"]),
            "BROWSER_READ": AgentCapabilitySettingRecord(enabled: true, mode: "APPROVAL_REQUIRED")
        ])
        let card = AgentSkillCardRecord(
            agent: agent,
            profile: profile,
            skillCatalog: [
                skillEntry(name: "browser-smoke", displayName: "Browser Tester", requiredCapabilities: ["BROWSER_READ"])
            ]
        )

        #expect(card.runnableSkills.isEmpty)
        #expect(card.primaryRunnableSkill == nil)
        #expect(card.blockedSkillReasons["browser-smoke"]?.contains("BROWSER_READ") == true)
    }

    @Test
    func skillBlockedByMissingRequiredCapabilityIsNotRunnable() {
        let agent = agentDefinition(id: "agent-op", title: "Operator", roleSummary: "marketing")
        let profile = capabilityProfile(agentId: agent.id, settings: [
            "SKILL_RUN": AgentCapabilitySettingRecord(enabled: true, mode: "AUTO", skillAllowlist: ["browser-smoke"])
        ])
        let card = AgentSkillCardRecord(
            agent: agent,
            profile: profile,
            skillCatalog: [
                skillEntry(name: "browser-smoke", displayName: "Browser Tester", requiredCapabilities: ["BROWSER_READ"])
            ]
        )

        #expect(card.runnableSkills.isEmpty)
        #expect(card.primaryRunnableSkill == nil)
        #expect(card.blockedSkillReasons["browser-smoke"]?.contains("BROWSER_READ") == true)
    }

    @Test
    func refreshTuiSessionListDoesNotOverwriteSelectedWorkspaceWithFirstSession() async throws {
        let host = "desktop-tui-first.test"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DesktopStoreCapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        DesktopStoreCapturingURLProtocol.setRequestHandler(forHost: host) { request in
            let path = request.url?.path ?? ""
            let body: String
            if path.contains("/tui/sessions") {
                // session-b has higher updatedAt and sorts first, but ws-a is the selected workspace.
                body = """
                [
                  {"id":"session-a","workspaceId":"ws-a","repositoryId":"repo-a","repositoryPath":"/tmp/a","agentName":null,"baseBranch":"main","status":"IDLE","transcript":"","transcriptStartOffset":0,"transcriptEndOffset":0,"processId":null,"exitCode":null,"createdAt":1,"updatedAt":1},
                  {"id":"session-b","workspaceId":"ws-b","repositoryId":"repo-b","repositoryPath":"/tmp/b","agentName":null,"baseBranch":"main","status":"IDLE","transcript":"","transcriptStartOffset":0,"transcriptEndOffset":0,"processId":null,"exitCode":null,"createdAt":2,"updatedAt":2}
                ]
                """
            } else {
                body = "[]"
            }
            let response = HTTPURLResponse(url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, Data(body.utf8))
        }
        defer { DesktopStoreCapturingURLProtocol.removeRequestHandler(forHost: host) }
        let store = DesktopStore(
            api: DesktopAPI(
                baseURL: try #require(URL(string: "http://\(host)")),
                token: nil,
                session: session
            )
        )
        store.selectedWorkspaceID = "ws-a"

        await store.refreshTuiSessionList()

        // session-b sorts first (updatedAt=2) but must NOT be auto-selected because workspace differs.
        #expect(store.tuiSession?.id == "session-a")
        #expect(store.tuiSession?.workspaceId == "ws-a")
        #expect(store.selectedWorkspaceID == "ws-a")
    }

    @Test
    func refreshTuiSessionListSetsNilWhenNoSessionMatchesSelectedWorkspace() async throws {
        let host = "desktop-tui-none.test"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DesktopStoreCapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        DesktopStoreCapturingURLProtocol.setRequestHandler(forHost: host) { request in
            let path = request.url?.path ?? ""
            let body: String
            if path.contains("/tui/sessions") {
                body = """
                [
                  {"id":"session-b","workspaceId":"ws-b","repositoryId":"repo-b","repositoryPath":"/tmp/b","agentName":null,"baseBranch":"main","status":"IDLE","transcript":"","transcriptStartOffset":0,"transcriptEndOffset":0,"processId":null,"exitCode":null,"createdAt":1,"updatedAt":1}
                ]
                """
            } else {
                body = "[]"
            }
            let response = HTTPURLResponse(url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, Data(body.utf8))
        }
        defer { DesktopStoreCapturingURLProtocol.removeRequestHandler(forHost: host) }
        let store = DesktopStore(
            api: DesktopAPI(
                baseURL: try #require(URL(string: "http://\(host)")),
                token: nil,
                session: session
            )
        )
        store.selectedWorkspaceID = "ws-a"

        await store.refreshTuiSessionList()

        // No session matches ws-a — tuiSession must remain nil, not fall back to ws-b's session.
        #expect(store.tuiSession == nil)
        #expect(store.selectedTuiSessionID == nil)
        #expect(store.selectedWorkspaceID == "ws-a")
    }

    @Test
    func selectingExplicitTuiSessionMovesWorkspaceAndRepositorySelection() async {
        let store = DesktopStore()
        store.selectedWorkspaceID = "ws-a"
        store.selectedRepositoryID = "repo-a"

        let other = TuiSessionRecord(
            id: "session-b",
            workspaceId: "ws-b",
            repositoryId: "repo-b",
            repositoryPath: "/tmp/b",
            agentName: nil,
            baseBranch: "main",
            status: "IDLE",
            transcript: "",
            transcriptStartOffset: 0,
            transcriptEndOffset: 0,
            processId: nil,
            exitCode: nil,
            createdAt: 1,
            updatedAt: 1
        )

        await store.selectTuiSession(other)

        #expect(store.selectedWorkspaceID == "ws-b")
        #expect(store.selectedRepositoryID == "repo-b")
        #expect(store.tuiSession?.id == "session-b")
        #expect(store.selectedTuiSessionID == "session-b")
    }

    @Test
    func issueBlockedReasonCodeDecodesRuntimeInterruptedVariant() throws {
        let json = """
        {
          "id":"issue-qa","companyId":"c1","goalId":"g1","workspaceId":"ws1",
          "title":"QA review","description":"","status":"BLOCKED",
          "priority":0,"kind":"review","codeProducing":false,"riskLevel":"LOW",
          "blockedBy":[],"dependsOn":[],"acceptanceCriteria":[],
          "sourceSignal":"qa-review:issue-exec",
          "blockedReasonCode":"RUNTIME_INTERRUPTED",
          "createdAt":0,"updatedAt":0
        }
        """
        let issue = try JSONDecoder().decode(IssueRecord.self, from: Data(json.utf8))

        #expect(issue.blockedReasonCode == "RUNTIME_INTERRUPTED")
        #expect(issue.status == "BLOCKED")
    }

    private func scopedSelectionDashboard() -> DashboardPayload {
        DashboardPayload(
            repositories: [
                repository(id: "repo-a", name: "repo-a"),
                repository(id: "repo-b", name: "repo-b")
            ],
            workspaces: [
                workspace(id: "workspace-a", repositoryId: "repo-a", name: "Company A · master"),
                workspace(id: "workspace-b", repositoryId: "repo-b", name: "Company B · master")
            ],
            tasks: [
                task(id: "task-a", workspaceId: "workspace-a", issueId: "issue-a"),
                task(id: "task-b", workspaceId: "workspace-b", issueId: "issue-b")
            ],
            settings: DashboardPayload.empty.settings,
            companies: [
                company(id: "company-a", repositoryId: "repo-a", name: "Company A"),
                company(id: "company-b", repositoryId: "repo-b", name: "Company B")
            ],
            companyAgentDefinitions: [],
            agentCapabilityProfiles: [],
            projectContexts: [],
            goals: [
                goal(id: "goal-a", companyId: "company-a", title: "Company A goal", status: "ACTIVE"),
                goal(id: "goal-b", companyId: "company-b", title: "Company B goal", status: "ACTIVE")
            ],
            issues: [
                issue(id: "issue-a", companyId: "company-a", goalId: "goal-a", workspaceId: "workspace-a", status: "PLANNED"),
                issue(id: "issue-b", companyId: "company-b", goalId: "goal-b", workspaceId: "workspace-b", status: "BLOCKED")
            ],
            reviewQueue: [
                reviewQueueItem(id: "review-b", companyId: "company-b", issueId: "issue-b", status: "READY_TO_MERGE")
            ],
            orgProfiles: [],
            workflowTopologies: [],
            goalDecisions: [],
            runningAgentSessions: [],
            backendStatuses: [],
            opsMetrics: OpsMetricSnapshotRecord(openGoals: 2, activeIssues: 1, blockedIssues: 1, readyToMergeCount: 1, mergedCount: 0, lastUpdatedAt: 42),
            activity: [],
            companyRuntimes: [],
            agentContextEntries: [],
            agentMessages: [],
            agentPerformance: []
        )
    }

    private func repository(id: String, name: String) -> RepositoryRecord {
        RepositoryRecord(id: id, name: name, localPath: "/tmp/\(name)", sourceKind: "local", remoteUrl: nil, defaultBranch: "master", createdAt: 0, updatedAt: 0)
    }

    private func workspace(id: String, repositoryId: String, name: String) -> WorkspaceRecord {
        WorkspaceRecord(id: id, repositoryId: repositoryId, name: name, baseBranch: "master", createdAt: 0, updatedAt: 0)
    }

    private func company(
        id: String,
        repositoryId: String,
        name: String,
        operatorAutomationMode: String = "AGENT_APPROVED"
    ) -> CompanyRecord {
        CompanyRecord(id: id, name: name, rootPath: "/tmp/\(name)", repositoryId: repositoryId, defaultBaseBranch: "master", backendKind: "LOCAL_COTOR", linearSyncEnabled: false, linearConfigOverride: nil, autonomyEnabled: true, dailyBudgetCents: nil, monthlyBudgetCents: nil, createdAt: 0, updatedAt: 0, operatorAutomationMode: operatorAutomationMode)
    }

    private func goal(id: String, companyId: String, title: String, status: String) -> GoalRecord {
        GoalRecord(id: id, companyId: companyId, projectContextId: nil, title: title, description: title, status: status, priority: 0, successMetrics: [], operatingPolicy: nil, followUpContext: nil, autonomyEnabled: true, createdAt: 0, updatedAt: 0)
    }

    private func issue(id: String, companyId: String, goalId: String, workspaceId: String, status: String) -> IssueRecord {
        IssueRecord(id: id, companyId: companyId, projectContextId: nil, goalId: goalId, workspaceId: workspaceId, title: id, description: id, status: status, priority: 0, kind: "execution", assigneeProfileId: nil, linearIssueId: nil, linearIssueIdentifier: nil, linearIssueUrl: nil, lastLinearSyncAt: nil, blockedBy: [], dependsOn: [], acceptanceCriteria: [], riskLevel: "LOW", codeProducing: true, executionIntent: nil, branchName: nil, worktreePath: nil, pullRequestNumber: nil, pullRequestUrl: nil, pullRequestState: nil, qaVerdict: nil, qaFeedback: nil, ceoVerdict: nil, ceoFeedback: nil, mergeResult: nil, transitionReason: nil, sourceSignal: "test", blockedReasonCode: nil, blockedRetryable: nil, createdAt: 0, updatedAt: 0)
    }

    private func task(id: String, workspaceId: String, issueId: String) -> TaskRecord {
        TaskRecord(id: id, workspaceId: workspaceId, issueId: issueId, title: id, prompt: id, agents: ["opencode"], status: "PENDING", createdAt: 0, updatedAt: 0)
    }

    private func reviewQueueItem(id: String, companyId: String, issueId: String, status: String) -> ReviewQueueItemRecord {
        ReviewQueueItemRecord(id: id, companyId: companyId, projectContextId: nil, issueId: issueId, runId: "run-\(id)", branchName: nil, worktreePath: nil, pullRequestNumber: nil, pullRequestUrl: nil, pullRequestState: nil, status: status, checksSummary: nil, mergeability: nil, requestedReviewers: [], qaVerdict: nil, qaFeedback: nil, qaReviewedAt: nil, qaIssueId: nil, ceoVerdict: nil, ceoFeedback: nil, ceoReviewedAt: nil, approvalIssueId: nil, mergeCommitSha: nil, mergedAt: nil, createdAt: 0, updatedAt: 0)
    }

    private func agentDefinition(
        id: String,
        title: String,
        roleSummary: String,
        specialties: [String] = [],
        enabled: Bool = true
    ) -> CompanyAgentDefinitionRecord {
        CompanyAgentDefinitionRecord(
            id: id,
            companyId: "company",
            title: title,
            agentCli: "opencode",
            model: "opencode/deepseek-v4-flash-free",
            roleSummary: roleSummary,
            specialties: specialties,
            collaborationInstructions: nil,
            preferredCollaboratorIds: [],
            mentorAgentId: nil,
            memoryNotes: nil,
            enabled: enabled,
            displayOrder: 0,
            createdAt: 0,
            updatedAt: 0
        )
    }

    private func capabilityProfile(
        agentId: String,
        settings: [String: AgentCapabilitySettingRecord]
    ) -> AgentCapabilityProfileRecord {
        AgentCapabilityProfileRecord(companyId: "company", agentId: agentId, settings: settings, updatedAt: 0)
    }

    private func skillEntry(
        name: String,
        displayName: String,
        requiredCapabilities: [String]
    ) -> SkillCatalogEntryRecord {
        SkillCatalogEntryRecord(
            name: name,
            displayName: displayName,
            description: displayName,
            requiredCapabilities: requiredCapabilities,
            localOnly: true,
            dangerous: false
        )
    }
}

final class DesktopStoreCapturingURLProtocol: URLProtocol, @unchecked Sendable {
    typealias RequestHandler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let handlerLock = NSLock()
    nonisolated(unsafe) private static var requestHandlersByHost: [String: RequestHandler] = [:]

    static func setRequestHandler(forHost host: String, handler: @escaping RequestHandler) {
        handlerLock.lock()
        requestHandlersByHost[host] = handler
        handlerLock.unlock()
    }

    static func removeRequestHandler(forHost host: String) {
        handlerLock.lock()
        requestHandlersByHost.removeValue(forKey: host)
        handlerLock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (response, data) = try Self.requestHandler(for: request)?(request) ?? {
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

    private static func requestHandler(for request: URLRequest) -> RequestHandler? {
        let host = request.url?.host ?? ""
        handlerLock.lock()
        let handler = requestHandlersByHost[host]
        handlerLock.unlock()
        return handler
    }
}

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

private func requestBodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        if read < 0 {
            return nil
        }
        if read == 0 {
            break
        }
        data.append(buffer, count: read)
    }
    return data
}
