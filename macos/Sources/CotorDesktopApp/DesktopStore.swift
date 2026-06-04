import AppKit
import Foundation
import SwiftUI

func isCompanyEventStreamHeartbeat(_ envelope: CompanyEventEnvelopePayload) -> Bool {
    envelope.event.type == "stream.heartbeat"
}

/// Tracks the high-level backend/runtime state shown in the shell header.
///
/// The visible text is derived later through the active app language so the same
/// state can be re-rendered instantly when the user flips languages.
private enum StatusState {
    case connecting
    case waitingForServer
    case connected(String)
    case offlineMock
    case taskStarted(String)
}

enum AppShellMode: String, CaseIterable, Identifiable {
    case company
    case tui

    var id: String { rawValue }
}

/// Main view model for the macOS shell.
///
/// It coordinates bootstrap, selection state, optimistic actions, and runtime
/// language choice for the live desktop shell.
@MainActor
final class DesktopStore: ObservableObject {
    private static let languageDefaultsKey = "cotor.desktop.language"
    private static let themeDefaultsKey = "cotor.desktop.theme"

    @Published var dashboard: DashboardPayload = .empty
    @Published var runs: [RunRecord] = []
    @Published var issueExecutionDetails: [IssueAgentExecutionDetailRecord] = []
    @Published var tuiSessions: [TuiSessionRecord] = []
    @Published var tuiSession: TuiSessionRecord?
    @Published var selectedTuiSessionID: String?
    @Published var availableBranches: [String] = ["main"]
    @Published var pendingWorkspaceBaseBranch = "main"
    @Published var selectedRepositoryID: String?
    @Published var selectedWorkspaceID: String?
    @Published var selectedCompanyID: String?
    @Published var selectedGoalID: String?
    @Published var selectedIssueID: String?
    @Published var selectedTaskID: String?
    @Published var selectedAgentName: String?
    @Published var shellMode: AppShellMode = .company
    @Published var inspectorTab: InspectorTab = .changes
    @Published var changes: ChangeSummaryPayload = ChangeSummaryPayload(runId: "", branchName: "", baseBranch: "", patch: "", changedFiles: [])
    @Published var files: [FileTreeNodePayload] = []
    @Published var ports: [PortEntryPayload] = []
    @Published var browserURL: URL?
    @Published var companyMemorySnapshot: CompanyMemorySnapshotPayload?
    @Published var companyProblemSignals: [CompanyProblemSignalRecord] = []
    @Published var selectedCompanyGitHubStatus: GitHubPublishStatusPayload?
    @Published var language: AppLanguage
    @Published var theme: AppTheme
    @Published var isOffline = false
    @Published var isBusy = false
    @Published var repositoryPathInput = ""
    @Published var cloneURLInput = ""
    @Published var newCompanyName = ""
    @Published var newCompanyRootPath = ""
    @Published var newCompanyDailyBudgetInput = ""
    @Published var newCompanyMonthlyBudgetInput = ""
    @Published var newCompanyAgentTitle = ""
    @Published var newCompanyAgentCli = ""
    @Published var newCompanyAgentModel = ""
    @Published var newCompanyAgentRole = ""
    @Published var newCompanyAgentSpecialties = ""
    @Published var newCompanyAgentCollaborationNotes = ""
    @Published var newCompanyAgentMemoryNotes = ""
    @Published var newCompanyAgentPreferredCollaboratorIDs: Set<String> = []
    @Published var newCompanyAgentMentorID = ""
    @Published var newCompanyAgentSkillIDs: Set<String> = []
    @Published var marketingPolicyAllowedDomains = ""
    @Published var marketingPolicyChannels = "web"
    @Published var marketingPolicyDailyPostLimit = "1"
    @Published var marketingPolicyForbiddenTerms = ""
    @Published var marketingPolicyBrandTone = ""
    @Published var marketingPolicyProhibitedActions = "paid-ad, budget-change, bulk-email, direct-message, payment, credential-storage"
    @Published var marketingPolicySecretRefs = ""
    @Published var marketingPolicyBrowserSessionRef = ""
    @Published var marketingPolicyMaxRuntimeSeconds = "900"
    @Published var newCompanyAgentEnabled = true
    @Published var editingCompanyAgentID: String?
    @Published var editingCompanyAgentCompanyID: String?
    @Published var newWorkspaceName = ""
    @Published var newGoalTitle = ""
    @Published var newGoalDescription = ""
    @Published var editingGoalID: String?
    @Published var newIssueCompanyID: String?
    @Published var newIssueGoalID: String?
    @Published var newIssueTitle = ""
    @Published var newIssueDescription = ""
    @Published var defaultBackendKind = "LOCAL_COTOR"
    @Published var codePublishMode = "REQUIRE_GITHUB_PR"
    @Published var codexLaunchMode = "MANAGED"
    @Published var codexCommand = "codex"
    @Published var codexArgs = "app-server --host 127.0.0.1 --port {port}"
    @Published var codexWorkingDirectory = ""
    @Published var codexPort = ""
    @Published var codexStartupTimeoutSeconds = "15"
    @Published var codexAppServerBaseURL = ""
    @Published var codexBackendStatus: ExecutionBackendStatusPayload?
    @Published var codexOAuthAuthenticated = false
    @Published var codexOAuthHomePath = ""
    @Published var codexOAuthStatusMessage: String?
    @Published var companyLinearSyncEnabled = false
    @Published var companyLinearEndpoint = ""
    @Published var companyLinearTeamID = ""
    @Published var companyLinearProjectID = ""
    @Published var companyDailyBudgetInput = ""
    @Published var companyMonthlyBudgetInput = ""
    @Published var companyLinearStatusMessage: String?
    @Published var companyGitHubStatusMessage: String?
    @Published var companyGitHubOriginInput = ""
    @Published var newTaskTitle = ""
    @Published var newTaskPrompt = ""
    @Published var agentSelection: Set<String> = ["claude", "codex"]
    @Published var selectedOrgProfileIDs: Set<String> = []
    @Published var selectedCompanyAgentDefinitionIDs: Set<String> = []
    @Published var showingOrgProfileBatchEdit = false
    @Published var lastSelectedOrgProfileID: String?
    @Published var workflowLeadAgent: String
    @Published var showingOpenSheet = false
    @Published var showingCloneSheet = false
    @Published var actionErrorMessage: String?
    @Published var companyStreamStatusMessage: String?
    @Published var backendStatusMessage: String?
    @Published var errorMessage: String?
    @Published var showingHelpGuide = false
    @Published var helpGuide: HelpGuidePayload?
    @Published var availableSkills: [SkillCatalogEntryRecord] = []
    @Published var marketingDelegationPolicies: [MarketingDelegationPolicyRecord] = []
    @Published var marketingRuns: [MarketingRunRecord] = []
    @Published var skillRuns: [SkillRunRecord] = []
    @Published var recentSkillRunResults: [SkillRunResultRecord] = []
    @Published var runningSkillRunKeys: Set<String> = []
    @Published var operatorCommandDraft = ""
    @Published var operatorCommandResponses: [OperatorCommandResponsePayload] = []
    @Published var operatorChatMessages: [OperatorChatMessage] = []
    @Published var operatorPendingPrompt: OperatorChatPendingPrompt?
    @Published var isSendingOperatorChatMessage = false
    @Published var companyReports: [CompanyDailyReportSummaryRecord] = []
    @Published var selectedCompanyReportDate: String?
    @Published var selectedCompanyReport: CompanyDailyReportRecord?
    @Published var isGeneratingCompanyReport = false

    let api: DesktopAPI
    private var statusState: StatusState = .connecting
    private var tuiPollingTask: Task<Void, Never>?
    private var companyEventTask: Task<Void, Never>?
    private var companyPollingTask: Task<Void, Never>?
    private var backendWatchdogTask: Task<Void, Never>?
    private var isBootstrapping = false
    private var isRefreshingDashboard = false
    private var companyEventStreamGeneration = 0
    private var polledTuiSessionID: String?
    private var didInitializeShellMode = false
    private var didRequestDesktopLifecycleStartup = false

    init(api: DesktopAPI = DesktopAPI()) {
        self.api = api
        let storedLanguage = UserDefaults.standard.string(forKey: Self.languageDefaultsKey)
        language = AppLanguage(rawValue: storedLanguage ?? "") ?? .english
        let storedTheme = UserDefaults.standard.string(forKey: Self.themeDefaultsKey)
        theme = AppTheme(rawValue: storedTheme ?? "") ?? .system
        workflowLeadAgent = ""
    }

    deinit {
        tuiPollingTask?.cancel()
        companyEventTask?.cancel()
        companyPollingTask?.cancel()
        backendWatchdogTask?.cancel()
    }

    /// Header status copy is generated from the current state and active language.
    var statusMessage: String {
        switch statusState {
        case .connecting:
            return text(.connectingToServer)
        case .waitingForServer:
            return text(.waitingForServer)
        case let .connected(url):
            return DesktopStrings.connectedToServer(url, language: language)
        case .offlineMock:
            return text(.offlineMockData)
        case let .taskStarted(title):
            return DesktopStrings.startedTask(title, language: language)
        }
    }

    var repositories: [RepositoryRecord] {
        dashboard.repositories.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    var companies: [CompanyRecord] {
        dashboard.companies.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    var availableCliAgents: [String] {
        let cliAgents = dashboard.settings.availableCliAgents.sorted()
        return cliAgents.isEmpty ? dashboard.settings.availableAgents.sorted() : cliAgents
    }

    var preferredCliAgent: String {
        preferredDesktopAgent(from: availableCliAgents) ?? preferredDesktopAgent(from: dashboard.settings.availableAgents) ?? ""
    }

    var resolvedNewCompanyAgentCli: String {
        let cli = newCompanyAgentCli.trimmingCharacters(in: .whitespacesAndNewlines)
        return cli.isEmpty ? preferredCliAgent : cli
    }

    var availableAgentModels: [String: [String]] {
        dashboard.settings.availableAgentModels
    }

    var defaultAgentModels: [String: String] {
        dashboard.settings.defaultAgentModels
    }

    var newCompanyAgentModelOptions: [String] {
        modelOptions(for: resolvedNewCompanyAgentCli)
    }

    func modelOptions(for agentCli: String) -> [String] {
        let normalized = agentCli.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return [] }
        return availableAgentModels[normalized]
            ?? availableAgentModels.first(where: { $0.key.lowercased() == normalized })?.value
            ?? []
    }

    func defaultModel(for agentCli: String) -> String? {
        let normalized = agentCli.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return defaultAgentModels[normalized]
            ?? defaultAgentModels.first(where: { $0.key.lowercased() == normalized })?.value
    }

    func selectNewCompanyAgentCli(_ agentCli: String) {
        newCompanyAgentCli = agentCli
        let options = modelOptions(for: agentCli)
        if let defaultModel = defaultModel(for: agentCli),
           shouldAutoFillDefaultModel(for: agentCli, options: options, defaultModel: defaultModel) {
            newCompanyAgentModel = defaultModel
        } else if !options.isEmpty {
            newCompanyAgentModel = options.first ?? ""
        } else if options.isEmpty || !options.contains(newCompanyAgentModel) {
            newCompanyAgentModel = ""
        }
    }

    func shouldAutoFillDefaultModel(for agentCli: String, options: [String], defaultModel: String) -> Bool {
        if options.contains(defaultModel) {
            return true
        }
        return options.isEmpty && !requiresDiscoveredLocalModel(agentCli)
    }

    func requiresDiscoveredLocalModel(_ agentCli: String) -> Bool {
        let normalized = agentCli.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["gemma4", "ollama", "lmstudio"].contains(normalized)
    }

    var availableCompanyAgentCollaborators: [CompanyAgentDefinitionRecord] {
        companyAgentDefinitions.filter { $0.id != editingCompanyAgentID }
    }

    var availableCompanyAgentMentors: [CompanyAgentDefinitionRecord] {
        companyAgentDefinitions.filter { $0.id != editingCompanyAgentID && $0.enabled }
    }

    var companyAgentDefinitions: [CompanyAgentDefinitionRecord] {
        dashboard.companyAgentDefinitions
            .filter { selectedCompanyID == nil || $0.companyId == selectedCompanyID }
            .sorted { lhs, rhs in
                if lhs.displayOrder == rhs.displayOrder {
                    return lhs.title < rhs.title
                }
                return lhs.displayOrder < rhs.displayOrder
            }
    }

    var agentPerformance: [AgentPerformanceSnapshotRecord] {
        let visibleAgentIDs = Set(companyAgentDefinitions.map(\.id))
        return dashboard.agentPerformance
            .filter { selectedCompanyID == nil || visibleAgentIDs.contains($0.agentId) }
            .sorted { lhs, rhs in
                if (lhs.score ?? -1) == (rhs.score ?? -1) {
                    return lhs.roleName < rhs.roleName
                }
                return (lhs.score ?? -1) > (rhs.score ?? -1)
            }
    }

    var scoreableAgentPerformanceCount: Int {
        agentPerformance.filter { $0.score != nil && $0.dataSufficiency == "SUFFICIENT" }.count
    }

    var projectContexts: [CompanyProjectContextRecord] {
        dashboard.projectContexts
            .filter { selectedCompanyID == nil || $0.companyId == selectedCompanyID }
            .sorted { $0.lastUpdatedAt > $1.lastUpdatedAt }
    }

    var activity: [CompanyActivityItemRecord] {
        dashboard.activity
            .filter { selectedCompanyID == nil || $0.companyId == selectedCompanyID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var selectedCompanyReports: [CompanyDailyReportSummaryRecord] {
        companyReports
            .filter { selectedCompanyID == nil || $0.companyId == selectedCompanyID }
            .sorted {
                if $0.date == $1.date {
                    return $0.generatedAt > $1.generatedAt
                }
                return $0.date > $1.date
            }
    }

    var companyRuntimes: [CompanyRuntimeSnapshotRecord] {
        dashboard.companyRuntimes
            .filter { selectedCompanyID == nil || $0.companyId == selectedCompanyID }
            .sorted { ($0.lastTickAt ?? 0) > ($1.lastTickAt ?? 0) }
    }

    var workspaces: [WorkspaceRecord] {
        dashboard.workspaces
            .filter { selectedRepositoryID == nil || $0.repositoryId == selectedRepositoryID }
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    var goals: [GoalRecord] {
        dashboard.goals
            .filter { selectedCompanyID == nil || $0.companyId == selectedCompanyID }
            .sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
            }
    }

    var issues: [IssueRecord] {
        dashboard.issues
            .filter { (selectedCompanyID == nil || $0.companyId == selectedCompanyID) && (selectedGoalID == nil || $0.goalId == selectedGoalID) }
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    var orgProfiles: [OrgAgentProfileRecord] {
        dashboard.orgProfiles
            .filter { selectedCompanyID == nil || $0.companyId == selectedCompanyID }
            .sorted { lhs, rhs in
            lhs.roleName < rhs.roleName
            }
    }

    var tasks: [TaskRecord] {
        dashboard.tasks
            .filter { task in
                let workspaceMatch = selectedWorkspaceID == nil || task.workspaceId == selectedWorkspaceID
                guard workspaceMatch else { return false }
                guard let companyID = selectedCompanyID else { return true }
                if let issueID = task.issueId,
                   let issue = dashboard.issues.first(where: { $0.id == issueID }) {
                    return issue.companyId == companyID
                }
                guard let workspace = dashboard.workspaces.first(where: { $0.id == task.workspaceId }),
                      let company = selectedCompany else {
                    return true
                }
                return workspace.repositoryId == company.repositoryId
            }
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    var selectedRepository: RepositoryRecord? {
        repositories.first { $0.id == selectedRepositoryID }
    }

    var selectedWorkspace: WorkspaceRecord? {
        dashboard.workspaces.first { $0.id == selectedWorkspaceID }
    }

    var selectedGoal: GoalRecord? {
        goals.first { $0.id == selectedGoalID }
    }

    var selectedCompany: CompanyRecord? {
        companies.first { $0.id == selectedCompanyID }
    }

    private func isCurrentCompany(_ companyId: String) -> Bool {
        (selectedCompanyID ?? selectedCompany?.id) == companyId
    }

    var selectedIssue: IssueRecord? {
        issues.first { $0.id == selectedIssueID }
    }

    var issueComposerCompany: CompanyRecord? {
        if let newIssueCompanyID,
           let explicit = companies.first(where: { $0.id == newIssueCompanyID }) {
            return explicit
        }
        return selectedCompany
    }

    var issueComposerGoals: [GoalRecord] {
        let companyID = issueComposerCompany?.id
        return dashboard.goals
            .filter { companyID == nil || $0.companyId == companyID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var selectedReviewQueueItem: ReviewQueueItemRecord? {
        guard let selectedIssueID = selectedIssue?.id else { return nil }
        return dashboard.reviewQueue
            .filter { $0.issueId == selectedIssueID }
            .sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
            .first
    }

    var selectedIssueAssignee: OrgAgentProfileRecord? {
        guard let profileID = selectedIssue?.assigneeProfileId else { return nil }
        return dashboard.orgProfiles.first { $0.id == profileID }
    }

    var selectedRuntime: CompanyRuntimeSnapshotRecord? {
        companyRuntimes.first { $0.companyId == (selectedCompanyID ?? selectedCompany?.id) }
    }

    var activeGitHubPublishStatus: GitHubPublishStatusPayload {
        selectedCompanyGitHubStatus ?? dashboard.settings.githubPublishStatus
    }

    var activeGitHubConnectionReady: Bool {
        activeGitHubPublishStatus.ghInstalled &&
            activeGitHubPublishStatus.ghAuthenticated &&
            activeGitHubPublishStatus.originConfigured
    }

    var activeGitHubConnectionNeedsSetup: Bool {
        activeGitHubPublishStatus.policy == "REQUIRE_GITHUB_PR" && !activeGitHubConnectionReady
    }

    var selectedOperatorAutomationMode: String {
        selectedCompany?.operatorAutomationMode ?? "FULL_AUTO"
    }

    func scopedOpsMetrics(companyID: String?) -> OpsMetricSnapshotRecord {
        let scopedGoals = dashboard.goals.filter { companyID == nil || $0.companyId == companyID }
        let scopedIssues = dashboard.issues.filter { companyID == nil || $0.companyId == companyID }
        let scopedReviewQueue = dashboard.reviewQueue.filter { companyID == nil || $0.companyId == companyID }

        return OpsMetricSnapshotRecord(
            openGoals: scopedGoals.count { $0.status != "COMPLETED" },
            activeIssues: scopedIssues.count {
                ["PLANNED", "DELEGATED", "IN_PROGRESS", "IN_REVIEW", "READY_FOR_CEO"].contains($0.status)
            },
            blockedIssues: scopedIssues.count { $0.status == "BLOCKED" },
            readyToMergeCount: scopedReviewQueue.count { $0.status == "READY_FOR_CEO" || $0.status == "READY_TO_MERGE" },
            mergedCount: scopedReviewQueue.count { $0.status == "MERGED" },
            lastUpdatedAt: dashboard.opsMetrics.lastUpdatedAt
        )
    }

    var currentWorkspaceBaseBranch: String {
        selectedWorkspace?.baseBranch ?? selectedCompany?.defaultBaseBranch ?? selectedRepository?.defaultBranch ?? pendingWorkspaceBaseBranch
    }

    var selectedTask: TaskRecord? {
        if let selectedTaskID,
           let explicit = tasks.first(where: { $0.id == selectedTaskID }) {
            return explicit
        }
        if let selectedIssueID {
            return tasks
                .filter { $0.issueId == selectedIssueID }
                .sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
                .first
        }
        return nil
    }

    var selectedRun: RunRecord? {
        let preferredAgent = selectedAgentName ?? selectedTask?.agents.first
        if let selectedTaskID,
           let exact = runs.first(where: { $0.taskId == selectedTaskID && $0.agentName == preferredAgent }) {
            return exact
        }
        if let selectedTaskID,
           let latestForTask = runs.first(where: { $0.taskId == selectedTaskID }) {
            return latestForTask
        }
        return runs.first
    }

    var activeTuiSession: TuiSessionRecord? {
        if let selectedTuiSessionID,
           let explicit = tuiSessions.first(where: { $0.id == selectedTuiSessionID }) {
            return explicit
        }
        return tuiSession ?? tuiSessions.first
    }

    func text(_ key: DesktopTextKey) -> String {
        DesktopStrings.text(key, language: language)
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.languageDefaultsKey)
        if showingHelpGuide {
            Task { await loadHelpGuide() }
        }
        objectWillChange.send()
    }

    func setTheme(_ theme: AppTheme) {
        self.theme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.themeDefaultsKey)
        objectWillChange.send()
    }

    func setShellMode(_ mode: AppShellMode) {
        guard shellMode != mode else { return }
        shellMode = mode
        Task { await handleShellModeChange(mode) }
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openHelpGuide() async {
        await loadHelpGuide()
        showingHelpGuide = true
    }

    func loadHelpGuide() async {
        do {
            helpGuide = try await api.helpGuide(languageCode: language.rawValue)
            actionErrorMessage = nil
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    /// The desktop app treats the first workflow agent as the coordinator that
    /// fans work out to the remaining worker agents. The backend still stores a
    /// simple ordered agent list, so keeping this invariant in the client makes
    /// the workflow authoring UX line up with the product concept.
    func setWorkflowLeadAgent(_ agent: String) {
        workflowLeadAgent = agent
        agentSelection.insert(agent)
        // The embedded terminal is the live "lead AI" console, so when the user
        // switches leaders we immediately re-open the interactive session against
        // that agent instead of leaving the old TUI attached to the workspace.
        if selectedWorkspace != nil, !isOffline {
            Task { await restartTuiSession() }
        }
    }

    /// Keep lead-agent selection coherent while the user edits the workflow roster.
    func toggleWorkflowAgent(_ agent: String) {
        if agentSelection.contains(agent) {
            // Never leave the workflow without a lead agent. If the user removes
            // the current leader, immediately promote the next remaining agent.
            if agent == workflowLeadAgent {
                guard agentSelection.count > 1 else { return }
                agentSelection.remove(agent)
                workflowLeadAgent = agentSelection.sorted().first ?? ""
            } else {
                agentSelection.remove(agent)
            }
        } else {
            agentSelection.insert(agent)
            if workflowLeadAgent.isEmpty {
                workflowLeadAgent = agent
            }
        }
    }

    // MARK: - Org Chart Profile Selection

    /// Returns org profiles matching the current multi-selection set.
    var selectedOrgProfiles: [OrgAgentProfileRecord] {
        guard !selectedOrgProfileIDs.isEmpty else { return [] }
        return orgProfiles.filter { selectedOrgProfileIDs.contains($0.id) }
    }

    var selectedCompanyAgentDefinitions: [CompanyAgentDefinitionRecord] {
        guard !selectedCompanyAgentDefinitionIDs.isEmpty else { return [] }
        return companyAgentDefinitions.filter { selectedCompanyAgentDefinitionIDs.contains($0.id) }
    }

    var selectedBatchEditableAgents: [CompanyAgentDefinitionRecord] {
        if !selectedCompanyAgentDefinitionIDs.isEmpty {
            return selectedCompanyAgentDefinitions
        }
        if !selectedOrgProfileIDs.isEmpty {
            let profiles = selectedOrgProfiles
            return profiles.compactMap { profile in
                companyAgentDefinitions.first { definition in
                    definition.companyId == profile.companyId &&
                        definition.title == profile.roleName &&
                        definition.agentCli == profile.executionAgentName
                }
            }
        }
        return []
    }

    var defaultCompanyAgentSkillIDs: Set<String> {
        Set(availableSkills.filter { !isMarketingSkill($0.name) }.map(\.name))
    }

    var isMarketingOperatorSelected: Bool {
        newCompanyAgentSkillIDs.contains("marketing-operator")
    }

    var recentMarketingRunsForEditedAgent: [MarketingRunRecord] {
        guard let companyId = editingCompanyAgentCompanyID ?? selectedCompanyID else { return [] }
        let agentId = editingCompanyAgentID
        return marketingRuns
            .filter { $0.companyId == companyId && (agentId == nil || $0.agentId == agentId) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var marketingPolicyConnectionSummary: String {
        let domains = splitAgentMeta(marketingPolicyAllowedDomains)
        let channels = splitAgentMeta(marketingPolicyChannels)
        if domains.isEmpty || channels.isEmpty {
            return language("Add at least one domain and channel before saving.", "저장하기 전에 도메인과 채널을 하나 이상 추가하세요.")
        }
        let secretState = splitAgentMeta(marketingPolicySecretRefs).isEmpty && marketingPolicyBrowserSessionRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? language("No session reference", "세션 참조 없음")
            : language("Session/secret refs configured", "세션/secret 참조 설정됨")
        return "\(channels.joined(separator: ", ")) · \(domains.joined(separator: ", ")) · \(secretState)"
    }

    func selectedSkills(for agent: CompanyAgentDefinitionRecord) -> [SkillCatalogEntryRecord] {
        let allowedIDs = skillIDs(for: agent)
        guard !allowedIDs.isEmpty else { return [] }
        return availableSkills.filter { allowedIDs.contains($0.name) }
    }

    func skillDisplayName(_ skillID: String) -> String {
        if let displayName = availableSkills.first(where: { $0.name == skillID })?.displayName {
            return displayName
        }
        return skillID
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func skillIDs(for agent: CompanyAgentDefinitionRecord) -> Set<String> {
        let setting = skillRunSetting(companyId: agent.companyId, agentId: agent.id)
        guard setting.enabled, setting.mode != "DISABLED" else { return [] }
        if setting.skillAllowlist.isEmpty {
            return defaultCompanyAgentSkillIDs
        }
        return Set(setting.skillAllowlist)
    }

    private func skillRunSetting(companyId: String, agentId: String) -> AgentCapabilitySettingRecord {
        dashboard.agentCapabilityProfiles
            .first { $0.companyId == companyId && $0.agentId == agentId }?
            .settings["SKILL_RUN"] ?? AgentCapabilitySettingRecord()
    }

    private func isMarketingSkill(_ skillID: String) -> Bool {
        ["marketing-operator", "audience-scout", "content-publisher", "social-publisher", "analytics-reporter"].contains(skillID)
    }

    /// Toggle or range-select org chart profiles for multi-selection.
    ///
    /// When shiftKey is true and a previous selection anchor exists, selects all
    /// profiles between the last selected and the current one (range selection).
    /// When shiftKey is false, toggles the clicked profile while preserving any
    /// existing selection so the org chart behaves like the preferred-collaborator
    /// picker and supports additive multi-select without modifier keys.
    func toggleOrgProfileSelection(id: String, shiftKey: Bool) {
        let previousAnchor = lastSelectedOrgProfileID

        if shiftKey, let lastID = previousAnchor, lastID != id {
            // Range selection: find indices and select everything between them
            let profileIDs = orgProfiles.map(\.id)
            guard let lastIndex = profileIDs.firstIndex(of: lastID),
                  let currentIndex = profileIDs.firstIndex(of: id) else {
                selectedOrgProfileIDs = [id]
                lastSelectedOrgProfileID = id
                return
            }
            let lower = min(lastIndex, currentIndex)
            let upper = max(lastIndex, currentIndex)
            let rangeIDs = Set(profileIDs[lower...upper])
            selectedOrgProfileIDs.formUnion(rangeIDs)
        } else {
            // Default interaction is additive toggle so multiple org nodes can be
            // selected the same way collaborator chips are selected.
            if selectedOrgProfileIDs.contains(id) {
                selectedOrgProfileIDs.remove(id)
            } else {
                selectedOrgProfileIDs.insert(id)
            }
        }
        lastSelectedOrgProfileID = id
    }

    /// Clear all org profile selection state.
    func clearOrgProfileSelection() {
        selectedOrgProfileIDs = []
        lastSelectedOrgProfileID = nil
    }

    func toggleCompanyAgentSelection(id: String, shiftKey: Bool) {
        let previousAnchor = lastSelectedOrgProfileID

        if shiftKey, let lastID = previousAnchor, lastID != id {
            let agentIDs = companyAgentDefinitions.map(\.id)
            guard let lastIndex = agentIDs.firstIndex(of: lastID),
                  let currentIndex = agentIDs.firstIndex(of: id) else {
                selectedCompanyAgentDefinitionIDs = [id]
                lastSelectedOrgProfileID = id
                return
            }
            let lower = min(lastIndex, currentIndex)
            let upper = max(lastIndex, currentIndex)
            let rangeIDs = Set(agentIDs[lower...upper])
            selectedCompanyAgentDefinitionIDs.formUnion(rangeIDs)
        } else {
            if selectedCompanyAgentDefinitionIDs.contains(id) {
                selectedCompanyAgentDefinitionIDs.remove(id)
            } else {
                selectedCompanyAgentDefinitionIDs.insert(id)
            }
        }
        lastSelectedOrgProfileID = id
    }

    func clearCompanyAgentSelection() {
        selectedCompanyAgentDefinitionIDs = []
    }

    func statusLabel(_ status: String) -> String {
        DesktopStrings.status(status, language: language)
    }

    func shortcutTitle(_ binding: ShortcutBindingPayload) -> String {
        DesktopStrings.shortcutTitle(id: binding.id, fallback: binding.title, language: language)
    }

    /// Entry point invoked by the app scene once the window becomes active.
    func bootstrap() async {
        guard !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }
        // Bootstrap intentionally starts local background observers before the first network call.
        // That way a just-launched app can recover embedded backend state, begin polling, and only
        // then decide whether the shell should present live data or an offline fallback.
        startCompanyStatePolling()
        startEmbeddedBackendWatchdog()
        await EmbeddedBackendLauncher.shared.ensureRunning()
        await prepareDesktopLifecycleStartupIfNeeded()
        // Installed app bundles launch the backend lazily, so the first request can
        // arrive before `cotor app-server` has finished binding its localhost port.
        let maxAttempts = 4
        for attempt in 0 ..< maxAttempts {
            await refreshDashboard()
            if !shouldRetryBootstrapAfterRefresh(attempt: attempt, maxAttempts: maxAttempts) {
                return
            }
            statusState = .waitingForServer
            objectWillChange.send()
            await EmbeddedBackendLauncher.shared.ensureRunning()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func prepareDesktopLifecycleStartupIfNeeded() async {
        guard !didRequestDesktopLifecycleStartup else { return }
        didRequestDesktopLifecycleStartup = true
        do {
            let result = try await runWithEmbeddedBackendRecovery {
                try await api.prepareDesktopStartup()
            }
            if result.runtimeStarted {
                AppLogger.warning("Desktop lifecycle startup unexpectedly reported runtimeStarted=true.")
            }
        } catch {
            didRequestDesktopLifecycleStartup = false
            AppLogger.warning("Desktop lifecycle startup warmup failed: \(error.localizedDescription)")
        }
    }

    func shouldRetryBootstrapAfterRefresh(attempt: Int, maxAttempts: Int) -> Bool {
        guard attempt < maxAttempts - 1 else { return false }
        if isOffline { return true }
        return dashboard.companies.isEmpty &&
            dashboard.repositories.isEmpty &&
            dashboard.goals.isEmpty &&
            dashboard.issues.isEmpty &&
            dashboard.tasks.isEmpty
    }

    func handleAppBecameActive() async {
        await bootstrap()
    }

    /// Reload the top-level dashboard payload and preserve/repair selection state.
    func refreshDashboard(restartEventStream: Bool = true) async {
        guard !isRefreshingDashboard else { return }
        isRefreshingDashboard = true
        defer { isRefreshingDashboard = false }
        if shouldUseCompanyScopedRefresh {
            await refreshCompanyDashboard(restartEventStream: restartEventStream)
            return
        }
        await refreshFullDashboard(restartEventStream: restartEventStream)
    }

    private var shouldUseCompanyScopedRefresh: Bool {
        didInitializeShellMode && shellMode == .company && selectedCompanyID != nil
    }

    private func refreshFullDashboard(restartEventStream: Bool) async {
        // The dashboard payload is the SwiftUI store's source of truth. Most per-pane selections
        // are repaired immediately after loading so the shell can survive backend restarts, data
        // deletions, and stream reconnects without stranding the user on stale identifiers.
        isBusy = true
        defer { isBusy = false }

        do {
            let fresh = try await runWithEmbeddedBackendRecovery {
                try await api.dashboard()
            }
            let skillCatalog = try await runWithEmbeddedBackendRecovery {
                try await api.skills()
            }
            dashboard = fresh
            marketingDelegationPolicies = fresh.marketingDelegationPolicies
            marketingRuns = fresh.marketingRuns
            skillRuns = fresh.skillRuns
            availableSkills = skillCatalog
            await refreshMarketingState()
            syncDefaultCompanyAgentSkillsIfNeeded()
            errorMessage = nil
            isOffline = false
            statusState = .connected(api.baseURL.absoluteString)
            if !didInitializeShellMode {
                shellMode = .company
                didInitializeShellMode = true
            }
            reconcileWorkflowLeadAgent()
            reconcileSelection()
            syncIssueComposerState()
            syncBackendFormState()
            await refreshCompanyReports()
            await refreshCompanyProblemSignals()
            await refreshAvailableBranches()
            await refreshTaskDetails()
            await refreshTuiSessionList()
            if shellMode == .tui {
                selectWorkspaceForTuiIfNeeded()
                if let session = activeTuiSession {
                    await selectTuiSession(session)
                }
            }
            if restartEventStream, shellMode == .company {
                await restartCompanyEventStream()
            }
        } catch is CancellationError {
            return
        } catch {
            if isBenignCancellationLikeError(error) {
                return
            }
            let backendStillHealthy = (try? await api.health()) == true
            if backendStillHealthy {
                AppLogger.error("Dashboard refresh failed while backend remained healthy: \(error.localizedDescription)")
                isOffline = false
                statusState = .connected(api.baseURL.absoluteString)
                errorMessage = error.localizedDescription
                return
            }
            isOffline = true
            statusState = .offlineMock
            AppLogger.error("Dashboard refresh marked app offline: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            reconcileWorkflowLeadAgent()
            reconcileSelection()
            syncIssueComposerState()
            selectedAgentName = selectedTask?.agents.first
            await refreshAvailableBranches()
            stopTuiPolling()
            companyEventTask?.cancel()
            companyEventTask = nil
            tuiSessions = []
            tuiSession = nil
            selectedTuiSessionID = nil
        }
    }

    private func refreshCompanyDashboard(restartEventStream: Bool) async {
        guard let companyID = selectedCompanyID else {
            await refreshFullDashboard(restartEventStream: restartEventStream)
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let fresh = try await runWithEmbeddedBackendRecovery {
                try await api.companyDashboard(companyId: companyID)
            }
            let skillCatalog = try await runWithEmbeddedBackendRecovery {
                try await api.skills()
            }
            applyCompanyDashboard(fresh, companyId: companyID)
            availableSkills = skillCatalog
            await refreshMarketingState(companyId: companyID)
            await refreshCompanyReports(companyId: companyID)
            await refreshCompanyProblemSignals(companyId: companyID)
            syncDefaultCompanyAgentSkillsIfNeeded()
            errorMessage = nil
            isOffline = false
            statusState = .connected(api.baseURL.absoluteString)
            if restartEventStream {
                await restartCompanyEventStream()
            }
        } catch is CancellationError {
            return
        } catch {
            if isBenignCancellationLikeError(error) {
                return
            }
            let backendStillHealthy = (try? await api.health()) == true
            if backendStillHealthy {
                AppLogger.error("Company dashboard refresh failed while backend remained healthy: \(error.localizedDescription)")
                isOffline = false
                statusState = .connected(api.baseURL.absoluteString)
                errorMessage = error.localizedDescription
                return
            }
            isOffline = true
            statusState = .offlineMock
            AppLogger.error("Company dashboard refresh marked app offline: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            selectedAgentName = selectedTask?.agents.first
            stopTuiPolling()
            companyEventTask?.cancel()
            companyEventTask = nil
        }
    }

    private func applyCompanyDashboard(_ snapshot: CompanyDashboardPayload, companyId: String) {
        dashboard = DashboardPayloadMerger.applyingCompanySnapshot(
            current: dashboard,
            snapshot: snapshot,
            companyId: companyId,
            currentMarketingPolicies: marketingDelegationPolicies,
            currentMarketingRuns: marketingRuns,
            currentSkillRuns: skillRuns
        )
        marketingDelegationPolicies = dashboard.marketingDelegationPolicies
        marketingRuns = dashboard.marketingRuns
        skillRuns = dashboard.skillRuns
        companyStreamStatusMessage = nil
        reconcileWorkflowLeadAgent()
        reconcileCompanySelection()
        syncIssueComposerState()
        syncBackendFormState()
    }

    private func syncDefaultCompanyAgentSkillsIfNeeded() {
        guard editingCompanyAgentID == nil, newCompanyAgentSkillIDs.isEmpty else { return }
        newCompanyAgentSkillIDs = defaultCompanyAgentSkillIDs
    }

    private func refreshMarketingState(companyId: String? = nil) async {
        let scopedCompanyId = companyId ?? selectedCompanyID
        do {
            let policies = try await runWithEmbeddedBackendRecovery {
                try await api.marketingPolicies(companyId: scopedCompanyId)
            }
            let runs = try await runWithEmbeddedBackendRecovery {
                try await api.marketingRuns(companyId: scopedCompanyId)
            }
            if let scopedCompanyId {
                marketingDelegationPolicies = marketingDelegationPolicies.filter { $0.companyId != scopedCompanyId } + policies
                marketingRuns = marketingRuns.filter { $0.companyId != scopedCompanyId } + runs
            } else {
                marketingDelegationPolicies = policies
                marketingRuns = runs
            }
            if let editingCompanyAgentID {
                syncMarketingPolicyForm(forAgentId: editingCompanyAgentID)
            }
        } catch {
            AppLogger.error("Marketing state refresh failed: \(error.localizedDescription)")
        }
    }

    func refreshCompanyReports(companyId: String? = nil) async {
        guard let scopedCompanyId = companyId ?? selectedCompanyID else {
            companyReports = []
            selectedCompanyReportDate = nil
            selectedCompanyReport = nil
            return
        }
        do {
            let summaries = try await runWithEmbeddedBackendRecovery {
                try await api.companyReports(companyId: scopedCompanyId)
            }
            guard isCurrentCompany(scopedCompanyId) else { return }
            companyReports = companyReports.filter { $0.companyId != scopedCompanyId } + summaries
            let sortedSummaries = summaries.sorted {
                if $0.date == $1.date {
                    return $0.generatedAt > $1.generatedAt
                }
                return $0.date > $1.date
            }
            if let selectedCompanyReportDate,
               sortedSummaries.contains(where: { $0.date == selectedCompanyReportDate }) {
                await selectCompanyReport(date: selectedCompanyReportDate)
            } else if let latest = sortedSummaries.first {
                await selectCompanyReport(date: latest.date)
            } else {
                selectedCompanyReportDate = nil
                selectedCompanyReport = nil
            }
        } catch {
            AppLogger.error("Company report refresh failed: \(error.localizedDescription)")
        }
    }

    func selectCompanyReport(date: String) async {
        guard let companyID = selectedCompanyID else { return }
        do {
            let report = try await runWithEmbeddedBackendRecovery {
                try await api.companyReport(companyId: companyID, date: date)
            }
            guard isCurrentCompany(companyID) else { return }
            selectedCompanyReportDate = date
            selectedCompanyReport = report
        } catch {
            if isCurrentCompany(companyID) {
                errorMessage = error.localizedDescription
            }
            AppLogger.error("Company report load failed: \(error.localizedDescription)")
        }
    }

    func generateCompanyReport() async {
        guard let companyID = selectedCompanyID else { return }
        isGeneratingCompanyReport = true
        defer { isGeneratingCompanyReport = false }
        do {
            let report = try await runWithEmbeddedBackendRecovery {
                try await api.generateCompanyReport(companyId: companyID)
            }
            guard isCurrentCompany(companyID) else { return }
            selectedCompanyReportDate = report.date
            selectedCompanyReport = report
            await refreshCompanyReports(companyId: companyID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.error("Company report generation failed: \(error.localizedDescription)")
        }
    }

    /// Repair selection state after a dashboard refresh so every pane still points
    /// at records that exist in the freshly returned payload.
    private func reconcileSelection() {
        if !companies.contains(where: { $0.id == selectedCompanyID }) {
            selectedCompanyID = companies.first?.id
        }
        if !repositories.contains(where: { $0.id == selectedRepositoryID }) {
            selectedRepositoryID = selectedCompany.map(\.repositoryId) ?? repositories.first?.id
        }
        if !workspaces.contains(where: { $0.id == selectedWorkspaceID }) {
            selectedWorkspaceID = workspaces.first?.id
        }
        if !goals.contains(where: { $0.id == selectedGoalID }) {
            selectedGoalID = goals.first?.id
        }
        if !issues.contains(where: { $0.id == selectedIssueID }) {
            selectedIssueID = issues.first?.id
        }
        if !tasks.contains(where: { $0.id == selectedTaskID }) {
            selectedTaskID = tasks.first?.id
        }

        if let issue = selectedIssue {
            if selectedCompanyID != issue.companyId {
                selectedCompanyID = issue.companyId
            }
            if selectedWorkspaceID != issue.workspaceId {
                selectedWorkspaceID = issue.workspaceId
            }
            if selectedTask == nil {
                selectedTaskID = dashboard.tasks
                    .filter { $0.issueId == issue.id }
                    .sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
                    .first?.id
            }
        }

        if let task = selectedTask {
            if !task.agents.contains(selectedAgentName ?? "") {
                selectedAgentName = task.agents.first
            }
        } else {
            selectedAgentName = nil
        }
        if let editingAgentID = editingCompanyAgentID,
           !companyAgentDefinitions.contains(where: { $0.id == editingAgentID && $0.companyId == editingCompanyAgentCompanyID }) {
            resetCompanyAgentComposer()
        }
        pendingWorkspaceBaseBranch = selectedWorkspace?.baseBranch ?? selectedCompany?.defaultBaseBranch ?? selectedRepository?.defaultBranch ?? "main"
    }

    private func reconcileCompanySelection() {
        if !companies.contains(where: { $0.id == selectedCompanyID }) {
            selectedCompanyID = companies.first?.id
        }
        if let selectedCompany {
            selectedRepositoryID = selectedCompany.repositoryId
        }
        if !goals.contains(where: { $0.id == selectedGoalID }) {
            selectedGoalID = goals.first?.id
        }
        if !issues.contains(where: { $0.id == selectedIssueID }) {
            selectedIssueID = issues.first?.id
        }
        if let issue = selectedIssue {
            selectedCompanyID = issue.companyId
            selectedGoalID = issue.goalId
            selectedWorkspaceID = issue.workspaceId
        }
        if let selectedIssueID {
            let matchingTask = dashboard.tasks
                .filter { $0.issueId == selectedIssueID }
                .sorted { $0.updatedAt > $1.updatedAt }
                .first
            if selectedTaskID == nil || !dashboard.tasks.contains(where: { $0.id == selectedTaskID }) {
                selectedTaskID = matchingTask?.id
            }
        }
        if let task = selectedTask {
            if !task.agents.contains(selectedAgentName ?? "") {
                selectedAgentName = task.agents.first
            }
        } else {
            selectedAgentName = nil
        }
        if let editingAgentID = editingCompanyAgentID,
           !companyAgentDefinitions.contains(where: { $0.id == editingAgentID && $0.companyId == editingCompanyAgentCompanyID }) {
            resetCompanyAgentComposer()
        }
        pendingWorkspaceBaseBranch = selectedWorkspace?.baseBranch ?? selectedCompany?.defaultBaseBranch ?? selectedRepository?.defaultBranch ?? "main"
    }

    private func syncIssueComposerState() {
        if issueComposerCompany == nil {
            newIssueCompanyID = selectedCompanyID ?? companies.first?.id
        }
        let validCompanyID = issueComposerCompany?.id
        if let currentGoalID = newIssueGoalID,
           !dashboard.goals.contains(where: { $0.id == currentGoalID && $0.companyId == validCompanyID }) {
            newIssueGoalID = nil
        }
        if newIssueGoalID == nil {
            newIssueGoalID = issueComposerGoals.first?.id ?? selectedGoalID
        }
    }

    /// Repair the workflow lead and selected agent roster after bootstrap or
    /// dashboard refresh. This keeps the authoring UI stable even when the
    /// backend roster changes after a live dashboard refresh.
    private func reconcileWorkflowLeadAgent() {
        let availableAgents = dashboard.settings.availableAgents
        let cliAgents = availableCliAgents

        if availableAgents.isEmpty {
            workflowLeadAgent = ""
            agentSelection = []
            newCompanyAgentCli = ""
            return
        }

        if workflowLeadAgent.isEmpty || !availableAgents.contains(workflowLeadAgent) {
            workflowLeadAgent = preferredDesktopAgent(from: availableAgents) ?? ""
        }

        if newCompanyAgentCli.isEmpty || !cliAgents.contains(newCompanyAgentCli) {
            selectNewCompanyAgentCli(preferredDesktopAgent(from: cliAgents) ?? preferredDesktopAgent(from: availableAgents) ?? "")
        }
        if newCompanyAgentModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let defaultModel = defaultModel(for: newCompanyAgentCli),
           shouldAutoFillDefaultModel(
                for: newCompanyAgentCli,
                options: modelOptions(for: newCompanyAgentCli),
                defaultModel: defaultModel
           ) {
            newCompanyAgentModel = defaultModel
        }

        let validSelection = Set(agentSelection.filter { availableAgents.contains($0) })
        agentSelection = validSelection.isEmpty ? [workflowLeadAgent] : validSelection
        agentSelection.insert(workflowLeadAgent)
    }

    private func syncBackendFormState() {
        defaultBackendKind = dashboard.settings.backendSettings.defaultBackendKind
        codePublishMode = dashboard.settings.backendSettings.codePublishMode
        if let config = dashboard.settings.backendSettings.backends.first(where: { $0.kind == "CODEX_APP_SERVER" }) {
            codexLaunchMode = config.launchMode
            codexCommand = config.command
            codexArgs = config.args.joined(separator: " ")
            codexWorkingDirectory = config.workingDirectory ?? ""
            codexPort = config.port.map(String.init) ?? ""
            codexStartupTimeoutSeconds = String(config.startupTimeoutSeconds)
            codexAppServerBaseURL = config.baseUrl ?? ""
        } else {
            codexLaunchMode = "MANAGED"
            codexCommand = "codex"
            codexArgs = "app-server --host 127.0.0.1 --port {port}"
            codexWorkingDirectory = ""
            codexPort = ""
            codexStartupTimeoutSeconds = "15"
            codexAppServerBaseURL = ""
        }
        codexBackendStatus = dashboard.backendStatuses.first(where: { $0.kind == "CODEX_APP_SERVER" })
        syncCodexOAuthState()
        syncSelectedCompanyLinearFormState()
    }

    func syncSelectedCompanyBudgetFormState() {
        guard let company = selectedCompany else {
            companyDailyBudgetInput = ""
            companyMonthlyBudgetInput = ""
            return
        }
        companyDailyBudgetInput = budgetInputString(from: company.dailyBudgetCents)
        companyMonthlyBudgetInput = budgetInputString(from: company.monthlyBudgetCents)
    }

    private func syncSelectedCompanyLinearFormState() {
        guard let company = selectedCompany else {
            companyLinearSyncEnabled = false
            companyLinearEndpoint = dashboard.settings.linearSettings?.defaultConfig.endpoint ?? ""
            companyLinearTeamID = ""
            companyLinearProjectID = ""
            companyLinearStatusMessage = nil
            return
        }

        let config = company.linearConfigOverride ?? dashboard.settings.linearSettings?.defaultConfig
        companyLinearSyncEnabled = company.linearSyncEnabled ?? false
        companyLinearEndpoint = config?.endpoint ?? ""
        companyLinearTeamID = config?.teamId ?? ""
        companyLinearProjectID = config?.projectId ?? ""
        companyLinearStatusMessage = latestCompanyLinearActivityMessage(companyId: company.id)
    }

    private func budgetInputString(from cents: Int?) -> String {
        guard let cents, cents > 0 else { return "" }
        let dollars = Double(cents) / 100.0
        if cents % 100 == 0 {
            return String(Int(dollars))
        }
        return String(format: "%.2f", dollars)
    }

    private func budgetCentsForCreateInput(_ value: String) throws -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try parseBudgetInput(trimmed)
    }

    private func budgetCentsForUpdateInput(_ value: String) throws -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return try parseBudgetInput(trimmed) ?? 0
    }

    private func parseBudgetInput(_ value: String) throws -> Int? {
        let sanitized = value.replacingOccurrences(of: ",", with: "")
        guard let amount = Double(sanitized), amount >= 0 else {
            throw NSError(
                domain: "CotorDesktop",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: language(
                    "Enter a valid USD budget amount such as 25 or 25.50.",
                    "25 또는 25.50 같은 올바른 USD 예산 금액을 입력하세요."
                )]
            )
        }
        return Int((amount * 100.0).rounded())
    }

    private func latestCompanyLinearActivityMessage(companyId: String) -> String? {
        activity
            .first(where: { $0.companyId == companyId && ($0.source == "linear-sync" || $0.source == "linear") })
            .flatMap { item in
                [item.title, item.detail].compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }.joined(separator: " · ")
            }
    }

    func saveSelectedCompanyLinearSettings() async {
        guard let company = selectedCompany else { return }
        do {
            _ = try await api.updateCompanyLinear(
                companyId: company.id,
                enabled: companyLinearSyncEnabled,
                endpoint: trimmedOptional(companyLinearEndpoint),
                apiToken: nil,
                teamId: trimmedOptional(companyLinearTeamID),
                projectId: trimmedOptional(companyLinearProjectID),
                useGlobalDefault: false
            )
            await refreshDashboard()
            companyLinearStatusMessage = language("Saved company Linear mirror settings.", "회사 Linear 미러 설정을 저장했습니다.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resyncSelectedCompanyLinear() async {
        guard let company = selectedCompany else { return }
        do {
            let result = try await api.resyncCompanyLinear(companyId: company.id)
            companyLinearStatusMessage = result.message
            await refreshDashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Refresh the right-hand inspector panels for the currently selected task and agent.
    func refreshTaskDetails() async {
        if isOffline {
            runs = []
            issueExecutionDetails = []
            changes = emptyChangeSummary()
            files = []
            ports = []
            browserURL = nil
            return
        }

        // Eagerly clear stale detail state so the panel never momentarily shows
        // data from the previously selected issue while the new one is loading.
        let requestedIssueID = selectedIssueID
        issueExecutionDetails = []
        runs = []
        changes = emptyChangeSummary()
        files = []
        ports = []
        browserURL = nil

        if let issueId = selectedIssue?.id {
            do {
                let fetchedIssueExecutionDetails = try await api.issueExecutionDetails(issueId: issueId)
                    .sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
                guard selectedIssue?.id == issueId else { return }
                issueExecutionDetails = fetchedIssueExecutionDetails
            } catch {
                issueExecutionDetails = []
                errorMessage = error.localizedDescription
            }
        } else {
            issueExecutionDetails = []
        }

        guard let task = selectedTask else {
            runs = []
            changes = emptyChangeSummary()
            files = []
            ports = []
            browserURL = nil
            return
        }
        let agent = selectedAgentName ?? task.agents.first
        selectedAgentName = agent
        guard let agent else { return }
        let requestedTaskID = task.id

        // Determine which task IDs belong to the selected issue so effectiveRun
        // never crosses the issue boundary when falling back.
        let issueTaskIDs: Set<String> = requestedIssueID.map { iid in
            Set(tasks.filter { $0.issueId == iid }.map { $0.id })
        } ?? []

        do {
            let fetchedRuns: [RunRecord]
            if let issueId = requestedIssueID {
                fetchedRuns = try await api.issueRuns(issueId: issueId).sorted { lhs, rhs in
                    lhs.updatedAt > rhs.updatedAt
                }
            } else {
                fetchedRuns = try await api.runs(taskId: task.id).sorted { lhs, rhs in
                    lhs.updatedAt > rhs.updatedAt
                }
            }
            guard selectedIssueID == requestedIssueID, selectedTask?.id == requestedTaskID else { return }
            runs = fetchedRuns

            let latestForTask = fetchedRuns.filter { $0.taskId == task.id }
            // Only fall back to other runs when they belong to the same issue's tasks.
            let issueRuns = issueTaskIDs.isEmpty ? fetchedRuns : fetchedRuns.filter { issueTaskIDs.contains($0.taskId) }
            let effectiveRun = latestForTask.first { $0.agentName.caseInsensitiveCompare(agent) == .orderedSame }
                ?? latestForTask.first
                ?? issueRuns.first { $0.agentName.caseInsensitiveCompare(agent) == .orderedSame }
                ?? issueRuns.first
            if let effectiveRun, issueTaskIDs.isEmpty || issueTaskIDs.contains(effectiveRun.taskId) {
                selectedTaskID = effectiveRun.taskId
            }
            let effectiveAgent = effectiveRun?.agentName ?? agent
            selectedAgentName = effectiveAgent

            guard let effectiveRun else {
                changes = emptyChangeSummary()
                files = []
                ports = []
                browserURL = nil
                return
            }

            async let fetchedChanges = safeChanges(runId: effectiveRun.id)
            async let fetchedFiles = safeFiles(runId: effectiveRun.id)
            async let fetchedPorts = safePorts(runId: effectiveRun.id)

            let resolvedChanges = await fetchedChanges
            let resolvedFiles = await fetchedFiles
            let resolvedPorts = await fetchedPorts
            guard selectedIssueID == requestedIssueID, selectedTask?.id == effectiveRun.taskId else { return }
            changes = resolvedChanges
            files = resolvedFiles
            ports = resolvedPorts
            browserURL = resolvedPorts.first.flatMap { URL(string: $0.url) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func emptyChangeSummary() -> ChangeSummaryPayload {
        ChangeSummaryPayload(
            runId: "",
            branchName: "",
            baseBranch: selectedWorkspace?.baseBranch ?? selectedCompany?.defaultBaseBranch ?? "",
            patch: "",
            changedFiles: []
        )
    }

    private func safeChanges(runId: String) async -> ChangeSummaryPayload {
        do {
            return try await api.changes(runId: runId)
        } catch {
            return emptyChangeSummary()
        }
    }

    private func safeFiles(runId: String) async -> [FileTreeNodePayload] {
        do {
            return try await api.files(runId: runId, path: nil)
        } catch {
            return []
        }
    }

    private func safePorts(runId: String) async -> [PortEntryPayload] {
        do {
            return try await api.ports(runId: runId)
        } catch {
            return []
        }
    }

    /// Create a workspace using the repository currently focused in the sidebar.
    func createWorkspace() async {
        guard let repository = selectedRepository else { return }
        let name = newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let created = try await api.createWorkspace(
                repositoryId: repository.id,
                name: name.isEmpty ? nil : name,
                baseBranch: pendingWorkspaceBaseBranch
            )
            newWorkspaceName = ""
            await refreshDashboard()
            selectedWorkspaceID = created.id
            pendingWorkspaceBaseBranch = created.baseBranch
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Create a task in the selected workspace from the current composer state.
    func createTask() async {
        guard let workspace = selectedWorkspace else { return }
        let prompt = newTaskPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        let workerAgents = Array(agentSelection.subtracting([workflowLeadAgent])).sorted()
        let orderedAgents = [workflowLeadAgent].filter { !$0.isEmpty } + workerAgents

        do {
            let created = try await api.createTask(
                workspaceId: workspace.id,
                title: newTaskTitle.isEmpty ? nil : newTaskTitle,
                prompt: prompt,
                agents: orderedAgents
            )
            newTaskTitle = ""
            newTaskPrompt = ""
            await refreshDashboard()
            selectedTaskID = created.id
            selectedAgentName = created.agents.first
            await refreshTaskDetails()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createGoal() async {
        guard let company = selectedCompany else { return }
        let title = newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = newGoalDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveDescription = description.isEmpty ? title : description
        guard !title.isEmpty else { return }

        do {
            actionErrorMessage = nil
            errorMessage = nil
            AppLogger.info("Saving goal '\(title)' for company \(company.id).")
            let saved: GoalRecord
            if let goalID = editingGoalID {
                saved = try await runWithEmbeddedBackendRecovery {
                    try await api.updateGoal(
                        companyId: company.id,
                        goalId: goalID,
                        title: title,
                        description: effectiveDescription
                    )
                }
            } else {
                saved = try await runWithEmbeddedBackendRecovery {
                    try await api.createGoal(companyId: company.id, title: title, description: effectiveDescription)
                }
            }
            resetGoalComposer()
            selectedGoalID = saved.id
            selectedCompanyID = company.id
            AppLogger.info("Saved goal '\(saved.title)' (\(saved.id)) for company \(company.id).")
            await performNonCriticalGoalRefresh(saved, companyID: company.id)
        } catch is CancellationError {
            actionErrorMessage = nil
            errorMessage = nil
        } catch {
            AppLogger.error("Save goal failed for company \(company.id): \(error.localizedDescription)")
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func chatGoalProposal(from draft: String) -> ChatGoalProposal? {
        OperatorChatProposalParser.goal(from: draft)
    }

    func chatCompanyRequestProposal(from draft: String) -> ChatCompanyRequestProposal? {
        let companyName = selectedCompany?.name ?? language("selected company", "선택한 회사")
        return OperatorChatProposalParser.companyRequest(from: draft, companyName: companyName, language: language)
    }

    func chatIssueProposal(from draft: String) -> ChatIssueProposal? {
        let goalId = selectedGoalID ?? selectedIssue?.goalId
        return OperatorChatProposalParser.issue(from: draft, goalId: goalId)
    }

    func applyChatGoalProposal(_ proposal: ChatGoalProposal) async -> GoalRecord? {
        guard let company = selectedCompany else {
            actionErrorMessage = language(
                "Select a company before applying a goal proposal.",
                "목표 제안을 적용하기 전에 회사를 선택하세요."
            )
            return nil
        }

        do {
            actionErrorMessage = nil
            errorMessage = nil
            AppLogger.info("Applying chat goal proposal '\(proposal.title)' for company \(company.id).")
            let saved = try await runWithEmbeddedBackendRecovery {
                try await api.createGoal(
                    companyId: company.id,
                    title: proposal.title,
                    description: proposal.description
                )
            }
            selectedCompanyID = company.id
            selectedGoalID = saved.id
            AppLogger.info("Applied chat goal proposal '\(saved.title)' (\(saved.id)) for company \(company.id).")
            await performNonCriticalGoalRefresh(saved, companyID: company.id)
            return saved
        } catch is CancellationError {
            actionErrorMessage = nil
            errorMessage = nil
            return nil
        } catch {
            AppLogger.error("Apply chat goal proposal failed for company \(company.id): \(error.localizedDescription)")
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func applyChatCompanyRequestProposal(_ proposal: ChatCompanyRequestProposal) async -> ChatIntakeResponsePayload? {
        guard let company = selectedCompany else {
            actionErrorMessage = language(
                "Select a company before asking the CEO to plan from chat.",
                "채팅으로 CEO 계획을 요청하기 전에 회사를 선택하세요."
            )
            return nil
        }

        do {
            actionErrorMessage = nil
            errorMessage = nil
            let response = try await runWithEmbeddedBackendRecovery {
                try await api.createChatIntake(
                    companyId: company.id,
                    message: proposal.request,
                    startRuntime: false
                )
            }
            selectedCompanyID = response.goal.companyId
            selectedGoalID = response.goal.id
            if let firstIssue = response.issues.first {
                selectedIssueID = firstIssue.id
                selectedWorkspaceID = firstIssue.workspaceId
            } else if let planningIssue = response.planningIssue {
                selectedIssueID = planningIssue.id
                selectedWorkspaceID = planningIssue.workspaceId
            }
            await refreshDashboard()
            await refreshTaskDetails()
            await loadSelectedCompanyMemorySnapshot()
            return response
        } catch is CancellationError {
            actionErrorMessage = nil
            errorMessage = nil
            return nil
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func applyChatIssueProposal(_ proposal: ChatIssueProposal) async -> IssueRecord? {
        guard let company = selectedCompany else {
            actionErrorMessage = language(
                "Select a company before applying an issue proposal.",
                "이슈 제안을 적용하기 전에 회사를 선택하세요."
            )
            return nil
        }

        do {
            actionErrorMessage = nil
            errorMessage = nil
            let saved = try await runWithEmbeddedBackendRecovery {
                try await api.createIssue(
                    companyId: company.id,
                    goalId: proposal.goalId,
                    title: proposal.title,
                    description: proposal.description
                )
            }
            selectedCompanyID = saved.companyId
            selectedGoalID = saved.goalId
            selectedIssueID = saved.id
            await performNonCriticalIssueRefresh(saved)
            return saved
        } catch is CancellationError {
            actionErrorMessage = nil
            errorMessage = nil
            return nil
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func chatReviewProposal(from draft: String, kind: String) -> ChatReviewProposal? {
        OperatorChatProposalParser.review(from: draft, kind: kind)
    }

    func chatMergeProposal(from draft: String) -> ChatMergeProposal? {
        OperatorChatProposalParser.merge(from: draft)
    }

    func chatRuntimeProposal(from draft: String) -> ChatRuntimeProposal? {
        OperatorChatProposalParser.runtime(from: draft)
    }

    func chatAgentProposal(from draft: String) -> ChatAgentProposal? {
        let workflowLead = workflowLeadAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredCli = preferredDesktopAgent(from: dashboard.settings.availableAgents) ?? (workflowLead.isEmpty ? nil : workflowLead) ?? "opencode"
        return OperatorChatProposalParser.agent(from: draft, preferredCli: preferredCli, language: language)
    }

    func chatBackendProposal(from draft: String) -> ChatBackendProposal? {
        OperatorChatProposalParser.backend(from: draft)
    }

    func chatExecutionProposal(from draft: String) -> ChatExecutionProposal? {
        OperatorChatProposalParser.execution(from: draft)
    }

    func chatDelegationProposal(from draft: String) -> ChatDelegationProposal? {
        OperatorChatProposalParser.delegation(from: draft)
    }

    func chatGoalDecompositionProposal(from draft: String) -> ChatGoalDecompositionProposal? {
        OperatorChatProposalParser.goalDecomposition(from: draft)
    }

    func chatGoalAutonomyProposal(from draft: String) -> ChatGoalAutonomyProposal? {
        OperatorChatProposalParser.goalAutonomy(from: draft)
    }

    func applyChatReviewProposal(_ proposal: ChatReviewProposal) async -> ReviewQueueItemRecord? {
        guard let item = selectedReviewQueueItem else {
            actionErrorMessage = language(
                "Select a review queue item before applying a review proposal.",
                "리뷰 제안을 적용하기 전에 리뷰 큐 항목을 선택하세요."
            )
            return nil
        }

        do {
            actionErrorMessage = nil
            errorMessage = nil
            let updated = try await runWithEmbeddedBackendRecovery {
                switch proposal.stage {
                case .qa:
                    return try await api.submitQaReviewVerdict(itemId: item.id, verdict: proposal.verdict, feedback: proposal.feedback)
                case .ceo:
                    return try await api.submitCeoReviewVerdict(itemId: item.id, verdict: proposal.verdict, feedback: proposal.feedback)
                }
            }
            await refreshDashboard()
            if let refreshedIssue = dashboard.issues.first(where: { $0.id == updated.issueId }) {
                selectedCompanyID = refreshedIssue.companyId
                selectedGoalID = refreshedIssue.goalId
                selectedIssueID = refreshedIssue.id
                selectedWorkspaceID = refreshedIssue.workspaceId
            }
            await refreshTaskDetails()
            return updated
        } catch is CancellationError {
            actionErrorMessage = nil
            errorMessage = nil
            return nil
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func applyChatMergeProposal(_ proposal: ChatMergeProposal) async -> ReviewQueueItemRecord? {
        guard let item = selectedReviewQueueItem else {
            actionErrorMessage = language(
                "Select a review queue item before applying a merge proposal.",
                "머지 제안을 적용하기 전에 리뷰 큐 항목을 선택하세요."
            )
            return nil
        }

        do {
            actionErrorMessage = nil
            errorMessage = nil
            let updated = try await runWithEmbeddedBackendRecovery {
                try await api.mergeReviewQueueItem(itemId: item.id)
            }
            await refreshDashboard()
            if let refreshedIssue = dashboard.issues.first(where: { $0.id == updated.issueId }) {
                selectedCompanyID = refreshedIssue.companyId
                selectedGoalID = refreshedIssue.goalId
                selectedIssueID = refreshedIssue.id
                selectedWorkspaceID = refreshedIssue.workspaceId
            }
            await refreshTaskDetails()
            return updated
        } catch is CancellationError {
            actionErrorMessage = nil
            errorMessage = nil
            return nil
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func applyChatRuntimeProposal(_ proposal: ChatRuntimeProposal) async -> CompanyRuntimeSnapshotRecord? {
        guard let company = selectedCompany else {
            actionErrorMessage = language(
                "Select a company before applying a runtime proposal.",
                "런타임 제안을 적용하기 전에 회사를 선택하세요."
            )
            return nil
        }

        do {
            actionErrorMessage = nil
            errorMessage = nil
            let snapshot = try await runWithEmbeddedBackendRecovery {
                switch proposal.action {
                case .start:
                    return try await api.startCompanyRuntime(companyId: company.id)
                case .stop:
                    return try await api.stopCompanyRuntime(companyId: company.id)
                }
            }
            await refreshDashboard()
            return dashboard.companyRuntimes.first(where: { $0.companyId == company.id }) ?? snapshot
        } catch is CancellationError {
            actionErrorMessage = nil
            errorMessage = nil
            return nil
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func applyChatAgentProposal(_ proposal: ChatAgentProposal) async -> CompanyAgentDefinitionRecord? {
        guard let company = selectedCompany else {
            actionErrorMessage = language(
                "Select a company before applying an agent proposal.",
                "에이전트 제안을 적용하기 전에 회사를 선택하세요."
            )
            return nil
        }

        do {
            actionErrorMessage = nil
            errorMessage = nil
            let saved = try await runWithEmbeddedBackendRecovery {
                try await api.createCompanyAgent(
                    companyId: company.id,
                    title: proposal.title,
                    agentCli: proposal.agentCli,
                    model: proposal.model,
                    roleSummary: proposal.roleSummary,
                    specialties: proposal.specialties,
                    collaborationInstructions: proposal.collaborationInstructions,
                    preferredCollaboratorIds: [],
                    mentorAgentId: nil,
                    memoryNotes: proposal.memoryNotes,
                    enabled: proposal.enabled
                )
            }
            await refreshDashboard()
            selectedCompanyID = company.id
            return saved
        } catch is CancellationError {
            actionErrorMessage = nil
            errorMessage = nil
            return nil
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func applyChatBackendProposal(_ proposal: ChatBackendProposal) async -> ExecutionBackendStatusPayload? {
        guard let company = selectedCompany else {
            actionErrorMessage = language(
                "Select a company before applying a backend proposal.",
                "백엔드 제안을 적용하기 전에 회사를 선택하세요."
            )
            return nil
        }

        do {
            actionErrorMessage = nil
            errorMessage = nil
            let status = try await runWithEmbeddedBackendRecovery {
                switch proposal.action {
                case .start:
                    return try await api.startCompanyBackend(companyId: company.id)
                case .stop:
                    return try await api.stopCompanyBackend(companyId: company.id)
                case .restart:
                    return try await api.restartCompanyBackend(companyId: company.id)
                }
            }
            await refreshDashboard()
            return dashboard.backendStatuses.first(where: { $0.kind == status.kind }) ?? status
        } catch is CancellationError {
            actionErrorMessage = nil
            errorMessage = nil
            return nil
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func applyChatExecutionProposal(_ proposal: ChatExecutionProposal) async -> IssueRecord? {
        guard let issue = selectedIssue else {
            actionErrorMessage = language(
                "Select an issue before applying an execution proposal.",
                "실행 제안을 적용하기 전에 이슈를 선택하세요."
            )
            return nil
        }

        do {
            actionErrorMessage = nil
            errorMessage = nil
            let updated = try await runWithEmbeddedBackendRecovery {
                try await api.runIssue(issueId: issue.id)
            }
            statusState = .taskStarted(updated.title)
            objectWillChange.send()
            await refreshDashboard()
            await refreshTaskDetails()
            await ensureTuiSession()
            return updated
        } catch is CancellationError {
            actionErrorMessage = nil
            errorMessage = nil
            return nil
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func applyChatDelegationProposal(_ proposal: ChatDelegationProposal) async -> IssueRecord? {
        guard let issue = selectedIssue else {
            actionErrorMessage = language(
                "Select an issue before applying a delegation proposal.",
                "위임 제안을 적용하기 전에 이슈를 선택하세요."
            )
            return nil
        }

        do {
            actionErrorMessage = nil
            errorMessage = nil
            let updated = try await runWithEmbeddedBackendRecovery {
                try await api.delegateIssue(issueId: issue.id)
            }
            await refreshDashboard()
            await refreshTaskDetails()
            return updated
        } catch is CancellationError {
            actionErrorMessage = nil
            errorMessage = nil
            return nil
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func applyChatGoalDecompositionProposal(_ proposal: ChatGoalDecompositionProposal) async -> [IssueRecord]? {
        guard let goal = selectedGoal else {
            actionErrorMessage = language(
                "Select a goal before applying a decomposition proposal.",
                "분해 제안을 적용하기 전에 목표를 선택하세요."
            )
            return nil
        }

        do {
            actionErrorMessage = nil
            errorMessage = nil
            let issues = try await runWithEmbeddedBackendRecovery {
                try await api.decomposeGoal(goalId: goal.id)
            }
            await refreshDashboard()
            return issues
        } catch is CancellationError {
            actionErrorMessage = nil
            errorMessage = nil
            return nil
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func applyChatGoalAutonomyProposal(_ proposal: ChatGoalAutonomyProposal) async -> GoalRecord? {
        guard let goal = selectedGoal, let company = selectedCompany else {
            actionErrorMessage = language(
                "Select a goal before applying a goal autonomy proposal.",
                "목표 자율 제안을 적용하기 전에 목표를 선택하세요."
            )
            return nil
        }

        do {
            actionErrorMessage = nil
            errorMessage = nil
            let saved = try await runWithEmbeddedBackendRecovery {
                try await api.updateGoal(
                    companyId: company.id,
                    goalId: goal.id,
                    title: goal.title,
                    description: goal.description,
                    successMetrics: goal.successMetrics,
                    autonomyEnabled: proposal.mode == .enable
                )
            }
            await refreshDashboard()
            selectedGoalID = saved.id
            return saved
        } catch is CancellationError {
            actionErrorMessage = nil
            errorMessage = nil
            return nil
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func loadSelectedCompanyMemorySnapshot() async {
        guard let companyId = selectedCompanyID ?? selectedCompany?.id else {
            companyMemorySnapshot = nil
            return
        }

        let issueId = selectedIssue?.id
        do {
            let snapshot = try await runWithEmbeddedBackendRecovery {
                try await api.companyMemorySnapshot(
                    companyId: companyId,
                    issueId: issueId,
                    agentProfileId: nil
                )
            }
            guard (selectedCompanyID ?? selectedCompany?.id) == companyId, selectedIssue?.id == issueId else { return }
            companyMemorySnapshot = snapshot
        } catch is CancellationError {
            return
        } catch {
            if companyMemorySnapshot == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshCompanyProblemSignals(companyId explicitCompanyId: String? = nil) async {
        guard let companyId = explicitCompanyId ?? selectedCompanyID ?? selectedCompany?.id else {
            companyProblemSignals = []
            return
        }

        do {
            let signals = try await runWithEmbeddedBackendRecovery {
                try await api.companyProblemSignals(companyId: companyId)
            }
            guard isCurrentCompany(companyId) else { return }
            companyProblemSignals = signals
        } catch is CancellationError {
            return
        } catch {
            AppLogger.error("Company problem signal refresh failed: \(error.localizedDescription)")
        }
    }

    func runSelectedCompanyDiscoveryScan() async {
        guard let companyId = selectedCompanyID ?? selectedCompany?.id else { return }

        do {
            let signals = try await runWithEmbeddedBackendRecovery {
                try await api.runCompanyDiscoveryScan(companyId: companyId)
            }
            guard (selectedCompanyID ?? selectedCompany?.id) == companyId else { return }
            companyProblemSignals = signals
            await refreshDashboard()
        } catch is CancellationError {
            return
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func createIssue() async {
        guard let company = issueComposerCompany else { return }
        let title = newIssueTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = newIssueDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !description.isEmpty, let goalID = newIssueGoalID else { return }

        do {
            actionErrorMessage = nil
            errorMessage = nil
            AppLogger.info("Creating issue '\(title)' for company \(company.id), goal \(goalID).")
            let saved = try await runWithEmbeddedBackendRecovery {
                try await api.createIssue(
                    companyId: company.id,
                    goalId: goalID,
                    title: title,
                    description: description
                )
            }
            selectedCompanyID = saved.companyId
            selectedGoalID = saved.goalId
            selectedIssueID = saved.id
            resetIssueComposer()
            AppLogger.info("Created issue '\(saved.title)' (\(saved.id)) for company \(saved.companyId).")
            await performNonCriticalIssueRefresh(saved)
        } catch is CancellationError {
            actionErrorMessage = nil
            errorMessage = nil
        } catch {
            AppLogger.error("Create issue failed for company \(company.id): \(error.localizedDescription)")
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }


    private func performNonCriticalCompanyRefresh(selecting company: CompanyRecord) async {
        await refreshDashboard()
        selectedCompanyID = company.id
        syncSelectedCompanyBudgetFormState()
        if let repository = repositories.first(where: { $0.id == company.repositoryId }) {
            await selectRepository(repository)
        }
    }

    private func performNonCriticalGoalRefresh(_ goal: GoalRecord, companyID: String) async {
        await refreshDashboard()
        selectedCompanyID = companyID
        selectedGoalID = goal.id
        selectedIssueID = dashboard.issues
            .filter { $0.goalId == goal.id }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?.id
        await refreshTaskDetails()
        await ensureTuiSession()
    }

    private func performNonCriticalIssueRefresh(_ issue: IssueRecord) async {
        await refreshDashboard()
        selectedCompanyID = issue.companyId
        selectedGoalID = issue.goalId
        selectedIssueID = issue.id
        await refreshTaskDetails()
    }

    func beginEditingGoal(_ goal: GoalRecord) {
        editingGoalID = goal.id
        newGoalTitle = goal.title
        newGoalDescription = goal.description
    }

    func cancelGoalEditing() {
        resetGoalComposer()
    }

    func deleteSelectedGoal() async {
        guard let company = selectedCompany, let goal = selectedGoal else { return }
        do {
            _ = try await api.deleteGoal(companyId: company.id, goalId: goal.id)
            if editingGoalID == goal.id {
                resetGoalComposer()
            }
            selectedGoalID = nil
            selectedIssueID = nil
            selectedTaskID = nil
            await refreshDashboard()
            await refreshTaskDetails()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createCompany() async {
        let name = newCompanyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootPath = newCompanyRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !rootPath.isEmpty else { return }
        do {
            let dailyBudgetCents = try budgetCentsForCreateInput(newCompanyDailyBudgetInput)
            let monthlyBudgetCents = try budgetCentsForCreateInput(newCompanyMonthlyBudgetInput)
            actionErrorMessage = nil
            companyGitHubStatusMessage = nil
            errorMessage = nil
            AppLogger.info("Creating company '\(name)' with rootPath '\(rootPath)'.")
            let response = try await runWithEmbeddedBackendRecovery {
                try await api.createCompany(
                    name: name,
                    rootPath: rootPath,
                    defaultBaseBranch: pendingWorkspaceBaseBranch,
                    dailyBudgetCents: dailyBudgetCents,
                    monthlyBudgetCents: monthlyBudgetCents
                )
            }
            let company = response.company
            newCompanyName = ""
            newCompanyRootPath = ""
            newCompanyDailyBudgetInput = ""
            newCompanyMonthlyBudgetInput = ""
            selectedCompanyID = company.id
            companyGitHubStatusMessage = githubRequirementMessage(for: response.githubPublishStatus)
            selectedCompanyGitHubStatus = response.githubPublishStatus
            syncGitHubOriginInput(with: response.githubPublishStatus)
            AppLogger.info("Created company '\(company.name)' (\(company.id)).")
            await performNonCriticalCompanyRefresh(selecting: company)
        } catch is CancellationError {
            companyGitHubStatusMessage = nil
            actionErrorMessage = nil
            errorMessage = nil
        } catch {
            companyGitHubStatusMessage = nil
            actionErrorMessage = error.localizedDescription
            AppLogger.error("Create company failed for '\(name)': \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private func githubRequirementMessage(for status: GitHubPublishStatusPayload) -> String? {
        guard status.policy == "REQUIRE_GITHUB_PR" else { return nil }
        var requirements: [String] = []
        if !status.ghInstalled {
            requirements.append(language("install the gh CLI", "gh CLI를 설치"))
        }
        if !status.ghAuthenticated {
            requirements.append(language("sign in with GitHub", "GitHub 로그인"))
        }
        if !status.originConfigured {
            requirements.append(language("connect an existing origin remote", "기존 origin remote 연결"))
        }
        guard !requirements.isEmpty else { return nil }
        let prefix = language(
            "GitHub PR mode is enabled for this company. Connect GitHub before starting code work:",
            "이 회사는 GitHub PR 모드입니다. 코드 작업을 시작하기 전에 GitHub를 연결하세요:"
        )
        let detail = status.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = requirements.joined(separator: ", ")
        if let detail, !detail.isEmpty {
            return "\(prefix) \(body). \(detail)"
        }
        return "\(prefix) \(body)."
    }

    func refreshSelectedCompanyGitHubStatus() async {
        guard let company = selectedCompany else {
            selectedCompanyGitHubStatus = nil
            companyGitHubStatusMessage = language("Select a company before checking GitHub readiness.", "GitHub 준비 상태를 확인하려면 회사를 먼저 선택하세요.")
            return
        }
        do {
            let companyId = company.id
            let status = try await api.companyGitHubStatus(companyId: companyId)
            guard isCurrentCompany(companyId) else { return }
            selectedCompanyGitHubStatus = status
            syncGitHubOriginInput(with: status)
            companyGitHubStatusMessage = githubRequirementMessage(for: status) ?? status.message
            errorMessage = nil
        } catch {
            if selectedCompany?.id == company.id {
                companyGitHubStatusMessage = error.localizedDescription
                errorMessage = error.localizedDescription
            }
        }
    }

    func openGitHubLoginTerminal() {
        guard selectedCompany != nil else {
            companyGitHubStatusMessage = language("Select a company before signing in to GitHub.", "GitHub에 로그인하려면 회사를 먼저 선택하세요.")
            return
        }
        let path = activeGitHubPublishStatus.repositoryPath ?? selectedCompany?.rootPath ?? FileManager.default.homeDirectoryForCurrentUser.path
        let command = "cd \(shellQuoted(path)) && gh auth login"
        let script = """
        tell application "Terminal"
            activate
            do script \(appleScriptStringLiteral(command))
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else {
            companyGitHubStatusMessage = language("Could not open Terminal for GitHub login.", "GitHub 로그인을 위한 터미널을 열 수 없습니다.")
            return
        }
        var scriptError: NSDictionary?
        appleScript.executeAndReturnError(&scriptError)
        if let scriptError {
            companyGitHubStatusMessage = scriptError.description
        } else {
            companyGitHubStatusMessage = language("Opened Terminal for GitHub login. Finish the prompt, then check GitHub again.", "GitHub 로그인을 위해 터미널을 열었습니다. 안내를 마친 뒤 GitHub를 다시 확인하세요.")
        }
    }

    func saveSelectedCompanyGitHubOrigin() async {
        guard let company = selectedCompany else {
            companyGitHubStatusMessage = language("Select a company before connecting GitHub.", "GitHub를 연결하려면 회사를 먼저 선택하세요.")
            return
        }
        let remoteURL = companyGitHubOriginInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remoteURL.isEmpty else {
            companyGitHubStatusMessage = language("Paste an existing GitHub repository URL first.", "먼저 기존 GitHub 저장소 URL을 붙여 넣으세요.")
            return
        }
        do {
            let status = try await api.configureCompanyGitHubOrigin(companyId: company.id, remoteURL: remoteURL)
            selectedCompanyGitHubStatus = status
            syncGitHubOriginInput(with: status)
            companyGitHubStatusMessage = status.originConfigured
                ? language("GitHub origin is connected. Check GitHub again before starting code work.", "GitHub origin이 연결되었습니다. 코드 작업을 시작하기 전에 GitHub를 다시 확인하세요.")
                : status.message
            errorMessage = nil
            await refreshDashboard()
        } catch {
            companyGitHubStatusMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func syncGitHubOriginInput(with status: GitHubPublishStatusPayload) {
        if let originURL = status.originUrl, !originURL.isEmpty {
            companyGitHubOriginInput = originURL
        } else if companyGitHubOriginInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            companyGitHubOriginInput = ""
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptStringLiteral(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    func deleteSelectedCompany() async {
        guard let company = selectedCompany else { return }
        do {
            _ = try await api.deleteCompany(companyId: company.id)
            if editingCompanyAgentID != nil {
                resetCompanyAgentComposer()
            }
            if editingGoalID != nil {
                resetGoalComposer()
            }
            selectedCompanyID = nil
            selectedGoalID = nil
            selectedIssueID = nil
            selectedTaskID = nil
            selectedWorkspaceID = nil
            await refreshDashboard()
            if let company = companies.first {
                await selectCompany(company)
            } else if let repository = repositories.first {
                await selectRepository(repository)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createCompanyAgent() async {
        let targetCompanyID = editingCompanyAgentCompanyID ?? selectedCompanyID
        guard let targetCompanyID,
              companies.contains(where: { $0.id == targetCompanyID }) else { return }
        let title = newCompanyAgentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cli = resolvedNewCompanyAgentCli.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = trimmedOptional(newCompanyAgentModel)
        let role = newCompanyAgentRole.trimmingCharacters(in: .whitespacesAndNewlines)
        let specialties = splitAgentMeta(newCompanyAgentSpecialties)
        let collaborationNotes = trimmedOptional(newCompanyAgentCollaborationNotes)
        let memoryNotes = trimmedOptional(newCompanyAgentMemoryNotes)
        let preferredCollaboratorIds = Array(newCompanyAgentPreferredCollaboratorIDs).sorted()
        let mentorAgentId = newCompanyAgentMentorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !cli.isEmpty, !role.isEmpty else { return }
        do {
            actionErrorMessage = nil
            errorMessage = nil
            let savedAgent: CompanyAgentDefinitionRecord
            if let agentId = editingCompanyAgentID,
               companyAgentDefinitions.contains(where: { $0.id == agentId && $0.companyId == targetCompanyID }) {
                savedAgent = try await runWithEmbeddedBackendRecovery {
                    try await api.updateCompanyAgent(
                        companyId: targetCompanyID,
                        agentId: agentId,
                        title: title,
                        agentCli: cli,
                        model: model,
                        roleSummary: role,
                        specialties: specialties,
                        collaborationInstructions: collaborationNotes,
                        preferredCollaboratorIds: preferredCollaboratorIds,
                        mentorAgentId: mentorAgentId,
                        memoryNotes: memoryNotes,
                        enabled: newCompanyAgentEnabled
                    )
                }
            } else {
                savedAgent = try await runWithEmbeddedBackendRecovery {
                    try await api.createCompanyAgent(
                        companyId: targetCompanyID,
                        title: title,
                        agentCli: cli,
                        model: model,
                        roleSummary: role,
                        specialties: specialties,
                        collaborationInstructions: collaborationNotes,
                        preferredCollaboratorIds: preferredCollaboratorIds,
                        mentorAgentId: mentorAgentId.isEmpty ? nil : mentorAgentId,
                        memoryNotes: memoryNotes,
                        enabled: newCompanyAgentEnabled
                    )
                }
            }
            try await syncCompanyAgentSkills(companyId: targetCompanyID, agentId: savedAgent.id)
            resetCompanyAgentComposer()
            await refreshDashboard()
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func syncCompanyAgentSkills(companyId: String, agentId: String) async throws {
        let skillIDs = Array(newCompanyAgentSkillIDs).sorted()
        let currentSetting = skillRunSetting(companyId: companyId, agentId: agentId)
        let nextSetting = currentSetting.withSkillAllowlist(skillIDs)
        var capabilitySettings: [String: AgentCapabilitySettingRecord] = ["SKILL_RUN": nextSetting]
        if !isMarketingOperatorSelected {
            capabilitySettings.merge(disabledMarketingCapabilitySettings()) { _, new in new }
        }
        let finalCapabilitySettings = capabilitySettings
        _ = try await runWithEmbeddedBackendRecovery {
            try await api.updateAgentCapabilities(
                companyId: companyId,
                agentId: agentId,
                settings: finalCapabilitySettings
            )
        }
        if isMarketingOperatorSelected {
            try await syncMarketingDelegationPolicy(companyId: companyId, agentId: agentId)
        }
    }

    private func syncMarketingDelegationPolicy(companyId: String, agentId: String) async throws {
        let domains = splitAgentMeta(marketingPolicyAllowedDomains)
        let channels = splitAgentMeta(marketingPolicyChannels)
        guard !domains.isEmpty, !channels.isEmpty else {
            throw NSError(
                domain: "CotorDesktopApp.MarketingPolicy",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: language("Marketing policy requires at least one domain and channel.", "마케팅 정책에는 도메인과 채널이 하나 이상 필요합니다.")]
            )
        }
        let existingPolicy = marketingDelegationPolicies.first { $0.companyId == companyId && $0.agentId == agentId }
        let channelAccounts = channels.map { channel in
            MarketingChannelAccountRecord(
                channel: channel,
                accountRef: channel,
                allowedDomains: domains,
                secretRefs: splitAgentMeta(marketingPolicySecretRefs)
            )
        }
        let policy = try await runWithEmbeddedBackendRecovery {
            try await api.upsertMarketingPolicy(
                UpsertMarketingDelegationPolicyPayload(
                    id: existingPolicy?.id,
                    companyId: companyId,
                    agentId: agentId,
                    name: "Owned+Social",
                    allowedDomains: domains,
                    channelAccounts: channelAccounts,
                    dailyPostLimit: Int(marketingPolicyDailyPostLimit.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1,
                    forbiddenTerms: splitAgentMeta(marketingPolicyForbiddenTerms),
                    brandTone: trimmedOptional(marketingPolicyBrandTone),
                    prohibitedActions: splitAgentMeta(marketingPolicyProhibitedActions),
                    secretRefs: splitAgentMeta(marketingPolicySecretRefs),
                    browserSessionRef: trimmedOptional(marketingPolicyBrowserSessionRef),
                    maxRuntimeSeconds: Int(marketingPolicyMaxRuntimeSeconds.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 900
                )
            )
        }
        marketingDelegationPolicies = marketingDelegationPolicies.filter { $0.id != policy.id } + [policy]
    }

    private func disabledMarketingCapabilitySettings() -> [String: AgentCapabilitySettingRecord] {
        let disabled = AgentCapabilitySettingRecord(enabled: false, mode: "DISABLED")
        return [
            "BROWSER_READ": disabled,
            "BROWSER_INTERACT": disabled,
            "BROWSER_EXTERNAL_DOMAIN": disabled,
            "BROWSER_LOGIN_FLOW": disabled,
            "WEB_PUBLISH": disabled,
            "SOCIAL_POST_CREATE": disabled,
            "MARKETING_ANALYTICS_READ": disabled,
        ]
    }

    func batchUpdateSelectedCompanyAgents(
        agentCli: String?,
        model: String?,
        specialties: [String]?,
        enabled: Bool?
    ) async -> Bool {
        let selectedAgents = selectedBatchEditableAgents
        guard !selectedAgents.isEmpty else { return false }
        let companyIds = Set(selectedAgents.map(\.companyId))
        guard companyIds.count == 1, let companyId = companyIds.first else {
            actionErrorMessage = language(
                "Batch edit requires agents from a single company.",
                "일괄 수정은 같은 회사의 에이전트만 선택해야 합니다."
            )
            return false
        }

        do {
            actionErrorMessage = nil
            errorMessage = nil
            _ = try await runWithEmbeddedBackendRecovery {
                try await api.batchUpdateCompanyAgents(
                    companyId: companyId,
                    agentIds: selectedAgents.map(\.id),
                    agentCli: agentCli,
                    model: model,
                    specialties: specialties,
                    enabled: enabled
                )
            }
            await refreshDashboard()
            clearCompanyAgentSelection()
            clearOrgProfileSelection()
            showingOrgProfileBatchEdit = false
            return true
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return false
        }
    }

    func beginEditingCompanyAgent(_ agent: CompanyAgentDefinitionRecord) {
        editingCompanyAgentID = agent.id
        editingCompanyAgentCompanyID = agent.companyId
        selectedCompanyID = agent.companyId
        newCompanyAgentTitle = agent.title
        newCompanyAgentCli = agent.agentCli
        newCompanyAgentModel = agent.model ?? ""
        newCompanyAgentRole = agent.roleSummary
        newCompanyAgentSpecialties = agent.specialties.joined(separator: ", ")
        newCompanyAgentCollaborationNotes = agent.collaborationInstructions ?? ""
        newCompanyAgentMemoryNotes = agent.memoryNotes ?? ""
        newCompanyAgentPreferredCollaboratorIDs = Set(agent.preferredCollaboratorIds)
        newCompanyAgentMentorID = agent.mentorAgentId ?? ""
        newCompanyAgentSkillIDs = skillIDs(for: agent)
        syncMarketingPolicyForm(forAgentId: agent.id)
        newCompanyAgentEnabled = agent.enabled
    }

    func cancelEditingCompanyAgent() {
        resetCompanyAgentComposer()
    }

    func runCompanyOperatorCommand(
        message: String,
        automationMode: String? = nil,
        confirmFullAuto: Bool = false,
        confirmStaffing: Bool = false
    ) async -> OperatorCommandResponsePayload? {
        guard let company = selectedCompany else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            actionErrorMessage = nil
            errorMessage = nil
            let response = try await runWithEmbeddedBackendRecovery {
                try await api.runOperatorCommand(
                    companyId: company.id,
                    message: trimmed,
                    automationMode: automationMode,
                    confirmFullAuto: confirmFullAuto,
                    confirmStaffing: confirmStaffing
                )
            }
            operatorCommandResponses.insert(response, at: 0)
            await refreshDashboard(restartEventStream: false)
            await loadSelectedCompanyMemorySnapshot()
            return response
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func runCompanyOperatorChat(
        message: String,
        automationMode: String? = nil,
        confirmFullAuto: Bool = false,
        confirmStaffing: Bool = false
    ) async -> OperatorChatResponsePayload? {
        guard let company = selectedCompany else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            actionErrorMessage = nil
            errorMessage = nil
            let response = try await runWithEmbeddedBackendRecovery {
                try await api.runOperatorChat(
                    companyId: company.id,
                    message: trimmed,
                    automationMode: automationMode,
                    confirmFullAuto: confirmFullAuto,
                    confirmStaffing: confirmStaffing
                )
            }
            await refreshDashboard(restartEventStream: false)
            await loadSelectedCompanyMemorySnapshot()
            return response
        } catch {
            actionErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func setSelectedCompanyOperatorAutomationMode(_ mode: String, confirmFullAuto: Bool = false) async {
        guard let company = selectedCompany else { return }
        let response = await runCompanyOperatorCommand(
            message: "Set Company Operator automation mode to \(mode).",
            automationMode: mode,
            confirmFullAuto: confirmFullAuto
        )
        if response == nil {
            selectedCompanyID = company.id
        }
    }

    func operatorSuggestedCommands() -> [OperatorChatCommand] {
        [
            OperatorChatCommand(title: language("Check status", "상태 확인"), prompt: language("Check whether the agents are running well.", "에이전트들 잘 돌아가고 있는지 확인해줘")),
            OperatorChatCommand(title: language("Map repo", "리포 맵"), prompt: language("Run graphify and summarize the repository structure.", "graphify 실행해서 리포지토리 구조 알려줘")),
            OperatorChatCommand(title: language("Browser check", "브라우저 확인"), prompt: language("Open the app in a browser and collect smoke-test evidence.", "브라우저로 앱을 확인하고 증거 남겨줘")),
            OperatorChatCommand(title: language("Marketing report", "마케팅 성과"), prompt: language("Summarize marketing performance and next actions.", "마케팅 성과랑 다음 액션 요약해줘")),
            OperatorChatCommand(title: language("Staff team", "팀 보강"), prompt: language("Ask HR Manager to hire missing agents and assign mentors.", "HR 매니저가 필요한 사람을 고용하고 사수를 지정하게 해줘")),
            OperatorChatCommand(title: language("Assign mentors", "사수 지정"), prompt: language("Ask HR Manager to assign mentors for agents that need one.", "사수가 없는 에이전트들에게 사수를 지정해줘")),
            OperatorChatCommand(title: language("Start company", "회사 시작"), prompt: language("Start this company.", "회사 시작해줘")),
            OperatorChatCommand(title: language("Stop company", "회사 중지"), prompt: language("Stop this company.", "회사 중지해줘")),
            OperatorChatCommand(title: language("Use DeepSeek", "DeepSeek로 변경"), prompt: language("Change every agent to opencode deepseek.", "모든 에이전트 opencode deepseek 모델로 바꿔줘")),
            OperatorChatCommand(title: language("Retry blocked work", "막힌 일 재시도"), prompt: language("Retry blocked issues.", "막힌 이슈 다시 처리해줘")),
            OperatorChatCommand(title: language("Check GitHub", "GitHub 확인"), prompt: language("Check GitHub readiness.", "GitHub 확인해줘")),
            OperatorChatCommand(title: language("Resync Linear", "Linear 재동기화"), prompt: language("Resync Linear.", "Linear 재동기화해줘"))
        ]
    }

    @discardableResult
    func runSkill(
        skillName: String,
        agentId: String,
        input: String? = nil,
        parameters: [String: String] = [:]
    ) async -> SkillRunResultRecord? {
        guard let companyId = selectedCompanyID else { return nil }
        let key = "\(agentId):\(skillName)"
        let effectiveParameters = skillRunParameters(
            skillName: skillName,
            input: input,
            parameters: parameters
        )
        runningSkillRunKeys.insert(key)
        defer { runningSkillRunKeys.remove(key) }

        do {
            let result = try await api.runSkill(
                name: skillName,
                companyId: companyId,
                agentId: agentId,
                input: input,
                parameters: effectiveParameters
            )
            recentSkillRunResults = ([result] + recentSkillRunResults).prefix(20).map { $0 }
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let record = SkillRunRecord(
                id: result.runId ?? "\(skillName)-\(now)",
                companyId: companyId,
                agentId: agentId,
                skill: result.skill,
                status: result.status,
                actions: result.actions,
                evidence: result.evidence,
                summary: result.summary,
                output: result.output,
                error: result.error,
                createdAt: now,
                updatedAt: now,
                completedAt: result.status == "RUNNING" ? nil : now
            )
            skillRuns = ([record] + skillRuns.filter { $0.id != record.id })
                .sorted { $0.updatedAt > $1.updatedAt }
            await refreshCompanyDashboard(restartEventStream: false)
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func skillRunParameters(
        skillName: String,
        input: String?,
        parameters: [String: String]
    ) -> [String: String] {
        guard skillName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "browser-smoke",
              parameters["url"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              firstWebURL(from: input) == nil else {
            return parameters
        }
        var next = parameters
        next["url"] = api.baseURL.appendingPathComponent("health").absoluteString
        return next
    }

    private func firstWebURL(from text: String?) -> String? {
        guard let text else { return nil }
        return text
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                String(token).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)]}\"'"))
            }
            .first { token in
                token.hasPrefix("http://") || token.hasPrefix("https://")
            }
    }

    func submitOperatorChatCommand(_ command: OperatorChatCommand) async {
        switch command.kind {
        case .sendPrompt:
            await submitOperatorChatMessage(command.prompt)
        case .chooseCompanyFolder:
            openCompanyRootPicker()
            let text = newCompanyRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? language("No folder was selected.", "선택된 폴더가 없습니다.")
                : language("Folder selected. Tell me the company name to create it.", "폴더를 선택했습니다. 만들 회사 이름을 알려주세요.")
            appendOperatorChatMessage(role: .assistant, text: text)
        case .confirmFullAuto:
            appendOperatorChatMessage(role: .user, text: command.title)
            let reply = await runOperatorCommandAsChatReply(
                message: command.prompt,
                automationMode: "FULL_AUTO",
                confirmFullAuto: true
            )
            appendOperatorChatMessage(role: .assistant, text: reply)
        case .confirmHrStaffing:
            appendOperatorChatMessage(role: .user, text: command.title)
            let reply = await runOperatorCommandAsChatReply(
                message: command.prompt,
                confirmStaffing: true
            )
            appendOperatorChatMessage(role: .assistant, text: reply)
        case .confirmCompanyDelete:
            appendOperatorChatMessage(role: .user, text: command.title)
            let name = selectedCompany?.name ?? language("the selected company", "선택한 회사")
            await deleteSelectedCompany()
            appendOperatorChatMessage(
                role: .assistant,
                text: errorMessage.map { sanitizeOperatorUserText($0, language: language) }
                    ?? language("\(name) was deleted.", "\(name)을 삭제했습니다.")
            )
        case .confirmMerge:
            appendOperatorChatMessage(role: .user, text: command.title)
            if let proposal = chatMergeProposal(from: command.prompt),
               await applyChatMergeProposal(proposal) != nil {
                appendOperatorChatMessage(
                    role: .assistant,
                    text: language("Merged the approved pull request.", "승인된 PR을 머지했습니다.")
                )
            } else {
                appendOperatorChatMessage(role: .assistant, text: operatorFailureFallback())
            }
        case .cancelConfirmation:
            appendOperatorChatMessage(role: .user, text: command.title)
            appendOperatorChatMessage(role: .assistant, text: language("Cancelled.", "취소했습니다."))
        }
    }

    func submitOperatorChatMessage(_ message: String) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendOperatorChatMessage(role: .user, text: trimmed)
        operatorCommandDraft = ""
        isSendingOperatorChatMessage = true
        defer { isSendingOperatorChatMessage = false }

        if let pending = operatorPendingPrompt {
            operatorPendingPrompt = nil
            let resumed = "\(pending.resumePrompt) \(trimmed)"
            let reply = await executeOperatorChatMessage(resumed, normalized: resumed.lowercased())
            appendOperatorChatMessage(role: .assistant, text: reply)
            return
        }

        let normalized = trimmed.lowercased()
        if let blockedMessage = blockedOperatorChatSafetyMessage(for: normalized) {
            appendOperatorChatMessage(role: .assistant, text: blockedMessage)
            return
        }
        if looksLikeFullAutoChatRequest(normalized) {
            appendOperatorChatMessage(
                role: .assistant,
                text: language("Full auto can run routine actions without asking. Confirm once to turn it on.", "완전 자동은 일반 작업을 묻지 않고 실행합니다. 켜려면 한 번만 확인하세요."),
                commands: [
                    OperatorChatCommand(
                        title: language("Turn on full auto", "완전 자동 켜기"),
                        prompt: trimmed,
                        kind: .confirmFullAuto
                    ),
                    OperatorChatCommand(
                        title: language("Cancel", "취소"),
                        prompt: "",
                        kind: .cancelConfirmation
                    )
                ]
            )
            return
        }
        if looksLikeCompanyDeleteChatRequest(normalized) {
            let name = selectedCompany?.name ?? language("the selected company", "선택한 회사")
            appendOperatorChatMessage(
                role: .assistant,
                text: language("Delete \(name)? This cannot be undone.", "\(name)을 삭제할까요? 되돌릴 수 없습니다."),
                commands: [
                    OperatorChatCommand(
                        title: language("Delete company", "회사 삭제"),
                        prompt: trimmed,
                        kind: .confirmCompanyDelete,
                        destructive: true
                    ),
                    OperatorChatCommand(
                        title: language("Cancel", "취소"),
                        prompt: "",
                        kind: .cancelConfirmation
                    )
                ]
            )
            return
        }
        let reply = await executeOperatorChatMessage(trimmed, normalized: normalized)
        if !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendOperatorChatMessage(role: .assistant, text: reply)
        }
    }

    private func appendOperatorChatMessage(
        role: OperatorChatRole,
        text: String,
        commands: [OperatorChatCommand] = []
    ) {
        operatorChatMessages.append(
            OperatorChatMessage(
                role: role,
                text: sanitizeOperatorUserText(text, language: language),
                commands: commands
            )
        )
    }

    private func looksLikeStatusChatRequest(_ text: String) -> Bool {
        containsAny(text, ["상태 확인", "잘 돌아", "잘돌", "에이전트 잘", "health check", "status check", "점검해", "상태 보고"])
    }

    private func executeOperatorChatMessage(_ message: String, normalized: String) async -> String {
        if looksLikeCompanyCreateChatRequest(normalized) {
            return await createCompanyFromOperatorChat(message)
        }
        guard selectedCompany != nil else {
            return language("Select or create a company first.", "먼저 회사를 선택하거나 만들어주세요.")
        }

        // Status requests bypass the LLM planner entirely and return a
        // deterministic reply from the operator-command status path.
        if looksLikeStatusChatRequest(normalized) {
            return await runOperatorCommandAsChatReply(message: message)
        }

        if selectedOperatorAutomationMode.uppercased() == "ASK_ME",
           looksLikeHrStaffingChatRequest(normalized) {
            appendOperatorChatMessage(
                role: .assistant,
                text: language(
                    "HR Manager can hire missing agents or assign mentors. Confirm to run this staffing change.",
                    "HR 매니저가 필요한 에이전트를 고용하거나 사수를 지정할 수 있습니다. 실행하려면 확인하세요."
                ),
                commands: [
                    OperatorChatCommand(
                        title: language("Run HR staffing", "HR 보강 실행"),
                        prompt: message,
                        kind: .confirmHrStaffing
                    ),
                    OperatorChatCommand(
                        title: language("Cancel", "취소"),
                        prompt: "",
                        kind: .cancelConfirmation
                    )
                ]
            )
            return ""
        }

        if looksLikeRuntimeStartChatRequest(normalized) {
            if let snapshot = await applyChatRuntimeProposal(ChatRuntimeProposal(action: .start, summary: message)) {
                return snapshot.status.uppercased() == "RUNNING"
                    ? language("Started the company.", "회사를 시작했습니다.")
                    : language("Start request was sent.", "시작 요청을 보냈습니다.")
            }
            return operatorFailureFallback()
        }
        if looksLikeRuntimeStopChatRequest(normalized) {
            if await applyChatRuntimeProposal(ChatRuntimeProposal(action: .stop, summary: message)) != nil {
                return language("Stopped the company.", "회사를 중지했습니다.")
            }
            return operatorFailureFallback()
        }
        if looksLikeBackendChatRequest(normalized),
           let proposal = chatBackendProposal(from: message),
           await applyChatBackendProposal(proposal) != nil {
            switch proposal.action {
            case .start:
                return language("Started the backend.", "백엔드를 시작했습니다.")
            case .stop:
                return language("Stopped the backend.", "백엔드를 중지했습니다.")
            case .restart:
                return language("Restarted the backend.", "백엔드를 재시작했습니다.")
            }
        }
        if looksLikeGoalCreationChatRequest(normalized) {
            guard selectedCompany != nil else { return language("Select a company first.", "먼저 회사를 선택하세요.") }
            guard let proposal = chatGoalProposal(from: cleanedCreationPrompt(message)) else {
                return askOperatorChat(
                    question: language("What goal should I create?", "어떤 목표를 만들까요?"),
                    resumePrompt: language("Create goal:", "목표 생성:")
                )
            }
            if let goal = await applyChatGoalProposal(proposal) {
                return language("Created goal: \(goal.title)", "목표를 만들었습니다: \(goal.title)")
            }
            return operatorFailureFallback()
        }
        if looksLikeIssueCreationChatRequest(normalized) {
            guard selectedGoalID != nil || selectedIssue?.goalId != nil else {
                return language("Select a goal first, then tell me the issue.", "먼저 목표를 선택한 뒤 이슈를 알려주세요.")
            }
            guard let proposal = chatIssueProposal(from: cleanedCreationPrompt(message)) else {
                return askOperatorChat(
                    question: language("What issue should I create?", "어떤 이슈를 만들까요?"),
                    resumePrompt: language("Create issue:", "이슈 생성:")
                )
            }
            if let issue = await applyChatIssueProposal(proposal) {
                return language("Created issue: \(issue.title)", "이슈를 만들었습니다: \(issue.title)")
            }
            return operatorFailureFallback()
        }
        if looksLikeGoalDecompositionChatRequest(normalized),
           let proposal = chatGoalDecompositionProposal(from: message),
           let issues = await applyChatGoalDecompositionProposal(proposal) {
            return language("Created \(issues.count) issue(s) from the selected goal.", "선택한 목표에서 이슈 \(issues.count)개를 만들었습니다.")
        }
        if looksLikeGoalAutonomyChatRequest(normalized),
           let proposal = chatGoalAutonomyProposal(from: message),
           let goal = await applyChatGoalAutonomyProposal(proposal) {
            return goal.autonomyEnabled
                ? language("Turned on goal automation.", "목표 자동화를 켰습니다.")
                : language("Turned off goal automation.", "목표 자동화를 껐습니다.")
        }
        if looksLikeRepositoryMapChatRequest(normalized) {
            return await runSkillChatReply(
                skillIDs: ["graphify", "repository-mapper"],
                input: message,
                unavailable: language(
                    "No runnable repository mapping skill is available for the selected company.",
                    "선택한 회사에서 바로 실행 가능한 리포지토리 맵 스킬이 없습니다."
                )
            )
        }
        if looksLikeIssueRunChatRequest(normalized),
           await applyChatExecutionProposal(ChatExecutionProposal(summary: message)) != nil {
            return language("Started the selected issue.", "선택한 이슈를 실행했습니다.")
        }
        if looksLikeIssueDelegationChatRequest(normalized),
           await applyChatDelegationProposal(ChatDelegationProposal(summary: message)) != nil {
            return language("Delegated the selected issue.", "선택한 이슈를 위임했습니다.")
        }
        if looksLikeReviewChatRequest(normalized),
           let proposal = chatReviewProposal(from: message, kind: normalized.contains("qa") ? "qa" : "ceo"),
           await applyChatReviewProposal(proposal) != nil {
            return language("Saved the review decision.", "리뷰 판정을 저장했습니다.")
        }
        if looksLikeMergeChatRequest(normalized) {
            appendOperatorChatMessage(
                role: .assistant,
                text: language("Merge the approved pull request?", "승인된 PR을 머지할까요?"),
                commands: [
                    OperatorChatCommand(title: language("Merge", "머지"), prompt: message, kind: .confirmMerge),
                    OperatorChatCommand(title: language("Cancel", "취소"), prompt: "", kind: .cancelConfirmation)
                ]
            )
            return language("Waiting for your confirmation.", "확인을 기다리고 있습니다.")
        }
        if looksLikeGitHubLoginChatRequest(normalized) {
            openGitHubLoginTerminal()
            return companyGitHubStatusMessage ?? language("Opened GitHub login in Terminal.", "터미널에서 GitHub 로그인을 열었습니다.")
        }
        if looksLikeGitHubOriginChatRequest(normalized) {
            if let url = extractRemoteURL(from: message) {
                companyGitHubOriginInput = url
                await saveSelectedCompanyGitHubOrigin()
                return companyGitHubStatusMessage ?? language("GitHub repository is connected.", "GitHub 저장소를 연결했습니다.")
            }
            return askOperatorChat(
                question: language("Send the GitHub repository URL.", "GitHub 저장소 URL을 보내주세요."),
                resumePrompt: language("Connect GitHub origin:", "GitHub 저장소 연결:")
            )
        }
        if looksLikeBudgetChatRequest(normalized) {
            await saveSelectedCompanyBudget()
            return errorMessage.map { sanitizeOperatorUserText($0, language: language) }
                ?? language("Saved the budget settings.", "예산 설정을 저장했습니다.")
        }
        if looksLikeLinearSettingsChatRequest(normalized) {
            await saveSelectedCompanyLinearSettings()
            return companyLinearStatusMessage ?? language("Saved Linear settings.", "Linear 설정을 저장했습니다.")
        }

        return await runOperatorChatAsChatReply(message: message)
    }

    private func runOperatorCommandAsChatReply(
        message: String,
        automationMode: String? = nil,
        confirmFullAuto: Bool = false,
        confirmStaffing: Bool = false
    ) async -> String {
        guard let response = await runCompanyOperatorCommand(
            message: message,
            automationMode: automationMode,
            confirmFullAuto: confirmFullAuto,
            confirmStaffing: confirmStaffing
        ) else {
            return operatorFailureFallback()
        }
        return operatorAssistantText(for: response)
    }

    private func runOperatorChatAsChatReply(message: String) async -> String {
        guard let response = await runCompanyOperatorChat(message: message) else {
            if let commandResponse = await runCompanyOperatorCommand(message: message) {
                return operatorAssistantText(for: commandResponse)
            }
            return operatorFailureFallback()
        }
        return operatorAssistantText(for: response)
    }

    private func runSkillChatReply(
        skillIDs: Set<String>,
        input: String,
        unavailable: String
    ) async -> String {
        let normalizedSkillIDs = Set(skillIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        guard let card = agentSkillCards.first(where: { card in
            card.companyId == selectedCompanyID &&
                card.enabled &&
                card.runnableSkills.contains { normalizedSkillIDs.contains($0.id.lowercased()) }
        }),
            let skill = card.runnableSkills.first(where: { normalizedSkillIDs.contains($0.id.lowercased()) }) else {
            return unavailable
        }

        guard let result = await runSkill(skillName: skill.id, agentId: card.id, input: input) else {
            return operatorFailureFallback()
        }
        return operatorSkillRunText(for: result)
    }

    private func operatorSkillRunText(for result: SkillRunResultRecord) -> String {
        let detail = sanitizeOperatorUserText(result.summary ?? result.error ?? result.output ?? "", language: language)
        if !detail.isEmpty {
            return detail
        }
        switch result.status.uppercased() {
        case "COMPLETED":
            return language("Skill run completed.", "스킬 실행이 완료되었습니다.")
        case "RUNNING":
            return language("Skill run started.", "스킬 실행을 시작했습니다.")
        case "DENIED", "APPROVAL_REQUIRED":
            return language("Skill run needs delegated permission.", "스킬 실행 권한 위임이 필요합니다.")
        default:
            return language("Skill run recorded.", "스킬 실행을 기록했습니다.")
        }
    }

    private func operatorAssistantText(for response: OperatorCommandResponsePayload) -> String {
        let blocked = response.blockedActions.map { operatorActionText($0) }
        if !blocked.isEmpty {
            return blocked.joined(separator: "\n")
        }
        let pending = response.pendingApprovals.map { operatorActionText($0) }
        if !pending.isEmpty {
            return language("Sent this to internal approval.", "내부 승인으로 보냈습니다.") + "\n" + pending.joined(separator: "\n")
        }
        let actions = response.actions.map { operatorActionText($0) }
        if !actions.isEmpty {
            return actions.joined(separator: "\n")
        }
        return sanitizeOperatorUserText(response.message, language: language)
    }

    private func operatorAssistantText(for response: OperatorChatResponsePayload) -> String {
        let message = sanitizeOperatorUserText(response.message, language: language)
        if !message.isEmpty {
            return message
        }
        let blocked = response.blockedActions.map { operatorActionText($0) }
        if !blocked.isEmpty {
            return blocked.joined(separator: "\n")
        }
        let pending = response.pendingApprovals.map { operatorActionText($0) }
        if !pending.isEmpty {
            return language("Sent this to internal approval.", "내부 승인으로 보냈습니다.") + "\n" + pending.joined(separator: "\n")
        }
        let actions = response.actions.map { operatorActionText($0) }
        if !actions.isEmpty {
            return actions.joined(separator: "\n")
        }
        return operatorFailureFallback()
    }

    private func operatorActionText(_ action: OperatorCommandActionPayload) -> String {
        let status = operatorActionStatusDisplayName(action.status, language: language)
        let detail = sanitizeOperatorUserText(action.detail, language: language)
        return detail.isEmpty ? "\(action.title) · \(status)" : "\(action.title) · \(status)\n\(detail)"
    }

    private func askOperatorChat(question: String, resumePrompt: String) -> String {
        operatorPendingPrompt = OperatorChatPendingPrompt(question: question, resumePrompt: resumePrompt)
        return question
    }

    private func operatorFailureFallback() -> String {
        actionErrorMessage ?? errorMessage ?? language("I could not complete that from chat.", "채팅에서 처리하지 못했습니다.")
    }

    private func createCompanyFromOperatorChat(_ message: String) async -> String {
        let trimmedName = extractedCompanyName(from: message) ?? newCompanyName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            newCompanyName = trimmedName
        }
        if newCompanyRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            openCompanyRootPicker()
        }
        if newCompanyRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return language("Choose a folder for the company first.", "먼저 회사 폴더를 선택해주세요.")
        }
        if newCompanyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return askOperatorChat(
                question: language("What should I name the company?", "회사 이름을 무엇으로 할까요?"),
                resumePrompt: language("Create company named", "회사 생성")
            )
        }
        await createCompany()
        return selectedCompany.map { language("Created company: \($0.name)", "회사를 만들었습니다: \($0.name)") }
            ?? operatorFailureFallback()
    }

    private func cleanedCreationPrompt(_ message: String) -> String {
        var cleaned = strippedLeadingSlashCommand(
            from: strippedLeadingListPrefix(from: message),
            commands: ["goal", "objective", "issue", "task", "ticket", "목표", "이슈", "태스크", "작업"]
        )
        cleaned = cleaned
            .replacingOccurrences(
                of: #"(?i)^\s*(create|make|add)\s+(a\s+|an\s+)?(goal|objective|issue|task|ticket)\s*[:：\-]?\s*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"^\s*(목표|이슈|태스크|작업)\s*(생성|만들기|만들어|추가)?\s*[:：\-]?\s*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s*(만들어|만들어줘|만들어 줘|생성|생성해줘|생성해 줘|추가|추가해줘|추가해 줘|해줘|해 줘|해주세요)\s*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }

    private func strippedLeadingListPrefix(from message: String) -> String {
        message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^([\-*•]\s+|\d+[.)]\s+)"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func strippedLeadingSlashCommand(from message: String, commands: [String]) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return trimmed }
        let escapedCommands = commands.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = #"(?i)^\s*/("# + escapedCommands + #")(?=$|[:：\-\s])\s*[:：\-]?\s*"#
        return trimmed
            .replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractedCompanyName(from message: String) -> String? {
        let cleaned = message
            .replacingOccurrences(of: #"(?i)\b(create|make|add|company|named)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(회사|만들어|생성|추가|이름|으로|해줘)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(80))
    }

    private func extractRemoteURL(from message: String) -> String? {
        message
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .first { token in
                token.hasPrefix("https://github.com/")
                    || token.hasPrefix("git@github.com:")
                    || token.hasSuffix(".git")
            }
    }

    private func blockedOperatorChatSafetyMessage(for normalized: String) -> String? {
        let hardGate = (normalized.contains("저장소 삭제") || normalized.contains("delete repo") || normalized.contains("delete repository")) ||
            (normalized.contains("rm -rf") || ((normalized.contains("대량") || normalized.contains("모든 파일") || normalized.contains("all files")) && (normalized.contains("삭제") || normalized.contains("delete")))) ||
            ((normalized.contains("secret") || normalized.contains("token") || normalized.contains("password") || normalized.contains("시크릿") || normalized.contains("토큰")) && (normalized.contains("노출") || normalized.contains("보여") || normalized.contains("expose") || normalized.contains("변경") || normalized.contains("change"))) ||
            ((normalized.contains("비용 상한") || normalized.contains("budget cap") || normalized.contains("cost cap")) && (normalized.contains("해제") || normalized.contains("remove") || normalized.contains("disable"))) ||
            ((normalized.contains("배포") || normalized.contains("deploy") || normalized.contains("merge") || normalized.contains("머지")) && normalized.contains("policy") && (normalized.contains("disable") || normalized.contains("해제")))
        return hardGate
            ? language("That action is blocked in chat for safety. Use the dedicated settings or repository screen to review it manually.", "그 작업은 안전상 채팅에서 실행하지 않습니다. 전용 설정이나 저장소 화면에서 직접 확인해주세요.")
            : nil
    }

    private func containsAny(_ text: String, _ values: [String]) -> Bool {
        values.contains { text.contains($0) }
    }

    private func looksLikeFullAutoChatRequest(_ text: String) -> Bool {
        containsAny(text, ["full_auto", "full auto", "풀오토", "완전 자동"])
    }

    private func looksLikeCompanyDeleteChatRequest(_ text: String) -> Bool {
        containsAny(text, ["회사 삭제", "delete company", "remove company"])
    }

    private func looksLikeCompanyCreateChatRequest(_ text: String) -> Bool {
        containsAny(text, ["회사 생성", "회사 만들어", "create company", "new company", "make company"])
    }

    private func looksLikeRuntimeStartChatRequest(_ text: String) -> Bool {
        containsAny(text, ["회사 시작", "runtime start", "start runtime", "런타임 시작", "가동", "start company"])
    }

    private func looksLikeRuntimeStopChatRequest(_ text: String) -> Bool {
        containsAny(text, ["회사 중지", "runtime stop", "stop runtime", "런타임 중지", "정지", "stop company"])
    }

    private func looksLikeBackendChatRequest(_ text: String) -> Bool {
        text.contains("backend") || text.contains("백엔드")
    }

    private func looksLikeHrStaffingChatRequest(_ text: String) -> Bool {
        containsAny(text, ["hr", "hiring", "hire", "staff", "mentor", "팀 보강", "사수", "고용", "채용", "필요한 사람", "사람 붙"])
    }

    private func looksLikeGoalCreationChatRequest(_ text: String) -> Bool {
        isSlashCommand(text, commands: ["goal", "objective", "목표"]) ||
            ((text.contains("목표") || text.contains("goal")) && containsAny(text, ["생성", "만들", "추가", "create", "add"]))
    }

    private func looksLikeIssueCreationChatRequest(_ text: String) -> Bool {
        isSlashCommand(text, commands: ["issue", "task", "ticket", "이슈", "태스크", "작업"]) ||
            ((text.contains("이슈") || text.contains("issue") || text.contains("task")) && containsAny(text, ["생성", "만들", "추가", "create", "add"]))
    }

    private func isSlashCommand(_ text: String, commands: [String]) -> Bool {
        let trimmed = strippedLeadingListPrefix(from: text)
        guard trimmed.hasPrefix("/") else { return false }
        let escapedCommands = commands.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return trimmed.range(
            of: #"(?i)^/("# + escapedCommands + #")(?=$|[:：\-\s])"#,
            options: .regularExpression
        ) != nil
    }

    private func looksLikeGoalDecompositionChatRequest(_ text: String) -> Bool {
        containsAny(text, ["분해", "decompose", "split goal"])
    }

    private func looksLikeGoalAutonomyChatRequest(_ text: String) -> Bool {
        containsAny(text, ["목표 자동", "goal autonomy", "autonomy", "자율"])
    }

    private func looksLikeIssueRunChatRequest(_ text: String) -> Bool {
        containsAny(text, ["이슈 실행", "run issue", "실행해", "시작해"])
    }

    private func looksLikeRepositoryMapChatRequest(_ text: String) -> Bool {
        containsAny(text, ["graphify", "리포 맵", "리포지토리 맵", "리포지토리 구조", "repository map", "repository structure", "repo map", "map repo"])
    }

    private func looksLikeIssueDelegationChatRequest(_ text: String) -> Bool {
        containsAny(text, ["위임", "delegate", "assign"])
    }

    private func looksLikeReviewChatRequest(_ text: String) -> Bool {
        containsAny(text, ["qa 승인", "qa reject", "qa approve", "리뷰 승인", "ceo 승인", "review approve", "changes requested"])
    }

    private func looksLikeMergeChatRequest(_ text: String) -> Bool {
        containsAny(text, ["pr 머지", "머지해", "merge pr", "merge approved"])
    }

    private func looksLikeGitHubLoginChatRequest(_ text: String) -> Bool {
        text.contains("github") && containsAny(text, ["login", "로그인"])
    }

    private func looksLikeGitHubOriginChatRequest(_ text: String) -> Bool {
        text.contains("github") && containsAny(text, ["origin", "저장소 연결", "repo connect", "연결"])
    }

    private func looksLikeBudgetChatRequest(_ text: String) -> Bool {
        containsAny(text, ["budget", "예산"]) && containsAny(text, ["save", "저장", "설정"])
    }

    private func looksLikeLinearSettingsChatRequest(_ text: String) -> Bool {
        text.contains("linear") && containsAny(text, ["save", "저장", "settings", "설정"])
    }

    func startSelectedCompanyRuntime() async {
        guard let company = selectedCompany else { return }
        do {
            _ = try await runWithEmbeddedBackendRecovery {
                try await api.startCompanyRuntime(companyId: company.id)
            }
            await refreshDashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopSelectedCompanyRuntime() async {
        guard let company = selectedCompany else { return }
        do {
            _ = try await runWithEmbeddedBackendRecovery {
                try await api.stopCompanyRuntime(companyId: company.id)
            }
            await refreshDashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelectedIssue() async {
        guard let company = selectedCompany, let issue = selectedIssue else { return }
        do {
            _ = try await api.deleteIssue(companyId: company.id, issueId: issue.id)
            selectedIssueID = nil
            selectedTaskID = nil
            await refreshDashboard()
            await refreshTaskDetails()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSelectedWorkspaceBaseBranch() async {
        guard let workspace = selectedWorkspace else { return }
        do {
            let updated = try await api.updateWorkspaceBaseBranch(workspaceId: workspace.id, baseBranch: pendingWorkspaceBaseBranch)
            await refreshDashboard()
            selectedWorkspaceID = updated.id
            pendingWorkspaceBaseBranch = updated.baseBranch
            if shellMode == .tui {
                await ensureTuiSession(forceRestart: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Start execution for the task that is currently selected in the center pane.
    func runSelectedTask() async {
        if let issue = selectedIssue {
            do {
                _ = try await api.runIssue(issueId: issue.id)
                statusState = .taskStarted(issue.title)
                objectWillChange.send()
                await refreshDashboard()
                await refreshTaskDetails()
                await ensureTuiSession()
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }
        guard let task = selectedTask else { return }
        do {
            _ = try await api.runTask(taskId: task.id)
            statusState = .taskStarted(task.title)
            objectWillChange.send()
            // A fresh dashboard reload is cheap and ensures task/run status comes back
            // from the source of truth instead of from optimistic local mutation.
            await refreshDashboard()
            await refreshTaskDetails()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Present the native macOS folder picker and register the chosen repository.
    func openRepositoryPicker() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = text(.openRepositoryPrompt)
        if panel.runModal() == .OK, let url = panel.url {
            repositoryPathInput = url.path
            await submitOpenRepository()
        }
    }

    /// Present a native macOS folder picker for the company root path field.
    func openCompanyRootPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = language("Choose Folder", "폴더 선택")
        if panel.runModal() == .OK, let url = panel.url {
            newCompanyRootPath = url.path
        }
    }

    private func resetCompanyAgentComposer() {
        editingCompanyAgentID = nil
        editingCompanyAgentCompanyID = nil
        newCompanyAgentTitle = ""
        selectNewCompanyAgentCli(preferredCliAgent)
        newCompanyAgentModel = ""
        newCompanyAgentRole = ""
        newCompanyAgentSpecialties = ""
        newCompanyAgentCollaborationNotes = ""
        newCompanyAgentMemoryNotes = ""
        newCompanyAgentPreferredCollaboratorIDs = []
        newCompanyAgentMentorID = ""
        newCompanyAgentSkillIDs = defaultCompanyAgentSkillIDs
        resetMarketingPolicyForm()
        newCompanyAgentEnabled = true
    }

    private func syncMarketingPolicyForm(forAgentId agentId: String) {
        guard let policy = marketingDelegationPolicies.first(where: { $0.agentId == agentId }) else {
            resetMarketingPolicyForm()
            return
        }
        marketingPolicyAllowedDomains = policy.allowedDomains.joined(separator: ", ")
        marketingPolicyChannels = policy.channelAccounts.map(\.channel).joined(separator: ", ")
        marketingPolicyDailyPostLimit = "\(policy.dailyPostLimit)"
        marketingPolicyForbiddenTerms = policy.forbiddenTerms.joined(separator: ", ")
        marketingPolicyBrandTone = policy.brandTone ?? ""
        marketingPolicyProhibitedActions = policy.prohibitedActions.joined(separator: ", ")
        marketingPolicySecretRefs = policy.secretRefs.joined(separator: ", ")
        marketingPolicyBrowserSessionRef = policy.browserSessionRef ?? ""
        marketingPolicyMaxRuntimeSeconds = "\(policy.maxRuntimeSeconds)"
    }

    private func resetMarketingPolicyForm() {
        marketingPolicyAllowedDomains = ""
        marketingPolicyChannels = "web"
        marketingPolicyDailyPostLimit = "1"
        marketingPolicyForbiddenTerms = ""
        marketingPolicyBrandTone = ""
        marketingPolicyProhibitedActions = "paid-ad, budget-change, bulk-email, direct-message, payment, credential-storage"
        marketingPolicySecretRefs = ""
        marketingPolicyBrowserSessionRef = ""
        marketingPolicyMaxRuntimeSeconds = "900"
    }

    private func runWithEmbeddedBackendRecovery<T: Sendable>(_ action: @Sendable () async throws -> T) async throws -> T {
        do {
            return try await action()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if isBenignCancellationLikeError(error) {
                throw error
            }
            guard shouldAttemptEmbeddedBackendRecovery(for: error) else {
                AppLogger.error("Desktop action failed without backend recovery: \(error.localizedDescription)")
                throw error
            }
            AppLogger.info("Attempting embedded backend recovery after error: \(error.localizedDescription)")
            statusState = .waitingForServer
            await EmbeddedBackendLauncher.shared.ensureRunning()
            do {
                return try await action()
            } catch {
                AppLogger.error("Desktop action failed after backend recovery retry: \(error.localizedDescription)")
                throw error
            }
        }
    }

    private func shouldAttemptEmbeddedBackendRecovery(for error: Error) -> Bool {
        if isBenignCancellationLikeError(error) {
            return false
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorTimedOut:
                return true
            default:
                break
            }
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("network connection was lost")
            || message.contains("couldn't connect to server")
            || message.contains("cannot connect to host")
            || message.contains("connection refused")
    }

    private func isBenignCancellationLikeError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }
        let message = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return message == "cancelled" || message == "canceled"
    }

    private func resetGoalComposer() {
        editingGoalID = nil
        newGoalTitle = ""
        newGoalDescription = ""
    }

    private func resetIssueComposer() {
        newIssueCompanyID = selectedCompanyID ?? companies.first?.id
        newIssueGoalID = issueComposerGoals.first?.id ?? selectedGoalID
        newIssueTitle = ""
        newIssueDescription = ""
    }

    /// Submit the path collected from the picker or from a future manual input flow.
    func submitOpenRepository() async {
        let path = repositoryPathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        do {
            let repo = try await api.openRepository(path: path)
            repositoryPathInput = ""
            await refreshDashboard()
            if let refreshed = repositories.first(where: { $0.id == repo.id }) {
                await selectRepository(refreshed)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clone the repository URL from the clone sheet into the managed repository area.
    func submitCloneRepository() async {
        let url = cloneURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        do {
            let repo = try await api.cloneRepository(url: url)
            cloneURLInput = ""
            await refreshDashboard()
            if let refreshed = repositories.first(where: { $0.id == repo.id }) {
                await selectRepository(refreshed)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Refresh the branch picker options for the selected repository.
    func refreshAvailableBranches() async {
        guard let repository = selectedRepository else {
            availableBranches = []
            return
        }

        if isOffline {
            availableBranches = [selectedWorkspace?.baseBranch ?? selectedCompany?.defaultBaseBranch ?? repository.defaultBranch]
            pendingWorkspaceBaseBranch = selectedWorkspace?.baseBranch ?? selectedCompany?.defaultBaseBranch ?? repository.defaultBranch
            return
        }

        do {
            let branches = try await api.repositoryBranches(repositoryId: repository.id)
            availableBranches = branches.isEmpty ? [repository.defaultBranch] : branches
            if selectedWorkspace == nil, !availableBranches.contains(pendingWorkspaceBaseBranch) {
                pendingWorkspaceBaseBranch = selectedCompany?.defaultBaseBranch ?? repository.defaultBranch
            }
        } catch {
            availableBranches = [repository.defaultBranch]
            pendingWorkspaceBaseBranch = selectedWorkspace?.baseBranch ?? selectedCompany?.defaultBaseBranch ?? repository.defaultBranch
            errorMessage = error.localizedDescription
        }
    }

    /// Update every dependent selection when the repository changes.
    func selectRepository(_ repository: RepositoryRecord) async {
        selectedRepositoryID = repository.id
        if shellMode != .tui, let company = companies.first(where: { $0.repositoryId == repository.id }) {
            selectedCompanyID = company.id
        }
        // Selection cascades from repository -> workspace -> task so every pane stays aligned.
        selectedWorkspaceID = workspaces.first?.id
        if shellMode == .tui {
            selectedGoalID = nil
            selectedIssueID = nil
            selectedTaskID = nil
            selectedAgentName = nil
        } else {
            selectedGoalID = goals.first?.id
            selectedIssueID = issues.first?.id
            selectedTaskID = tasks.first?.id
            selectedAgentName = selectedTask?.agents.first
        }
        pendingWorkspaceBaseBranch = selectedWorkspace?.baseBranch ?? selectedCompany?.defaultBaseBranch ?? repository.defaultBranch
        await refreshAvailableBranches()
        await refreshTaskDetails()
    }

    /// Switch to a new workspace and reload the task/inspector state derived from it.
    func selectWorkspace(_ workspace: WorkspaceRecord) async {
        selectedWorkspaceID = workspace.id
        if shellMode != .tui, let company = companies.first(where: { $0.repositoryId == workspace.repositoryId }) {
            selectedCompanyID = company.id
        }
        if shellMode == .tui {
            selectedIssueID = nil
            selectedTaskID = nil
            selectedAgentName = nil
        } else {
            selectedIssueID = dashboard.issues.first(where: { $0.workspaceId == workspace.id && (selectedGoalID == nil || $0.goalId == selectedGoalID) })?.id
            selectedTaskID = tasks.first?.id
            selectedAgentName = selectedTask?.agents.first
        }
        pendingWorkspaceBaseBranch = workspace.baseBranch
        await refreshTaskDetails()
    }

    func selectCompany(_ company: CompanyRecord) async {
        selectedCompanyID = company.id
        newIssueCompanyID = company.id
        selectedRepositoryID = company.repositoryId
        operatorCommandResponses = []
        operatorChatMessages = []
        operatorPendingPrompt = nil
        operatorCommandDraft = ""
        resetCompanyAgentComposer()
        selectedWorkspaceID = dashboard.workspaces.first(where: { $0.repositoryId == company.repositoryId && $0.baseBranch == company.defaultBaseBranch })?.id
        selectedGoalID = goals.first?.id
        selectedIssueID = issues.first?.id
        selectedTaskID = selectedTask?.id
        pendingWorkspaceBaseBranch = selectedWorkspace?.baseBranch ?? company.defaultBaseBranch
        await refreshAvailableBranches()
        await refreshSelectedCompanyGitHubStatus()
        await refreshTaskDetails()
        syncIssueComposerState()
        syncSelectedCompanyBudgetFormState()
        syncSelectedCompanyLinearFormState()
        await refreshCompanyReports(companyId: company.id)
        await restartCompanyEventStream()
    }

    func selectGoal(_ goal: GoalRecord) async {
        selectedCompanyID = goal.companyId
        newIssueCompanyID = goal.companyId
        selectedGoalID = goal.id
        newIssueGoalID = goal.id
        selectedIssueID = issues.first?.id
        if let issue = selectedIssue {
            selectedWorkspaceID = issue.workspaceId
        }
        selectedTaskID = selectedTask?.id
        selectedAgentName = selectedTask?.agents.first
        await refreshTaskDetails()
        if shellMode == .tui {
            await ensureTuiSession()
        }
    }

    func selectIssue(_ issue: IssueRecord) async {
        selectedCompanyID = issue.companyId
        selectedGoalID = issue.goalId
        selectedIssueID = issue.id
        selectedWorkspaceID = issue.workspaceId
        selectedTaskID = dashboard.tasks
            .filter { $0.issueId == issue.id }
            .sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
            .first?.id
        selectedAgentName = selectedTask?.agents.first
        await refreshTaskDetails()
        if shellMode == .tui {
            await ensureTuiSession()
        }
    }

    /// Focus a task row and refresh the right-hand inspector for its default agent.
    func selectTask(_ task: TaskRecord) async {
        selectedTaskID = task.id
        selectedAgentName = task.agents.first
        await refreshTaskDetails()
    }

    /// Switch the inspector to a different agent run within the same task.
    func selectAgent(_ name: String) async {
        selectedAgentName = name
        await refreshTaskDetails()
    }

    /// Open Finder at the most relevant location for the current selection.
    func openSelectedLocation() {
        let path = activeTuiSession?.repositoryPath ?? selectedRun?.worktreePath ?? selectedRepository?.localPath
        guard let path else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Promote a discovered local port into the embedded browser tab.
    func openPort(_ port: PortEntryPayload) {
        browserURL = URL(string: port.url)
        inspectorTab = .browser
    }

    func saveBackendSettings() async {
        do {
            backendStatusMessage = nil
            let settings = try await api.updateBackendSettings(
                defaultBackendKind: defaultBackendKind,
                codePublishMode: codePublishMode,
                codexLaunchMode: codexLaunchMode,
                codexCommand: trimmedOptional(codexCommand),
                codexArgs: parseCodexArguments(codexArgs),
                codexWorkingDirectory: trimmedOptional(codexWorkingDirectory),
                codexPort: Int(trimmedOptional(codexPort) ?? ""),
                codexStartupTimeoutSeconds: Int(trimmedOptional(codexStartupTimeoutSeconds) ?? ""),
                codexAppServerBaseURL: trimmedOptional(codexAppServerBaseURL),
                codexAuthMode: nil,
                codexToken: nil,
                codexTimeoutSeconds: nil
            )
            dashboard = DashboardPayload(
                repositories: dashboard.repositories,
                workspaces: dashboard.workspaces,
                tasks: dashboard.tasks,
                settings: settings,
                companies: dashboard.companies,
                companyAgentDefinitions: dashboard.companyAgentDefinitions,
                agentCapabilityProfiles: dashboard.agentCapabilityProfiles,
                projectContexts: dashboard.projectContexts,
                goals: dashboard.goals,
                issues: dashboard.issues,
                reviewQueue: dashboard.reviewQueue,
                orgProfiles: dashboard.orgProfiles,
                workflowTopologies: dashboard.workflowTopologies,
                goalDecisions: dashboard.goalDecisions,
                runningAgentSessions: dashboard.runningAgentSessions,
                backendStatuses: settings.backendStatuses,
                opsMetrics: dashboard.opsMetrics,
                activity: dashboard.activity,
                companyRuntimes: dashboard.companyRuntimes,
                agentContextEntries: dashboard.agentContextEntries,
                agentMessages: dashboard.agentMessages,
                marketingDelegationPolicies: dashboard.marketingDelegationPolicies,
                marketingRuns: dashboard.marketingRuns,
                skillRuns: dashboard.skillRuns,
                agentPerformance: dashboard.agentPerformance
            )
            syncBackendFormState()
        } catch {
            backendStatusMessage = error.localizedDescription
        }
    }

    func testCodexBackendConnection() async {
        do {
            backendStatusMessage = nil
            codexBackendStatus = try await api.testBackend(
                kind: "CODEX_APP_SERVER",
                launchMode: codexLaunchMode,
                command: trimmedOptional(codexCommand),
                args: parseCodexArguments(codexArgs),
                workingDirectory: trimmedOptional(codexWorkingDirectory),
                port: Int(trimmedOptional(codexPort) ?? ""),
                startupTimeoutSeconds: Int(trimmedOptional(codexStartupTimeoutSeconds) ?? ""),
                baseURL: trimmedOptional(codexAppServerBaseURL),
                authMode: nil,
                token: nil,
                timeoutSeconds: nil
            )
        } catch {
            backendStatusMessage = error.localizedDescription
        }
    }

    func refreshCodexOAuthStatus() {
        syncCodexOAuthState()
    }

    func launchCodexOAuthLogin() {
        let home = codexOAuthHome()
        do {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let command = "export CODEX_HOME='\(home.path.replacingOccurrences(of: "'", with: "'\\''"))'; codex login"
            let script = """
            tell application "Terminal"
                activate
                do script "\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))"
            end tell
            """
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
            if let error {
                codexOAuthStatusMessage = error.description
            } else {
                codexOAuthStatusMessage = self.language == .korean
                    ? "Codex OAuth 로그인을 위해 터미널을 열었습니다."
                    : "Opened Terminal for Codex OAuth login."
            }
        } catch {
            codexOAuthStatusMessage = error.localizedDescription
        }
    }

    func logoutCodexOAuth() {
        do {
            let authFile = codexOAuthHome().appendingPathComponent("auth.json")
            if FileManager.default.fileExists(atPath: authFile.path) {
                try FileManager.default.removeItem(at: authFile)
            }
            syncCodexOAuthState()
            codexOAuthStatusMessage = self.language == .korean
                ? "관리되는 Codex OAuth 인증 파일을 삭제했습니다."
                : "Removed managed Codex OAuth auth file."
        } catch {
            codexOAuthStatusMessage = error.localizedDescription
        }
    }

    func updateSelectedCompanyBackend(kind: String) async {
        guard let company = selectedCompany else { return }
        do {
            backendStatusMessage = nil
            _ = try await api.updateCompanyBackend(
                companyId: company.id,
                backendKind: kind,
                launchMode: codexLaunchMode,
                command: trimmedOptional(codexCommand),
                args: parseCodexArguments(codexArgs),
                workingDirectory: trimmedOptional(codexWorkingDirectory),
                port: Int(trimmedOptional(codexPort) ?? ""),
                startupTimeoutSeconds: Int(trimmedOptional(codexStartupTimeoutSeconds) ?? ""),
                baseURL: trimmedOptional(codexAppServerBaseURL),
                authMode: nil,
                token: nil,
                timeoutSeconds: nil,
                useGlobalDefault: false
            )
            await refreshDashboard()
        } catch {
            backendStatusMessage = error.localizedDescription
        }
    }

    func saveSelectedCompanyBudget() async {
        guard let company = selectedCompany else { return }
        do {
            let dailyBudgetCents = try budgetCentsForUpdateInput(companyDailyBudgetInput)
            let monthlyBudgetCents = try budgetCentsForUpdateInput(companyMonthlyBudgetInput)
            _ = try await api.updateCompany(
                companyId: company.id,
                dailyBudgetCents: dailyBudgetCents,
                monthlyBudgetCents: monthlyBudgetCents
            )
            await refreshDashboard()
            syncSelectedCompanyBudgetFormState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restartCompanyEventStream() async {
        // Company mode uses the event stream as the primary data path. Events now carry a focused
        // company snapshot so the store can patch live state without forcing a heavyweight global
        // dashboard refresh on every runtime transition.
        companyEventTask?.cancel()
        companyEventTask = nil
        guard !isOffline, shellMode == .company, let companyID = selectedCompanyID else { return }
        companyEventStreamGeneration += 1
        let generation = companyEventStreamGeneration
        companyEventTask = Task { [weak self] in
            guard let self else { return }
            var reconnectBackoff = CompanyEventStreamBackoff()
            var lastEventCursor: String? = nil
            defer {
                Task { @MainActor [weak self] in
                    guard let self, self.companyEventStreamGeneration == generation else { return }
                    self.companyEventTask = nil
                }
            }
            while !Task.isCancelled {
                do {
                    for try await envelope in api.companyEvents(companyId: companyID, cursor: lastEventCursor) {
                        let shouldApply = await MainActor.run { () -> Bool in
                            self.companyEventStreamGeneration == generation &&
                                self.selectedCompanyID == companyID &&
                                self.shellMode == .company
                        }
                        guard shouldApply else { return }
                        if isCompanyEventStreamHeartbeat(envelope) {
                            reconnectBackoff.reset()
                            continue
                        }
                        if let cursor = envelope.cursor, !cursor.isEmpty {
                            lastEventCursor = cursor
                        } else if let sequence = envelope.sequence {
                            lastEventCursor = String(sequence)
                        }
                        await MainActor.run {
                            self.companyStreamStatusMessage = nil
                            if let companyDashboard = envelope.companyDashboard {
                                self.applyCompanyDashboard(companyDashboard, companyId: companyID)
                            } else if let dashboard = envelope.dashboard {
                                self.dashboard = dashboard
                                self.marketingDelegationPolicies = dashboard.marketingDelegationPolicies
                                self.marketingRuns = dashboard.marketingRuns
                                self.skillRuns = dashboard.skillRuns
                                self.reconcileWorkflowLeadAgent()
                                self.reconcileSelection()
                                self.syncBackendFormState()
                            }
                        }
                        reconnectBackoff.reset()
                        if envelope.companyDashboard == nil && envelope.dashboard == nil {
                            await self.refreshCompanyDashboard(restartEventStream: false)
                        }
                    }
                    let shouldReconnect = await MainActor.run { () -> Bool in
                        guard self.companyEventStreamGeneration == generation,
                              self.selectedCompanyID == companyID,
                              self.shellMode == .company else { return false }
                        self.companyStreamStatusMessage = nil
                        return true
                    }
                    guard shouldReconnect else { return }
                    await self.refreshCompanyDashboard(restartEventStream: false)
                    try? await Task.sleep(for: reconnectBackoff.sleepDuration)
                    reconnectBackoff.advance()
                } catch is CancellationError {
                    return
                } catch {
                    let expectedInterruption = isExpectedCompanyEventStreamInterruption(error)
                    if expectedInterruption {
                        AppLogger.info("Company event stream reconnecting after expected interruption: \(error.localizedDescription)")
                    } else {
                        AppLogger.error("Company event stream failed: \(error.localizedDescription)")
                    }
                    let shouldRetry = await MainActor.run { () -> Bool in
                        guard self.companyEventStreamGeneration == generation,
                              self.selectedCompanyID == companyID,
                              self.shellMode == .company else { return false }
                        self.companyStreamStatusMessage = expectedInterruption ? nil : self.companyStreamRecoveryMessage()
                        self.errorMessage = nil
                        return true
                    }
                    guard shouldRetry else { return }
                    await self.refreshCompanyDashboard(restartEventStream: false)
                    try? await Task.sleep(for: reconnectBackoff.sleepDuration)
                    reconnectBackoff.advance()
                }
            }
        }
    }

    private func startCompanyStatePolling() {
        guard companyPollingTask == nil else { return }
        companyPollingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.companyPollingTask = nil
                }
            }
            while !Task.isCancelled {
                let pollState = await MainActor.run { () -> (shouldRefresh: Bool, isOffline: Bool) in
                    (
                        shouldRefresh: self.shellMode == .company &&
                            self.selectedCompanyID != nil &&
                            !self.isBusy &&
                            (self.isOffline || self.companyStreamStatusMessage != nil || self.companyEventTask == nil),
                        isOffline: self.isOffline
                    )
                }
                if pollState.shouldRefresh && pollState.isOffline {
                    await EmbeddedBackendLauncher.shared.ensureRunning()
                }
                if pollState.shouldRefresh {
                    await self.refreshCompanyDashboard(restartEventStream: false)
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func startEmbeddedBackendWatchdog() {
        guard backendWatchdogTask == nil else { return }
        backendWatchdogTask = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.backendWatchdogTask = nil
                }
            }
            while !Task.isCancelled {
                await EmbeddedBackendLauncher.shared.ensureRunning()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func isBenignCompanyEventError(_ error: Error) -> Bool {
        if isBenignCancellationLikeError(error) {
            return true
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func companyStreamRecoveryMessage() -> String {
        language(
            "Live company updates disconnected. Re-syncing...",
            "회사 실시간 업데이트 연결이 끊어졌습니다. 다시 동기화하는 중..."
        )
    }

    private func handleShellModeChange(_ mode: AppShellMode) async {
        switch mode {
        case .company:
            stopTuiPolling()
            await restartCompanyEventStream()
        case .tui:
            companyEventStreamGeneration += 1
            companyEventTask?.cancel()
            companyEventTask = nil
            await refreshTuiSessionList(suppressErrors: true)
            selectWorkspaceForTuiIfNeeded()
            if let session = activeTuiSession {
                await selectTuiSession(session)
            }
        }
    }

    private func selectWorkspaceForTuiIfNeeded() {
        if let session = activeTuiSession {
            if session.workspaceId == selectedWorkspaceID {
                // Session already matches the selected workspace — sync the session
                // chip without touching the repository or workspace selection.
                selectedTuiSessionID = session.id
                pendingWorkspaceBaseBranch = session.baseBranch
            } else if selectedWorkspaceID == nil {
                // No workspace was selected yet — let the active session drive it.
                selectedTuiSessionID = session.id
                selectedRepositoryID = session.repositoryId
                selectedWorkspaceID = session.workspaceId
                pendingWorkspaceBaseBranch = session.baseBranch
            }
            // When the session's workspace differs from the user's current selection,
            // preserve the user's selection and let ensureTuiSession open a new one.
            return
        }

        if selectedRepositoryID == nil {
            selectedRepositoryID = repositories.first?.id
        }
        if selectedWorkspaceID == nil {
            selectedWorkspaceID = dashboard.workspaces.first?.id
        }
        if selectedWorkspace?.repositoryId != selectedRepositoryID {
            selectedWorkspaceID = workspaces.first?.id
        }
        pendingWorkspaceBaseBranch = selectedWorkspace?.baseBranch ?? selectedRepository?.defaultBranch ?? pendingWorkspaceBaseBranch
    }

    func refreshTuiSessionList(suppressErrors: Bool = false) async {
        if isOffline {
            tuiSessions = []
            tuiSession = nil
            selectedTuiSessionID = nil
            return
        }

        do {
            let sessions = try await api.listTuiSessions()
                .sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
            tuiSessions = sessions

            if let selectedTuiSessionID,
               let selected = sessions.first(where: { $0.id == selectedTuiSessionID }) {
                tuiSession = selected
            } else if let current = tuiSession,
                      let refreshed = sessions.first(where: { $0.id == current.id }) {
                selectedTuiSessionID = refreshed.id
                tuiSession = refreshed
            } else if let match = sessions.first(where: { $0.workspaceId == selectedWorkspaceID }) {
                // Only adopt an unrelated session when it matches the current workspace.
                // Falling back to sessions.first would silently override the user's
                // folder selection with whatever session was opened last.
                selectedTuiSessionID = match.id
                tuiSession = match
            } else {
                selectedTuiSessionID = nil
                tuiSession = nil
            }
        } catch {
            if !suppressErrors {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The desktop TUI should behave like the CLI interactive shell, with one
    /// live terminal per selected folder/workspace and the ability to switch
    /// between several open sessions without routing through company state.
    func ensureTuiSession(forceRestart: Bool = false) async {
        if shellMode != .tui && !forceRestart {
            return
        }
        guard let workspace = selectedWorkspace else {
            stopTuiPolling()
            tuiSession = nil
            selectedTuiSessionID = nil
            return
        }

        if isOffline {
            stopTuiPolling()
            tuiSession = nil
            selectedTuiSessionID = nil
            return
        }

        do {
            let preferredAgent = workflowLeadAgent.isEmpty ? preferredCliAgent : workflowLeadAgent
            if forceRestart, let session = activeTuiSession {
                _ = try? await api.terminateTuiSession(sessionId: session.id)
                removeTuiSession(session.id)
            }
            let session = try await api.openTuiSession(workspaceId: workspace.id, preferredAgent: preferredAgent)
            upsertTuiSession(session, selectSession: true)
            errorMessage = nil
            startTuiPolling(sessionID: session.id, workspaceID: workspace.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func launchTuiSession() async {
        guard let workspace = await ensureWorkspaceForTuiSelection() else { return }
        selectedWorkspaceID = workspace.id
        selectedRepositoryID = workspace.repositoryId
        pendingWorkspaceBaseBranch = workspace.baseBranch
        await ensureTuiSession()
    }

    func selectTuiSession(_ session: TuiSessionRecord) async {
        selectedTuiSessionID = session.id
        tuiSession = session
        selectedRepositoryID = session.repositoryId
        selectedWorkspaceID = session.workspaceId
        pendingWorkspaceBaseBranch = session.baseBranch
        errorMessage = nil
        startTuiPolling(sessionID: session.id, workspaceID: session.workspaceId)
    }

    func terminateTuiSession(_ session: TuiSessionRecord) async {
        do {
            let terminated = try await api.terminateTuiSession(sessionId: session.id)
            removeTuiSession(session.id)
            if selectedTuiSessionID == session.id {
                let nextSession = tuiSessions.first
                selectedTuiSessionID = nextSession?.id
                tuiSession = nextSession
                if let nextSession {
                    await selectTuiSession(nextSession)
                } else {
                    stopTuiPolling()
                }
            }
            upsertTuiSession(terminated, selectSession: false)
            removeTuiSession(terminated.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stop the current TUI loop so the user can launch a fresh interactive shell.
    func restartTuiSession() async {
        if let session = activeTuiSession {
            _ = try? await api.terminateTuiSession(sessionId: session.id)
            removeTuiSession(session.id)
        }
        await ensureTuiSession()
    }

    private func startTuiPolling(sessionID: String, workspaceID: String) {
        guard polledTuiSessionID != sessionID else { return }

        stopTuiPolling()
        polledTuiSessionID = sessionID
        tuiPollingTask = Task { [weak self] in
            guard let self else { return }
            var refreshCounter = 0
            defer {
                Task { @MainActor [weak self] in
                    guard let self, self.polledTuiSessionID == sessionID else { return }
                    self.tuiPollingTask = nil
                    self.polledTuiSessionID = nil
                }
            }

            while !Task.isCancelled {
                do {
                    let latest = try await api.tuiSession(sessionId: sessionID)
                    self.upsertTuiSession(latest, selectSession: self.selectedTuiSessionID == sessionID)
                    refreshCounter += 1
                    if refreshCounter % 3 == 0 {
                        await self.refreshTuiSessionList(suppressErrors: true)
                    }

                    if latest.status == "EXITED" || latest.status == "FAILED" {
                        await self.refreshTuiSessionList(suppressErrors: true)
                        break
                    }
                } catch {
                    if await self.recoverFromStaleTuiSession(error, sessionID: sessionID, workspaceID: workspaceID) {
                        break
                    }
                    self.errorMessage = error.localizedDescription
                    break
                }

                try? await Task.sleep(for: .milliseconds(800))
            }
        }
    }

    private func stopTuiPolling() {
        tuiPollingTask?.cancel()
        tuiPollingTask = nil
        polledTuiSessionID = nil
    }

    /// Backend restarts invalidate the in-memory PTY session table, so an older
    /// embedded terminal can briefly point at a session id that no longer exists.
    /// Treat that as recoverable and open a fresh workspace session instead of
    /// surfacing a sticky HTTP 404/500 alert to the user.
    private func recoverFromStaleTuiSession(_ error: Error, sessionID: String, workspaceID: String) async -> Bool {
        guard selectedWorkspaceID == workspaceID else { return false }
        guard isRecoverableTuiSessionError(error) else { return false }
        guard selectedTuiSessionID == sessionID || tuiSession?.id == sessionID || polledTuiSessionID == sessionID else { return false }

        stopTuiPolling()
        removeTuiSession(sessionID)
        tuiSession = nil
        errorMessage = nil
        await ensureTuiSession()
        return true
    }

    private func isRecoverableTuiSessionError(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        if apiError.statusCode == 404 {
            return true
        }

        // Older backend builds returned a blank 500 for missing TUI sessions.
        // Keep the client tolerant until every packaged app is on the structured
        // status-page response path.
        if apiError.statusCode == 500 {
            let body = apiError.responseBody.trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty || body == "Unknown server error"
        }

        return false
    }

    private func syncCodexOAuthState() {
        let home = codexOAuthHome()
        codexOAuthHomePath = home.path
        let authFile = home.appendingPathComponent("auth.json")
        codexOAuthAuthenticated = FileManager.default.fileExists(atPath: authFile.path)
    }

    private func codexOAuthHome() -> URL {
        if let override = ProcessInfo.processInfo.environment["COTOR_CODEX_OAUTH_HOME"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".cotor", isDirectory: true)
            .appendingPathComponent("auth", isDirectory: true)
            .appendingPathComponent("codex-oauth", isDirectory: true)
    }

    private func ensureWorkspaceForTuiSelection() async -> WorkspaceRecord? {
        guard let repository = selectedRepository else { return nil }
        if let existing = dashboard.workspaces.first(where: { $0.repositoryId == repository.id && $0.baseBranch == pendingWorkspaceBaseBranch }) {
            return existing
        }

        do {
            let created = try await api.createWorkspace(
                repositoryId: repository.id,
                name: nil,
                baseBranch: pendingWorkspaceBaseBranch
            )
            await refreshDashboard(restartEventStream: false)
            return dashboard.workspaces.first(where: { $0.id == created.id }) ?? created
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func upsertTuiSession(_ session: TuiSessionRecord, selectSession: Bool) {
        var next = tuiSessions.filter { $0.id != session.id }
        next.append(session)
        next.sort { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
        tuiSessions = next
        if selectSession {
            selectedTuiSessionID = session.id
            tuiSession = session
        } else if selectedTuiSessionID == session.id || tuiSession?.id == session.id {
            tuiSession = session
        }
    }

    private func removeTuiSession(_ sessionID: String) {
        tuiSessions.removeAll { $0.id == sessionID }
        if selectedTuiSessionID == sessionID {
            selectedTuiSessionID = nil
        }
        if tuiSession?.id == sessionID {
            tuiSession = nil
        }
    }
}
