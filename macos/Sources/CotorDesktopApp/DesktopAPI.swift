import Foundation
import Security


// MARK: - File Overview
// DesktopAPI belongs to the native macOS client layer for the Cotor desktop application.
// It collects declarations centered on desktop a p i so the native shell code stays easier to navigate.
// Start with this file when tracing how the desktop client presents, stores, or moves state in this area.

/// Thin HTTP client for the localhost `cotor app-server`.
///
/// Keeping transport concerns here lets the view model stay focused on user intent
/// and state transitions instead of URLSession boilerplate.
struct DesktopAPI {
    static var appToken: String? {
        configuredAppToken() ?? readRuntimeAppToken() ?? processGeneratedAppToken
    }

    static func ensureAppToken() -> String {
        appToken ?? processGeneratedAppToken
    }

    private static let processGeneratedAppToken: String = {
        let token = generateAppToken()
        _ = writeRuntimeAppToken(token)
        return token
    }()

    internal static func configuredAppToken(processEnvironment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        nonEmpty(processEnvironment["COTOR_APP_TOKEN"])
    }

    internal static func readRuntimeAppToken(appHome: URL = defaultDesktopAppHome()) -> String? {
        let tokenURL = runtimeAppTokenURL(appHome: appHome)
        guard let token = try? String(contentsOf: tokenURL, encoding: .utf8) else {
            return nil
        }
        return nonEmpty(token)
    }

    @discardableResult
    internal static func writeRuntimeAppToken(_ token: String, appHome: URL = defaultDesktopAppHome()) -> URL? {
        guard let token = nonEmpty(token) else {
            return nil
        }
        let tokenURL = runtimeAppTokenURL(appHome: appHome)
        do {
            try FileManager.default.createDirectory(
                at: tokenURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try token.write(to: tokenURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
            return tokenURL
        } catch {
            AppLogger.warning("Failed to persist app-server token: \(error.localizedDescription)")
            return nil
        }
    }

    internal static func runtimeAppTokenURL(appHome: URL = defaultDesktopAppHome()) -> URL {
        appHome
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("backend", isDirectory: true)
            .appendingPathComponent("app-server.token")
    }

    internal static func defaultDesktopAppHome() -> URL {
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        return userHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("CotorDesktop", isDirectory: true)
    }

    private static func generateAppToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes).base64URLEncodedString()
        }
        return "\(UUID().uuidString)-\(UUID().uuidString)"
    }
    static func decodeCompanyEventLine(_ line: String) -> CompanyEventEnvelopePayload? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(CompanyEventEnvelopePayload.self, from: Data(trimmed.utf8))
        } catch {
            AppLogger.warning("Dropped malformed company event stream line: \(error.localizedDescription)")
            return nil
        }
    }

    let baseURL: URL
    let token: String?
    let session: URLSession

    internal init(baseURL: URL, token: String?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    init() {
        guard let fallbackURL = URL(string: "http://127.0.0.1:8787") else {
            fatalError("Invalid fallback URL")
        }
        let env = ProcessInfo.processInfo.environment
        let (validatedURL, resolvedToken) = DesktopAPI.validatedAppServerConfiguration(
            envURL: env["COTOR_APP_SERVER_URL"],
            envAllowRemote: env["COTOR_ALLOW_REMOTE_APP_SERVER"],
            envToken: env["COTOR_APP_TOKEN"],
            fallbackURL: fallbackURL,
            appToken: Self.ensureAppToken()
        )
        self.init(baseURL: validatedURL, token: resolvedToken)
    }

    internal static func validatedAppServerConfiguration(
        envURL: String?,
        envAllowRemote: String?,
        envToken: String?,
        fallbackURL: URL,
        appToken: String
    ) -> (URL, String) {
        let raw = envURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, let url = URL(string: raw) else {
            return (fallbackURL, appToken)
        }
        if isLoopbackAppServerURL(url) {
            return (url, appToken)
        }
        let allowRemote = envAllowRemote?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        let explicitToken = envToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if allowRemote && !explicitToken.isEmpty {
            return (url, explicitToken)
        }
        AppLogger.warning("Remote app-server URL '\(raw)' blocked: COTOR_ALLOW_REMOTE_APP_SERVER=1 and COTOR_APP_TOKEN are both required. Falling back to loopback.")
        return (fallbackURL, appToken)
    }

    private static func isLoopbackAppServerURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return false
        }
        let host = url.host?.lowercased() ?? ""
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    /// Fetch the full dashboard payload used to bootstrap most of the app state.
    func dashboard() async throws -> DashboardPayload {
        try await get(path: "api/app/dashboard")
    }

    /// Ask the backend to warm desktop-owned infrastructure without starting company work.
    func prepareDesktopStartup() async throws -> DesktopLifecycleStartupPayload {
        try await post(pathSegments: ["api", "app", "lifecycle", "startup"], body: EmptyPayload())
    }

    /// Ask the backend to stop desktop-owned work before the app-server process exits.
    func prepareDesktopShutdown() async throws -> DesktopLifecycleShutdownPayload {
        try await post(pathSegments: ["api", "app", "lifecycle", "shutdown"], body: EmptyPayload())
    }

    /// Fetch the focused company snapshot used for live company-mode updates.
    func companyDashboard(companyId: String) async throws -> CompanyDashboardPayload {
        try await get(pathSegments: ["api", "app", "companies", companyId, "dashboard"])
    }

    func agentPerformance(companyId: String) async throws -> [AgentPerformanceSnapshotRecord] {
        try await get(pathSegments: ["api", "app", "companies", companyId, "agents", "performance"])
    }

    func companyReports(companyId: String) async throws -> [CompanyDailyReportSummaryRecord] {
        try await get(pathSegments: ["api", "app", "companies", companyId, "reports"])
    }

    func companyReport(companyId: String, date: String) async throws -> CompanyDailyReportRecord {
        try await get(pathSegments: ["api", "app", "companies", companyId, "reports", date])
    }

    func generateCompanyReport(companyId: String) async throws -> CompanyDailyReportRecord {
        try await post(pathSegments: ["api", "app", "companies", companyId, "reports", "generate"], body: EmptyPayload())
    }

    func testCenterPlan(companyId: String, suiteId: String = "baseline") async throws -> TestCenterPlanRecord {
        try await get(
            pathSegments: ["api", "app", "companies", companyId, "test-center", "plan"],
            query: [URLQueryItem(name: "suiteId", value: suiteId)]
        )
    }

    func testCenterSessions(companyId: String) async throws -> [TestCenterSessionRecord] {
        try await get(pathSegments: ["api", "app", "companies", companyId, "test-center", "sessions"])
    }

    func startTestCenterSession(companyId: String, suiteId: String) async throws -> TestCenterSessionRecord {
        try await post(
            pathSegments: ["api", "app", "companies", companyId, "test-center", "sessions"],
            body: StartTestCenterSessionPayload(suiteId: suiteId)
        )
    }

    func testCenterSession(companyId: String, sessionId: String) async throws -> TestCenterSessionRecord {
        try await get(pathSegments: ["api", "app", "companies", companyId, "test-center", "sessions", sessionId])
    }

    func companyMemorySnapshot(companyId: String, issueId: String?, agentProfileId: String?) async throws -> CompanyMemorySnapshotPayload {
        var query: [URLQueryItem] = []
        if let issueId, !issueId.isEmpty {
            query.append(URLQueryItem(name: "issueId", value: issueId))
        }
        if let agentProfileId, !agentProfileId.isEmpty {
            query.append(URLQueryItem(name: "agentProfileId", value: agentProfileId))
        }
        return try await get(pathSegments: ["api", "app", "companies", companyId, "memory-snapshot"], query: query)
    }

    func companyProblemSignals(companyId: String) async throws -> [CompanyProblemSignalRecord] {
        try await get(pathSegments: ["api", "app", "companies", companyId, "problem-signals"])
    }

    func runCompanyDiscoveryScan(companyId: String) async throws -> [CompanyProblemSignalRecord] {
        try await post(pathSegments: ["api", "app", "companies", companyId, "autonomy", "discovery-scan"], body: EmptyPayload())
    }

    func companyGitHubStatus(companyId: String) async throws -> GitHubPublishStatusPayload {
        try await get(pathSegments: ["api", "app", "companies", companyId, "github", "status"])
    }

    func configureCompanyGitHubOrigin(companyId: String, remoteURL: String) async throws -> GitHubPublishStatusPayload {
        try await post(
            pathSegments: ["api", "app", "companies", companyId, "github", "origin"],
            body: ConfigureGitHubOriginPayload(remoteUrl: remoteURL)
        )
    }

    func health() async throws -> Bool {
        struct HealthPayload: Decodable {
            let status: String?
            let ok: Bool?
        }
        let payload: HealthPayload = try await get(path: "api/app/health")
        if let ok = payload.ok {
            return ok
        }
        return payload.status?.lowercased() == "ok"
    }

    func desktopUpdateStatus() async throws -> DesktopUpdateStatusPayload {
        try await get(path: "api/app/update-status")
    }

    func helpGuide(languageCode: String) async throws -> HelpGuidePayload {
        try await get(path: "api/app/help-guide", query: [URLQueryItem(name: "lang", value: languageCode)])
    }

    /// Return the selectable base branches for the currently focused repository.
    func repositoryBranches(repositoryId: String) async throws -> [String] {
        try await get(pathSegments: ["api", "app", "repositories", repositoryId, "branches"])
    }

    /// Expose the built-in agent roster advertised by the backend.
    func agents() async throws -> [String] {
        try await get(path: "api/app/agents")
    }

    /// Expose selectable provider models for one CLI agent.
    func agentModels(agent: String) async throws -> [String] {
        try await get(path: "api/app/agents/models", query: [URLQueryItem(name: "agent", value: agent)])
    }

    /// Fetch all persisted runs belonging to one task.
    func runs(taskId: String) async throws -> [RunRecord] {
        try await get(path: "api/app/runs", query: [URLQueryItem(name: "taskId", value: taskId)])
    }

    /// Fetch all persisted runs belonging to one company issue.
    func issueRuns(issueId: String) async throws -> [RunRecord] {
        try await get(pathSegments: ["api", "app", "issues", issueId, "runs"])
    }

    func issueExecutionDetails(issueId: String) async throws -> [IssueAgentExecutionDetailRecord] {
        try await get(pathSegments: ["api", "app", "issues", issueId, "execution-details"])
    }

    /// Fetch the git diff summary for one task/agent pair.
    func changes(taskId: String, agentName: String) async throws -> ChangeSummaryPayload {
        try await get(pathSegments: ["api", "app", "tasks", taskId, "changes", agentName])
    }

    /// Fetch the git diff summary for one concrete run.
    func changes(runId: String) async throws -> ChangeSummaryPayload {
        try await get(path: "api/app/changes", query: [URLQueryItem(name: "runId", value: runId)])
    }

    /// Fetch the nested file tree rooted at one agent worktree.
    func files(taskId: String, agentName: String, path: String?) async throws -> [FileTreeNodePayload] {
        let query = path.flatMap { $0.isEmpty ? nil : URLQueryItem(name: "path", value: $0) }.map { [$0] } ?? []
        return try await get(pathSegments: ["api", "app", "tasks", taskId, "files", agentName], query: query)
    }

    /// Fetch the nested file tree rooted at one concrete run worktree.
    func files(runId: String, path: String?) async throws -> [FileTreeNodePayload] {
        let query = [URLQueryItem(name: "runId", value: runId)] + (path.flatMap { $0.isEmpty ? nil : URLQueryItem(name: "path", value: $0) }.map { [$0] } ?? [])
        return try await get(path: "api/app/files", query: query)
    }

    /// Fetch ports exposed by the process attached to one agent run.
    func ports(taskId: String, agentName: String) async throws -> [PortEntryPayload] {
        try await get(pathSegments: ["api", "app", "tasks", taskId, "ports", agentName])
    }

    /// Fetch ports exposed by one concrete run process.
    func ports(runId: String) async throws -> [PortEntryPayload] {
        try await get(path: "api/app/ports", query: [URLQueryItem(name: "runId", value: runId)])
    }

    /// Register an existing local checkout with the desktop backend.
    func openRepository(path: String) async throws -> RepositoryRecord {
        try await post(path: "api/app/repositories/open", body: ["path": path])
    }

    /// Clone a remote repository into the app-managed storage area.
    func cloneRepository(url: String) async throws -> RepositoryRecord {
        try await post(path: "api/app/repositories/clone", body: ["url": url])
    }

    /// Create a workspace pinned to a specific repository/base-branch pair.
    func createWorkspace(repositoryId: String, name: String?, baseBranch: String?) async throws -> WorkspaceRecord {
        try await post(
            path: "api/app/workspaces",
            body: CreateWorkspacePayload(repositoryId: repositoryId, name: name, baseBranch: baseBranch)
        )
    }

    func updateWorkspaceBaseBranch(workspaceId: String, baseBranch: String) async throws -> WorkspaceRecord {
        try await patch(
            pathSegments: ["api", "app", "workspaces", workspaceId, "base-branch"],
            body: UpdateWorkspaceBaseBranchPayload(baseBranch: baseBranch)
        )
    }

    /// Create a new multi-agent task in the selected workspace.
    func createTask(workspaceId: String, title: String?, prompt: String, agents: [String]) async throws -> TaskRecord {
        try await post(
            path: "api/app/tasks",
            body: CreateTaskPayload(workspaceId: workspaceId, title: title, prompt: prompt, agents: agents, issueId: nil)
        )
    }

    func createGoal(companyId: String, title: String, description: String, successMetrics: [String] = [], autonomyEnabled: Bool = true) async throws -> GoalRecord {
        try await post(
            pathSegments: ["api", "app", "companies", companyId, "goals"],
            body: CreateGoalPayload(
                title: title,
                description: description,
                successMetrics: successMetrics,
                autonomyEnabled: autonomyEnabled
            )
        )
    }

    func createChatIntake(companyId: String, message: String, startRuntime: Bool = false) async throws -> ChatIntakeResponsePayload {
        try await post(
            pathSegments: ["api", "app", "companies", companyId, "chat-intake"],
            body: ChatIntakeRequestPayload(message: message, startRuntime: startRuntime)
        )
    }

    func runOperatorCommand(
        companyId: String,
        message: String,
        automationMode: String? = nil,
        confirmFullAuto: Bool = false,
        confirmStaffing: Bool = false
    ) async throws -> OperatorCommandResponsePayload {
        try await post(
            pathSegments: ["api", "app", "companies", companyId, "operator", "commands"],
            body: OperatorCommandRequestPayload(
                message: message,
                automationMode: automationMode,
                confirmFullAuto: confirmFullAuto,
                confirmStaffing: confirmStaffing
            )
        )
    }

    func runOperatorChat(
        companyId: String,
        message: String,
        automationMode: String? = nil,
        confirmFullAuto: Bool = false,
        confirmStaffing: Bool = false
    ) async throws -> OperatorChatResponsePayload {
        try await post(
            pathSegments: ["api", "app", "companies", companyId, "operator", "chat"],
            body: OperatorCommandRequestPayload(
                message: message,
                automationMode: automationMode,
                confirmFullAuto: confirmFullAuto,
                confirmStaffing: confirmStaffing
            )
        )
    }

    func skills() async throws -> [SkillCatalogEntryRecord] {
        try await get(path: "api/app/skills")
    }

    func directChatProviders() async throws -> [DirectChatProviderCatalogEntryRecord] {
        try await get(path: "api/app/direct-chat/providers")
    }

    func runSkill(
        name: String,
        companyId: String,
        agentId: String,
        input: String? = nil,
        parameters: [String: String] = [:]
    ) async throws -> SkillRunResultRecord {
        try await post(
            pathSegments: ["api", "app", "skills", name, "run"],
            body: SkillRunRequestPayload(
                companyId: companyId,
                agentId: agentId,
                input: input,
                parameters: parameters
            )
        )
    }

    func updateAgentCapabilities(
        companyId: String,
        agentId: String,
        settings: [String: AgentCapabilitySettingRecord]
    ) async throws -> AgentCapabilityProfileRecord {
        try await patch(
            pathSegments: ["api", "app", "companies", companyId, "agents", agentId, "capabilities"],
            body: UpdateAgentCapabilitiesPayload(settings: settings)
        )
    }

    func marketingPolicies(companyId: String? = nil, agentId: String? = nil) async throws -> [MarketingDelegationPolicyRecord] {
        var queryItems: [URLQueryItem] = []
        if let companyId, !companyId.isEmpty {
            queryItems.append(URLQueryItem(name: "companyId", value: companyId))
        }
        if let agentId, !agentId.isEmpty {
            queryItems.append(URLQueryItem(name: "agentId", value: agentId))
        }
        return try await get(path: "api/app/marketing/policies", query: queryItems)
    }

    func marketingRuns(companyId: String? = nil, agentId: String? = nil) async throws -> [MarketingRunRecord] {
        var queryItems: [URLQueryItem] = []
        if let companyId, !companyId.isEmpty {
            queryItems.append(URLQueryItem(name: "companyId", value: companyId))
        }
        if let agentId, !agentId.isEmpty {
            queryItems.append(URLQueryItem(name: "agentId", value: agentId))
        }
        return try await get(path: "api/app/marketing/runs", query: queryItems)
    }

    func upsertMarketingPolicy(_ payload: UpsertMarketingDelegationPolicyPayload) async throws -> MarketingDelegationPolicyRecord {
        if let id = payload.id, !id.isEmpty {
            return try await patch(pathSegments: ["api", "app", "marketing", "policies", id], body: payload)
        }
        return try await post(path: "api/app/marketing/policies", body: payload)
    }

    func updateGoal(
        companyId: String,
        goalId: String,
        title: String,
        description: String,
        successMetrics: [String] = [],
        autonomyEnabled: Bool = true
    ) async throws -> GoalRecord {
        try await patch(
            pathSegments: ["api", "app", "companies", companyId, "goals", goalId],
            body: UpdateGoalPayload(
                title: title,
                description: description,
                successMetrics: successMetrics,
                autonomyEnabled: autonomyEnabled
            )
        )
    }

    func deleteGoal(companyId: String, goalId: String) async throws -> GoalRecord {
        try await delete(pathSegments: ["api", "app", "companies", companyId, "goals", goalId])
    }

    func createCompany(
        name: String,
        rootPath: String,
        defaultBaseBranch: String?,
        dailyBudgetCents: Int?,
        monthlyBudgetCents: Int?
    ) async throws -> CreateCompanyResponsePayload {
        try await post(
            path: "api/app/companies",
            body: CreateCompanyPayload(
                name: name,
                rootPath: rootPath,
                defaultBaseBranch: defaultBaseBranch,
                autonomyEnabled: true,
                operatorAutomationMode: "FULL_AUTO",
                dailyBudgetCents: dailyBudgetCents,
                monthlyBudgetCents: monthlyBudgetCents
            )
        )
    }

    func updateCompany(
        companyId: String,
        name: String? = nil,
        defaultBaseBranch: String? = nil,
        autonomyEnabled: Bool? = nil,
        backendKind: String? = nil,
        dailyBudgetCents: Int? = nil,
        monthlyBudgetCents: Int? = nil
    ) async throws -> CompanyRecord {
        try await patch(
            pathSegments: ["api", "app", "companies", companyId],
            body: UpdateCompanyPayload(
                name: name,
                defaultBaseBranch: defaultBaseBranch,
                autonomyEnabled: autonomyEnabled,
                backendKind: backendKind,
                dailyBudgetCents: dailyBudgetCents,
                monthlyBudgetCents: monthlyBudgetCents
            )
        )
    }

    func updateBackendSettings(
        defaultBackendKind: String,
        codePublishMode: String,
        codexLaunchMode: String?,
        codexCommand: String?,
        codexArgs: [String],
        codexWorkingDirectory: String?,
        codexPort: Int?,
        codexStartupTimeoutSeconds: Int?,
        codexAppServerBaseURL: String?,
        codexAuthMode: String?,
        codexToken: String?,
        codexTimeoutSeconds: Int?
    ) async throws -> DesktopSettingsPayload {
        try await patch(
            path: "api/app/settings/backends/default",
            body: UpdateBackendSettingsPayload(
                defaultBackendKind: defaultBackendKind,
                codePublishMode: codePublishMode,
                codexLaunchMode: codexLaunchMode,
                codexCommand: codexCommand,
                codexArgs: codexArgs,
                codexWorkingDirectory: codexWorkingDirectory,
                codexPort: codexPort,
                codexStartupTimeoutSeconds: codexStartupTimeoutSeconds,
                codexAppServerBaseUrl: codexAppServerBaseURL,
                codexAuthMode: codexAuthMode,
                codexToken: codexToken,
                codexTimeoutSeconds: codexTimeoutSeconds
            )
        )
    }

    func testBackend(
        kind: String,
        launchMode: String?,
        command: String?,
        args: [String],
        workingDirectory: String?,
        port: Int?,
        startupTimeoutSeconds: Int?,
        baseURL: String?,
        authMode: String?,
        token: String?,
        timeoutSeconds: Int?
    ) async throws -> ExecutionBackendStatusPayload {
        try await post(
            path: "api/app/settings/backends/test",
            body: TestBackendPayload(
                kind: kind,
                launchMode: launchMode,
                command: command,
                args: args,
                workingDirectory: workingDirectory,
                port: port,
                startupTimeoutSeconds: startupTimeoutSeconds,
                baseUrl: baseURL,
                authMode: authMode,
                token: token,
                timeoutSeconds: timeoutSeconds
            )
        )
    }

    func updateCompanyBackend(
        companyId: String,
        backendKind: String,
        launchMode: String?,
        command: String?,
        args: [String],
        workingDirectory: String?,
        port: Int?,
        startupTimeoutSeconds: Int?,
        baseURL: String?,
        authMode: String?,
        token: String?,
        timeoutSeconds: Int?,
        useGlobalDefault: Bool
    ) async throws -> CompanyRecord {
        try await patch(
            pathSegments: ["api", "app", "companies", companyId, "backend"],
            body: UpdateCompanyBackendPayload(
                backendKind: backendKind,
                launchMode: launchMode,
                command: command,
                args: args,
                workingDirectory: workingDirectory,
                port: port,
                startupTimeoutSeconds: startupTimeoutSeconds,
                baseUrl: baseURL,
                authMode: authMode,
                token: token,
                timeoutSeconds: timeoutSeconds,
                useGlobalDefault: useGlobalDefault
            )
        )
    }

    func companyBackendStatus(companyId: String) async throws -> ExecutionBackendStatusPayload {
        try await get(pathSegments: ["api", "app", "companies", companyId, "backend"])
    }

    func startCompanyBackend(companyId: String) async throws -> ExecutionBackendStatusPayload {
        try await post(pathSegments: ["api", "app", "companies", companyId, "backend", "start"], body: EmptyPayload())
    }

    func stopCompanyBackend(companyId: String) async throws -> ExecutionBackendStatusPayload {
        try await post(pathSegments: ["api", "app", "companies", companyId, "backend", "stop"], body: EmptyPayload())
    }

    func restartCompanyBackend(companyId: String) async throws -> ExecutionBackendStatusPayload {
        try await post(pathSegments: ["api", "app", "companies", companyId, "backend", "restart"], body: EmptyPayload())
    }

    func updateCompanyLinear(
        companyId: String,
        enabled: Bool,
        endpoint: String?,
        apiToken: String?,
        teamId: String?,
        projectId: String?,
        useGlobalDefault: Bool
    ) async throws -> CompanyRecord {
        try await patch(
            pathSegments: ["api", "app", "companies", companyId, "linear"],
            body: UpdateCompanyLinearPayload(
                enabled: enabled,
                endpoint: endpoint,
                apiToken: apiToken,
                teamId: teamId,
                projectId: projectId,
                stateMappings: nil,
                useGlobalDefault: useGlobalDefault
            )
        )
    }

    func resyncCompanyLinear(companyId: String) async throws -> LinearSyncResponsePayload {
        try await post(pathSegments: ["api", "app", "companies", companyId, "linear", "resync"], body: EmptyPayload())
    }

    func deleteCompany(companyId: String) async throws -> CompanyRecord {
        try await delete(pathSegments: ["api", "app", "companies", companyId])
    }

    func createIssue(
        companyId: String,
        goalId: String,
        title: String,
        description: String,
        priority: Int = 3,
        kind: String = "manual"
    ) async throws -> IssueRecord {
        try await post(
            pathSegments: ["api", "app", "companies", companyId, "issues"],
            body: CreateIssuePayload(
                goalId: goalId,
                title: title,
                description: description,
                priority: priority,
                kind: kind
            )
        )
    }

    func decomposeGoal(goalId: String) async throws -> [IssueRecord] {
        try await post(pathSegments: ["api", "app", "goals", goalId, "decompose"], body: EmptyPayload())
    }

    func deleteIssue(companyId: String, issueId: String) async throws -> IssueRecord {
        try await delete(pathSegments: ["api", "app", "companies", companyId, "issues", issueId])
    }

    func createCompanyAgent(
        companyId: String,
        title: String,
        agentCli: String,
        model: String?,
        roleSummary: String,
        specialties: [String],
        collaborationInstructions: String?,
        preferredCollaboratorIds: [String],
        mentorAgentId: String?,
        memoryNotes: String?,
        enabled: Bool = true
    ) async throws -> CompanyAgentDefinitionRecord {
        try await post(
            pathSegments: ["api", "app", "companies", companyId, "agents"],
            body: CreateCompanyAgentPayload(
                title: title,
                agentCli: agentCli,
                model: model,
                roleSummary: roleSummary,
                specialties: specialties,
                collaborationInstructions: collaborationInstructions,
                preferredCollaboratorIds: preferredCollaboratorIds,
                mentorAgentId: mentorAgentId,
                memoryNotes: memoryNotes,
                enabled: enabled
            )
        )
    }

    func updateCompanyAgent(
        companyId: String,
        agentId: String,
        title: String,
        agentCli: String,
        model: String?,
        roleSummary: String,
        specialties: [String],
        collaborationInstructions: String?,
        preferredCollaboratorIds: [String],
        mentorAgentId: String?,
        memoryNotes: String?,
        enabled: Bool
    ) async throws -> CompanyAgentDefinitionRecord {
        try await patch(
            pathSegments: ["api", "app", "companies", companyId, "agents", agentId],
            body: UpdateCompanyAgentPayload(
                title: title,
                agentCli: agentCli,
                model: model,
                roleSummary: roleSummary,
                specialties: specialties,
                collaborationInstructions: collaborationInstructions,
                preferredCollaboratorIds: preferredCollaboratorIds,
                mentorAgentId: mentorAgentId,
                memoryNotes: memoryNotes,
                enabled: enabled,
                displayOrder: nil
            )
        )
    }

    func batchUpdateCompanyAgents(
        companyId: String,
        agentIds: [String],
        agentCli: String?,
        model: String?,
        specialties: [String]?,
        enabled: Bool?
    ) async throws -> [CompanyAgentDefinitionRecord] {
        try await patch(
            pathSegments: ["api", "app", "companies", companyId, "agents", "batch"],
            body: BatchUpdateCompanyAgentsPayload(
                agentIds: agentIds,
                agentCli: agentCli,
                model: model,
                specialties: specialties,
                enabled: enabled
            )
        )
    }

    func startCompanyRuntime(companyId: String) async throws -> CompanyRuntimeSnapshotRecord {
        try await post(pathSegments: ["api", "app", "companies", companyId, "runtime", "start"], body: EmptyPayload())
    }

    func stopCompanyRuntime(companyId: String) async throws -> CompanyRuntimeSnapshotRecord {
        try await post(pathSegments: ["api", "app", "companies", companyId, "runtime", "stop"], body: EmptyPayload())
    }

    func runIssue(issueId: String) async throws -> IssueRecord {
        try await post(pathSegments: ["api", "app", "issues", issueId, "run"], body: EmptyPayload())
    }

    func delegateIssue(issueId: String) async throws -> IssueRecord {
        try await post(pathSegments: ["api", "app", "issues", issueId, "delegate"], body: EmptyPayload())
    }

    func submitQaReviewVerdict(itemId: String, verdict: String, feedback: String?) async throws -> ReviewQueueItemRecord {
        try await post(
            pathSegments: ["api", "app", "review-queue", itemId, "qa"],
            body: ReviewQueueVerdictPayload(verdict: verdict, feedback: feedback)
        )
    }

    func submitCeoReviewVerdict(itemId: String, verdict: String, feedback: String?) async throws -> ReviewQueueItemRecord {
        try await post(
            pathSegments: ["api", "app", "review-queue", itemId, "ceo"],
            body: ReviewQueueVerdictPayload(verdict: verdict, feedback: feedback)
        )
    }

    func mergeReviewQueueItem(itemId: String) async throws -> ReviewQueueItemRecord {
        try await post(pathSegments: ["api", "app", "review-queue", itemId, "merge"], body: EmptyPayload())
    }

    /// Ask the backend to start executing an already-created task.
    func runTask(taskId: String) async throws -> TaskRecord {
        try await post(pathSegments: ["api", "app", "tasks", taskId, "run"], body: EmptyPayload())
    }

    /// Open or reuse the interactive TUI session for one workspace.
    func openTuiSession(workspaceId: String, preferredAgent: String?) async throws -> TuiSessionRecord {
        try await post(
            path: "api/app/tui/sessions",
            body: OpenTuiSessionPayload(workspaceId: workspaceId, preferredAgent: preferredAgent)
        )
    }

    /// List every active TUI session so the desktop shell can switch between
    /// multiple folder-backed terminals without relying on company state.
    func listTuiSessions() async throws -> [TuiSessionRecord] {
        try await get(path: "api/app/tui/sessions")
    }

    /// Fetch the latest rolling transcript for an active TUI session.
    func tuiSession(sessionId: String) async throws -> TuiSessionRecord {
        try await get(pathSegments: ["api", "app", "tui", "sessions", sessionId])
    }

    /// Fetch only the terminal bytes appended after the provided cursor.
    func tuiDelta(sessionId: String, offset: Int64) async throws -> TuiSessionDeltaPayload {
        try await get(
            pathSegments: ["api", "app", "tui", "sessions", sessionId, "delta"],
            query: [URLQueryItem(name: "offset", value: String(offset))]
        )
    }

    /// Forward raw terminal input into the running TUI process.
    func sendTuiInput(sessionId: String, input: String) async throws -> TuiSessionRecord {
        try await post(pathSegments: ["api", "app", "tui", "sessions", sessionId, "input"], body: TuiInputPayload(input: input))
    }

    /// Gracefully stop the TUI session when the user wants a fresh start.
    func terminateTuiSession(sessionId: String) async throws -> TuiSessionRecord {
        try await post(pathSegments: ["api", "app", "tui", "sessions", sessionId, "terminate"], body: EmptyPayload())
    }

    func companyEvents(companyId: String, cursor: String? = nil) -> AsyncThrowingStream<CompanyEventEnvelopePayload, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var queryItems: [URLQueryItem] = []
                    if let cursor, !cursor.isEmpty {
                        queryItems.append(URLQueryItem(name: "cursor", value: cursor))
                    }
                    var request = URLRequest(
                        url: try makeURL(
                            pathSegments: ["api", "app", "companies", companyId, "events"],
                            query: queryItems
                        )
                    )
                    request.httpMethod = "GET"
                    addHeaders(to: &request)
                    if let cursor, !cursor.isEmpty {
                        request.setValue(cursor, forHTTPHeaderField: "Last-Event-ID")
                    }
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                        throw URLError(.badServerResponse)
                    }
                    for try await line in bytes.lines {
                        if let envelope = Self.decodeCompanyEventLine(line) {
                            continuation.yield(envelope)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func get<T: Decodable>(path: String, query: [URLQueryItem] = []) async throws -> T {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = "GET"
        addHeaders(to: &request)
        return try await decode(request)
    }

    private func get<T: Decodable>(pathSegments: [String], query: [URLQueryItem] = []) async throws -> T {
        var request = URLRequest(url: try makeURL(pathSegments: pathSegments, query: query))
        request.httpMethod = "GET"
        addHeaders(to: &request)
        return try await decode(request)
    }

    private func post<T: Decodable, Body: Encodable>(path: String, body: Body) async throws -> T {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        addHeaders(to: &request)
        return try await decode(request)
    }

    private func post<T: Decodable, Body: Encodable>(pathSegments: [String], body: Body) async throws -> T {
        var request = URLRequest(url: try makeURL(pathSegments: pathSegments))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        addHeaders(to: &request)
        return try await decode(request)
    }

    private func patch<T: Decodable, Body: Encodable>(path: String, body: Body) async throws -> T {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "PATCH"
        request.httpBody = try JSONEncoder().encode(body)
        addHeaders(to: &request)
        return try await decode(request)
    }

    private func patch<T: Decodable, Body: Encodable>(pathSegments: [String], body: Body) async throws -> T {
        var request = URLRequest(url: try makeURL(pathSegments: pathSegments))
        request.httpMethod = "PATCH"
        request.httpBody = try JSONEncoder().encode(body)
        addHeaders(to: &request)
        return try await decode(request)
    }

    private func delete<T: Decodable>(path: String) async throws -> T {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "DELETE"
        addHeaders(to: &request)
        return try await decode(request)
    }

    private func delete<T: Decodable>(pathSegments: [String]) async throws -> T {
        var request = URLRequest(url: try makeURL(pathSegments: pathSegments))
        request.httpMethod = "DELETE"
        addHeaders(to: &request)
        return try await decode(request)
    }

    private func makeURL(path: String, query: [URLQueryItem] = []) throws -> URL {
        try Self.makeURL(baseURL: baseURL, path: path, query: query)
    }

    internal func makeURL(pathSegments: [String], query: [URLQueryItem] = []) throws -> URL {
        try Self.makeURL(baseURL: baseURL, pathSegments: pathSegments, query: query)
    }

    internal static func makeURL(baseURL: URL, path: String, query: [URLQueryItem] = []) throws -> URL {
        try makeURL(baseURL: baseURL, pathSegments: path.split(separator: "/").map(String.init), query: query)
    }

    internal static func makeURL(baseURL: URL, pathSegments: [String], query: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let routePath = try pathSegments
            .map(Self.percentEncodePathSegment)
            .joined(separator: "/")
        let joinedPath = [basePath, routePath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components?.percentEncodedPath = joinedPath.isEmpty ? "/" : "/\(joinedPath)"
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        return url
    }

    private static func percentEncodePathSegment(_ segment: String) throws -> String {
        guard let encoded = segment.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) else {
            throw URLError(.badURL)
        }
        return encoded
    }

    private static let pathSegmentAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%\\")
        return allowed
    }()

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        // Bubble server error bodies up to the UI because the desktop app is mostly
        // an orchestration shell and the backend already knows the relevant failure reason.
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "Unknown server error")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func addHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    // MARK: - Direct Chat API

    func listDirectChatConversations(companyId: String) async throws -> [DirectChatConversation] {
        try await get(pathSegments: ["api", "app", "companies", companyId, "direct-chat", "conversations"])
    }

    func createDirectChatConversation(
        companyId: String,
        title: String,
        model: String,
        provider: String,
        baseUrl: String = "",
        systemPrompt: String = ""
    ) async throws -> DirectChatConversation {
        struct Body: Encodable {
            let title: String
            let model: String
            let provider: String
            let baseUrl: String
            let systemPrompt: String
        }
        return try await post(
            pathSegments: ["api", "app", "companies", companyId, "direct-chat", "conversations"],
            body: Body(title: title, model: model, provider: provider, baseUrl: baseUrl, systemPrompt: systemPrompt)
        )
    }

    func deleteDirectChatConversation(conversationId: String, companyId: String) async throws {
        let _: EmptyPayload = try await delete(
            pathSegments: ["api", "app", "companies", companyId, "direct-chat", "conversations", conversationId]
        )
    }

    func listDirectChatModels(companyId: String, baseUrl: String = "http://127.0.0.1:11434") async throws -> [DirectChatAvailableModel] {
        try await get(
            pathSegments: ["api", "app", "companies", companyId, "direct-chat", "models"],
            query: [URLQueryItem(name: "baseUrl", value: baseUrl)]
        )
    }

    func streamDirectChatMessage(
        companyId: String,
        conversationId: String,
        message: String
    ) -> AsyncThrowingStream<DirectChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = try? makeURL(
                        pathSegments: ["api", "app", "companies", companyId, "direct-chat", "conversations", conversationId, "messages"]
                    ) else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    addHeaders(to: &request)
                    request.httpBody = try JSONEncoder().encode(["message": message])

                    let (bytes, response) = try await session.bytes(for: request)
                    if let httpResponse = response as? HTTPURLResponse,
                       !(200...299).contains(httpResponse.statusCode) {
                        continuation.finish(throwing: URLError(.badServerResponse))
                        return
                    }
                    var lineBuffer = Data()
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if byte == 0x0A {  // newline byte
                            if let line = String(data: lineBuffer, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                               !line.isEmpty,
                               let data = line.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(DirectChatStreamChunk.self, from: data) {
                                continuation.yield(chunk)
                                if chunk.done { break }
                            }
                            lineBuffer = Data()
                        } else {
                            lineBuffer.append(byte)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private struct EmptyPayload: Codable {}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private struct ConfigureGitHubOriginPayload: Codable {
    let remoteUrl: String
}

private struct UpdateBackendSettingsPayload: Codable {
    let defaultBackendKind: String
    let codePublishMode: String
    let codexLaunchMode: String?
    let codexCommand: String?
    let codexArgs: [String]
    let codexWorkingDirectory: String?
    let codexPort: Int?
    let codexStartupTimeoutSeconds: Int?
    let codexAppServerBaseUrl: String?
    let codexAuthMode: String?
    let codexToken: String?
    let codexTimeoutSeconds: Int?
}

private struct TestBackendPayload: Codable {
    let kind: String
    let launchMode: String?
    let command: String?
    let args: [String]
    let workingDirectory: String?
    let port: Int?
    let startupTimeoutSeconds: Int?
    let baseUrl: String?
    let authMode: String?
    let token: String?
    let timeoutSeconds: Int?
}

private struct UpdateCompanyBackendPayload: Codable {
    let backendKind: String
    let launchMode: String?
    let command: String?
    let args: [String]
    let workingDirectory: String?
    let port: Int?
    let startupTimeoutSeconds: Int?
    let baseUrl: String?
    let authMode: String?
    let token: String?
    let timeoutSeconds: Int?
    let useGlobalDefault: Bool
}

enum APIError: LocalizedError {
    case http(Int, String)

    var statusCode: Int {
        switch self {
        case let .http(code, _):
            return code
        }
    }

    var responseBody: String {
        switch self {
        case let .http(_, message):
            return message
        }
    }

    var errorDescription: String? {
        switch self {
        case let .http(code, message):
            return "Server returned \(code): \(message)"
        }
    }
}
