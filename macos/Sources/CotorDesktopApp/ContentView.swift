import AppKit
import SwiftUI


// MARK: - File Overview
// CotorDesktopApp belongs to the native macOS client layer for the Cotor desktop application.
// It collects declarations centered on content view so the native shell code stays easier to navigate.
// Start with this file when tracing how the desktop client presents, stores, or moves state in this area.

private enum DesktopLayoutMode {
    case wide
    case stacked
    case compact

    init(width: CGFloat) {
        switch width {
        case ..<860:
            self = .compact
        case ..<1360:
            self = .stacked
        default:
            self = .wide
        }
    }
}

enum CompactSurface: CaseIterable, Identifiable {
    case workspace
    case console
    case inspector

    var id: String {
        switch self {
        case .workspace:
            return "workspace"
        case .console:
            return "console"
        case .inspector:
            return "inspector"
        }
    }
}

private enum GoalSurface: CaseIterable, Identifiable {
    case board
    case canvas

    var id: String {
        switch self {
        case .board:
            return "board"
        case .canvas:
            return "canvas"
        }
    }
}

private enum CompanySidebarSurface: CaseIterable, Identifiable {
    case company
    case room
    case chat
    case goals
    case performance
    case reports
    case agents
    case issues

    var id: String {
        switch self {
        case .company:
            return "company"
        case .room:
            return "room"
        case .chat:
            return "chat"
        case .goals:
            return "goals"
        case .performance:
            return "performance"
        case .reports:
            return "reports"
        case .agents:
            return "agents"
        case .issues:
            return "issues"
        }
    }
}

private enum CompanyOverviewSurface: CaseIterable, Identifiable {
    case summary
    case meetingRoom

    var id: String {
        switch self {
        case .summary:
            return "summary"
        case .meetingRoom:
            return "meeting-room"
        }
    }
}

private enum MeetingRoomSurface: CaseIterable, Identifiable {
    case map
    case meeting
    case floor

    var id: String {
        switch self {
        case .map:
            return "map"
        case .meeting:
            return "meeting"
        case .floor:
            return "floor"
        }
    }
}

struct CompanySidebarDisclosureState {
    var isCompanyDraftExpanded = false
    var isAdvancedSettingsExpanded = false
    var isAgentAdvancedDetailsExpanded = false
}

private enum CompanyConversationHistoryItem: Identifiable {
    case activity(CompanyActivityItemRecord)
    case message(AgentMessageRecord)
    case context(AgentContextEntryRecord)

    var id: String {
        switch self {
        case let .activity(item):
            return "activity-\(item.id)"
        case let .message(message):
            return "message-\(message.id)"
        case let .context(entry):
            return "context-\(entry.id)"
        }
    }

    var createdAt: Int64 {
        switch self {
        case let .activity(item):
            return item.createdAt
        case let .message(message):
            return message.createdAt
        case let .context(entry):
            return entry.createdAt
        }
    }
}

private struct MeetingRoomSyntheticEvent: Identifiable {
    let id: String
    let createdAt: Int64
    let eyebrow: String
    let title: String
    let detail: String
    let tint: Color
}

private enum MeetingRoomWallItem: Identifiable {
    case activity(CompanyActivityItemRecord)
    case message(AgentMessageRecord)
    case context(AgentContextEntryRecord)
    case synthetic(MeetingRoomSyntheticEvent)

    var id: String {
        switch self {
        case let .activity(item):
            return "activity-\(item.id)"
        case let .message(message):
            return "message-\(message.id)"
        case let .context(entry):
            return "context-\(entry.id)"
        case let .synthetic(event):
            return "synthetic-\(event.id)"
        }
    }

    var createdAt: Int64 {
        switch self {
        case let .activity(item):
            return item.createdAt
        case let .message(message):
            return message.createdAt
        case let .context(entry):
            return entry.createdAt
        case let .synthetic(event):
            return event.createdAt
        }
    }
}

@main
struct CotorDesktopApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(DesktopAppLifecycleDelegate.self) private var appDelegate
    @StateObject private var store = DesktopStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 920, minHeight: 700)
                .preferredColorScheme(store.theme.colorScheme)
                .task {
                    await store.bootstrap()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await store.bootstrap()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1480, height: 920)
        .commands {
            DesktopCommandMenu(store: store)
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 720, height: 560)
        }
    }
}

final class DesktopAppLifecycleDelegate: NSObject, NSApplicationDelegate {
    private var terminationInFlight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await EmbeddedBackendLauncher.shared.ensureRunning()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task {
            await EmbeddedBackendLauncher.shared.ensureRunning()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationInFlight {
            return .terminateLater
        }
        terminationInFlight = true
        AppLogger.info("App termination requested.")
        Task {
            _ = await EmbeddedBackendLauncher.shared.stop(timeoutSeconds: 5)
            await MainActor.run {
                sender.reply(toApplicationShouldTerminate: true)
                self.terminationInFlight = false
            }
        }
        return .terminateLater
    }
}

/// Adaptive desktop shell with a dense admin-console layout: compact sidebar,
/// session strip, TUI-first center workspace, and an optional bottom drawer.
struct ContentView: View {
    @EnvironmentObject private var store: DesktopStore
    @State private var compactSurface: CompactSurface = .console
    @State private var companySurface: CompanySidebarSurface = .company
    @State private var searchText = ""

    private var l: AppLanguage { store.language }

    var body: some View {
        GeometryReader { geometry in
            let layoutMode = DesktopLayoutMode(width: geometry.size.width)

            ZStack {
                ShellCanvas()
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    DesktopTopBar(searchText: $searchText)

                    shell(for: layoutMode, size: geometry.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(12)
            }
        }
        .sheet(isPresented: $store.showingCloneSheet) {
            CloneRepositorySheet()
        }
        .alert(l.text(.requestFailed), isPresented: Binding(
            get: { store.actionErrorMessage != nil },
            set: {
                if !$0 {
                    store.actionErrorMessage = nil
                    store.errorMessage = nil
                }
            }
        )) {
            Button(l.text(.close), role: .cancel) {}
        } message: {
            Text(store.actionErrorMessage ?? "")
        }
        .animation(ShellMotion.spring, value: store.selectedGoalID)
        .animation(ShellMotion.spring, value: store.selectedIssueID)
        .animation(ShellMotion.spring, value: store.selectedRepositoryID)
        .animation(ShellMotion.spring, value: store.selectedWorkspaceID)
        .animation(ShellMotion.spring, value: store.selectedTaskID)
        .animation(ShellMotion.spring, value: store.selectedAgentName)
        .animation(ShellMotion.spring, value: store.inspectorTab)
    }

    @ViewBuilder
    private func shell(for layoutMode: DesktopLayoutMode, size: CGSize) -> some View {
        switch layoutMode {
        case .wide:
            if store.shellMode == .company {
                unifiedCompanyShell(layoutMode: layoutMode, sidebarWidth: ShellMetrics.sidebarIdealWidth)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    SidebarView(searchText: searchText, companySurface: $companySurface)
                        .frame(width: ShellMetrics.sidebarIdealWidth)
                        .frame(maxHeight: .infinity)

                    CenterPaneView(layoutMode: layoutMode, searchText: searchText, companySurface: $companySurface)
                        .frame(minWidth: ShellMetrics.contentMinWidth, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        case .stacked:
            if store.shellMode == .company {
                unifiedCompanyShell(layoutMode: layoutMode, sidebarWidth: 286)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    SidebarView(searchText: searchText, companySurface: $companySurface)
                        .frame(width: 286)
                        .frame(maxHeight: .infinity)

                    CenterPaneView(layoutMode: layoutMode, searchText: searchText, companySurface: $companySurface)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        case .compact:
            VStack(spacing: 12) {
                compactHeader

                Picker(l.text(.surface), selection: $compactSurface) {
                    ForEach(CompactSurface.allCases) { surface in
                        Text(l.compactSurface(surface)).tag(surface)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    switch compactSurface {
                    case .workspace:
                        SidebarView(searchText: searchText, companySurface: $companySurface)
                    case .console:
                        CenterPaneView(layoutMode: layoutMode, searchText: searchText, companySurface: $companySurface)
                    case .inspector:
                        InspectorPaneView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "hexagon.lefthalf.filled")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ShellPalette.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text(l.text(.appName))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                Text(store.statusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(store.isOffline ? ShellPalette.warning : ShellPalette.muted)
                    .lineLimit(1)
            }

            Spacer()

            ShellStatusPill(
                text: store.isOffline ? l.text(.offlinePreview) : l.text(.liveLocalSession),
                tint: store.isOffline ? ShellPalette.warning : ShellPalette.success
            )
        }
        .padding(14)
        .shellCard()
    }

    private func unifiedCompanyShell(layoutMode: DesktopLayoutMode, sidebarWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SidebarView(searchText: searchText, companySurface: $companySurface)
                .frame(width: sidebarWidth, alignment: .top)
                .frame(maxHeight: .infinity)

            CenterPaneView(
                layoutMode: layoutMode,
                searchText: searchText,
                companySurface: $companySurface
            )
            .frame(minWidth: layoutMode == .wide ? ShellMetrics.contentMinWidth : 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.trailing, 2)
    }
}

private struct DesktopTopBar: View {
    @EnvironmentObject private var store: DesktopStore
    @Binding var searchText: String
    private var l: AppLanguage { store.language }
    private var shellModeBinding: Binding<AppShellMode> {
        Binding(
            get: { store.shellMode },
            set: { store.setShellMode($0) }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Menu {
                    Picker(l("Shell Mode", "셸 모드"), selection: shellModeBinding) {
                        Text(l("Company", "회사")).tag(AppShellMode.company)
                        Text(l("TUI", "TUI")).tag(AppShellMode.tui)
                    }

                    Divider()

                    Menu(l("Language", "언어")) {
                        ForEach(AppLanguage.allCases) { language in
                            Button(language.displayName) {
                                store.setLanguage(language)
                            }
                        }
                    }

                    Menu(l("Appearance", "화면 모드")) {
                        ForEach(AppTheme.allCases) { theme in
                            Button(theme.label(l)) {
                                store.setTheme(theme)
                            }
                        }
                    }

                    Divider()

                    Button {
                        Task { await store.refreshDashboard() }
                    } label: {
                        Label(l("Refresh", "새로고침"), systemImage: "arrow.clockwise")
                    }

                    Button {
                        store.openSettings()
                    } label: {
                        Label(l("Settings", "설정"), systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(ShellPalette.panelAlt)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(ShellPalette.line, lineWidth: 1)
                        )
                }
                .menuStyle(.borderlessButton)
                .frame(width: 34, height: 34, alignment: .center)

                CotorBrandLogo(size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cotor")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                        .lineLimit(1)
                    Text(topBarSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(height: 34, alignment: .center)
            }
            .frame(minWidth: 218, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ShellPalette.muted)
                TextField(l("Search goals, issues, or runs", "목표, 이슈, 실행 검색"), text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(ShellPalette.text)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(ShellPalette.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ShellPalette.panelAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(ShellPalette.line, lineWidth: 1)
            )

            if store.shellMode == .company, let company = store.selectedCompany {
                ShellTag(text: company.name, tint: ShellPalette.accent)
            } else if let workspace = store.selectedWorkspace {
                ShellTag(text: workspace.baseBranch, tint: ShellPalette.accent)
            }

            ShellStatusPill(
                text: store.isOffline ? l.text(.offlinePreview) : l.text(.connected),
                tint: store.isOffline ? ShellPalette.warning : ShellPalette.success
            )

            CompactLanguagePicker()

            CompactThemePicker()

            Button {
                Task { await store.openHelpGuide() }
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(ShellTopBarButtonStyle(prominent: false))
            .popover(isPresented: $store.showingHelpGuide, arrowEdge: .top) {
                DesktopHelpGuideSheet()
                    .environmentObject(store)
            }

            if store.shellMode == .tui {
                Button {
                    Task { await store.runSelectedTask() }
                } label: {
                    Label(l.text(.runSelectedTask), systemImage: "play.fill")
                }
                .buttonStyle(ShellTopBarButtonStyle(prominent: true))
                .disabled(store.selectedTask == nil)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                .fill(ShellPalette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
    }

    private var topBarSubtitle: String {
        switch store.shellMode {
        case .company:
            return store.selectedGoal?.title ?? store.selectedCompany?.name ?? l("Autonomous company console", "자율 운영 회사 콘솔")
        case .tui:
            return store.selectedWorkspace?.name ?? store.selectedRepository?.name ?? l("Workspace TUI", "워크스페이스 TUI")
        }
    }
}

private struct CotorBrandLogo: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = Self.logoImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                fallbackMark
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .stroke(ShellPalette.lineStrong.opacity(0.75), lineWidth: 1)
        )
        .accessibilityLabel("Cotor")
    }

    private var fallbackMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(ShellPalette.panelRaised)
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundStyle(ShellPalette.accent)
                .frame(width: size, height: size)
        }
    }

    private static let logoImage: NSImage? = {
        guard let url = Bundle.module.url(
            forResource: "CotorHeaderMark",
            withExtension: "png",
            subdirectory: "Brand"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}

private struct SidebarView: View {
    @EnvironmentObject private var store: DesktopStore
    let searchText: String
    @Binding var companySurface: CompanySidebarSurface
    var scrollsInternally: Bool = true
    @State private var companySidebarDisclosureState = CompanySidebarDisclosureState()
    @State private var dismissedGitHubConnectCompanyID: String?
    private var l: AppLanguage { store.language }

    private var filteredGoals: [GoalRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.goals
        guard !query.isEmpty else { return base }
        return base.filter {
            matches(query: query, values: [$0.title, $0.description, $0.status, $0.successMetrics.joined(separator: " ")])
        }
    }

    private var filteredIssues: [IssueRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.issues
        guard !query.isEmpty else { return base }
        return base.filter {
            matches(query: query, values: [$0.title, $0.description, $0.status, $0.kind, $0.acceptanceCriteria.joined(separator: " ")])
        }
    }

    private var filteredRepositories: [RepositoryRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.repositories }

        return store.repositories.filter {
            matches(query: query, values: [
                $0.name,
                $0.localPath,
                $0.defaultBranch,
                $0.remoteUrl,
            ])
        }
    }

    private var filteredTasks: [TaskRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.tasks
        guard !query.isEmpty else { return base }

        return base.filter {
            matches(query: query, values: [
                $0.title,
                $0.prompt,
                $0.status,
                $0.agents.joined(separator: " "),
            ])
        }
    }

    var body: some View {
        Group {
            if scrollsInternally {
                ScrollView {
                    sidebarContent
                }
                .scrollIndicators(.hidden)
            } else {
                sidebarContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .shellCard()
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch store.shellMode {
            case .company:
                companySidebar
            case .tui:
                tuiSidebar
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var companySidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            sidebarHeader
            companySidebarNavigation

            switch companySurface {
            case .company:
                companySection
            case .room:
                companySection
            case .chat:
                companySection
            case .goals:
                VStack(alignment: .leading, spacing: 14) {
                    goalSection
                    goalComposer
                }
            case .performance:
                companySection
            case .reports:
                companySection
            case .agents:
                VStack(alignment: .leading, spacing: 14) {
                    rosterSection
                    companyAgentComposer
                }
            case .issues:
                issueSection
            }
        }
    }

    private var tuiSidebar: some View {
        Group {
            tuiSidebarHeader
            tuiSessionSection
            workspaceSection
            tuiLaunchSection
        }
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l("Company Console", "회사 콘솔"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                }
                Spacer()
                Button {
                    Task { await store.refreshDashboard() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                        .padding(9)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(ShellPalette.panelAlt)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(ShellPalette.line, lineWidth: 1)
                )
            }
        }
    }

    private var companySidebarNavigation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l("Navigate", "탐색"))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(ShellPalette.faint)
                .tracking(0.7)

            VStack(spacing: 8) {
                companyNavButton(
                    .company,
                    title: l("Company", "회사"),
                    subtitle: l("Folder, runtime, and overview", "폴더, 런타임, 개요"),
                    systemImage: "building.2",
                    badge: nil
                )
                companyNavButton(
                    .room,
                    title: l("Meeting Room", "미팅룸"),
                    subtitle: l("Live status and map", "실시간 현황과 지도"),
                    systemImage: "person.2.wave.2",
                    badge: "\(store.dashboard.runningAgentSessions.count)"
                )
                companyNavButton(
                    .chat,
                    title: l("Company Operator", "운영 채팅"),
                    subtitle: l("Agent chat and approvals", "에이전트 대화와 승인"),
                    systemImage: "bubble.left.and.text.bubble.right",
                    badge: "\(store.dashboard.agentMessages.count)"
                )
                companyNavButton(
                    .goals,
                    title: l("Goals", "목표"),
                    subtitle: l("Goals and creation", "목표 보기와 생성"),
                    systemImage: "flag.2.crossed",
                    badge: "\(store.goals.count)"
                )
                companyNavButton(
                    .performance,
                    title: l("Performance", "인사평가"),
                    subtitle: l("Scoreable agent signals", "에이전트 성과 지표"),
                    systemImage: "chart.line.uptrend.xyaxis",
                    badge: "\(store.scoreableAgentPerformanceCount)"
                )
                companyNavButton(
                    .reports,
                    title: l("Reports", "보고서"),
                    subtitle: l("Daily operating brief", "하루 운영 요약"),
                    systemImage: "doc.text.magnifyingglass",
                    badge: "\(store.selectedCompanyReports.count)"
                )
                companyNavButton(
                    .agents,
                    title: l("Team", "팀"),
                    subtitle: l("Team and assigned work", "팀과 담당 이슈"),
                    systemImage: "person.3.sequence",
                    badge: "\(store.companyAgentDefinitions.count)"
                )
                companyNavButton(
                    .issues,
                    title: l("Issues", "이슈"),
                    subtitle: l("Board and execution state", "보드와 실행 상태"),
                    systemImage: "square.stack.3d.down.right",
                    badge: "\(store.issues.count)"
                )
            }
        }
    }

    private func companyNavButton(
        _ surface: CompanySidebarSurface,
        title: String,
        subtitle: String,
        systemImage: String,
        badge: String?
    ) -> some View {
        Button {
            companySurface = surface
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(companySurface == surface ? ShellPalette.accentSoft : ShellPalette.panel)
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(companySurface == surface ? ShellPalette.accent : ShellPalette.muted)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if let badge, !badge.isEmpty, badge != "0" {
                    ShellTag(text: badge, tint: companySurface == surface ? ShellPalette.accentWarm : ShellPalette.panelRaised)
                }
            }
            .foregroundStyle(companySurface == surface ? ShellPalette.text : ShellPalette.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(companySurface == surface ? ShellPalette.panelRaised : ShellPalette.panelAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(companySurface == surface ? ShellPalette.lineStrong : ShellPalette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityIdentifier("company-nav-\(surface.id)")
    }

    private var tuiSidebarHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l("Interactive TUI", "대화형 TUI"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                    Text(l("Open folder-backed Cotor terminals and switch between active sessions.", "폴더별 Cotor 터미널을 열고 실행 중인 세션을 전환합니다."))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    Task { await store.openRepositoryPicker() }
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                        .padding(9)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(ShellPalette.panelAlt)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(ShellPalette.line, lineWidth: 1)
                )
                Button {
                    Task { await store.refreshDashboard() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                        .padding(9)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(ShellPalette.panelAlt)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(ShellPalette.line, lineWidth: 1)
                )
            }

        }
    }

    private var tuiSessionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(
                title: l("Live Sessions", "열린 세션"),
                subtitle: l("Folder-backed terminals", "폴더별 터미널 세션")
            )

            if store.tuiSessions.isEmpty {
                EmptyStateView(
                    image: "terminal",
                    title: l("No live sessions yet", "아직 열린 세션이 없습니다"),
                    subtitle: l("Open a folder to start a terminal session.", "폴더를 열어 터미널 세션을 시작하세요.")
                )
                .frame(height: 180)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.tuiSessions) { session in
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                Task { await store.selectTuiSession(session) }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 8) {
                                        Text(tuiSessionTitle(session))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(ShellPalette.text)
                                            .lineLimit(1)
                                        ShellStatusPill(text: l.status(session.status), tint: tuiStatusTint(session.status))
                                    }
                                    Text(session.repositoryPath)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(ShellPalette.muted)
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        ShellTag(text: session.baseBranch, tint: ShellPalette.accentWarm)
                                        if let agentName = session.agentName {
                                            ShellTag(text: agentName, tint: ShellPalette.accent)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            HStack(spacing: 6) {
                                Button {
                                    Task {
                                        await store.selectTuiSession(session)
                                        await store.restartTuiSession()
                                    }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    Task { await store.terminateTuiSession(session) }
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ShellPalette.muted)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(store.selectedTuiSessionID == session.id ? ShellPalette.accentSoft.opacity(0.82) : ShellPalette.panelAlt)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(store.selectedTuiSessionID == session.id ? ShellPalette.lineStrong : ShellPalette.line, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private var companySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            companySelectionSection
            companyQuickActionsSection
            companyDraftSection
            if store.selectedCompany != nil {
                advancedCompanySettingsSection
            }
        }
        .onAppear {
            store.syncSelectedCompanyBudgetFormState()
        }
        .onChange(of: store.selectedCompanyID) { _, _ in
            store.syncSelectedCompanyBudgetFormState()
        }
    }

    private var companySelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(
                title: l("Companies", "회사 목록"),
                subtitle: l("Select a company to inspect its runtime, goals, and work queue.", "회사를 선택해 런타임, 목표, 작업 큐를 확인합니다.")
            )

            HStack(spacing: 8) {
                ShellTag(text: "\(store.goals.count) \(l("goals", "목표"))", tint: ShellPalette.accent)
                ShellTag(text: "\(store.issues.count) \(l("issues", "이슈"))", tint: ShellPalette.accentWarm)
                let scopedMetrics = store.scopedOpsMetrics(companyID: store.selectedCompanyID)
                if scopedMetrics.readyToMergeCount > 0 {
                    ShellTag(text: "\(scopedMetrics.readyToMergeCount) \(l("ready", "병합대기"))", tint: ShellPalette.success)
                }
            }

            if store.companies.isEmpty {
                EmptyStateView(
                    image: "building.2",
                    title: l("No companies yet", "아직 회사가 없습니다"),
                    subtitle: l("Create a company and point it at a working folder.", "회사를 만들고 작업 폴더를 연결하세요.")
                )
                .frame(height: 150)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.companies) { company in
                        CompanyCard(
                            company: company,
                            runtime: store.companyRuntimes.first(where: { $0.companyId == company.id }),
                            language: l,
                            isSelected: store.selectedCompanyID == company.id
                        ) {
                            Task { await store.selectCompany(company) }
                        }
                    }
                }
            }
        }
        .padding(14)
        .shellInset()
    }

    private var companyDraftSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(ShellMotion.spring) {
                    companySidebarDisclosureState.isCompanyDraftExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l("New Company", "새 회사"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ShellPalette.text)
                        Text(l("Create a company from a local working folder.", "로컬 작업 폴더로 새 회사를 만듭니다."))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ShellPalette.muted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: companySidebarDisclosureState.isCompanyDraftExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ShellPalette.muted)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if companySidebarDisclosureState.isCompanyDraftExpanded {
                companySubpanel {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(l("Company name", "회사 이름"), text: $store.newCompanyName)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 8) {
                            TextField(l("Company root path", "회사 루트 경로"), text: $store.newCompanyRootPath)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                store.openCompanyRootPicker()
                            } label: {
                                Label(l("Choose Folder", "폴더 선택"), systemImage: "folder")
                            }
                            .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                        }

                        if !store.availableBranches.isEmpty {
                            Picker(l("New workspace base branch", "새 워크스페이스 기준 브랜치"), selection: $store.pendingWorkspaceBaseBranch) {
                                ForEach(store.availableBranches, id: \.self) { branch in
                                    Text(branch).tag(branch)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(l("Optional cost guardrails (USD)", "선택 사항: 비용 상한 (USD)"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ShellPalette.muted)
                            HStack(spacing: 8) {
                                TextField(l("Daily cap", "일 상한"), text: $store.newCompanyDailyBudgetInput)
                                    .textFieldStyle(.roundedBorder)
                                TextField(l("Monthly cap", "월 상한"), text: $store.newCompanyMonthlyBudgetInput)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }
            }
        }
    }

    private var companyQuickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(
                title: l("Quick Actions", "빠른 동작"),
                subtitle: l("Create from the draft and control the selected company runtime from one compact area.", "초안으로 회사를 만들고 선택한 회사 런타임을 한곳에서 빠르게 제어합니다.")
            )

            companySubpanel {
                VStack(alignment: .leading, spacing: 10) {
                    if let company = store.selectedCompany {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(company.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ShellPalette.text)
                                    Text(userFacingPathLabel(company.rootPath))
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(ShellPalette.muted)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                if let runtime = store.selectedRuntime {
                                    ShellStatusPill(text: l.status(runtime.status), tint: companyRuntimeTint(runtime.status))
                                }
                            }

                            HStack(spacing: 8) {
                                ShellTag(text: company.defaultBaseBranch, tint: ShellPalette.accentWarm)
                                ShellTag(
                                    text: company.backendKind == "CODEX_APP_SERVER"
                                        ? l("Codex App Server", "Codex App Server")
                                        : l("Local Cotor", "Local Cotor"),
                                    tint: ShellPalette.accent
                                )
                            }
                        }
                    } else {
                        Text(l("Select a company to start, stop, or delete it. You can still prepare a new company above.", "회사를 선택하면 시작/중지/삭제를 바로 실행할 수 있습니다. 위에서 새 회사 준비는 계속할 수 있습니다."))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ShellPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await store.createCompany() }
                    } label: {
                        Label(l("Create Company", "회사 생성"), systemImage: "building.2.crop.circle")
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.newCompanyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.newCompanyRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let company = store.selectedCompany, shouldShowGitHubQuickConnect(for: company) {
                        companyGitHubQuickConnectPrompt(company: company)
                    }

                    if let message = store.companyGitHubStatusMessage, !message.isEmpty, !isShowingGitHubQuickConnect {
                        Text(message)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ShellPalette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                    ], spacing: 8) {
                        Button {
                            Task { await store.startSelectedCompanyRuntime() }
                        } label: {
                            Label(l("Start", "시작"), systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                        .disabled(store.selectedCompany == nil)

                        Button {
                            Task { await store.stopSelectedCompanyRuntime() }
                        } label: {
                            Label(l("Stop", "중지"), systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                        .disabled(store.selectedCompany == nil)

                        Button {
                            Task { await store.deleteSelectedCompany() }
                        } label: {
                            Label(l("Delete", "삭제"), systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                        .disabled(store.selectedCompany == nil)
                    }
                }
            }
        }
        .padding(14)
        .shellInset()
    }

    private func shouldShowGitHubQuickConnect(for company: CompanyRecord) -> Bool {
        store.activeGitHubConnectionNeedsSetup && dismissedGitHubConnectCompanyID != company.id
    }

    private var isShowingGitHubQuickConnect: Bool {
        guard let company = store.selectedCompany else { return false }
        return shouldShowGitHubQuickConnect(for: company)
    }

    private func companyGitHubQuickConnectPrompt(company: CompanyRecord) -> some View {
        let status = store.activeGitHubPublishStatus
        return VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(l("Connect GitHub", "GitHub 연결"), systemImage: "link.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                    Text(l("PR work needs an existing GitHub remote. Cotor will not create a repository automatically.", "PR 작업에는 기존 GitHub 원격 저장소가 필요합니다. Cotor가 저장소를 자동 생성하지 않습니다."))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button {
                    dismissedGitHubConnectCompanyID = company.id
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ShellPalette.text)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .background(ShellPalette.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityLabel(l("Dismiss GitHub connection panel", "GitHub 연결 패널 닫기"))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ShellTag(text: status.ghInstalled ? l("gh ok", "gh OK") : l("gh needed", "gh 필요"), tint: status.ghInstalled ? ShellPalette.success : ShellPalette.warning)
                ShellTag(text: status.ghAuthenticated ? l("auth ok", "인증 OK") : l("auth needed", "인증 필요"), tint: status.ghAuthenticated ? ShellPalette.success : ShellPalette.warning)
                ShellTag(text: status.originConfigured ? l("origin ok", "origin OK") : l("origin needed", "origin 필요"), tint: status.originConfigured ? ShellPalette.success : ShellPalette.warning)
                ShellTag(text: status.policy == "REQUIRE_GITHUB_PR" ? l("PR mode", "PR 모드") : l("local git", "로컬 git"), tint: ShellPalette.accent)
            }

            TextField(l("https://github.com/owner/repo.git", "https://github.com/owner/repo.git"), text: $store.companyGitHubOriginInput)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .accessibilityIdentifier("github-origin-quick-input")

            if let message = store.companyGitHubStatusMessage, !message.isEmpty {
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ShellPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                Button {
                    Task { await store.refreshSelectedCompanyGitHubStatus() }
                } label: {
                    Label(l("Detect", "감지"), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ShellTopBarButtonStyle(prominent: false))

                Button {
                    store.openGitHubLoginTerminal()
                } label: {
                    Label(l("Sign in", "로그인"), systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                .disabled(!status.ghInstalled)

                Button {
                    Task { await store.openRepositoryPicker() }
                } label: {
                    Label(l("Git folder", "Git 폴더"), systemImage: "folder.badge.gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ShellTopBarButtonStyle(prominent: false))

                Button {
                    Task { await store.saveSelectedCompanyGitHubOrigin() }
                } label: {
                    Label(l("Connect", "연결"), systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ShellTopBarButtonStyle(prominent: true))
                .disabled(store.companyGitHubOriginInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("github-quick-connect-panel")
    }

    private var advancedCompanySettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(ShellMotion.spring) {
                    companySidebarDisclosureState.isAdvancedSettingsExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l("Company Settings", "회사 설정"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ShellPalette.text)
                        Text(l("Configure the selected company's backend, budget, GitHub, and Linear connection.", "선택한 회사의 백엔드, 예산, GitHub, Linear 연결을 설정합니다."))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ShellPalette.muted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    if let company = store.selectedCompany {
                        ShellTag(text: company.name, tint: ShellPalette.panelRaised)
                    }

                    Image(systemName: companySidebarDisclosureState.isAdvancedSettingsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ShellPalette.muted)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if companySidebarDisclosureState.isAdvancedSettingsExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    companyBackendSettingsPanel
                    companyGitHubSettingsPanel
                    companyBudgetSettingsPanel
                    companyLinearSettingsPanel
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .shellInset()
    }

    private var companyBackendSettingsPanel: some View {
        companySubpanel {
            VStack(alignment: .leading, spacing: 8) {
                panelHeading(
                    title: l("Execution Backend", "실행 백엔드"),
                    subtitle: l("Pick which runtime executes the selected company.", "선택한 회사를 어떤 런타임으로 실행할지 정합니다.")
                )

                if let company = store.selectedCompany {
                    Picker(l("Company execution backend", "회사 실행 백엔드"), selection: Binding(
                        get: { company.backendKind },
                        set: { newValue in
                            Task { await store.updateSelectedCompanyBackend(kind: newValue) }
                        }
                    )) {
                        Text("Local Cotor").tag("LOCAL_COTOR")
                        Text("Codex App Server").tag("CODEX_APP_SERVER")
                    }
                    .pickerStyle(.menu)
                } else {
                    Text(l("Select a company to adjust its backend.", "백엔드를 조정할 회사를 먼저 선택하세요."))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                }
            }
        }
    }

    private var companyGitHubSettingsPanel: some View {
        companySubpanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    panelHeading(
                        title: l("Git & GitHub Connection", "Git 및 GitHub 연결"),
                        subtitle: l("Connect repository publishing and PR readiness for this company.", "이 회사의 저장소 배포와 PR 준비 상태를 연결합니다.")
                    )
                    Spacer(minLength: 8)
                    ShellStatusPill(
                        text: store.activeGitHubConnectionReady ? l("Ready", "준비됨") : l("Needs setup", "설정 필요"),
                        tint: store.activeGitHubConnectionReady ? ShellPalette.success : ShellPalette.warning
                    )
                }

                if let company = store.selectedCompany {
                    let status = store.activeGitHubPublishStatus
                    valueGrid([
                        (l("Company", "회사"), company.name),
                        (l("Root", "루트"), userFacingPathLabel(company.rootPath)),
                        (l("Base branch", "기준 브랜치"), company.defaultBaseBranch),
                        (l("Publish policy", "배포 정책"), status.policy == "REQUIRE_GITHUB_PR" ? l("Require GitHub PR", "GitHub PR 필수") : l("Allow local git", "로컬 git 허용")),
                        (l("gh CLI", "gh CLI"), status.ghInstalled ? l("Installed", "설치됨") : l("Missing", "없음")),
                        (l("gh auth", "gh 인증"), status.ghAuthenticated ? l("Authenticated", "인증됨") : l("Not authenticated", "인증 안 됨")),
                        (l("origin", "origin"), status.originConfigured ? (status.originUrl ?? l("Configured", "설정됨")) : l("Not configured", "설정 안 됨")),
                        (l("Checked repo", "확인한 저장소"), userFacingPathLabel(status.repositoryPath ?? company.rootPath)),
                    ])

                    TextField(l("https://github.com/owner/repo.git", "https://github.com/owner/repo.git"), text: $store.companyGitHubOriginInput)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Button {
                            store.openGitHubLoginTerminal()
                        } label: {
                            Label(l("Sign in", "로그인"), systemImage: "person.crop.circle.badge.checkmark")
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                        .disabled(!status.ghInstalled)

                        Button {
                            Task { await store.saveSelectedCompanyGitHubOrigin() }
                        } label: {
                            Label(l("Connect origin", "origin 연결"), systemImage: "link.badge.plus")
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                        .disabled(store.companyGitHubOriginInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    HStack(spacing: 8) {
                        Button {
                            Task { await store.refreshSelectedCompanyGitHubStatus() }
                        } label: {
                            Label(l("Check GitHub", "GitHub 확인"), systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))

                        Button {
                            Task { await store.openRepositoryPicker() }
                        } label: {
                            Label(l("Choose Git Folder", "Git 폴더 선택"), systemImage: "folder.badge.gearshape")
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                    }

                    if let message = store.companyGitHubStatusMessage, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(store.activeGitHubConnectionReady ? ShellPalette.muted : ShellPalette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(l("Select a company to inspect its Git folder, origin remote, and GitHub PR readiness.", "Git 폴더, origin remote, GitHub PR 준비 상태를 확인하려면 회사를 먼저 선택하세요."))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                }
            }
        }
    }

    private var companyBudgetSettingsPanel: some View {
        companySubpanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l("Estimated AI spend guardrail", "추정 AI 비용 가드레일"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ShellPalette.text)
                        Text(l("Set optional daily and monthly spend limits.", "선택 사항으로 일간/월간 비용 상한을 설정합니다."))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ShellPalette.muted)
                    }
                    Spacer()
                    if let runtime = store.selectedRuntime, runtime.isBudgetPaused {
                        ShellTag(text: l("Cap reached", "상한 도달"), tint: ShellPalette.warning)
                    }
                }

                if let company = store.selectedCompany {
                    if let runtime = store.selectedRuntime {
                        HStack(spacing: 8) {
                            ShellTag(
                                text: runtimeSpendSummary(
                                    label: l("Today", "오늘"),
                                    spentCents: runtime.todaySpentCents,
                                    capCents: company.dailyBudgetCents,
                                    language: l
                                ),
                                tint: ShellPalette.accent
                            )
                            ShellTag(
                                text: runtimeSpendSummary(
                                    label: l("Month", "월"),
                                    spentCents: runtime.monthSpentCents,
                                    capCents: company.monthlyBudgetCents,
                                    language: l
                                ),
                                tint: ShellPalette.accentWarm
                            )
                            Spacer()
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(l("Daily cap", "일 상한"), text: $store.companyDailyBudgetInput)
                            .textFieldStyle(.roundedBorder)
                        TextField(l("Monthly cap", "월 상한"), text: $store.companyMonthlyBudgetInput)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        Task { await store.saveSelectedCompanyBudget() }
                    } label: {
                        Label(l("Save Guardrails", "상한 저장"), systemImage: "dollarsign.circle")
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                    }
                    .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                } else {
                    Text(l("Select a company to edit budget guardrails.", "비용 가드레일을 수정하려면 회사를 먼저 선택하세요."))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                }
            }
        }
    }

    private var companyLinearSettingsPanel: some View {
        companySubpanel {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $store.companyLinearSyncEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l("Optional: share progress to Linear", "선택 사항: 진행 상황을 Linear에 공유"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ShellPalette.text)
                        Text(l("Mirror Cotor issues and updates into Linear.", "Cotor 이슈와 업데이트를 Linear에 동기화합니다."))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ShellPalette.muted)
                    }
                }
                .toggleStyle(.switch)
                .disabled(store.selectedCompany == nil)

                if store.selectedCompany != nil {
                    TextField(l("Linear endpoint", "Linear 엔드포인트"), text: $store.companyLinearEndpoint)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        TextField(l("Team ID", "팀 ID"), text: $store.companyLinearTeamID)
                            .textFieldStyle(.roundedBorder)
                        TextField(l("Project ID", "프로젝트 ID"), text: $store.companyLinearProjectID)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 8) {
                        Button {
                            Task { await store.saveSelectedCompanyLinearSettings() }
                        } label: {
                            Label(l("Save Linear", "Linear 저장"), systemImage: "arrow.triangle.branch")
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))

                        Button {
                            Task { await store.resyncSelectedCompanyLinear() }
                        } label: {
                            Label(l("Resync", "다시 동기화"), systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                        .disabled(!(store.selectedCompany?.linearSyncEnabled ?? false) && !store.companyLinearSyncEnabled)
                    }
                } else {
                    Text(l("Select a company to adjust Linear sync.", "Linear 동기화를 조정하려면 회사를 먼저 선택하세요."))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                }

                if let message = store.companyLinearStatusMessage, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func panelHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ShellPalette.text)
            Text(subtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ShellPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func agentFieldBlock<Content: View>(
        title: String,
        helper: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ShellPalette.text)
            Text(helper)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ShellPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
    }

    private func agentTextEditorBlock(title: String, helper: String, text: Binding<String>) -> some View {
        agentFieldBlock(title: title, helper: helper) {
            TextEditor(text: text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(8)
                .background(ShellPalette.panelAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(ShellPalette.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var agentSkillsBlock: some View {
        agentFieldBlock(
            title: l("Skills", "스킬"),
            helper: l("Choose the skill set this agent can request through the backend gate.", "이 에이전트가 백엔드 게이트를 통해 요청할 수 있는 스킬을 고릅니다.")
        ) {
            if store.availableSkills.isEmpty {
                Text(l("No skills advertised by the app-server.", "app-server가 광고하는 스킬이 없습니다."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .padding(.vertical, 4)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(store.availableSkills) { skill in
                        agentSkillToggle(skill)
                    }
                }
            }
        }
    }

    private func agentSkillToggle(_ skill: SkillCatalogEntryRecord) -> some View {
        let isSelected = store.newCompanyAgentSkillIDs.contains(skill.name)
        return Button {
            if isSelected {
                store.newCompanyAgentSkillIDs.remove(skill.name)
            } else {
                store.newCompanyAgentSkillIDs.insert(skill.name)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? ShellPalette.accent : ShellPalette.muted)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                        .lineLimit(1)
                    Text(skill.description)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? ShellPalette.accent.opacity(0.14) : ShellPalette.panelAlt)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? ShellPalette.accent : ShellPalette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(skill.displayName)
    }

    private var agentMarketingPolicyBlock: some View {
        agentFieldBlock(
            title: l("Marketing Delegation Policy", "마케팅 위임 정책"),
            helper: l("Policy-outside browser actions are denied and replanned instead of queued for approval.", "정책 밖 브라우저 동작은 승인 대기 없이 거부되고 더 작은 범위로 재계획됩니다.")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], alignment: .leading, spacing: 10) {
                    agentFieldBlock(
                        title: l("Domains", "도메인"),
                        helper: l("Owned web, CMS, or social domains.", "자사 웹, CMS 또는 소셜 도메인입니다.")
                    ) {
                        TextField("example.com, cms.example.com", text: $store.marketingPolicyAllowedDomains)
                            .textFieldStyle(.roundedBorder)
                    }

                    agentFieldBlock(
                        title: l("Channels", "채널"),
                        helper: l("Organic channels only.", "유기적 채널만 허용합니다.")
                    ) {
                        TextField("web, linkedin, x", text: $store.marketingPolicyChannels)
                            .textFieldStyle(.roundedBorder)
                    }

                    agentFieldBlock(
                        title: l("Daily Posts", "일 게시 한도"),
                        helper: l("Maximum delegated publishes per day.", "하루 자동 게시 최대치입니다.")
                    ) {
                        TextField("1", text: $store.marketingPolicyDailyPostLimit)
                            .textFieldStyle(.roundedBorder)
                    }

                    agentFieldBlock(
                        title: l("Max Runtime", "최대 실행"),
                        helper: l("Seconds before browser work stops.", "브라우저 작업 중단 시간(초)입니다.")
                    ) {
                        TextField("900", text: $store.marketingPolicyMaxRuntimeSeconds)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                agentFieldBlock(
                    title: l("Brand Tone", "브랜드 톤"),
                    helper: l("Concise tone guidance for generated copy.", "생성 문구에 적용할 짧은 톤 가이드입니다.")
                ) {
                    TextField(l("Helpful, precise, product-led", "도움되고 정확한 제품 중심 톤"), text: $store.marketingPolicyBrandTone)
                        .textFieldStyle(.roundedBorder)
                }

                agentFieldBlock(
                    title: l("Forbidden Terms", "금칙어"),
                    helper: l("Comma-separated words or phrases.", "쉼표로 구분한 단어나 문구입니다.")
                ) {
                    TextField(l("forbidden, unapproved", "금칙어, 미승인"), text: $store.marketingPolicyForbiddenTerms)
                        .textFieldStyle(.roundedBorder)
                }

                agentFieldBlock(
                    title: l("Prohibited Actions", "금지 행동"),
                    helper: l("Paid ads, bulk email, DMs, payment, and budget changes stay out of V1.", "유료 광고, 대량 이메일, DM, 결제, 예산 변경은 V1 범위 밖입니다.")
                ) {
                    TextField("paid-ad, budget-change, bulk-email, direct-message, payment", text: $store.marketingPolicyProhibitedActions)
                        .textFieldStyle(.roundedBorder)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], alignment: .leading, spacing: 10) {
                    agentFieldBlock(
                        title: l("Session Ref", "세션 참조"),
                        helper: l("Browser profile or storage-state reference.", "브라우저 프로필 또는 storage-state 참조입니다.")
                    ) {
                        TextField("marketing-browser-profile", text: $store.marketingPolicyBrowserSessionRef)
                            .textFieldStyle(.roundedBorder)
                    }

                    agentFieldBlock(
                        title: l("Secret Refs", "Secret 참조"),
                        helper: l("References only; no secret values.", "값이 아닌 참조만 저장합니다.")
                    ) {
                        TextField("secret://cms/session", text: $store.marketingPolicySecretRefs)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack(spacing: 8) {
                    ShellTag(text: l("Delegated AUTO", "위임 자동"), tint: ShellPalette.accent)
                    Text(store.marketingPolicyConnectionSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }

                if !store.recentMarketingRunsForEditedAgent.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(l("Recent Runs", "최근 실행"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ShellPalette.text)
                        ForEach(store.recentMarketingRunsForEditedAgent.prefix(3)) { run in
                            HStack(spacing: 8) {
                                ShellTag(text: run.status, tint: run.status == "COMPLETED" ? ShellPalette.success : ShellPalette.accentWarm)
                                Text(run.objective)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(ShellPalette.muted)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
    }

    private func companySubpanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                    .fill(ShellPalette.panelAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                    .stroke(ShellPalette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
    }

    private func valueGrid(_ rows: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.0.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(ShellPalette.faint)
                    Text(row.1)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShellPalette.text)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(ShellPalette.panelDeeper)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(ShellPalette.line, lineWidth: 1)
                )
            }
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(
                title: l("Goals", "목표"),
                subtitle: l("Pick the single business outcome the company should chase next.", "회사가 다음으로 추적할 단일 비즈니스 목표를 고릅니다.")
            )

            if filteredGoals.isEmpty {
                EmptyStateView(
                    image: "flag.2.crossed",
                    title: l("No goals yet", "아직 목표가 없습니다"),
                    subtitle: l("Create one company goal to bootstrap the autonomous workflow.", "자율 워크플로우를 시작하려면 회사 목표를 하나 만드세요.")
                )
                .frame(height: 150)
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredGoals) { goal in
                        GoalRow(goal: goal, language: l, isSelected: store.selectedGoalID == goal.id) {
                            Task { await store.selectGoal(goal) }
                        }
                    }
                }
            }
        }
    }

    private var goalComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(
                title: store.editingGoalID == nil ? l("New Goal", "새 목표") : l("Edit Goal", "목표 수정"),
                subtitle: l("Write one clear outcome. The CEO turns it into issues.", "명확한 목표 하나를 쓰고 필요하면 바로 수정하세요.")
            )

            TextField(l("Goal title", "목표 제목"), text: $store.newGoalTitle)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $store.newGoalDescription)
                .font(.system(size: 12, design: .default))
                .frame(minHeight: 58, idealHeight: 72, maxHeight: 96)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(ShellPalette.panelAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                        .stroke(ShellPalette.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))

            HStack(spacing: 8) {
                Button {
                    Task { await store.createGoal() }
                } label: {
                    Label(
                        store.editingGoalID == nil ? l("Create Goal", "목표 생성") : l("Save Goal", "목표 저장"),
                        systemImage: store.editingGoalID == nil ? "plus.circle.fill" : "checkmark.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if store.editingGoalID != nil {
                    Button {
                        store.cancelGoalEditing()
                    } label: {
                        Label(l("Cancel", "취소"), systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                } else if let goal = store.selectedGoal {
                    Button {
                        store.beginEditingGoal(goal)
                    } label: {
                        Label(l("Edit Selected", "선택 목표 수정"), systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                }
            }
        }
        .padding(14)
        .shellInset()
    }

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(
                title: l("Team Roster", "팀 구성"),
                subtitle: l("Roles and handoff flow are built from the agents you defined.", "정의한 에이전트 정보를 바탕으로 역할과 담당 흐름을 정리합니다.")
            )

            VStack(spacing: 8) {
                ForEach(store.orgProfiles) { profile in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(profile.mergeAuthority ? ShellPalette.accentWarm : ShellPalette.accent)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.roleName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ShellPalette.text)
                            Text("\(profile.executionAgentName) · \(profile.capabilities.joined(separator: " · "))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(ShellPalette.muted)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        store.selectedOrgProfileIDs.contains(profile.id)
                            ? ShellPalette.accent.opacity(0.08)
                            : ShellPalette.panelAlt
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                store.selectedOrgProfileIDs.contains(profile.id)
                                    ? ShellPalette.accent
                                    : ShellPalette.line,
                                lineWidth: 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onTapGesture {
                        store.toggleOrgProfileSelection(
                            id: profile.id,
                            shiftKey: NSEvent.modifierFlags.contains(.shift)
                        )
                    }
                }
            }
        }
    }

    private var companyAgentComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(
                title: store.editingCompanyAgentID == nil ? l("Add Agent", "에이전트 추가") : l("Edit Agent", "에이전트 수정"),
                subtitle: l("Define roles, tools, and routing hints for company work.", "회사 작업에 사용할 역할, 도구, 배정 기준을 설정합니다.")
            )

            companySubpanel {
                VStack(alignment: .leading, spacing: 12) {
                    panelHeading(
                        title: l("Basic Settings", "기본 설정"),
                        subtitle: l("Set the role name, execution tool, and ownership summary.", "역할 이름, 실행 도구, 담당 범위를 설정합니다.")
                    )

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                        agentFieldBlock(
                            title: l("Title", "직함"),
                            helper: l("Role name shown in the team list.", "팀 목록에 표시되는 역할 이름입니다.")
                        ) {
                            TextField(l("Title", "직함"), text: $store.newCompanyAgentTitle)
                                .textFieldStyle(.roundedBorder)
                        }

                        agentFieldBlock(
                            title: l("Execution Tool", "실행 도구"),
                            helper: l("Which local tool runs this agent's work.", "이 에이전트가 사용할 로컬 실행 도구입니다.")
                        ) {
                            Picker(l("Execution Tool", "실행 도구"), selection: Binding(
                                get: {
                                    store.resolvedNewCompanyAgentCli
                                },
                                set: { store.selectNewCompanyAgentCli($0) }
                            )) {
                                ForEach(store.availableCliAgents, id: \.self) { agent in
                                    Text(agent).tag(agent)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(store.availableCliAgents.isEmpty)
                        }

                        agentFieldBlock(
                            title: l("Model", "모델"),
                            helper: l("Use a specific model only when this role needs one.", "역할에 필요한 경우에만 특정 모델을 지정합니다.")
                        ) {
                            let modelOptions = store.newCompanyAgentModelOptions
                            if modelOptions.isEmpty {
                                TextField(l("Model (optional)", "모델 (선택)"), text: $store.newCompanyAgentModel)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Picker(l("Model", "모델"), selection: $store.newCompanyAgentModel) {
                                    Text(l("Default", "기본값")).tag("")
                                    ForEach(modelOptions, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }

                    agentFieldBlock(
                        title: l("Role Summary", "역할 설명"),
                        helper: l("Short guidance the CEO uses when assigning work.", "CEO가 작업을 배정할 때 참고하는 짧은 역할 설명입니다.")
                    ) {
                        TextField(l("Role summary", "역할 설명"), text: $store.newCompanyAgentRole)
                            .textFieldStyle(.roundedBorder)
                    }

                    agentFieldBlock(
                        title: l("Specialties", "전문 분야"),
                        helper: l("Comma-separated strengths shown in team and assignment views.", "팀 구성과 배정 화면에 보일 강점을 쉼표로 구분해 적습니다.")
                    ) {
                        TextField(l("Specialties (comma separated)", "전문 분야 (쉼표로 구분)"), text: $store.newCompanyAgentSpecialties)
                            .textFieldStyle(.roundedBorder)
                    }

                    agentFieldBlock(
                        title: l("Availability", "활성 상태"),
                        helper: l("Keep the role configured but unavailable for assignment.", "역할 설정은 유지하고 배정 대상에서 제외합니다.")
                    ) {
                        Toggle(isOn: $store.newCompanyAgentEnabled) {
                            Text(l("Enabled", "활성화"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ShellPalette.text)
                        }
                        .toggleStyle(.switch)
                    }
                }

                    agentSkillsBlock

                    if store.isMarketingOperatorSelected {
                        agentFieldBlock(
                            title: l("Marketing Delegation Policy", "마케팅 위임 정책"),
                            helper: l("Policy-outside browser actions are denied.", "정책 밖 브라우저 동작은 거부됩니다.")
                        ) {
                            Text(store.marketingPolicyConnectionSummary)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ShellPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
            }

            companySubpanel {
                VStack(alignment: .leading, spacing: 10) {
                    panelHeading(
                        title: store.editingCompanyAgentID == nil ? l("Save Draft", "초안 저장") : l("Edit Actions", "수정 동작"),
                        subtitle: l("Review the draft and save the agent configuration.", "초안을 확인하고 에이전트 설정을 저장합니다.")
                    )

                    HStack(alignment: .center, spacing: 8) {
                        if store.editingCompanyAgentID != nil {
                            ShellTag(text: l("Editing", "수정 중"), tint: ShellPalette.accentWarm)
                        } else {
                            ShellTag(text: l("New Agent", "새 에이전트"), tint: ShellPalette.accent)
                        }

                        Spacer(minLength: 0)

                        if let company = store.selectedCompany {
                            ShellTag(text: company.name, tint: ShellPalette.panelRaised)
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            Task { await store.createCompanyAgent() }
                        } label: {
                            Label(
                                store.editingCompanyAgentID == nil ? l("Add Agent", "에이전트 추가") : l("Save Changes", "변경 저장"),
                                systemImage: store.editingCompanyAgentID == nil ? "person.crop.circle.badge.plus" : "checkmark.circle"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            store.selectedCompany == nil ||
                            store.newCompanyAgentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            store.resolvedNewCompanyAgentCli.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            store.newCompanyAgentRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )

                        if store.editingCompanyAgentID != nil {
                            Button {
                                store.cancelEditingCompanyAgent()
                            } label: {
                                Label(l("Cancel", "취소"), systemImage: "xmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                        }
                    }
                }
            }

            companySubpanel {
                agentTextEditorBlock(
                    title: l("Agent Memory Seed", "에이전트 메모 시드"),
                    helper: l("Add durable context for this role.", "이 역할에 적용할 지속 컨텍스트를 추가합니다."),
                    text: $store.newCompanyAgentMemoryNotes
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(ShellMotion.spring) {
                        companySidebarDisclosureState.isAgentAdvancedDetailsExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(l("Assignment Options", "배정 옵션"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ShellPalette.text)
                            Text(l("Set collaboration rules and preferred teammates.", "협업 규칙과 선호 동료를 설정합니다."))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(ShellPalette.muted)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        if !store.newCompanyAgentCollaborationNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.newCompanyAgentPreferredCollaboratorIDs.isEmpty {
                            ShellTag(text: l("Configured", "설정됨"), tint: ShellPalette.accentWarm)
                        }

                        Image(systemName: companySidebarDisclosureState.isAgentAdvancedDetailsExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ShellPalette.muted)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if companySidebarDisclosureState.isAgentAdvancedDetailsExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        companySubpanel {
                            agentTextEditorBlock(
                                title: l("Notes For This Role", "역할 메모"),
                                helper: l("When should this role ask another agent for help?", "이 역할이 언제 다른 에이전트에게 도움을 요청해야 하는지 적습니다."),
                                text: $store.newCompanyAgentCollaborationNotes
                            )
                        }

                        if !store.availableCompanyAgentCollaborators.isEmpty {
                            companySubpanel {
                                VStack(alignment: .leading, spacing: 10) {
                                    panelHeading(
                                        title: l("Preferred Collaborators", "선호 협업 에이전트"),
                                        subtitle: l("Prefer these teammates when assigning work.", "일을 배정할 때 이 동료들을 우선 참고합니다.")
                                    )

                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                                        ForEach(store.availableCompanyAgentCollaborators) { collaborator in
                                            let isSelected = store.newCompanyAgentPreferredCollaboratorIDs.contains(collaborator.id)
                                            Button {
                                                if isSelected {
                                                    store.newCompanyAgentPreferredCollaboratorIDs.remove(collaborator.id)
                                                } else {
                                                    store.newCompanyAgentPreferredCollaboratorIDs.insert(collaborator.id)
                                                }
                                            } label: {
                                                HStack(spacing: 8) {
                                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                        .font(.system(size: 11, weight: .semibold))
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(collaborator.title)
                                                            .font(.system(size: 11, weight: .semibold))
                                                            .lineLimit(1)
                                                        Text(collaborator.agentCli)
                                                            .font(.system(size: 10, weight: .medium))
                                                            .foregroundStyle(ShellPalette.text.opacity(0.72))
                                                            .lineLimit(1)
                                                    }
                                                    Spacer(minLength: 0)
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 9)
                                                .background(isSelected ? ShellPalette.panelRaised : ShellPalette.panelAlt)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .stroke(isSelected ? ShellPalette.accent : ShellPalette.line, lineWidth: 1)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .contentShape(Rectangle())
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if !store.companyAgentDefinitions.isEmpty {
                if !store.selectedCompanyAgentDefinitionIDs.isEmpty {
                    HStack(spacing: 12) {
                        Text("\(store.selectedCompanyAgentDefinitionIDs.count) selected")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ShellPalette.text.opacity(0.9))

                        Spacer()

                        Button(action: {
                            store.clearCompanyAgentSelection()
                        }) {
                            Text(l("Clear", "해제"))
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))

                        Button(action: {
                            store.showingOrgProfileBatchEdit = true
                        }) {
                            Text(l("Edit", "편집"))
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ShellPalette.panelAlt)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(ShellPalette.line, lineWidth: 1)
                    )
                }

                VStack(spacing: 8) {
                    ForEach(store.companyAgentDefinitions) { agent in
                        let isSelected = store.selectedCompanyAgentDefinitionIDs.contains(agent.id)
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(agent.enabled ? ShellPalette.success : ShellPalette.warning)
                                .frame(width: 8, height: 8)
                                .padding(.top, 8)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .center, spacing: 8) {
                                    Text(agent.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(ShellPalette.text)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(ShellPalette.accent)
                                    }
                                    if store.editingCompanyAgentID == agent.id {
                                        ShellTag(text: l("Editing", "수정 중"), tint: ShellPalette.accentWarm)
                                    }
                                    Spacer(minLength: 8)
                                    Button {
                                        store.beginEditingCompanyAgent(agent)
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(ShellPalette.text)
                                            .frame(width: 30, height: 30)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(ShellPalette.panelRaised)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(l("Edit Agent", "에이전트 수정"))
                                }

                                HStack(spacing: 6) {
                                    ShellTag(text: agent.agentCli, tint: ShellPalette.accent, maxWidth: 112)
                                    if let model = agent.model, !model.isEmpty {
                                        ShellTag(text: model, tint: ShellPalette.accentWarm, maxWidth: 190)
                                    }
                                }

                                Text(agent.roleSummary)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(ShellPalette.text.opacity(0.84))
                                    .lineLimit(2)
                                if !agent.specialties.isEmpty {
                                    Text(agent.specialties.joined(separator: " · "))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(ShellPalette.text.opacity(0.78))
                                        .lineLimit(2)
                                }
                                let skills = store.selectedSkills(for: agent)
                                if !skills.isEmpty {
                                    HStack(spacing: 6) {
                                        ForEach(Array(skills.prefix(3))) { skill in
                                            ShellTag(text: skill.displayName, tint: ShellPalette.accentSoft)
                                        }
                                        if skills.count > 3 {
                                            ShellTag(text: "+\(skills.count - 3)", tint: ShellPalette.panelRaised)
                                        }
                                    }
                                }
                                if !agent.preferredCollaboratorIds.isEmpty {
                                    Text(l("Collaborates with", "협업 대상") + " · " + agent.preferredCollaboratorIds.compactMap { collaboratorId in
                                        store.companyAgentDefinitions.first(where: { $0.id == collaboratorId })?.title
                                    }.joined(separator: ", "))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(ShellPalette.text.opacity(0.8))
                                    .lineLimit(2)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(isSelected ? ShellPalette.accent.opacity(0.18) : ShellPalette.panelAlt)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isSelected ? ShellPalette.accent : ShellPalette.line, lineWidth: isSelected ? 2.5 : 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.toggleCompanyAgentSelection(
                                id: agent.id,
                                shiftKey: NSEvent.modifierFlags.contains(.shift)
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
        .shellInset()
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(
                title: l("Folders", "폴더"),
                subtitle: l("Choose repository folders for terminal sessions.", "터미널 세션에 사용할 저장소 폴더를 선택합니다.")
            )

            if filteredRepositories.isEmpty {
                EmptyStateView(
                    image: "shippingbox",
                    title: l.text(.noRepositories),
                    subtitle: l.text(.noRepositoriesSubtitle)
                )
                .frame(height: 180)
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredRepositories) { repository in
                        RepositoryStackView(repository: repository, searchText: searchText)
                    }
                }
            }
        }
    }

    private var tuiLaunchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(
                title: l("Open Session", "세션 열기"),
                subtitle: l("Start a terminal session for the selected folder and branch.", "선택한 폴더와 브랜치로 터미널 세션을 시작합니다.")
            )

            if !store.availableCliAgents.isEmpty {
                Picker(l("Preferred agent tool", "선호 실행 도구"), selection: Binding(
                    get: { store.workflowLeadAgent },
                    set: { store.setWorkflowLeadAgent($0) }
                )) {
                    ForEach(store.availableCliAgents, id: \.self) { agent in
                        Text(agent).tag(agent)
                    }
                }
                .pickerStyle(.menu)
            }

            if !store.availableBranches.isEmpty, store.selectedRepository != nil {
                Picker(l("New workspace base branch", "새 워크스페이스 기준 브랜치"), selection: $store.pendingWorkspaceBaseBranch) {
                    ForEach(store.availableBranches, id: \.self) { branch in
                        Text(branch).tag(branch)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await store.openRepositoryPicker() }
                } label: {
                    Label(l("Pick Folder", "폴더 선택"), systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ShellTopBarButtonStyle(prominent: false))

                Button {
                    Task { await store.launchTuiSession() }
                } label: {
                    Label(l("Open TUI Session", "TUI 세션 열기"), systemImage: "terminal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ShellTopBarButtonStyle(prominent: true))
                .disabled(store.selectedRepository == nil)
            }

            if let repository = store.selectedRepository {
                HStack(spacing: 8) {
                    ShellTag(text: repository.name, tint: ShellPalette.accent)
                    ShellTag(text: store.pendingWorkspaceBaseBranch, tint: ShellPalette.accentWarm)
                    Spacer()
                }
            }
        }
        .padding(14)
        .shellInset()
    }

    private var issueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(
                title: l("Issues", "이슈"),
                subtitle: l("Issues are the execution units the CEO agent plans, delegates, and routes into runs.", "이슈는 CEO 에이전트가 계획하고 위임하여 실행으로 보내는 단위입니다.")
            )

            if filteredIssues.isEmpty {
                EmptyStateView(
                    image: "square.stack.3d.down.right",
                    title: l("No issues yet", "아직 이슈가 없습니다"),
                    subtitle: l("Select or create a goal to populate the issue queue.", "목표를 선택하거나 생성하면 이슈 큐가 채워집니다.")
                )
                .frame(height: 170)
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredIssues) { issue in
                        IssueSidebarRow(issue: issue, language: l, isSelected: store.selectedIssueID == issue.id) {
                            Task { await store.selectIssue(issue) }
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ShellPalette.text)
            Text(subtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ShellPalette.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tuiStatusTint(_ status: String) -> Color {
        switch status.uppercased() {
        case "RUNNING":
            return ShellPalette.success
        case "STARTING":
            return ShellPalette.accent
        case "FAILED":
            return ShellPalette.danger
        default:
            return ShellPalette.warning
        }
    }

    private func tuiSessionTitle(_ session: TuiSessionRecord) -> String {
        let folderName = URL(fileURLWithPath: session.repositoryPath).lastPathComponent
        return folderName.isEmpty ? session.repositoryPath : folderName
    }
}

private struct CompactLanguagePicker: View {
    @EnvironmentObject private var store: DesktopStore

    var body: some View {
        HStack(spacing: 4) {
            languageButton(.english, label: "EN")
            languageButton(.korean, label: "KO")
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(ShellPalette.panelAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
    }

    private func languageButton(_ language: AppLanguage, label: String) -> some View {
        Button {
            store.setLanguage(language)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(store.language == language ? ShellPalette.text : ShellPalette.muted)
                .frame(width: 34, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(store.language == language ? ShellPalette.panelRaised : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct CompactThemePicker: View {
    @EnvironmentObject private var store: DesktopStore
    private var l: AppLanguage { store.language }

    var body: some View {
        HStack(spacing: 4) {
            themeButton(.light)
            themeButton(.dark)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(ShellPalette.panelAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
        .help(l("Choose light or dark mode. Use Settings for system mode.", "라이트/다크 모드를 고릅니다. 시스템 모드는 설정에서 선택합니다."))
    }

    private func themeButton(_ theme: AppTheme) -> some View {
        Button {
            store.setTheme(theme)
        } label: {
            Image(systemName: theme.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(store.theme == theme ? ShellPalette.text : ShellPalette.muted)
                .frame(width: 34, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(store.theme == theme ? ShellPalette.panelRaised : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.shortLabel(l))
    }
}

private struct GoalRow: View {
    let goal: GoalRecord
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(goal.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(goal.description)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(2)

                HStack {
                    ShellTag(text: language.status(goal.status), tint: statusTint(for: goal.status))
                    Spacer()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? ShellPalette.panelRaised : ShellPalette.panelAlt)
            .overlay(
                RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                    .stroke(isSelected ? ShellPalette.lineStrong : ShellPalette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct GoalNodeCard: View {
    let goal: GoalRecord
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    StatusSummaryPill(text: language.status(goal.status), tint: statusTint(for: goal.status))
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ShellPalette.muted)
                }

                Text(goal.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                Text(goal.description)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    StatusSummaryPill(text: "\(language("Metrics", "지표")) \(goal.successMetrics.count)", tint: ShellPalette.accentWarm)
                    Spacer()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? ShellPalette.panelRaised : ShellPalette.panelAlt)
            .overlay(
                RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                    .stroke(isSelected ? ShellPalette.lineStrong : ShellPalette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PerformanceMetricTile: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(ShellPalette.faint)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(ShellPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ShellPalette.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .fill(ShellPalette.panelAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .stroke(tint.opacity(0.34), lineWidth: 1)
        )
    }
}

private struct PerformanceAgentCard: View {
    let snapshot: AgentPerformanceSnapshotRecord
    let language: AppLanguage

    private var stateText: String {
        if snapshot.dataSufficiency != "SUFFICIENT" {
            return language("Insufficient data", "데이터 부족")
        }
        if (snapshot.score ?? 0) >= 80 {
            return language("Good", "좋음")
        }
        return language("Attention", "주의")
    }

    private var stateTint: Color {
        if snapshot.dataSufficiency != "SUFFICIENT" {
            return ShellPalette.faint
        }
        if (snapshot.score ?? 0) >= 80 {
            return ShellPalette.success
        }
        return ShellPalette.warning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.agentName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                        .lineLimit(1)
                    Text(snapshot.roleName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(snapshot.score.map { "\($0)" } ?? "—")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(ShellPalette.text)
                        .monospacedDigit()
                    StatusSummaryPill(text: stateText, tint: stateTint)
                }
            }

            HStack(spacing: 6) {
                ShellTag(text: snapshot.agentCli, tint: ShellPalette.accent, maxWidth: 110)
                if let model = snapshot.model, !model.isEmpty {
                    ShellTag(text: model, tint: ShellPalette.accentWarm, maxWidth: 170)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], alignment: .leading, spacing: 8) {
                PerformanceValue(label: language("Done", "완료"), value: "\(snapshot.completedIssues)")
                PerformanceValue(label: language("Active", "진행"), value: "\(snapshot.activeIssues)")
                PerformanceValue(label: language("Blocked", "막힘"), value: "\(snapshot.blockedIssues)")
                PerformanceValue(label: language("Run", "실행"), value: percent(snapshot.runSuccessRate))
                PerformanceValue(label: "QA", value: percent(snapshot.qaPassRate))
                PerformanceValue(label: language("Retry", "재시도"), value: "\(snapshot.retryCount)")
                PerformanceValue(label: language("Avg", "평균"), value: duration(snapshot.averageDurationMs))
                PerformanceValue(label: language("Cost", "비용"), value: cost(snapshot.estimatedCostCents))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                .fill(ShellPalette.panelAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func duration(_ value: Int64?) -> String {
        guard let value else { return "—" }
        let seconds = max(0, value / 1_000)
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h"
    }

    private func cost(_ cents: Int?) -> String {
        guard let cents else { return "—" }
        let dollars = Double(cents) / 100.0
        return dollars.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}

private struct PerformanceValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(ShellPalette.faint)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(ShellPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(ShellPalette.panelDeeper)
        )
    }
}

private struct StatusSummaryPill: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ShellPalette.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.14))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tint.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct StatusSummaryLine: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .padding(.top, 4)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ShellPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct IssueSummaryRow: View {
    let issue: IssueRecord
    let language: AppLanguage
    var assignee: OrgAgentProfileRecord? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(statusTint(for: issue.status))
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(userFacingIssueTitle(issue.title, language: language))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                        .lineLimit(2)
                    Spacer()
                    StatusSummaryPill(text: language.status(issue.status), tint: statusTint(for: issue.status))
                }
                Text(userFacingIssueDescription(issue.description, language: language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    StatusSummaryPill(text: userFacingIssueKind(issue.kind, language: language), tint: ShellPalette.accentSoft)
                    if let assignee {
                        StatusSummaryPill(text: assignee.roleName, tint: ShellPalette.accent)
                    }
                    if let linearIdentifier = issue.linearIssueIdentifier, !linearIdentifier.isEmpty {
                        StatusSummaryPill(text: linearIdentifier, tint: ShellPalette.accentWarm)
                    }
                }
            }
        }
        .padding(12)
        .background(ShellPalette.panelAlt)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
    }
}

@MainActor
private func valueLine(label: String, value: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ShellPalette.muted)
        Spacer(minLength: 8)
        Text(value)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ShellPalette.text)
            .multilineTextAlignment(.trailing)
            .textSelection(.enabled)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct AgentWorkSummaryRow: View {
    let agent: CompanyAgentDefinitionRecord
    let profile: OrgAgentProfileRecord?
    let issues: [IssueRecord]
    let language: AppLanguage

    private var assignedIssues: [IssueRecord] {
        guard let profile else { return [] }
        return issues
            .filter { $0.assigneeProfileId == profile.id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                    Text("\(agent.agentCli) · \(agent.roleSummary)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .lineLimit(2)
                }
                Spacer()
                StatusSummaryPill(
                    text: agent.enabled ? "ON" : "OFF",
                    tint: agent.enabled ? ShellPalette.success : ShellPalette.warning
                )
            }

            if let issue = assignedIssues.first {
                IssueSummaryRow(issue: issue, language: language, assignee: profile)
            } else {
                Text(language("No assigned issue", "담당 중인 이슈 없음"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
            }
        }
        .padding(12)
        .background(ShellPalette.panelAlt)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
    }
}

private struct MeetingRoomZoneCard<Content: View>: View {
    let title: String
    let subtitle: String
    let tint: Color
    @ViewBuilder let content: Content

    init(title: String, subtitle: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(ShellPalette.text)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShellPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(ShellPalette.panelAlt)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous))
    }
}

private struct MeetingRoomFeedRow: View {
    let eyebrow: String
    let title: String
    let detail: String?
    let meta: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.14))
                    .clipShape(Capsule())
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(meta)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(ShellPalette.faint)
                    .lineLimit(1)
            }

            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(ShellPalette.text)
                .lineLimit(2)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(ShellPalette.panelDeeper)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
    }
}

private struct MeetingRoomSeatCard: View {
    let title: String
    let subtitle: String
    let status: String
    let tint: Color

    private var isActive: Bool {
        ["RUNNING", "IN_PROGRESS", "STARTING", "QUEUED"].contains(status.uppercased())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            MeetingRoomDotAgentAvatar(tint: tint, isActive: isActive)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ShellPalette.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    StatusSummaryPill(text: status, tint: tint)
                }

                Text(subtitle)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    ShellTag(text: "seat", tint: ShellPalette.panelRaised)
                    ShellTag(text: "live", tint: tint.opacity(0.8))
                }
            }
        }
        .padding(8)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 74, maxHeight: 74, alignment: .topLeading)
        .background(ShellPalette.panelAlt)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .stroke(tint.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
    }
}

private struct MeetingRoomDotAgentAvatar: View {
    let tint: Color
    let isActive: Bool
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(ShellPalette.panelDeeper)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .stroke(tint.opacity(0.35), lineWidth: 1)
                    )

                VStack(spacing: 3) {
                    HStack(spacing: 4) {
                        Circle().fill(ShellPalette.text).frame(width: 3, height: 3)
                        Circle().fill(ShellPalette.text).frame(width: 3, height: 3)
                    }
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(tint)
                        .frame(width: 10, height: 2)
                        .scaleEffect(x: isAnimating ? 1.0 : 0.82, y: 1, anchor: .center)
                }
            }
            .offset(y: isActive && isAnimating ? -1.5 : 0)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint.opacity(0.92))
                .frame(width: 20, height: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(ShellPalette.lineStrong.opacity(0.5), lineWidth: 1)
                )

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(ShellPalette.panelDeeper)
                .frame(width: 26, height: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(ShellPalette.line, lineWidth: 1)
                )
        }
        .frame(width: 30, height: 52, alignment: .top)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
                .opacity(isActive ? (isAnimating ? 1 : 0.35) : 0.45)
        }
        .animation(
            isActive ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
            value: isAnimating
        )
        .onAppear {
            guard isActive else { return }
            isAnimating = true
        }
        .onChange(of: isActive) { _, newValue in
            isAnimating = newValue
        }
    }
}

private enum LocalProposalKind {
    case companyRequest
    case goal
    case goalAutonomy
    case decomposition
    case issue
    case delegation
    case execution
    case qa
    case review
    case runtime
    case agent
    case backend
    case generalNote

    var tint: Color {
        switch self {
        case .companyRequest:
            return ShellPalette.accent
        case .goal:
            return ShellPalette.accent
        case .goalAutonomy:
            return ShellPalette.success
        case .decomposition:
            return ShellPalette.accentWarm
        case .issue:
            return ShellPalette.warning
        case .delegation:
            return ShellPalette.accentWarm
        case .execution:
            return ShellPalette.success
        case .qa:
            return ShellPalette.accentWarm
        case .review:
            return ShellPalette.success
        case .runtime:
            return ShellPalette.accentWarm
        case .agent:
            return ShellPalette.accent
        case .backend:
            return ShellPalette.warning
        case .generalNote:
            return ShellPalette.faint
        }
    }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .companyRequest:
            return language("CEO Intake", "CEO 인테이크")
        case .goal:
            return language("Goal", "목표")
        case .goalAutonomy:
            return language("Goal Autonomy", "목표 자율")
        case .decomposition:
            return language("Decomposition", "분해")
        case .issue:
            return language("Issue", "이슈")
        case .delegation:
            return language("Delegation", "위임")
        case .execution:
            return language("Execution", "실행")
        case .qa:
            return language("QA", "QA")
        case .review:
            return language("Review", "리뷰")
        case .runtime:
            return language("Runtime", "런타임")
        case .agent:
            return language("Agent", "에이전트")
        case .backend:
            return language("Backend", "백엔드")
        case .generalNote:
            return language("General Note", "일반 메모")
        }
    }

    func summary(_ language: AppLanguage) -> String {
        switch self {
        case .companyRequest:
            return language("CEO can turn this chat request into a concrete company plan.", "CEO가 이 채팅 요청을 구체적인 회사 실행안으로 바꿀 수 있습니다.")
        case .goal:
            return language("Looks like a goal-level proposal.", "목표 수준 제안으로 보입니다.")
        case .goalAutonomy:
            return language("Looks like a request to toggle the selected goal's autonomy mode.", "선택한 목표의 자율 모드를 바꾸라는 요청으로 보입니다.")
        case .decomposition:
            return language("Looks like a request to break the selected goal into issues.", "선택한 목표를 이슈로 분해하라는 요청으로 보입니다.")
        case .issue:
            return language("Looks like an issue-level action draft.", "이슈 수준 액션 초안으로 보입니다.")
        case .delegation:
            return language("Looks like a request to assign the selected issue to the team.", "선택한 이슈를 팀에 배정하라는 요청으로 보입니다.")
        case .execution:
            return language("Looks like a request to run the selected issue.", "선택한 이슈를 실행하라는 요청으로 보입니다.")
        case .qa:
            return language("Looks like a QA or verification note.", "QA 또는 검증 메모로 보입니다.")
        case .review:
            return language("Looks like a review or approval step.", "리뷰 또는 승인 단계로 보입니다.")
        case .runtime:
            return language("Looks like a runtime control action.", "런타임 제어 액션으로 보입니다.")
        case .agent:
            return language("Looks like an agent creation or staffing request.", "에이전트 생성 또는 배치 요청으로 보입니다.")
        case .backend:
            return language("Looks like a backend process control action.", "백엔드 프로세스 제어 액션으로 보입니다.")
        case .generalNote:
            return language("Reads like a general room note for later review.", "나중에 검토할 일반 메모처럼 읽힙니다.")
        }
    }
}

private struct LocalProposalPreview {
    let kind: LocalProposalKind
    let targetScope: String
    let riskLevel: String
    let nextStep: String
    let confirmationReason: String
}

private struct CompanyChatControlRail: View {
    @EnvironmentObject private var store: DesktopStore
    let layoutMode: DesktopLayoutMode
    @Binding var draft: String
    @Binding var applyReviewDraft: String
    @State private var isApplyingGoalProposal = false
    @State private var showFullAutoConfirmation = false
    @State private var requestedAutomationMode: String?

    private var l: AppLanguage { store.language }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var scopedMessages: [AgentMessageRecord] {
        let companyID = store.selectedCompanyID
        if let issueID = store.selectedIssue?.id {
            return store.dashboard.agentMessages
                .filter { (companyID == nil || $0.companyId == companyID) && $0.issueId == issueID }
                .sorted { $0.createdAt > $1.createdAt }
        }

        return store.dashboard.agentMessages
            .filter { companyID == nil || $0.companyId == companyID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var scopedContextEntries: [AgentContextEntryRecord] {
        let companyID = store.selectedCompanyID
        if let issueID = store.selectedIssue?.id {
            return store.dashboard.agentContextEntries
                .filter { (companyID == nil || $0.companyId == companyID) && ($0.issueId == issueID || $0.visibility == "company") }
                .sorted { $0.createdAt > $1.createdAt }
        }

        return store.dashboard.agentContextEntries
            .filter { companyID == nil || $0.companyId == companyID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var conversationHistory: [CompanyConversationHistoryItem] {
        Array(
            (scopedMessages.map { CompanyConversationHistoryItem.message($0) } +
                scopedContextEntries.map { CompanyConversationHistoryItem.context($0) })
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(layoutMode == .wide ? 14 : 10)
        )
    }

    private var scopeChip: String {
        if let issue = store.selectedIssue {
            return l("Issue scope", "이슈 범위") + ": " + userFacingIssueTitle(issue.title, language: l)
        }
        if let company = store.selectedCompany {
            return l("Company scope", "회사 범위") + ": " + company.name
        }
        return l("Live company scope", "실시간 회사 범위")
    }

    private var memorySummaryRows: [(String, String, Color)] {
        let companyValue = store.companyMemorySnapshot.map {
            userFacingCompanyMemory($0.companyMemory)
        } ?? (store.selectedCompany?.name ?? l("No company selected", "선택된 회사 없음"))
        let projectValue = store.companyMemorySnapshot.map {
            userFacingWorkflowMemory($0.projectMemory)
        } ?? {
            if let issue = store.selectedIssue {
                return userFacingIssueTitle(issue.title, language: l) + " · " + l.status(issue.status)
            }
            if let goal = store.selectedGoal {
                return goal.title + " · " + l.status(goal.status)
            }
            return l("No active goal or issue selected", "활성 목표/이슈 없음")
        }()
        let teamValue = store.companyMemorySnapshot.map {
            userFacingTeamMemory($0.teamMemory)
        } ?? l("No recent handoff", "최근 인수인계 없음")
        let agentValue = store.companyMemorySnapshot.map {
            userFacingAgentMemory($0.agentMemory)
        } ?? {
            let lead = store.workflowLeadAgent.isEmpty ? (store.dashboard.settings.availableAgents.first ?? "—") : store.workflowLeadAgent
            let count = store.dashboard.runningAgentSessions.count
            return lead + " · " + l("live", "실행중") + " \(count)"
        }()
        return [
            (l("Company memory", "회사 메모리"), companyValue, ShellPalette.accent),
            (l("Project memory", "프로젝트 메모리"), projectValue, ShellPalette.warning),
            (l("Team memory", "팀 메모리"), teamValue, ShellPalette.success),
            (l("Agent memory", "에이전트 메모리"), agentValue, ShellPalette.accentWarm)
        ]
    }

    private func userFacingCompanyMemory(_ raw: String) -> String {
        let fields = memoryFields(from: raw)
        var rows: [String] = []
        appendMemoryRow(&rows, label: l("Company", "회사"), value: fields["company"])
        appendMemoryRow(&rows, label: l("Active goal", "진행 목표"), value: fields["activeGoals"])
        appendMemoryRow(&rows, label: l("Recent", "최근"), value: friendlyMemoryList(fields["recentActivity"], language: l))
        return rows.isEmpty ? redactedMemoryFallback(raw) : rows.joined(separator: "\n")
    }

    private func userFacingWorkflowMemory(_ raw: String) -> String {
        let fields = memoryFields(from: raw)
        var rows: [String] = []
        appendMemoryRow(&rows, label: l("Goal", "목표"), value: fields["goal"])
        appendMemoryRow(&rows, label: l("Issue", "이슈"), value: fields["issue"].map { userFacingIssueTitle($0, language: l) })
        appendMemoryRow(&rows, label: l("Status", "상태"), value: fields["issueStatus"].map(l.status))
        appendMemoryRow(&rows, label: l("Related work", "관련 작업"), value: friendlyMemoryList(fields["goalIssues"], language: l))
        return rows.isEmpty ? redactedMemoryFallback(raw) : rows.joined(separator: "\n")
    }

    private func userFacingAgentMemory(_ raw: String) -> String {
        let fields = memoryFields(from: raw)
        var rows: [String] = []
        appendMemoryRow(&rows, label: l("Lead", "담당"), value: fields["role"])
        appendMemoryRow(&rows, label: l("Tool", "도구"), value: fields["agentCli"])
        appendMemoryRow(&rows, label: l("Assigned", "맡은 일"), value: friendlyMemoryList(fields["assignedIssues"], language: l))
        appendMemoryRow(&rows, label: l("Recent message", "최근 메시지"), value: friendlyMemoryList(fields["recentMessages"], language: l))
        return rows.isEmpty ? redactedMemoryFallback(raw) : rows.joined(separator: "\n")
    }

    private func userFacingTeamMemory(_ raw: String) -> String {
        let fields = memoryFields(from: raw)
        var rows: [String] = []
        appendMemoryRow(&rows, label: l("Decisions", "결정"), value: friendlyMemoryList(fields["recentDecisions"], language: l))
        appendMemoryRow(&rows, label: l("Handoffs", "인수인계"), value: friendlyMemoryList(fields["handoffs"], language: l))
        appendMemoryRow(&rows, label: l("Messages", "메시지"), value: friendlyMemoryList(fields["recentMessages"], language: l))
        return rows.isEmpty ? redactedMemoryFallback(raw) : rows.joined(separator: "\n")
    }

    private func memoryFields(from raw: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in raw.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2, !parts[0].isEmpty, !isInternalMemoryLine(parts[0], parts[1]) {
                fields[parts[0]] = parts[1]
            }
        }
        return fields
    }

    private func appendMemoryRow(_ rows: inout [String], label: String, value: String?) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
        rows.append("\(label): \(value)")
    }

    private func friendlyMemoryList(_ value: String?, language: AppLanguage) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        let items = value.split(separator: "|")
            .map { item in
                let cleaned = item.replacingOccurrences(of: #"\s*\[[^\]]+\]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return userFacingMemoryEvent(cleaned, language: language)
            }
            .filter { !$0.isEmpty && !containsInternalMemoryDetail($0) }
            .prefix(3)
        return items.isEmpty ? nil : items.joined(separator: ", ")
    }

    private func redactedMemoryFallback(_ raw: String) -> String {
        let lines = raw.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !containsInternalMemoryDetail($0) }
            .prefix(3)
        return lines.isEmpty ? l("No summary yet", "아직 요약 없음") : lines.joined(separator: "\n")
    }

    private func isInternalMemoryLine(_ key: String, _ value: String) -> Bool {
        key == "rootPath" || key == "defaultBaseBranch" || key == "graphify" || containsInternalMemoryDetail(value)
    }

    private func containsInternalMemoryDetail(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered.contains("/users/")
            || lowered.contains("graphify ")
            || lowered.contains("graphify=")
            || lowered.contains(".json")
    }

    private var memorySnapshotRequestKey: String {
        [store.selectedCompanyID ?? store.selectedCompany?.id ?? "none", store.selectedIssueID ?? "none"].joined(separator: ":")
    }

    private var stagedProposalPreview: LocalProposalPreview? {
        let stagedDraft = applyReviewDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stagedDraft.isEmpty else { return nil }

        let kind = classifyProposal(stagedDraft)
        return LocalProposalPreview(
            kind: kind,
            targetScope: likelyTargetScope(for: kind),
            riskLevel: proposalRiskLevel(for: kind),
            nextStep: proposalNextStep(for: kind),
            confirmationReason: confirmationReason(for: kind)
        )
    }

    private var stagedGoalProposal: ChatGoalProposal? {
        guard stagedProposalPreview?.kind == .goal else { return nil }
        return store.chatGoalProposal(from: applyReviewDraft)
    }

    private var stagedCompanyRequestProposal: ChatCompanyRequestProposal? {
        guard stagedProposalPreview?.kind == .companyRequest else { return nil }
        return store.chatCompanyRequestProposal(from: applyReviewDraft)
    }

    private var stagedGoalAutonomyProposal: ChatGoalAutonomyProposal? {
        guard stagedProposalPreview?.kind == .goalAutonomy else { return nil }
        return store.chatGoalAutonomyProposal(from: applyReviewDraft)
    }

    private var stagedGoalDecompositionProposal: ChatGoalDecompositionProposal? {
        guard stagedProposalPreview?.kind == .decomposition else { return nil }
        return store.chatGoalDecompositionProposal(from: applyReviewDraft)
    }

    private var stagedIssueProposal: ChatIssueProposal? {
        guard stagedProposalPreview?.kind == .issue else { return nil }
        return store.chatIssueProposal(from: applyReviewDraft)
    }

    private var stagedDelegationProposal: ChatDelegationProposal? {
        guard stagedProposalPreview?.kind == .delegation else { return nil }
        return store.chatDelegationProposal(from: applyReviewDraft)
    }

    private var stagedReviewProposal: ChatReviewProposal? {
        guard let preview = stagedProposalPreview else { return nil }
        switch preview.kind {
        case .qa:
            return store.chatReviewProposal(from: applyReviewDraft, kind: "qa")
        case .review:
            return store.chatReviewProposal(from: applyReviewDraft, kind: "ceo")
        default:
            return nil
        }
    }

    private var stagedMergeProposal: ChatMergeProposal? {
        guard stagedProposalPreview?.kind == .review else { return nil }
        return store.chatMergeProposal(from: applyReviewDraft)
    }

    private var stagedRuntimeProposal: ChatRuntimeProposal? {
        guard stagedProposalPreview?.kind == .runtime else { return nil }
        return store.chatRuntimeProposal(from: applyReviewDraft)
    }

    private var stagedAgentProposal: ChatAgentProposal? {
        guard stagedProposalPreview?.kind == .agent else { return nil }
        return store.chatAgentProposal(from: applyReviewDraft)
    }

    private var stagedBackendProposal: ChatBackendProposal? {
        guard stagedProposalPreview?.kind == .backend else { return nil }
        return store.chatBackendProposal(from: applyReviewDraft)
    }

    private var canApplyGoalProposal: Bool {
        stagedGoalProposal != nil && store.selectedCompany != nil && !isApplyingGoalProposal
    }

    private var canApplyCompanyRequestProposal: Bool {
        stagedCompanyRequestProposal != nil && store.selectedCompany != nil && !isApplyingGoalProposal
    }

    private var canApplyGoalAutonomyProposal: Bool {
        guard let proposal = stagedGoalAutonomyProposal,
              let goal = store.selectedGoal,
              !isApplyingGoalProposal else {
            return false
        }
        return proposal.mode == .enable ? !goal.autonomyEnabled : goal.autonomyEnabled
    }

    private var canApplyGoalDecompositionProposal: Bool {
        stagedGoalDecompositionProposal != nil && store.selectedGoal != nil && !isApplyingGoalProposal
    }

    private var canApplyIssueProposal: Bool {
        stagedIssueProposal != nil && store.selectedCompany != nil && !isApplyingGoalProposal
    }

    private var canApplyDelegationProposal: Bool {
        guard stagedDelegationProposal != nil,
              let issue = store.selectedIssue,
              !isApplyingGoalProposal else {
            return false
        }
        let status = issue.status.uppercased()
        return status != "DELEGATED" && status != "DONE"
    }

    private var canApplyReviewProposal: Bool {
        stagedReviewProposal != nil && stagedMergeProposal == nil && store.selectedReviewQueueItem != nil && !isApplyingGoalProposal
    }

    private var canApplyMergeProposal: Bool {
        guard stagedMergeProposal != nil,
              let item = store.selectedReviewQueueItem,
              !isApplyingGoalProposal else {
            return false
        }
        let prOpen = item.pullRequestState?.uppercased() == "OPEN"
        let mergeable = item.mergeability?.uppercased()
        let readyVerdict = item.ceoVerdict?.uppercased() == "APPROVE" || item.status == "READY_TO_MERGE"
        return prOpen && readyVerdict && (mergeable == nil || mergeable == "CLEAN")
    }

    private var canApplyRuntimeProposal: Bool {
        guard let proposal = stagedRuntimeProposal,
              let company = store.selectedCompany,
              !isApplyingGoalProposal else {
            return false
        }
        let runtime = store.dashboard.companyRuntimes.first(where: { $0.companyId == company.id })
        let isRunning = runtime?.status.uppercased() == "RUNNING"
        switch proposal.action {
        case .start:
            return !isRunning
        case .stop:
            return isRunning
        }
    }

    private var canApplyAgentProposal: Bool {
        stagedAgentProposal != nil && store.selectedCompany != nil && !isApplyingGoalProposal
    }

    private var canApplyBackendProposal: Bool {
        guard let proposal = stagedBackendProposal,
              store.selectedCompany != nil,
              !isApplyingGoalProposal else {
            return false
        }
        let status = store.codexBackendStatus ?? store.dashboard.backendStatuses.first
        let lifecycle = status?.lifecycleState.uppercased()
        switch proposal.action {
        case .start:
            return lifecycle != "RUNNING"
        case .stop:
            return lifecycle == "RUNNING"
        case .restart:
            return lifecycle == "RUNNING" || lifecycle == "STARTING"
        }
    }

    private var selectedLeadAgentLabel: String {
        store.workflowLeadAgent.isEmpty ? (store.dashboard.settings.availableAgents.first ?? "—") : store.workflowLeadAgent
    }

    private var selectedWorkerAgentLabel: String {
        let workers = Array(store.agentSelection.subtracting([selectedLeadAgentLabel])).sorted()
        return workers.isEmpty ? l("No helpers selected", "선택된 도움 에이전트 없음") : workers.joined(separator: ", ")
    }

    private var routingParticipants: [(String, String, Color)] {
        store.dashboard.settings.availableAgents
            .filter { store.agentSelection.contains($0) || $0 == selectedLeadAgentLabel }
            .map { agent in
                let matchingSession = store.dashboard.runningAgentSessions.first {
                    ($0.agentName == agent) || ($0.roleName == agent)
                }
                if let matchingSession {
                    return (agent, l.status(matchingSession.status), statusTint(for: matchingSession.status))
                }
                if agent == selectedLeadAgentLabel {
                    return (agent, l("Lead", "리더"), ShellPalette.accent)
                }
                return (agent, l("Idle", "대기"), ShellPalette.faint)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            operatorHeader
            operatorStatusStrip
            operatorConversationZone
            operatorComposerZone
        }
        .shellCard(accent: ShellPalette.lineStrong)
        .confirmationDialog(
            l("Enable FULL_AUTO?", "FULL_AUTO를 켤까요?"),
            isPresented: $showFullAutoConfirmation,
            titleVisibility: .visible
        ) {
            Button(l("Enable FULL_AUTO", "FULL_AUTO 켜기")) {
                Task {
                    await store.setSelectedCompanyOperatorAutomationMode("FULL_AUTO", confirmFullAuto: true)
                    requestedAutomationMode = nil
                }
            }
            Button(l("Cancel", "취소"), role: .cancel) {
                requestedAutomationMode = nil
            }
        } message: {
            Text(l("Routine approvals will stop. Hard-gated actions remain blocked.", "일반 승인 요청은 줄어들지만 hard-gate 작업은 계속 차단됩니다."))
        }
    }

    private var operatorHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l("Company Operator", "운영 채팅"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                Text(l("Natural-language control for the selected company.", "선택된 회사를 자연어로 운영합니다."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            StatusSummaryPill(text: store.selectedOperatorAutomationMode, tint: automationModeTint(store.selectedOperatorAutomationMode))
        }
    }

    private var operatorStatusStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(l("Automation", "자동화"), selection: Binding(
                get: { store.selectedOperatorAutomationMode },
                set: { nextMode in
                    if nextMode == "FULL_AUTO", store.selectedOperatorAutomationMode != "FULL_AUTO" {
                        requestedAutomationMode = nextMode
                        showFullAutoConfirmation = true
                    } else {
                        Task { await store.setSelectedCompanyOperatorAutomationMode(nextMode) }
                    }
                }
            )) {
                Text("ASK_ME").tag("ASK_ME")
                Text("AGENT_APPROVED").tag("AGENT_APPROVED")
                Text("FULL_AUTO").tag("FULL_AUTO")
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ShellTag(text: scopeChip, tint: ShellPalette.accent)
                    ShellTag(text: l("Runtime", "런타임") + " " + (store.selectedRuntime?.status ?? "STOPPED"), tint: runtimeTint(store.selectedRuntime?.status ?? "STOPPED"))
                    ShellTag(text: l("Approvals", "승인") + " \(operatorPendingApprovalCount)", tint: operatorPendingApprovalCount > 0 ? ShellPalette.warning : ShellPalette.faint)
                    ShellTag(text: l("Blocked", "막힘") + " \(store.scopedOpsMetrics(companyID: store.selectedCompanyID).blockedIssues)", tint: ShellPalette.accentWarm)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var operatorConversationZone: some View {
        MeetingRoomZoneCard(
            title: l("Operator Results", "운영 결과"),
            subtitle: l("Commands, status cards, and internal approval routes.", "명령 결과, 상태 카드, 내부 승인 라우팅입니다."),
            tint: ShellPalette.accent
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if store.operatorCommandResponses.isEmpty && conversationHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        EmptyStateView(
                            image: "terminal",
                            title: l("No operator commands yet", "아직 운영 명령이 없습니다"),
                            subtitle: l("Try a short command below.", "아래에 짧게 입력하세요.")
                        )
                        .frame(minHeight: 150)
                        exampleCommandChips
                    }
                } else {
                    ForEach(store.operatorCommandResponses) { response in
                        operatorResponseCard(response)
                    }
                    ForEach(conversationHistory.prefix(layoutMode == .wide ? 8 : 5)) { item in
                        historyRow(item)
                    }
                }
            }
        }
    }

    private var operatorComposerZone: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $store.operatorCommandDraft)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(ShellPalette.text)
                    .frame(minHeight: layoutMode == .wide ? 106 : 92)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(ShellPalette.panelDeeper)
                    .overlay(
                        RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                            .stroke(ShellPalette.line, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))

                if store.operatorCommandDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(l("에이전트들 잘 돌아가고 있는지 확인해줘", "에이전트들 잘 돌아가고 있는지 확인해줘"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ShellPalette.faint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 8) {
                exampleButton("에이전트들 잘 돌아가?") {
                    store.operatorCommandDraft = "에이전트들 잘 돌아가고 있는지 확인해줘"
                }
                exampleButton("opencode deepseek") {
                    store.operatorCommandDraft = "모든 에이전트 opencode deepseek 모델로 바꿔줘"
                }
                Spacer(minLength: 8)
                Button {
                    let command = store.operatorCommandDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !command.isEmpty else { return }
                    store.operatorCommandDraft = ""
                    Task { _ = await store.runCompanyOperatorCommand(message: command) }
                } label: {
                    Label(l("Run", "실행"), systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedCompany == nil || store.operatorCommandDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var exampleCommandChips: some View {
        FlowLayout(
            items: [
                "에이전트들 잘 돌아가?",
                "모든 에이전트 opencode deepseek",
                "막힌 이슈 다시 굴려"
            ],
            selected: []
        ) { command in
            store.operatorCommandDraft = command
        }
    }

    private func operatorResponseCard(_ response: OperatorCommandResponsePayload) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                StatusSummaryPill(text: response.automationMode, tint: automationModeTint(response.automationMode))
                Spacer(minLength: 0)
                if let summary = response.summary {
                    StatusSummaryPill(text: summary.runtimeStatus, tint: runtimeTint(summary.runtimeStatus))
                }
            }

            Text(response.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ShellPalette.text)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = response.summary {
                HStack(spacing: 6) {
                    summaryChip(l("Agents", "에이전트"), "\(summary.activeAgentCount)", ShellPalette.accent)
                    summaryChip(l("Blocked", "막힘"), "\(summary.blockedIssueCount)", ShellPalette.accentWarm)
                    summaryChip(l("Review", "리뷰"), "\(summary.reviewQueueCount)", ShellPalette.warning)
                    summaryChip(l("Approval", "승인"), "\(summary.pendingApprovalCount)", ShellPalette.faint)
                }
            }

            operatorActionGroup(actions: response.actions, tint: ShellPalette.accent)
            operatorActionGroup(actions: response.pendingApprovals, tint: ShellPalette.warning)
            operatorActionGroup(actions: response.blockedActions, tint: ShellPalette.accentWarm)
        }
        .padding(10)
        .background(ShellPalette.panel)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
    }

    private func operatorActionGroup(actions: [OperatorCommandActionPayload], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(actions) { action in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ShellPalette.text)
                        Text(action.detail)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(ShellPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    StatusSummaryPill(text: action.status, tint: statusTint(for: action.status))
                }
            }
        }
    }

    private func summaryChip(_ title: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(ShellPalette.faint)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(ShellPalette.panelDeeper)
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusTiny, style: .continuous))
    }

    private func exampleButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.borderless)
    }

    private var operatorPendingApprovalCount: Int {
        let responsePending = store.operatorCommandResponses.first?.pendingApprovals.count ?? 0
        return responsePending + (store.selectedRuntime?.waitingApprovalCount ?? 0)
    }

    private func automationModeTint(_ mode: String) -> Color {
        switch mode.uppercased() {
        case "FULL_AUTO": return ShellPalette.accentWarm
        case "ASK_ME": return ShellPalette.warning
        default: return ShellPalette.accent
        }
    }

    private func runtimeTint(_ status: String) -> Color {
        switch status.uppercased() {
        case "RUNNING": return ShellPalette.accent
        case "ERROR": return ShellPalette.accentWarm
        default: return ShellPalette.faint
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l("Company Operator", "운영 채팅"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                Text(
                    l(
                        "Natural-language company operations and internal approval routing.",
                        "자연어 회사 운영과 내부 승인 라우팅입니다."
                    )
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ShellPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            StatusSummaryPill(text: l("LIVE STATE", "실시간 상태"), tint: ShellPalette.accent)
        }
    }

    private var sourceStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ShellTag(text: scopeChip, tint: ShellPalette.accent)
                    ShellTag(text: l("Messages", "메시지") + " \(scopedMessages.count)", tint: ShellPalette.accentWarm)
                    ShellTag(text: l("Context", "컨텍스트") + " \(scopedContextEntries.count)", tint: ShellPalette.warning)
                }
                .padding(.vertical, 2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(l("Chat Team Assignment", "채팅 팀 배정"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(ShellPalette.faint)

                Picker(l("Lead AI", "리더 AI"), selection: Binding(
                    get: { store.workflowLeadAgent.isEmpty ? (store.dashboard.settings.availableAgents.first ?? "") : store.workflowLeadAgent },
                    set: { store.setWorkflowLeadAgent($0) }
                )) {
                    ForEach(store.dashboard.settings.availableAgents, id: \.self) { agent in
                        Text(agent).tag(agent)
                    }
                }
                .pickerStyle(.menu)

                FlowLayout(items: store.dashboard.settings.availableAgents, selected: store.agentSelection) { agent in
                    store.toggleWorkflowAgent(agent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(l("Active participants", "활성 참가자"))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(ShellPalette.faint)

                    ForEach(routingParticipants, id: \.0) { participant in
                        HStack(spacing: 8) {
                            Text(participant.0)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(ShellPalette.text)
                            Spacer(minLength: 8)
                            StatusSummaryPill(text: participant.1, tint: participant.2)
                        }
                    }
                }
            }
        }
    }

    private var memoryStrip: some View {
        MeetingRoomZoneCard(
            title: l("Memory Snapshot", "메모리 스냅샷"),
            subtitle: l(
                "Current company context for the pending request.",
                "대기 중인 요청에 적용되는 현재 회사 컨텍스트입니다."
            ),
            tint: ShellPalette.accentWarm
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(memorySummaryRows.enumerated()), id: \.offset) { _, row in
                    proposalSummaryRow(label: row.0, value: row.1, tint: row.2)
                }
            }
            .task(id: memorySnapshotRequestKey) {
                await store.loadSelectedCompanyMemorySnapshot()
            }
        }
    }

    private var conversationZone: some View {
        MeetingRoomZoneCard(
            title: l("Conversation History", "대화 히스토리"),
            subtitle: l(
                "Recent messages, context updates, and activity signals.",
                "최근 메시지, 컨텍스트 업데이트, 활동 신호를 봅니다."
            ),
            tint: ShellPalette.accent
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if conversationHistory.isEmpty {
                    EmptyStateView(
                        image: "bubble.left.and.text.bubble.right",
                        title: l("No live conversation yet", "아직 실시간 대화가 없습니다"),
                        subtitle: l(
                            "New coordination activity will appear here.",
                            "새 조율 활동이 여기에 표시됩니다."
                        )
                    )
                    .frame(minHeight: 180)
                } else {
                    ForEach(conversationHistory) { item in
                        historyRow(item)
                    }
                }
            }
        }
    }

    private var composerZone: some View {
        MeetingRoomZoneCard(
            title: l("Compose Request", "요청 초안"),
            subtitle: l(
                "Draft a request and review the action before it changes company state.",
                "요청을 작성하고 회사 상태 변경 전 액션을 검토합니다."
            ),
            tint: ShellPalette.warning
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShellPalette.text)
                        .frame(minHeight: layoutMode == .wide ? 124 : 108)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(ShellPalette.panelDeeper)
                        .overlay(
                            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                                .stroke(ShellPalette.line, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))

                    if draft.isEmpty {
                        Text(
                            l(
                                "Describe the company action you want Cotor to prepare.",
                                "Cotor가 준비할 회사 액션을 입력하세요."
                            )
                        )
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.faint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        applyReviewDraft = trimmedDraft
                    } label: {
                        Label(l("Stage Apply Review", "적용 검토 준비"), systemImage: "checklist.checked")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                    .disabled(trimmedDraft.isEmpty)

                    Button {
                        draft = ""
                        applyReviewDraft = ""
                    } label: {
                        Label(l("Clear", "지우기"), systemImage: "xmark")
                    }
                    .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                    .disabled(draft.isEmpty && applyReviewDraft.isEmpty)
                }

                applyReviewPanel
            }
        }
    }

    @ViewBuilder
    private func historyRow(_ item: CompanyConversationHistoryItem) -> some View {
        switch item {
        case let .activity(activity):
            MeetingRoomFeedRow(
                eyebrow: activity.source.uppercased(),
                title: userFacingActivityTitle(activity.title, language: l),
                detail: userFacingActivityDetail(activity.detail ?? activity.source, language: l),
                meta: relativeTimestamp(activity.createdAt),
                tint: statusTint(for: activity.severity)
            )
        case let .message(message):
            MeetingRoomFeedRow(
                eyebrow: message.fromAgentName + " → " + (message.toAgentName ?? l("room", "room")),
                title: message.subject.isEmpty ? l("Agent message", "에이전트 메시지") : message.subject,
                detail: message.body,
                meta: relativeTimestamp(message.createdAt),
                tint: message.kind.lowercased() == "escalation" ? ShellPalette.warning : ShellPalette.accent
            )
        case let .context(entry):
            MeetingRoomFeedRow(
                eyebrow: "\(entry.agentName) · \(entry.kind.uppercased())",
                title: entry.title,
                detail: entry.content,
                meta: relativeTimestamp(entry.createdAt),
                tint: entry.visibility == "company" ? ShellPalette.accentWarm : ShellPalette.warning
            )
        }
    }

    private var applyReviewPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(l("Apply?", "적용할까요?"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                    Text(
                        l(
                            "Review the proposed action before applying it.",
                            "적용하기 전에 제안된 액션을 검토합니다."
                        )
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                }

                Spacer(minLength: 8)

                StatusSummaryPill(text: l("CONFIRM FIRST", "확인 우선"), tint: ShellPalette.warning)
            }

            if applyReviewDraft.isEmpty {
                Text(
                    l(
                        "Prepare a draft to review the proposed action.",
                        "초안을 준비해 제안된 액션을 검토하세요."
                    )
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ShellPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                if let preview = stagedProposalPreview {
                    proposalSummaryCard(preview)
                }

                proposalSummaryRow(
                    label: l("Main agent", "대표 에이전트"),
                    value: selectedLeadAgentLabel,
                    tint: ShellPalette.accent
                )
                proposalSummaryRow(
                    label: l("Helper agents", "도움 에이전트"),
                    value: selectedWorkerAgentLabel,
                    tint: ShellPalette.success
                )

                if let companyRequestProposal = stagedCompanyRequestProposal {
                    proposalSummaryCard(
                        LocalProposalPreview(
                            kind: .companyRequest,
                            targetScope: l("Selected company · \(store.selectedCompany?.name ?? "—")", "선택한 회사 · \(store.selectedCompany?.name ?? "—")"),
                            riskLevel: l("High · creates a real CEO-owned goal and assigned issues after confirmation.", "높음 · 확인 뒤 실제 CEO 소유 목표와 담당 이슈를 생성합니다."),
                            nextStep: l("Create one goal, let CEO clarify the request, and generate assigned work items for the company roster.", "목표 하나를 만들고 CEO가 요청을 정리한 뒤 회사 팀에 배정된 작업을 생성합니다."),
                            confirmationReason: l("The request can be vague, so the app shows the CEO interpretation before changing company state.", "요청이 모호할 수 있으므로 회사 상태를 바꾸기 전에 CEO 해석을 먼저 보여줍니다.")
                        )
                    )

                    proposalSummaryRow(
                        label: l("CEO outcome", "CEO가 정리한 결과"),
                        value: companyRequestProposal.title,
                        tint: ShellPalette.success
                    )
                    proposalSummaryRow(
                        label: l("CEO plan", "CEO 계획"),
                        value: companyRequestProposal.ceoBrief,
                        tint: ShellPalette.accent
                    )
                }

                if let goalProposal = stagedGoalProposal {
                    proposalSummaryCard(
                        LocalProposalPreview(
                            kind: .goal,
                            targetScope: l("Selected company · \(store.selectedCompany?.name ?? "—")", "선택한 회사 · \(store.selectedCompany?.name ?? "—")"),
                            riskLevel: l("High · creates a real company goal immediately after confirmation.", "높음 · 확인 직후 실제 회사 목표를 생성합니다."),
                            nextStep: l("Create one goal with the first draft line as the title and the full draft as the description.", "초안의 첫 줄을 제목으로, 전체 초안을 설명으로 사용해 목표 하나를 생성합니다."),
                            confirmationReason: l("Cotor inferred this from the draft and current selection. Confirm before creating the goal.", "Cotor가 초안과 현재 선택에서 추론했습니다. 목표 생성 전에 확인하세요.")
                        )
                    )

                    proposalSummaryRow(
                        label: l("Confirmed goal title", "확정될 목표 제목"),
                        value: goalProposal.title,
                        tint: ShellPalette.success
                    )
                }

                if let goalAutonomyProposal = stagedGoalAutonomyProposal {
                    proposalSummaryRow(
                        label: l("Autonomy action", "자율 액션"),
                        value: goalAutonomyProposal.mode == .enable ? l("Set selected goal to AUTO", "선택한 목표를 자동으로 설정") : l("Set selected goal to MANUAL", "선택한 목표를 수동으로 설정"),
                        tint: ShellPalette.success
                    )
                    proposalSummaryRow(
                        label: l("Operator note", "운영 메모"),
                        value: goalAutonomyProposal.summary,
                        tint: ShellPalette.warning
                    )
                }

                if let decompositionProposal = stagedGoalDecompositionProposal {
                    proposalSummaryRow(
                        label: l("Decomposition action", "분해 액션"),
                        value: l("Break the selected goal into explicit issues", "선택한 목표를 명시적인 이슈로 분해"),
                        tint: ShellPalette.accentWarm
                    )
                    proposalSummaryRow(
                        label: l("Operator note", "운영 메모"),
                        value: decompositionProposal.summary,
                        tint: ShellPalette.warning
                    )
                }

                if let delegationProposal = stagedDelegationProposal {
                    proposalSummaryRow(
                        label: l("Delegation action", "위임 액션"),
                        value: l("Assign the selected issue to the company team", "선택한 이슈를 회사 팀에 배정"),
                        tint: ShellPalette.accentWarm
                    )
                    proposalSummaryRow(
                        label: l("Operator note", "운영 메모"),
                        value: delegationProposal.summary,
                        tint: ShellPalette.warning
                    )
                }

                if let issueProposal = stagedIssueProposal {
                    proposalSummaryRow(
                        label: l("Target goal", "대상 목표"),
                        value: store.dashboard.goals.first(where: { $0.id == issueProposal.goalId })?.title ?? issueProposal.goalId,
                        tint: ShellPalette.accent
                    )
                    proposalSummaryRow(
                        label: l("Confirmed issue title", "확정될 이슈 제목"),
                        value: issueProposal.title,
                        tint: ShellPalette.success
                    )
                }

                if let reviewProposal = stagedReviewProposal {
                    proposalSummaryRow(
                        label: l("Review stage", "리뷰 단계"),
                        value: reviewProposal.stage == .qa ? l("QA", "QA") : l("CEO", "CEO"),
                        tint: ShellPalette.warning
                    )
                    proposalSummaryRow(
                        label: l("Confirmed verdict", "확정될 판정"),
                        value: l.status(reviewProposal.verdict),
                        tint: ShellPalette.success
                    )
                }

                if let mergeProposal = stagedMergeProposal {
                    proposalSummaryRow(
                        label: l("Merge action", "머지 액션"),
                        value: l("Merge the selected approved pull request", "선택한 승인된 풀 리퀘스트 머지"),
                        tint: ShellPalette.success
                    )
                    proposalSummaryRow(
                        label: l("Operator note", "운영 메모"),
                        value: mergeProposal.summary,
                        tint: ShellPalette.warning
                    )
                }

                if let runtimeProposal = stagedRuntimeProposal {
                    proposalSummaryRow(
                        label: l("Runtime action", "런타임 액션"),
                        value: runtimeProposal.action == .start ? l("Start selected company runtime", "선택한 회사 런타임 시작") : l("Stop selected company runtime", "선택한 회사 런타임 중지"),
                        tint: ShellPalette.accentWarm
                    )
                }

                if let agentProposal = stagedAgentProposal {
                    proposalSummaryRow(
                        label: l("Agent title", "에이전트 직함"),
                        value: agentProposal.title,
                        tint: ShellPalette.accent
                    )
                    proposalSummaryRow(
                        label: l("Specialties", "전문 분야"),
                        value: agentProposal.specialties.joined(separator: " · "),
                        tint: ShellPalette.success
                    )
                }

                if let backendProposal = stagedBackendProposal {
                    proposalSummaryRow(
                        label: l("Backend action", "백엔드 액션"),
                        value: backendProposal.action.rawValue.uppercased(),
                        tint: ShellPalette.warning
                    )
                }

                Text(applyReviewDraft)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ShellPalette.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    stagedCompanyRequestProposal != nil
                        ? l(
                            "Confirming creates the goal, asks the CEO to refine the request, and generates assigned issues.",
                            "확인하면 목표를 만들고 CEO가 요청을 정리한 뒤 담당 이슈를 생성합니다."
                        )
                        : stagedGoalProposal != nil
                        ? l(
                            "Confirming creates one goal in the selected company.",
                            "확인하면 선택한 회사에 목표 하나를 생성합니다."
                        )
                        : stagedGoalAutonomyProposal != nil
                        ? l(
                            "Confirming updates the selected goal's AUTO/MANUAL mode.",
                            "확인하면 선택한 목표의 자동/수동 모드를 변경합니다."
                        )
                        : stagedGoalDecompositionProposal != nil
                        ? l(
                            "Confirming breaks the selected goal into assigned issues.",
                            "확인하면 선택한 목표를 담당 이슈로 분해합니다."
                        )
                        : stagedDelegationProposal != nil
                        ? l(
                            "Confirming assigns the selected issue to the company team.",
                            "확인하면 선택한 이슈를 회사 팀에 배정합니다."
                        )
                        : stagedMergeProposal != nil
                        ? l(
                            "Confirming merges the approved pull request.",
                            "확인하면 승인된 풀 리퀘스트를 머지합니다."
                        )
                        : stagedRuntimeProposal != nil
                        ? l(
                            "Confirming starts or stops the selected company runtime.",
                            "확인하면 선택한 회사 런타임을 시작하거나 중지합니다."
                        )
                        : stagedAgentProposal != nil
                        ? l(
                            "Confirming creates or updates the selected company team member.",
                            "확인하면 선택한 회사 팀원을 생성하거나 변경합니다."
                        )
                        : stagedBackendProposal != nil
                        ? l(
                            "Confirming changes the selected company backend process.",
                            "확인하면 선택한 회사 백엔드 프로세스를 변경합니다."
                        )
                        : stagedReviewProposal != nil
                        ? l(
                            "Confirming submits the selected review verdict.",
                            "확인하면 선택한 리뷰 판정을 제출합니다."
                        )
                        : stagedIssueProposal != nil
                        ? l(
                            "Confirming creates one issue under the selected goal.",
                            "확인하면 선택한 목표 아래에 이슈 하나를 생성합니다."
                        )
                        : l(
                            "This request needs a supported action before it can be applied.",
                            "이 요청은 지원되는 액션으로 정리된 뒤 적용할 수 있습니다."
                        )
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ShellPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        applyReviewDraft = ""
                    } label: {
                        Label(l("Discard Review", "검토 취소"), systemImage: "trash")
                    }
                    .buttonStyle(ShellTopBarButtonStyle(prominent: false))

                    Button {
                        Task {
                            isApplyingGoalProposal = true
                            defer { isApplyingGoalProposal = false }
                            if let companyRequestProposal = stagedCompanyRequestProposal {
                                let saved = await store.applyChatCompanyRequestProposal(companyRequestProposal)
                                guard saved != nil else { return }
                            } else if let goalProposal = stagedGoalProposal {
                                let saved = await store.applyChatGoalProposal(goalProposal)
                                guard saved != nil else { return }
                            } else if let goalAutonomyProposal = stagedGoalAutonomyProposal {
                                let saved = await store.applyChatGoalAutonomyProposal(goalAutonomyProposal)
                                guard saved != nil else { return }
                            } else if let decompositionProposal = stagedGoalDecompositionProposal {
                                let saved = await store.applyChatGoalDecompositionProposal(decompositionProposal)
                                guard saved != nil else { return }
                            } else if let delegationProposal = stagedDelegationProposal {
                                let saved = await store.applyChatDelegationProposal(delegationProposal)
                                guard saved != nil else { return }
                            } else if let issueProposal = stagedIssueProposal {
                                let saved = await store.applyChatIssueProposal(issueProposal)
                                guard saved != nil else { return }
                            } else if let mergeProposal = stagedMergeProposal {
                                let saved = await store.applyChatMergeProposal(mergeProposal)
                                guard saved != nil else { return }
                            } else if let runtimeProposal = stagedRuntimeProposal {
                                let saved = await store.applyChatRuntimeProposal(runtimeProposal)
                                guard saved != nil else { return }
                            } else if let agentProposal = stagedAgentProposal {
                                let saved = await store.applyChatAgentProposal(agentProposal)
                                guard saved != nil else { return }
                            } else if let backendProposal = stagedBackendProposal {
                                let saved = await store.applyChatBackendProposal(backendProposal)
                                guard saved != nil else { return }
                            } else if let reviewProposal = stagedReviewProposal {
                                let saved = await store.applyChatReviewProposal(reviewProposal)
                                guard saved != nil else { return }
                            } else {
                                return
                            }
                            draft = ""
                            applyReviewDraft = ""
                        }
                    } label: {
                        Label(
                            stagedCompanyRequestProposal != nil
                                ? (isApplyingGoalProposal ? l("CEO Planning…", "CEO 계획 중…") : l("Confirm & Let CEO Plan", "확인 후 CEO 계획"))
                                : stagedGoalProposal != nil
                                ? (isApplyingGoalProposal ? l("Creating Goal…", "목표 생성 중…") : l("Confirm & Create Goal", "확인 후 목표 생성"))
                                : stagedGoalAutonomyProposal != nil
                                ? (isApplyingGoalProposal ? l("Updating Goal Mode…", "목표 모드 변경 중…") : l("Confirm Goal Mode", "목표 모드 확인"))
                                : stagedGoalDecompositionProposal != nil
                                ? (isApplyingGoalProposal ? l("Decomposing Goal…", "목표 분해 중…") : l("Confirm & Decompose Goal", "확인 후 목표 분해"))
                                : stagedDelegationProposal != nil
                                ? (isApplyingGoalProposal ? l("Delegating Issue…", "이슈 위임 중…") : l("Confirm & Delegate Issue", "확인 후 이슈 위임"))
                                : stagedIssueProposal != nil
                                ? (isApplyingGoalProposal ? l("Creating Issue…", "이슈 생성 중…") : l("Confirm & Create Issue", "확인 후 이슈 생성"))
                                : stagedMergeProposal != nil
                                ? (isApplyingGoalProposal ? l("Merging PR…", "PR 머지 중…") : l("Confirm & Merge PR", "확인 후 PR 머지"))
                                : stagedRuntimeProposal != nil
                                ? (isApplyingGoalProposal
                                    ? (stagedRuntimeProposal?.action == .start ? l("Starting Runtime…", "런타임 시작 중…") : l("Stopping Runtime…", "런타임 중지 중…"))
                                    : (stagedRuntimeProposal?.action == .start ? l("Confirm & Start Runtime", "확인 후 런타임 시작") : l("Confirm & Stop Runtime", "확인 후 런타임 중지")))
                                : stagedAgentProposal != nil
                                ? (isApplyingGoalProposal ? l("Creating Agent…", "에이전트 생성 중…") : l("Confirm & Create Agent", "확인 후 에이전트 생성"))
                                : stagedBackendProposal != nil
                                ? (isApplyingGoalProposal
                                    ? (stagedBackendProposal?.action == .restart ? l("Restarting Backend…", "백엔드 재시작 중…") : stagedBackendProposal?.action == .stop ? l("Stopping Backend…", "백엔드 중지 중…") : l("Starting Backend…", "백엔드 시작 중…"))
                                    : (stagedBackendProposal?.action == .restart ? l("Confirm & Restart Backend", "확인 후 백엔드 재시작") : stagedBackendProposal?.action == .stop ? l("Confirm & Stop Backend", "확인 후 백엔드 중지") : l("Confirm & Start Backend", "확인 후 백엔드 시작")))
                                : stagedReviewProposal != nil
                                ? (isApplyingGoalProposal ? l("Submitting Verdict…", "판정 제출 중…") : l("Confirm & Submit Verdict", "확인 후 판정 제출"))
                                : l("Confirm & Apply (future)", "확인 후 적용 (추후)"),
                            systemImage: (stagedCompanyRequestProposal != nil || stagedGoalProposal != nil || stagedGoalAutonomyProposal != nil || stagedGoalDecompositionProposal != nil || stagedDelegationProposal != nil || stagedReviewProposal != nil) ? "checkmark.circle.fill" : "lock.fill"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ShellTopBarButtonStyle(prominent: true))
                    .disabled(!(canApplyCompanyRequestProposal || canApplyGoalProposal || canApplyGoalAutonomyProposal || canApplyGoalDecompositionProposal || canApplyDelegationProposal || canApplyIssueProposal || canApplyReviewProposal || canApplyMergeProposal || canApplyRuntimeProposal || canApplyAgentProposal || canApplyBackendProposal))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShellPalette.panelDeeper)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
    }

    private func proposalSummaryCard(_ preview: LocalProposalPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(l("Proposal Preview", "제안 미리보기").uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(ShellPalette.text)
                    Text(preview.kind.summary(l))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShellPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                StatusSummaryPill(text: preview.kind.label(l).uppercased(), tint: preview.kind.tint)
            }

            proposalSummaryRow(
                label: l("Type", "유형"),
                value: preview.kind.label(l),
                tint: preview.kind.tint
            )

            proposalSummaryRow(
                label: l("Likely target scope", "예상 대상 범위"),
                value: preview.targetScope,
                tint: ShellPalette.accent
            )

            proposalSummaryRow(
                label: l("Risk level", "위험도"),
                value: preview.riskLevel,
                tint: ShellPalette.warning
            )

            proposalSummaryRow(
                label: l("Next step after approval", "승인 후 다음 단계"),
                value: preview.nextStep,
                tint: ShellPalette.success
            )

            proposalSummaryRow(
                label: l("Review required", "검토 필요"),
                value: preview.confirmationReason,
                tint: ShellPalette.warning
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShellPalette.panelAlt)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .stroke(preview.kind.tint.opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
    }

    private func proposalSummaryRow(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(ShellPalette.faint)
            }

            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ShellPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func classifyProposal(_ draft: String) -> LocalProposalKind {
        let normalized = " " + draft.lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ") + " "

        let qaScore = keywordScore(in: normalized, keywords: [
            " qa ", " test", " verify", " verification", " regression", " acceptance", " pass", " fail"
        ])
        let reviewScore = keywordScore(in: normalized, keywords: [
            " review", " approve", " approval", " reviewer", " sign-off", " sign off", " merge", " pull request", " review queue"
        ])
        let runtimeScore = keywordScore(in: normalized, keywords: [
            " runtime", " start company", " stop company", " pause runtime", " resume runtime"
        ])
        let agentScore = keywordScore(in: normalized, keywords: [
            " agent ", " qa agent", " review agent", " reviewer ", " tester "
        ])
        let backendScore = keywordScore(in: normalized, keywords: [
            " backend ", " app server ", " codex backend ", " restart backend ", " stop backend ", " start backend "
        ])
        let goalAutonomyScore = keywordScore(in: normalized, keywords: [
            " enable autonomy ", " disable autonomy ", " turn autonomy on ", " turn autonomy off ", " enable auto mode ", " disable auto mode ", " make this goal autonomous ", " make this goal manual "
        ])
        let decompositionScore = keywordScore(in: normalized, keywords: [
            " break this goal ", " decompose this goal ", " split this goal ", " generate issues for this goal ", " break selected goal "
        ])
        let delegationScore = keywordScore(in: normalized, keywords: [
            " delegate this issue ", " assign this issue ", " route this issue ", " delegate selected issue ", " assign selected issue "
        ])
        let goalScore = keywordScore(in: normalized, keywords: [
            " goal", " objective", " roadmap", " milestone", " outcome", " strategy", " north star", " plan"
        ])
        let issueScore = keywordScore(in: normalized, keywords: [
            " issue", " task", " bug", " blocker", " implement", " fix", " ship", " ticket"
        ])

        if qaScore > 0 && qaScore >= reviewScore && qaScore >= goalScore && qaScore >= issueScore {
            return .qa
        }
        if reviewScore > 0 && reviewScore >= goalScore && reviewScore >= issueScore {
            return .review
        }
        if runtimeScore > 0 && runtimeScore >= goalScore && runtimeScore >= issueScore {
            return .runtime
        }
        if agentScore > 0 && agentScore >= goalScore && agentScore >= issueScore {
            return .agent
        }
        if backendScore > 0 && backendScore >= goalScore && backendScore >= issueScore {
            return .backend
        }
        if goalAutonomyScore > 0 && goalAutonomyScore >= goalScore && goalAutonomyScore >= issueScore {
            return .goalAutonomy
        }
        if decompositionScore > 0 && decompositionScore >= goalScore && decompositionScore >= issueScore {
            return .decomposition
        }
        if delegationScore > 0 && delegationScore >= goalScore && delegationScore >= issueScore {
            return .delegation
        }
        if goalScore > 0 && goalScore >= issueScore {
            return .goal
        }
        if issueScore > 0 {
            return .issue
        }
        return .companyRequest
    }

    private func keywordScore(in text: String, keywords: [String]) -> Int {
        keywords.reduce(into: 0) { partialResult, keyword in
            if text.contains(keyword) {
                partialResult += 1
            }
        }
    }

    private func likelyTargetScope(for kind: LocalProposalKind) -> String {
        switch kind {
        case .companyRequest:
            if let company = store.selectedCompany {
                return l("CEO intake · \(company.name)", "CEO 인테이크 · \(company.name)")
            }
        case .goal:
            if let goal = store.selectedGoal {
                return l("Selected goal · \(goal.title)", "선택한 목표 · \(goal.title)")
            }
            if let issue = store.selectedIssue,
               let goal = store.dashboard.goals.first(where: { $0.id == issue.goalId }) {
                return l("Parent goal · \(goal.title)", "상위 목표 · \(goal.title)")
            }
            if let company = store.selectedCompany {
                return l("Company roadmap · \(company.name)", "회사 로드맵 · \(company.name)")
            }
        case .goalAutonomy:
            if let goal = store.selectedGoal {
                return l("Selected goal autonomy · \(goal.title)", "선택한 목표 자율 · \(goal.title)")
            }
        case .decomposition:
            if let goal = store.selectedGoal {
                return l("Selected goal breakdown · \(goal.title)", "선택한 목표 분해 · \(goal.title)")
            }
        case .issue:
            if let issue = store.selectedIssue {
                let title = userFacingIssueTitle(issue.title, language: l)
                return l("Selected issue · \(title)", "선택한 이슈 · \(title)")
            }
            if let goal = store.selectedGoal {
                return l("Issue lane under goal · \(goal.title)", "목표 아래 이슈 레인 · \(goal.title)")
            }
        case .delegation:
            if let issue = store.selectedIssue {
                let title = userFacingIssueTitle(issue.title, language: l)
                return l("Selected issue assignment · \(title)", "선택한 이슈 배정 · \(title)")
            }
        case .execution:
            if let issue = store.selectedIssue {
                let title = userFacingIssueTitle(issue.title, language: l)
                return l("Selected issue execution · \(title)", "선택한 이슈 실행 · \(title)")
            }
        case .qa:
            if let issue = store.selectedIssue {
                let title = userFacingIssueTitle(issue.title, language: l)
                return l("QA pass on issue · \(title)", "이슈 QA 패스 · \(title)")
            }
            if let goal = store.selectedGoal {
                return l("Goal verification pass · \(goal.title)", "목표 검증 패스 · \(goal.title)")
            }
        case .review:
            if let issue = store.selectedIssue, store.selectedReviewQueueItem != nil {
                let title = userFacingIssueTitle(issue.title, language: l)
                return l("Selected review item · \(title)", "선택한 리뷰 항목 · \(title)")
            }
            if let issue = store.selectedIssue {
                let title = userFacingIssueTitle(issue.title, language: l)
                return l("Selected issue review lane · \(title)", "선택한 이슈 리뷰 레인 · \(title)")
            }
        case .runtime:
            if let company = store.selectedCompany {
                return l("Selected company runtime · \(company.name)", "선택한 회사 런타임 · \(company.name)")
            }
        case .agent:
            if let company = store.selectedCompany {
                return l("Selected company team · \(company.name)", "선택한 회사 팀 · \(company.name)")
            }
        case .backend:
            if let company = store.selectedCompany {
                return l("Selected company backend · \(company.name)", "선택한 회사 백엔드 · \(company.name)")
            }
        case .generalNote:
            if let issue = store.selectedIssue {
                let title = userFacingIssueTitle(issue.title, language: l)
                return l("Current issue room · \(title)", "현재 이슈 룸 · \(title)")
            }
            if let goal = store.selectedGoal {
                return l("Current goal room · \(goal.title)", "현재 목표 룸 · \(goal.title)")
            }
        }

        if let company = store.selectedCompany {
            return l("Current company room · \(company.name)", "현재 회사 룸 · \(company.name)")
        }

        return l("Current live company selection", "현재 라이브 회사 선택 범위")
    }

    private func confirmationReason(for kind: LocalProposalKind) -> String {
        switch kind {
        case .companyRequest:
            return l(
                "Creates a goal and assigned issues after confirmation.",
                "확인 후 목표와 담당 이슈를 생성합니다."
            )
        case .goal:
            return l(
                "Creates a goal from the draft and current company selection.",
                "초안과 현재 회사 선택을 기준으로 목표를 생성합니다."
            )
        case .goalAutonomy:
            return l(
                "Updates the selected goal's autonomous follow-up mode.",
                "선택한 목표의 자율 후속 진행 모드를 변경합니다."
            )
        case .decomposition:
            return l(
                "Breaks the selected goal into executable issues.",
                "선택한 목표를 실행 가능한 이슈로 분해합니다."
            )
        case .issue:
            return l(
                "Creates an issue from the draft under the selected goal.",
                "선택한 목표 아래에 초안 기반 이슈를 생성합니다."
            )
        case .delegation:
            return l(
                "Assigns the selected issue to a company agent.",
                "선택한 이슈를 회사 에이전트에게 배정합니다."
            )
        case .execution:
            return l(
                "Starts work on the selected issue.",
                "선택한 이슈의 실행을 시작합니다."
            )
        case .qa:
            return l(
                "Submits a QA verdict for the selected work.",
                "선택한 작업의 QA 판정을 제출합니다."
            )
        case .review:
            return l(
                "Submits a CEO review verdict for the selected item.",
                "선택한 항목의 CEO 리뷰 판정을 제출합니다."
            )
        case .runtime:
            return l(
                "Starts or stops the selected company runtime.",
                "선택한 회사 런타임을 시작하거나 중지합니다."
            )
        case .agent:
            return l(
                "Creates a company agent from the draft.",
                "초안 기반 회사 에이전트를 생성합니다."
            )
        case .backend:
            return l(
                "Changes the selected company backend process state.",
                "선택한 회사 백엔드 프로세스 상태를 변경합니다."
            )
        case .generalNote:
            return l(
                "No supported action has been detected yet.",
                "아직 지원되는 액션이 감지되지 않았습니다."
            )
        }
    }

    private func proposalRiskLevel(for kind: LocalProposalKind) -> String {
        switch kind {
        case .companyRequest:
            return l("High · creates a goal and several assigned work items.", "높음 · 목표와 여러 담당 작업을 생성합니다.")
        case .goal:
            return l("High · changes company direction and can spawn many downstream actions.", "높음 · 회사 방향과 하위 작업 다수를 바꿀 수 있습니다.")
        case .goalAutonomy:
            return l("Medium · changes whether the selected goal keeps generating autonomous follow-up work.", "중간 · 선택한 목표가 자율 후속 작업을 계속 생성할지 바꿉니다.")
        case .decomposition:
            return l("High · expands one goal into multiple new execution issues.", "높음 · 하나의 목표를 여러 새 실행 이슈로 확장합니다.")
        case .issue:
            return l("Medium · likely creates or reshapes one execution item.", "중간 · 하나의 실행 이슈를 만들거나 바꿀 가능성이 큽니다.")
        case .delegation:
            return l("Medium · changes who owns the selected issue next.", "중간 · 다음에 누가 선택한 이슈를 맡는지 바꿉니다.")
        case .execution:
            return l("High · starts real work on the selected issue.", "높음 · 선택한 이슈에서 실제 작업을 시작합니다.")
        case .qa, .review:
            return l("Medium · can alter review or approval state for existing work.", "중간 · 기존 작업의 리뷰/승인 상태를 바꿀 수 있습니다.")
        case .runtime:
            return l("Medium · changes whether the selected company loop is running.", "중간 · 선택한 회사 루프의 실행 여부를 바꿉니다.")
        case .agent:
            return l("Medium · changes the selected company team.", "중간 · 선택한 회사의 인력 구성을 바꿉니다.")
        case .backend:
            return l("Medium · changes the selected company backend process state.", "중간 · 선택한 회사 백엔드 프로세스 상태를 바꿉니다.")
        case .generalNote:
            return l("Low · usually captured as a note until you explicitly apply it.", "낮음 · 명시적으로 적용하기 전까지는 메모로 남을 가능성이 큽니다.")
        }
    }

    private func proposalNextStep(for kind: LocalProposalKind) -> String {
        switch kind {
        case .companyRequest:
            return l("Ask CEO to clarify the chat request, create the goal, and split it into assigned issues.", "CEO에게 채팅 요청을 정리하게 하고 목표와 담당 이슈로 나눕니다.")
        case .goal:
            return l("Review the goal proposal, then create the company goal.", "목표 제안을 검토한 뒤 회사 목표를 생성합니다.")
        case .goalAutonomy:
            return l("Review the goal autonomy action, then change the selected goal's AUTO/MANUAL mode.", "목표 자율 액션을 검토한 뒤 선택한 목표의 자동/수동 모드를 변경합니다.")
        case .decomposition:
            return l("Review the decomposition action, then break the selected goal into issues.", "분해 액션을 검토한 뒤 선택한 목표를 이슈로 분해합니다.")
        case .issue:
            return l("Review the issue draft, then create the issue.", "이슈 초안을 검토한 뒤 이슈를 생성합니다.")
        case .delegation:
            return l("Review the delegation action, then assign the selected issue.", "위임 액션을 검토한 뒤 선택한 이슈를 배정합니다.")
        case .execution:
            return l("Review the execution action, then run the selected issue.", "실행 액션을 검토한 뒤 선택한 이슈를 실행합니다.")
        case .qa:
            return l("Review the QA action, then submit the verdict.", "QA 액션을 검토한 뒤 판정을 제출합니다.")
        case .review:
            return l("Review the approval action, then submit the CEO verdict.", "승인 액션을 검토한 뒤 CEO 판정을 제출합니다.")
        case .runtime:
            return l("Review the runtime action, then start or stop the selected company loop.", "런타임 액션을 검토한 뒤 선택한 회사 루프를 시작하거나 중지합니다.")
        case .agent:
            return l("Review the staffing action, then create the company agent.", "인력 배치 액션을 검토한 뒤 회사 에이전트를 생성합니다.")
        case .backend:
            return l("Review the backend action, then start, stop, or restart the selected company backend.", "백엔드 액션을 검토한 뒤 선택한 회사 백엔드를 시작, 중지, 재시작합니다.")
        case .generalNote:
            return l("Preview a room note and keep it read-only until you intentionally turn it into an action.", "방 메모로 미리 보여주고, 의도적으로 액션으로 바꾸기 전까지는 읽기 전용으로 둡니다.")
        }
    }
}

private struct OrgChartNode: View {
    let profile: OrgAgentProfileRecord
    let language: AppLanguage
    var isLeader: Bool = false
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(isLeader ? ShellPalette.accentWarm : ShellPalette.accent)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: isLeader ? "crown.fill" : "person.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                )

            Text(profile.roleName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ShellPalette.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(profile.executionAgentName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ShellPalette.text.opacity(0.9))

            StatusSummaryPill(
                text: profile.mergeAuthority ? language("CEO", "CEO") : "\(profile.capabilities.count) \(language("skills", "역량"))",
                tint: profile.mergeAuthority ? ShellPalette.success : ShellPalette.accent
            )

            if !profile.capabilities.isEmpty {
                Text(profile.capabilities.joined(separator: " · "))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ShellPalette.text.opacity(0.84))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(isSelected ? ShellPalette.accent.opacity(0.08) : ShellPalette.panelAlt)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                .stroke(
                    isSelected ? ShellPalette.accent : (isLeader ? ShellPalette.success.opacity(0.6) : ShellPalette.line),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous))
        .onTapGesture {
            onTap?()
        }
    }
}

private struct AgentSkillCardView: View {
    let card: AgentSkillCardRecord
    let language: AppLanguage
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(card.enabled ? ShellPalette.success : ShellPalette.warning)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(card.roleSummary.isEmpty ? language("No role summary", "역할 설명 없음") : card.roleSummary)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                        .frame(width: 24, height: 24)
                        .background(ShellPalette.panelRaised)
                        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language("Edit Agent", "에이전트 수정"))
            }

            compactTags([
                (card.agentCli, ShellPalette.accent),
                (card.model ?? "", ShellPalette.accentWarm),
                (card.enabled ? language("ENABLED", "활성") : language("DISABLED", "비활성"), card.enabled ? ShellPalette.success : ShellPalette.warning),
            ].filter { !$0.0.isEmpty })

            if !skillTags.isEmpty {
                compactTags(skillTags)
            }

            if !scopeTags.isEmpty {
                compactTags(scopeTags)
            } else {
                Text(language("No scope configured", "설정된 범위 없음"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ShellPalette.faint)
            }

            if !policyTags.isEmpty {
                compactTags(policyTags)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .padding(12)
        .background(ShellPalette.panelAlt)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .stroke(card.enabled ? ShellPalette.line : ShellPalette.warning.opacity(0.38), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
    }

    private var skillTags: [(String, Color)] {
        var tags = card.selectedSkills.prefix(4).map { ($0.displayName, ShellPalette.accentSoft) }
        if card.selectedSkills.count > 4 {
            tags.append(("+\(card.selectedSkills.count - 4)", ShellPalette.panelRaised))
        }
        return tags
    }

    private var scopeTags: [(String, Color)] {
        card.capabilityScopes.map { ($0.label(language), scopeTint($0)) }
    }

    private var policyTags: [(String, Color)] {
        card.policyChips.map { ($0.rawValue, policyTint($0)) }
    }

    private func compactTags(_ tags: [(String, Color)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                ShellTag(text: tag.0, tint: tag.1, maxWidth: 132)
            }
        }
    }

    private func scopeTint(_ scope: AgentSkillScope) -> Color {
        switch scope {
        case .repositoryMap:
            return ShellPalette.accent
        case .browserQA:
            return ShellPalette.accentWarm
        case .marketing:
            return ShellPalette.warning
        case .video:
            return ShellPalette.accent
        case .videoRender, .videoUpload:
            return ShellPalette.warning
        case .buildTest:
            return ShellPalette.success
        case .qaReview:
            return ShellPalette.accentWarm
        }
    }

    private func policyTint(_ policy: AgentSkillPolicy) -> Color {
        switch policy {
        case .auto:
            return ShellPalette.success
        case .approvalRequired:
            return ShellPalette.warning
        case .readOnly:
            return ShellPalette.accent
        case .disabled:
            return ShellPalette.danger
        }
    }
}

private struct GoalDetailSheet: View {
    let goal: GoalRecord
    let issues: [IssueRecord]
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        StatusSummaryPill(text: language.status(goal.status), tint: statusTint(for: goal.status))
                        Spacer()
                        StatusSummaryPill(text: "\(language("Issues", "이슈")) \(issues.count)", tint: ShellPalette.accent)
                    }

                    Text(goal.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)

                    Text(goal.description)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if !goal.successMetrics.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(language("Success Metrics", "성공 지표"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ShellPalette.text)
                            ForEach(goal.successMetrics, id: \.self) { metric in
                                StatusSummaryLine(text: metric, tint: ShellPalette.accent)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(language("Created Issues", "생성된 이슈"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ShellPalette.text)
                        if issues.isEmpty {
                            Text(language("No issues created yet.", "아직 생성된 이슈가 없습니다."))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ShellPalette.muted)
                        } else {
                            ForEach(issues) { issue in
                                IssueSummaryRow(issue: issue, language: language)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(language("Goal Detail", "목표 상세"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalCloseButton(accessibilityLabel: language("Close goal detail", "목표 상세 닫기")) {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }
}

private struct ModalCloseButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ShellPalette.text)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(ShellPalette.panelAlt)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct RepositoryStackView: View {
    @EnvironmentObject private var store: DesktopStore
    let repository: RepositoryRecord
    let searchText: String
    private var l: AppLanguage { store.language }

    private var workspaces: [WorkspaceRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.dashboard.workspaces.filter { $0.repositoryId == repository.id }
        guard !query.isEmpty else {
            return base.sorted { $0.updatedAt > $1.updatedAt }
        }

        return base
            .filter {
                matches(query: query, values: [
                    $0.name,
                    $0.baseBranch,
                ])
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await store.selectRepository(repository) }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill((store.selectedRepositoryID == repository.id ? ShellPalette.accent : ShellPalette.panelRaised).opacity(0.30))
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(store.selectedRepositoryID == repository.id ? ShellPalette.accentWarm : ShellPalette.muted)
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(repository.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ShellPalette.text)
                            Spacer(minLength: 8)
                            ShellTag(
                                text: localizedSourceKind(repository.sourceKind, language: l),
                                tint: repository.sourceKind.uppercased() == "LOCAL" ? ShellPalette.accent : ShellPalette.accentWarm
                            )
                        }

                        Text(repository.localPath)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(ShellPalette.muted)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            dotLabel(systemImage: "arrow.triangle.branch", text: repository.defaultBranch)
                            if let remote = repository.remoteUrl, !remote.isEmpty {
                                dotLabel(systemImage: "link", text: remote)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(store.selectedRepositoryID == repository.id ? ShellPalette.panelRaised : ShellPalette.panelAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                        .stroke(store.selectedRepositoryID == repository.id ? ShellPalette.lineStrong : ShellPalette.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
            }
            .buttonStyle(.plain)

            if !workspaces.isEmpty {
                VStack(spacing: 7) {
                    ForEach(workspaces) { workspace in
                        Button {
                            Task { await store.selectWorkspace(workspace) }
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(store.selectedWorkspaceID == workspace.id ? ShellPalette.accent : ShellPalette.lineStrong)
                                    .frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(workspace.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(ShellPalette.text)
                                    Text(workspace.baseBranch)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(ShellPalette.muted)
                                }
                                Spacer()
                                Text("\(store.dashboard.tasks.filter { $0.workspaceId == workspace.id }.count)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(ShellPalette.muted)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(store.selectedWorkspaceID == workspace.id ? ShellPalette.accentSoft.opacity(0.82) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 10)
            }
        }
    }

    private func dotLabel(systemImage: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(ShellPalette.faint)
    }
}

private struct SidebarTaskRow: View {
    let task: TaskRecord
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {
                    Text(userFacingIssueTitle(task.title, language: language))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(language.status(task.status))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ShellPalette.muted)
                }

                Text(userFacingIssueDescription(task.prompt, language: language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(2)

                Text(task.agents.joined(separator: " · "))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ShellPalette.faint)
            }
            .padding(.top, 12)
            .padding(.bottom, 12)
            .padding(.trailing, 12)
            .padding(.leading, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(isSelected ? ShellPalette.panelRaised : ShellPalette.panelAlt)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(statusTint(for: task.status))
                    .frame(width: 6)
                    .padding(.vertical, 12)
                    .padding(.leading, 12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                    .stroke(isSelected ? ShellPalette.lineStrong : ShellPalette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct IssueSidebarRow: View {
    let issue: IssueRecord
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(userFacingIssueTitle(issue.title, language: language))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(userFacingIssueDescription(issue.description, language: language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    ShellTag(text: userFacingIssueKind(issue.kind, language: language), tint: ShellPalette.accentSoft)
                    ShellTag(text: language.status(issue.status), tint: statusTint(for: issue.status))
                    Spacer()
                }

                if !issue.dependsOn.isEmpty {
                    HStack(spacing: 8) {
                        ShellTag(text: "\(issue.dependsOn.count) \(language("deps", "의존"))", tint: ShellPalette.warning)
                        Spacer()
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 12)
            .padding(.trailing, 12)
            .padding(.leading, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(isSelected ? ShellPalette.panelRaised : ShellPalette.panelAlt)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(statusTint(for: issue.status))
                    .frame(width: 6)
                    .padding(.vertical, 12)
                    .padding(.leading, 12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                    .stroke(isSelected ? ShellPalette.lineStrong : ShellPalette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CenterPaneView: View {
    @EnvironmentObject private var store: DesktopStore
    let layoutMode: DesktopLayoutMode
    let searchText: String
    @Binding var companySurface: CompanySidebarSurface
    var scrollsInternally: Bool = true
    @State private var goalSurface: GoalSurface = .board
    @State private var companyOverviewSurface: CompanyOverviewSurface = .summary
    @State private var meetingRoomSurface: MeetingRoomSurface = .map
    @State private var detailDrawerOpen = false
    @State private var issueComposerExpanded = false
    @State private var presentedGoal: GoalRecord?
    @State private var companyChatDraft = ""
    @State private var companyChatApplyReviewDraft = ""
    private var l: AppLanguage { store.language }

    private var workflowLeader: String {
        if !store.workflowLeadAgent.isEmpty {
            return store.workflowLeadAgent
        }
        return store.dashboard.settings.availableAgents.first ?? "—"
    }

    private var workerAgents: [String] {
        Array(store.agentSelection.subtracting([workflowLeader])).sorted()
    }

    private var filteredGoals: [GoalRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.goals.sorted { $0.updatedAt > $1.updatedAt }
        guard !query.isEmpty else { return base }

        return base.filter {
            matches(query: query, values: [
                $0.title,
                $0.description,
                $0.status,
                $0.successMetrics.joined(separator: " ")
            ])
        }
    }

    private var selectedGoalIssues: [IssueRecord] {
        guard let goal = store.selectedGoal else { return [] }
        return store.dashboard.issues
            .filter { $0.goalId == goal.id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var selectedIssueTask: TaskRecord? {
        guard let issue = store.selectedIssue else { return nil }
        return store.dashboard.tasks
            .filter { $0.issueId == issue.id }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    private var selectedIssueRuns: [RunRecord] {
        store.runs
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var selectedIssueLog: String {
        if let run = store.selectedRun, let output = run.output, !output.isEmpty {
            return output
        }
        if let run = selectedIssueRuns.first, let output = run.output, !output.isEmpty {
            return output
        }
        if let run = store.selectedRun, let error = run.error, !error.isEmpty {
            return error
        }
        if let run = selectedIssueRuns.first, let error = run.error, !error.isEmpty {
            return error
        }
        if let issueId = store.selectedIssue?.id,
           let liveSnippet = runningSessions.first(where: { $0.issueId == issueId })?.outputSnippet,
           !liveSnippet.isEmpty {
            return liveSnippet
        }
        if let issueId = store.selectedIssue?.id,
           let recentDetail = visibleActivity.first(where: { $0.issueId == issueId })?.detail,
           !recentDetail.isEmpty {
            return recentDetail
        }
        return l("No execution log has been captured for this issue yet.", "이 이슈에 대해 아직 캡처된 실행 로그가 없습니다.")
    }

    private var shouldShowIssueComposer: Bool {
        issueComposerExpanded || filteredIssues.isEmpty
    }

    private var visibleActivity: [CompanyActivityItemRecord] {
        Array(store.activity.prefix(40))
    }

    private var selectedIssueMessages: [AgentMessageRecord] {
        let companyID = store.selectedCompanyID
        guard let issueID = store.selectedIssue?.id else { return [] }
        return store.dashboard.agentMessages
            .filter { (companyID == nil || $0.companyId == companyID) && $0.issueId == issueID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var selectedIssueContextEntries: [AgentContextEntryRecord] {
        let companyID = store.selectedCompanyID
        guard let issueID = store.selectedIssue?.id else { return [] }
        return store.dashboard.agentContextEntries
            .filter { (companyID == nil || $0.companyId == companyID) && ($0.issueId == issueID || $0.visibility == "company") }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var visibleDecisions: [GoalOrchestrationDecisionRecord] {
        Array(
            store.dashboard.goalDecisions
                .filter { store.selectedCompanyID == nil || $0.companyId == store.selectedCompanyID }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(3)
        )
    }

    private var runningSessions: [RunningAgentSessionRecord] {
        store.dashboard.runningAgentSessions
            .filter { store.selectedCompanyID == nil || $0.companyId == store.selectedCompanyID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var scoreablePerformanceSnapshots: [AgentPerformanceSnapshotRecord] {
        store.agentPerformance.filter { $0.score != nil && $0.dataSufficiency == "SUFFICIENT" }
    }

    private var averagePerformanceScore: Int? {
        let scores = scoreablePerformanceSnapshots.compactMap(\.score)
        guard !scores.isEmpty else { return nil }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }

    private var averagePerformanceQaPassRate: Double? {
        let rates = scoreablePerformanceSnapshots.compactMap(\.qaPassRate)
        guard !rates.isEmpty else { return nil }
        return rates.reduce(0, +) / Double(rates.count)
    }

    private func performancePercent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func runningSessionSummary(_ session: RunningAgentSessionRecord) -> String {
        if let issueId = session.issueId,
           let issue = store.dashboard.issues.first(where: { $0.id == issueId }) {
            return userFacingIssueTitle(issue.title, language: l)
        }
        if let snippet = session.outputSnippet?.trimmingCharacters(in: .whitespacesAndNewlines), !snippet.isEmpty {
            return userFacingIssueDescription(snippet, language: l)
        }
        return l("Assigned work is running", "배정된 작업 실행 중")
    }

    private var meetingRoomReviewItems: [ReviewQueueItemRecord] {
        store.dashboard.reviewQueue
            .filter { store.selectedCompanyID == nil || $0.companyId == store.selectedCompanyID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var meetingRoomProjection: MeetingRoomProjection {
        let companyId = store.selectedCompanyID ?? store.selectedCompany?.id
        return MeetingRoomProjection.build(
            companyId: companyId,
            agents: store.dashboard.companyAgentDefinitions,
            goals: store.dashboard.goals,
            orgProfiles: store.dashboard.orgProfiles,
            issues: store.dashboard.issues,
            runningSessions: store.dashboard.runningAgentSessions,
            reviewQueue: store.dashboard.reviewQueue,
            runtime: MeetingRoomProjection.runtime(for: companyId, in: store.dashboard.companyRuntimes),
            activity: store.dashboard.activity,
            messages: store.dashboard.agentMessages
        )
    }

    private var meetingRoomMessages: [AgentMessageRecord] {
        store.dashboard.agentMessages
            .filter { store.selectedCompanyID == nil || $0.companyId == store.selectedCompanyID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var meetingRoomContextEntries: [AgentContextEntryRecord] {
        store.dashboard.agentContextEntries
            .filter { store.selectedCompanyID == nil || $0.companyId == store.selectedCompanyID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var meetingRoomTableSessions: [RunningAgentSessionRecord] {
        Array(runningSessions.prefix(4))
    }

    private var meetingRoomWallActivity: [CompanyActivityItemRecord] {
        Array(store.activity.prefix(2))
    }

    private var meetingRoomSyntheticWallEvents: [MeetingRoomSyntheticEvent] {
        var events: [MeetingRoomSyntheticEvent] = []

        if let runtime = store.dashboard.companyRuntimes
            .filter({ store.selectedCompanyID == nil || $0.companyId == store.selectedCompanyID })
            .sorted(by: {
                let lhs = $0.lastTickAt ?? $0.lastStartedAt ?? $0.lastStoppedAt ?? $0.manuallyStoppedAt ?? 0
                let rhs = $1.lastTickAt ?? $1.lastStartedAt ?? $1.lastStoppedAt ?? $1.manuallyStoppedAt ?? 0
                return lhs > rhs
            })
            .first {
            let runtimeTimestamp = runtime.lastTickAt ?? runtime.lastStartedAt ?? runtime.lastStoppedAt ?? runtime.manuallyStoppedAt ?? 0
            if runtimeTimestamp > 0 {
                events.append(
                    MeetingRoomSyntheticEvent(
                        id: "runtime-\(runtime.companyId ?? "unknown")",
                        createdAt: runtimeTimestamp,
                        eyebrow: l("RUNTIME", "런타임"),
                        title: l("Company loop \(runtime.status)", "회사 루프 \(runtime.status)"),
                        detail: runtime.lastAction ?? runtime.backendMessage ?? runtime.lastError ?? l("Runtime heartbeat updated.", "런타임 heartbeat가 갱신되었습니다."),
                        tint: statusTint(for: runtime.status)
                    )
                )
            }
        }

        for status in store.dashboard.backendStatuses.prefix(2) {
            events.append(
                MeetingRoomSyntheticEvent(
                    id: "backend-\(status.kind)",
                    createdAt: Int64(Date().timeIntervalSince1970 * 1000),
                    eyebrow: l("BACKEND", "백엔드"),
                    title: "\(status.displayName) · \(status.lifecycleState)",
                    detail: status.message ?? status.lastError ?? "\(status.health) · \(status.kind)",
                    tint: statusTint(for: status.lifecycleState)
                )
            )
        }

        for review in meetingRoomReviewItems.prefix(2) {
            events.append(
                MeetingRoomSyntheticEvent(
                    id: "review-\(review.id)",
                    createdAt: review.updatedAt,
                    eyebrow: l("REVIEW", "리뷰"),
                    title: meetingRoomIssueTitle(for: review.issueId),
                    detail: meetingRoomReviewDetail(for: review),
                    tint: reviewTint(review.status)
                )
            )
        }

        for session in runningSessions.prefix(2) {
            let headline = session.outputSnippet?.trimmingCharacters(in: .whitespacesAndNewlines)
            events.append(
                MeetingRoomSyntheticEvent(
                    id: "session-\(session.runId)",
                    createdAt: session.updatedAt,
                    eyebrow: l("AGENT", "에이전트"),
                    title: "\(session.agentName) · \(session.status)",
                    detail: headline?.isEmpty == false ? headline! : (session.roleName ?? session.branchName),
                    tint: statusTint(for: session.status)
                )
            )
        }

        return events.sorted { $0.createdAt > $1.createdAt }
    }

    private var meetingRoomWallItems: [MeetingRoomWallItem] {
        Array(
            (meetingRoomWallActivity.map { MeetingRoomWallItem.activity($0) } +
                meetingRoomContextEntries.prefix(3).map { MeetingRoomWallItem.context($0) } +
                meetingRoomMessages.prefix(3).map { MeetingRoomWallItem.message($0) } +
                meetingRoomSyntheticWallEvents.prefix(6).map { MeetingRoomWallItem.synthetic($0) })
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(8)
        )
    }

    private var meetingRoomCurrentAgendaTitle: String {
        if let issue = store.selectedIssue {
            return userFacingIssueTitle(issue.title, language: l)
        }
        if let goal = store.selectedGoal {
            return goal.title
        }
        return l("No active agenda selected", "활성 안건이 없습니다")
    }

    private var meetingRoomCurrentAgendaDetail: String {
        if let issue = store.selectedIssue {
            return l(
                "Issue · \(l.status(issue.status)) · \(userFacingIssueKind(issue.kind, language: l))",
                "이슈 · \(l.status(issue.status)) · \(userFacingIssueKind(issue.kind, language: l))"
            )
        }
        if let goal = store.selectedGoal {
            return l("Goal · \(l.status(goal.status))", "목표 · \(l.status(goal.status))")
        }
        return l("Select a goal or issue to anchor the room.", "방의 기준이 될 목표나 이슈를 선택하세요.")
    }

    private var meetingRoomNextActionLabel: String {
        if let review = meetingRoomReviewItems.first {
            return l("Review is waiting on \(l.status(review.status)).", "리뷰가 \(l.status(review.status)) 상태를 기다리고 있습니다.")
        }
        if let session = runningSessions.first {
            return l("\(session.roleName ?? session.agentName) is currently \(l.status(session.status)).", "\(session.roleName ?? session.agentName)이(가) 현재 \(l.status(session.status)) 상태입니다.")
        }
        if let issue = store.selectedIssue {
            return l("Next action tracks the selected issue: \(l.status(issue.status)).", "다음 액션은 선택한 이슈의 상태를 따릅니다: \(l.status(issue.status)).")
        }
        return l("No active next action yet.", "아직 활성 다음 액션이 없습니다.")
    }

    private var meetingRoomReviewDeskItems: [ReviewQueueItemRecord] {
        Array(meetingRoomReviewItems.prefix(3))
    }

    private var meetingRoomLatestMessages: [AgentMessageRecord] {
        Array(meetingRoomMessages.prefix(2))
    }

    private var filteredIssues: [IssueRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.issues.sorted { $0.updatedAt > $1.updatedAt }
        guard !query.isEmpty else { return base }

        return base.filter {
            matches(query: query, values: [
                $0.title,
                $0.description,
                $0.status,
                $0.kind,
            ])
        }
    }

    private var filteredTasks: [TaskRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.tasks.sorted { $0.updatedAt > $1.updatedAt }
        guard !query.isEmpty else { return base }

        return base.filter {
            matches(query: query, values: [
                $0.title,
                $0.prompt,
                $0.status,
                $0.agents.joined(separator: " "),
            ])
        }
    }

    var body: some View {
        Group {
            if scrollsInternally {
                ScrollView {
                    content
                }
                .scrollIndicators(.hidden)
            } else {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .shellCard()
        .sheet(item: $presentedGoal) { goal in
            GoalDetailSheet(goal: goal, issues: store.dashboard.issues.filter { $0.goalId == goal.id }, language: l)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            sessionStrip

            if store.shellMode == .tui {
                terminalContextBar
                tuiConsole
            } else {
                companyPageContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var companyPageContent: some View {
        switch companySurface {
        case .company:
            companyOverviewPage
        case .room:
            companyMeetingRoomPage
        case .chat:
            companyChatControlPage
        case .goals:
            goalOverviewPage
        case .performance:
            performanceReviewPage
        case .reports:
            companyReportsPage
        case .agents:
            organizationOverviewPage
        case .issues:
            issuePage
        }
    }

    private var companyMeetingRoomPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            companyPageHeader(
                title: l("Status Room", "상황실"),
                subtitle: l("Monitor live activity, work distribution, and review load.", "실시간 활동, 작업 배정, 리뷰 현황을 모니터링합니다.")
            )
            companyMeetingRoomPanel
        }
    }

    private var companyChatControlPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            companyPageHeader(
                title: l("Company Operator", "운영 채팅"),
                subtitle: l("Run selected-company operations through a command chat.", "선택된 회사 운영을 명령 채팅으로 실행합니다.")
            )
            CompanyChatControlRail(
                layoutMode: layoutMode,
                draft: $companyChatDraft,
                applyReviewDraft: $companyChatApplyReviewDraft
            )
        }
    }

    private var sessionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if store.shellMode == .tui {
                    ForEach(store.tuiSessions) { session in
                        SessionStripItem(
                            title: tuiSessionTitle(session),
                            subtitle: session.baseBranch,
                            tint: store.selectedTuiSessionID == session.id ? ShellPalette.accent : tuiStatusTint(session.status)
                        ) {
                            Task { await store.selectTuiSession(session) }
                        }
                    }
                } else {
                    if let repository = store.selectedRepository {
                        SessionStripItem(
                            title: repository.name,
                            subtitle: repository.defaultBranch,
                            tint: ShellPalette.accent
                        ) {
                            Task { await store.selectRepository(repository) }
                        }
                    }
                    if let workspace = store.selectedWorkspace {
                        SessionStripItem(
                            title: workspace.name,
                            subtitle: workspace.baseBranch,
                            tint: ShellPalette.accentWarm
                        ) {
                            Task { await store.selectWorkspace(workspace) }
                        }
                    }
                    if let goal = store.selectedGoal {
                        SessionStripItem(
                            title: goal.title,
                            subtitle: l.status(goal.status),
                            tint: statusTint(for: goal.status)
                        ) {
                            Task { await store.selectGoal(goal) }
                        }
                    }
                    if let issue = store.selectedIssue {
                        SessionStripItem(
                            title: userFacingIssueTitle(issue.title, language: l),
                            subtitle: l.status(issue.status),
                            tint: statusTint(for: issue.status)
                        ) {
                            withAnimation(ShellMotion.spring) {
                                companySurface = .issues
                            }
                            Task { await store.selectIssue(issue) }
                        }
                    }
                    if let task = store.selectedTask {
                        SessionStripItem(
                            title: userFacingIssueTitle(task.title, language: l),
                            subtitle: task.agents.joined(separator: " · "),
                            tint: statusTint(for: task.status)
                        ) {
                            Task { await store.selectTask(task) }
                        }
                    }
                    if let reviewItem = store.selectedReviewQueueItem {
                        SessionStripItem(
                            title: l("Review Queue", "리뷰 큐"),
                            subtitle: l.status(reviewItem.status),
                            tint: reviewTint(reviewItem.status)
                        ) {}
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var terminalContextBar: some View {
        HStack(spacing: 10) {
            if let session = store.activeTuiSession {
                ShellTag(text: tuiSessionTitle(session), tint: ShellPalette.accent)
                ShellTag(text: session.baseBranch, tint: ShellPalette.accentWarm)
                if let agentName = session.agentName {
                    ShellTag(text: "\(l("CLI", "CLI")): \(agentName)", tint: ShellPalette.accent)
                }
                ShellTag(text: l.status(session.status), tint: tuiStatusTint(session.status))
            } else if let repository = store.selectedRepository {
                ShellTag(text: repository.name, tint: ShellPalette.accent)
                ShellTag(text: store.pendingWorkspaceBaseBranch, tint: ShellPalette.accentWarm)
            }
            Spacer()
        }
    }

    private var companyOverviewPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            companyPageHeader(
                title: l("Company Summary", "회사 요약"),
                subtitle: l("Monitor current goals, active work, runtime health, and reviews.", "현재 목표, 진행 중인 작업, 런타임 상태, 리뷰를 모니터링합니다.")
            )
            HStack(spacing: 8) {
                Button {
                    companyOverviewSurface = .summary
                } label: {
                    Text(l("Summary", "요약"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ShellTopBarButtonStyle(prominent: companyOverviewSurface == .summary))
                .accessibilityLabel(l("Summary", "요약"))
                .accessibilityIdentifier("company-overview-summary")

                Button {
                    companyOverviewSurface = .meetingRoom
                } label: {
                    Text(l("Status Room", "상황실"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ShellTopBarButtonStyle(prominent: companyOverviewSurface == .meetingRoom))
                .accessibilityLabel(l("Status Room", "상황실"))
                .accessibilityIdentifier("company-overview-status-room")
            }

            if companyOverviewSurface == .meetingRoom {
                companyMeetingRoomPanel
            } else {
                operationsBanner
                if store.companyStreamStatusMessage != nil || store.backendStatusMessage != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        if let stream = store.companyStreamStatusMessage, !stream.isEmpty {
                            StatusSummaryPill(text: stream, tint: ShellPalette.warning)
                        }
                        if let backend = store.backendStatusMessage, !backend.isEmpty {
                            StatusSummaryPill(text: backend, tint: ShellPalette.warning)
                        }
                    }
                }

                if layoutMode == .wide {
                    HStack(alignment: .top, spacing: 12) {
                        companyCurrentIssuesPanel
                        companyAgentWorkPanel
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        companyCurrentIssuesPanel
                        companyAgentWorkPanel
                    }
                }

                if layoutMode == .wide {
                    HStack(alignment: .top, spacing: 12) {
                        companyRunningAgentsPanel
                        companyDecisionPanel
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        companyRunningAgentsPanel
                        companyDecisionPanel
                    }
                }

                companyLinearPanel
                companyActivityFeed
            }
        }
    }

    @ViewBuilder
    private var companyRuntimeSummaryStrip: some View {
        if let runtime = store.selectedRuntime {
            let selectedCompany = store.selectedCompany
            let companyID = store.selectedCompany?.id
            let approvalNeededCount = store.dashboard.issues.filter { issue in
                issue.companyId == companyID &&
                    issue.status == "WAITING_FOR_APPROVAL" &&
                    ["execution", "review", "approval"].contains(issue.kind.lowercased())
            }.count
            let blockedWorkflowCount = store.dashboard.issues.filter { issue in
                issue.companyId == companyID &&
                    issue.status == "BLOCKED" &&
                    ["execution", "review", "approval"].contains(issue.kind.lowercased())
            }.count
            let reviewAttentionCount = store.dashboard.reviewQueue.filter { item in
                item.companyId == companyID &&
                    (item.status == "CHANGES_REQUESTED" || item.status == "READY_FOR_CEO")
            }.count
            let runtimeHealthy = runtime.status.uppercased() == "RUNNING" && runtime.backendHealth.lowercased() == "healthy"
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        StatusSummaryPill(text: l.status(runtime.status), tint: companyRuntimeTint(runtime.status))
                        if runtime.isManuallyStopped {
                            ShellTag(
                                text: l("Stopped manually", "수동 중지"),
                                tint: ShellPalette.warning
                            )
                        }
                        StatusSummaryPill(text: runtime.backendHealth.uppercased(), tint: companyRuntimeHealthTint(runtime.backendHealth))
                        if approvalNeededCount > 0 {
                            ShellTag(
                                text: "\(approvalNeededCount) \(l("CEO approvals queued", "CEO 승인 대기"))",
                                tint: ShellPalette.accentWarm
                            )
                        }
                        if blockedWorkflowCount > 0 {
                            ShellTag(
                                text: "\(blockedWorkflowCount) \(l("workflow issues blocked", "워크플로우 차단"))",
                                tint: ShellPalette.warning
                            )
                        }
                        if reviewAttentionCount > 0 {
                            ShellTag(
                                text: "\(reviewAttentionCount) \(l("reviews need attention", "리뷰 대기"))",
                                tint: ShellPalette.accentWarm
                            )
                        }
                        if let company = selectedCompany {
                            ShellTag(
                                text: runtimeSpendSummary(
                                    label: l("Today", "오늘"),
                                    spentCents: runtime.todaySpentCents,
                                    capCents: company.dailyBudgetCents,
                                    language: l
                                ),
                                tint: ShellPalette.accent
                            )
                            ShellTag(
                                text: runtimeSpendSummary(
                                    label: l("Month", "월"),
                                    spentCents: runtime.monthSpentCents,
                                    capCents: company.monthlyBudgetCents,
                                    language: l
                                ),
                                tint: ShellPalette.accentWarm
                            )
                        }
                        if runtime.isBudgetPaused {
                            ShellTag(
                                text: l("Cost cap reached", "비용 상한 도달"),
                                tint: ShellPalette.warning
                            )
                        }
                    }
                }

                if let lastError = runtime.lastError, !lastError.isEmpty {
                    Text("\(l("Latest runtime error", "최근 런타임 오류")): \(lastError)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.danger)
                        .lineLimit(1)
                } else if runtime.isManuallyStopped {
                    Text(
                        l(
                            "Runtime was stopped manually. Press Start to resume company automation.",
                            "런타임이 수동으로 중지되었습니다. 회사 자동화를 다시 시작하려면 시작을 누르세요."
                        )
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(1)
                } else if runtime.isBudgetPaused {
                    Text(
                        l(
                            "Estimated spend hit a configured guardrail. Raise the cap or wait for the budget window to reset.",
                            "추정 비용이 설정한 상한에 도달했습니다. 상한을 올리거나 예산 창이 리셋될 때까지 기다리세요."
                        )
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.warning)
                    .lineLimit(2)
                } else if runtimeHealthy && approvalNeededCount > 0 {
                    Text(
                        l(
                            "Runtime is healthy. A company approval agent is handling pull request creation.",
                            "런타임은 정상입니다. 회사 승인 에이전트가 PR 생성을 처리 중입니다."
                        )
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(1)
                } else if runtimeHealthy && (blockedWorkflowCount > 0 || reviewAttentionCount > 0) {
                    Text(
                        l(
                            "Runtime is healthy. The bottleneck is in QA, CEO approval, or merge follow-up.",
                            "런타임은 정상입니다. 병목은 QA, CEO 승인, 또는 병합 후속 작업입니다."
                        )
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(1)
                } else if let lastAction = runtime.lastAction, !lastAction.isEmpty {
                    Text("\(l("Last runtime action", "최근 런타임 동작")): \(lastAction)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .lineLimit(1)
                }
            }
        }
    }

    private var goalOverviewPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            companyPageHeader(
                title: l("Goals", "목표"),
                subtitle: l("Review goals, edit direction, and inspect generated issues.", "목표를 검토하고 방향을 수정하며 생성된 이슈를 확인합니다.")
            )

            if filteredGoals.isEmpty {
                EmptyStateView(
                    image: "flag.2.crossed",
                    title: l("No goals yet", "아직 목표가 없습니다"),
                    subtitle: l("Create a goal to start company planning.", "목표를 만들어 회사 계획을 시작하세요.")
                )
                .frame(minHeight: 220)
                .shellInset()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    goalNodeGrid
                    selectedGoalSummaryPanel
                }
            }
        }
    }

    private var organizationOverviewPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            companyPageHeader(
                title: l("Team", "팀"),
                subtitle: l("See the team structure and what each agent is working on.", "팀 구성과 각 에이전트가 맡은 이슈를 함께 봅니다.")
            )

            if store.orgProfiles.isEmpty && store.companyAgentDefinitions.isEmpty {
                EmptyStateView(
                    image: "person.3.sequence",
                    title: l("No team yet", "아직 팀이 없습니다"),
                    subtitle: l("Add agents to define the company team.", "에이전트를 추가해 회사 팀을 구성하세요.")
                )
                .frame(minHeight: 240)
                .shellInset()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if !store.orgProfiles.isEmpty {
                        organizationChartPanel
                    }
                    agentSkillCardsPanel
                    organizationWorkPanel
                }
            }
        }
    }

    private var performanceReviewPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            companyPageHeader(
                title: l("Performance", "인사평가"),
                subtitle: l("Derived agent performance signals from issues, runs, and review outcomes.", "이슈, 실행, 리뷰 결과에서 파생한 에이전트 성과 지표입니다.")
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                PerformanceMetricTile(
                    title: l("Average Score", "평균 점수"),
                    value: averagePerformanceScore.map { "\($0)" } ?? "—",
                    detail: l("Scoreable agents", "산정 가능") + " \(scoreablePerformanceSnapshots.count)",
                    tint: ShellPalette.accent
                )
                PerformanceMetricTile(
                    title: l("Data Ready", "데이터 충분"),
                    value: "\(scoreablePerformanceSnapshots.count)",
                    detail: l("of", "전체") + " \(store.agentPerformance.count)",
                    tint: ShellPalette.accentWarm
                )
                PerformanceMetricTile(
                    title: l("QA Pass Rate", "QA 통과율"),
                    value: performancePercent(averagePerformanceQaPassRate),
                    detail: l("Reviewed work only", "리뷰된 작업 기준"),
                    tint: ShellPalette.success
                )
                PerformanceMetricTile(
                    title: l("Retries / Rejections", "재시도 / 반려"),
                    value: "\(store.agentPerformance.reduce(0) { $0 + $1.retryCount }) / \(store.agentPerformance.reduce(0) { $0 + $1.reviewRejectionCount })",
                    detail: l("Current company", "현재 회사"),
                    tint: ShellPalette.warning
                )
            }

            if store.agentPerformance.isEmpty {
                EmptyStateView(
                    image: "chart.line.uptrend.xyaxis",
                    title: l("No performance data yet", "아직 인사평가 데이터가 없습니다"),
                    subtitle: l("Runs and QA reviews will populate this panel.", "실행과 QA 리뷰가 쌓이면 여기에 표시됩니다.")
                )
                .frame(minHeight: 240)
                .shellInset()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                    ForEach(store.agentPerformance) { snapshot in
                        PerformanceAgentCard(snapshot: snapshot, language: l)
                    }
                }
            }
        }
    }

    private var companyReportsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            companyPageHeader(
                title: l("Reports", "보고서"),
                subtitle: l("Read the previous day's work, review outcomes, blockers, and cost snapshot.", "어제 하루의 작업, 리뷰 결과, 막힌 일, 비용 스냅샷을 확인합니다.")
            )

            HStack(spacing: 8) {
                if let report = store.selectedCompanyReport {
                    ShellTag(text: report.date, tint: ShellPalette.accent)
                    ShellTag(text: "\(report.activityCount) \(l("events", "이벤트"))", tint: ShellPalette.accentWarm)
                } else {
                    ShellTag(text: l("No report selected", "선택된 보고서 없음"), tint: ShellPalette.warning)
                }
                Spacer()
                Button {
                    Task { await store.refreshCompanyReports() }
                } label: {
                    Label(l("Refresh", "새로고침"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(ShellTopBarButtonStyle(prominent: false))

                Button {
                    Task { await store.generateCompanyReport() }
                } label: {
                    Label(
                        store.isGeneratingCompanyReport ? l("Generating", "생성 중") : l("Generate Latest", "최신 생성"),
                        systemImage: "doc.badge.plus"
                    )
                }
                .buttonStyle(ShellTopBarButtonStyle(prominent: true))
                .disabled(store.selectedCompany == nil || store.isGeneratingCompanyReport)
            }

            if store.selectedCompanyReports.isEmpty && store.selectedCompanyReport == nil {
                EmptyStateView(
                    image: "doc.text.magnifyingglass",
                    title: l("No morning report yet", "아직 아침 보고서가 없습니다"),
                    subtitle: l("Generate the latest report to summarize yesterday's company operation.", "최신 보고서를 생성하면 어제 회사 운영이 요약됩니다.")
                )
                .frame(minHeight: 260)
                .shellInset()
            } else if layoutMode == .wide {
                HStack(alignment: .top, spacing: 12) {
                    companyReportListPanel
                        .frame(width: 260, alignment: .top)
                    companyReportDetailPanel
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    companyReportListPanel
                    companyReportDetailPanel
                }
            }
        }
        .task(id: store.selectedCompanyID) {
            await store.refreshCompanyReports()
        }
    }

    private var companyReportListPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l("Report Archive", "보고서 보관함"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                Spacer()
                ShellTag(text: "\(store.selectedCompanyReports.count)", tint: ShellPalette.accentWarm)
            }

            if store.selectedCompanyReports.isEmpty {
                Text(l("No saved daily reports.", "저장된 일일 보고서가 없습니다."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(ShellPalette.panelAlt)
                    .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(store.selectedCompanyReports) { summary in
                        Button {
                            Task { await store.selectCompanyReport(date: summary.date) }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(summary.date)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ShellPalette.text)
                                    Spacer()
                                    if store.selectedCompanyReportDate == summary.date {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(ShellPalette.accent)
                                    }
                                }
                                Text(summary.summary)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(ShellPalette.muted)
                                    .lineLimit(3)
                                HStack(spacing: 6) {
                                    ShellTag(text: "\(summary.completedCount) \(l("done", "완료"))", tint: ShellPalette.success)
                                    ShellTag(text: "\(summary.blockedCount) \(l("blocked", "차단"))", tint: summary.blockedCount > 0 ? ShellPalette.warning : ShellPalette.panelRaised)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(store.selectedCompanyReportDate == summary.date ? ShellPalette.panelRaised : ShellPalette.panelAlt)
                            .overlay(
                                RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                                    .stroke(store.selectedCompanyReportDate == summary.date ? ShellPalette.lineStrong : ShellPalette.line, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .shellInset()
    }

    @ViewBuilder
    private var companyReportDetailPanel: some View {
        if let report = store.selectedCompanyReport {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(l("Morning Brief", "아침 보고서"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ShellPalette.text)
                        Spacer()
                        Text(relativeTimestamp(report.generatedAt))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ShellPalette.faint)
                    }
                    Text(report.summary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    PerformanceMetricTile(title: l("Done", "완료"), value: "\(report.completedItems.count)", detail: l("Completed issues", "완료 이슈"), tint: ShellPalette.success)
                    PerformanceMetricTile(title: "QA", value: "\(report.reviewItems.filter { $0.status == "QA_PASS" }.count)", detail: l("Pass results", "통과 결과"), tint: ShellPalette.accent)
                    PerformanceMetricTile(title: l("Blocked", "차단"), value: "\(report.blockedItems.count)", detail: l("Needs attention", "주의 필요"), tint: report.blockedItems.isEmpty ? ShellPalette.panelRaised : ShellPalette.warning)
                    PerformanceMetricTile(title: l("Cost", "비용"), value: usdCurrencyText(report.costSummary.estimatedRunCostCents), detail: l("Estimated run cost", "추정 실행 비용"), tint: ShellPalette.accentWarm)
                }

                if report.costSummary.todaySpentCents > 0 || report.costSummary.monthSpentCents > 0 || report.costSummary.dailyBudgetCents != nil || report.costSummary.monthlyBudgetCents != nil {
                    HStack(spacing: 8) {
                        ShellTag(
                            text: runtimeSpendSummary(
                                label: l("Today", "오늘"),
                                spentCents: report.costSummary.todaySpentCents,
                                capCents: report.costSummary.dailyBudgetCents,
                                language: l
                            ),
                            tint: ShellPalette.accent
                        )
                        ShellTag(
                            text: runtimeSpendSummary(
                                label: l("Month", "월"),
                                spentCents: report.costSummary.monthSpentCents,
                                capCents: report.costSummary.monthlyBudgetCents,
                                language: l
                            ),
                            tint: ShellPalette.accentWarm
                        )
                        if report.costSummary.budgetPaused {
                            ShellTag(text: l("Cost cap reached", "비용 상한 도달"), tint: ShellPalette.warning)
                        }
                        Spacer()
                    }
                }

                companyReportSection(title: l("Highlights", "하이라이트"), items: report.highlights, empty: l("No activity highlights.", "활동 하이라이트가 없습니다."))
                companyReportSection(title: l("Completed Work", "완료한 일"), items: report.completedItems, empty: l("No completed work in this window.", "이 기간에 완료된 일이 없습니다."))
                companyReportSection(title: l("Pull Requests", "Pull Request"), items: report.pullRequests, empty: l("No pull requests changed.", "변경된 PR이 없습니다."))
                companyReportSection(title: l("Review Outcomes", "리뷰 결과"), items: report.reviewItems, empty: l("No QA or CEO review outcomes.", "QA 또는 CEO 리뷰 결과가 없습니다."))
                companyReportSection(title: l("Blocked", "차단"), items: report.blockedItems, empty: l("No blockers recorded for the day.", "이날 기록된 차단 항목이 없습니다."))
                companyReportSection(title: l("Next Actions", "다음 액션"), items: report.recommendedNextActions, empty: l("No recommended action.", "권장 액션이 없습니다."))
            }
            .padding(14)
            .shellInset()
        } else {
            EmptyStateView(
                image: "doc.text",
                title: l("Select a report", "보고서를 선택하세요"),
                subtitle: l("Choose a date from the archive or generate the latest report.", "보관함에서 날짜를 선택하거나 최신 보고서를 생성하세요.")
            )
            .frame(minHeight: 260)
            .shellInset()
        }
    }

    private func companyReportSection(title: String, items: [CompanyDailyReportItemRecord], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                Spacer()
                ShellTag(text: "\(items.count)", tint: items.isEmpty ? ShellPalette.panelRaised : ShellPalette.accentWarm)
            }
            if items.isEmpty {
                Text(empty)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(ShellPalette.panelDeeper)
                    .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in
                        CompanyReportItemRow(item: item, language: l)
                    }
                }
            }
        }
    }

    private var issuePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            companyPageHeader(
                title: l("Issues", "이슈"),
                subtitle: l("Select an issue to see its status, linked task, and latest execution log.", "이슈를 선택하면 상태, 연결된 task, 최근 실행 로그를 볼 수 있습니다.")
            )
            if shouldShowIssueComposer {
                issueComposerPanel
            }
            if layoutMode == .wide, store.selectedIssue != nil {
                HStack(alignment: .top, spacing: 12) {
                    issueBoardWorkspacePanel
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
                    selectedIssueDetailPanel
                        .frame(width: 344, alignment: .top)
                }
            } else {
                if store.selectedIssue != nil {
                    selectedIssueDetailPanel
                }
                issueBoardWorkspacePanel
                if store.selectedIssue == nil {
                    selectedIssueDetailPanel
                }
            }
            detailDrawer
        }
    }

    private var issueBoardWorkspacePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l("Execution Board", "실행 보드"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                    Text(
                        l(
                            "Track issue status, ownership, and execution progress.",
                            "이슈 상태, 담당자, 실행 진행 상황을 추적합니다."
                        )
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                }

                Spacer(minLength: 0)

                surfaceSwitcher
                    .frame(width: layoutMode == .compact ? nil : 220)

                Button {
                    withAnimation(ShellMotion.spring) {
                        issueComposerExpanded.toggle()
                    }
                } label: {
                    Label(
                        shouldShowIssueComposer ? l("Hide Composer", "입력 접기") : l("New Issue", "새 이슈"),
                        systemImage: shouldShowIssueComposer ? "chevron.up.circle" : "plus.circle"
                    )
                }
                .buttonStyle(ShellTopBarButtonStyle(prominent: false))
            }

            issueSurface
        }
        .padding(14)
        .shellInset()
    }

    private var issueComposerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(l("Create Issue", "이슈 만들기"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                Text(l("Create a scoped work item for the selected goal.", "선택한 목표에 연결할 작업 이슈를 만듭니다."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                Spacer()
                if let company = store.issueComposerCompany {
                    StatusSummaryPill(text: company.name, tint: ShellPalette.accent)
                }
                if !filteredIssues.isEmpty {
                    Button {
                        withAnimation(ShellMotion.spring) {
                            issueComposerExpanded = false
                        }
                    } label: {
                        Label(l("Close", "닫기"), systemImage: "xmark")
                    }
                    .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                }
            }

            if layoutMode == .wide {
                HStack(alignment: .top, spacing: 12) {
                    issueComposerFields
                    issueComposerActions
                        .frame(width: 220)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    issueComposerFields
                    issueComposerActions
                }
            }
        }
        .padding(14)
        .shellInset()
    }

    private var issueComposerFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker(l("Company", "회사"), selection: Binding(
                    get: { store.newIssueCompanyID ?? store.selectedCompanyID ?? store.companies.first?.id ?? "" },
                    set: {
                        store.newIssueCompanyID = $0
                        if !store.issueComposerGoals.contains(where: { $0.id == store.newIssueGoalID }) {
                            store.newIssueGoalID = store.issueComposerGoals.first?.id
                        }
                    }
                )) {
                    ForEach(store.companies) { company in
                        Text(company.name).tag(company.id)
                    }
                }
                .pickerStyle(.menu)

                Picker(l("Goal", "목표"), selection: Binding(
                    get: { store.newIssueGoalID ?? store.issueComposerGoals.first?.id ?? "" },
                    set: { store.newIssueGoalID = $0 }
                )) {
                    ForEach(store.issueComposerGoals) { goal in
                        Text(goal.title).tag(goal.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(store.issueComposerGoals.isEmpty)
            }

            TextField(l("Issue title", "이슈 제목"), text: $store.newIssueTitle)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $store.newIssueDescription)
                .font(.system(size: 12, weight: .medium))
                .frame(minHeight: 58, idealHeight: 72, maxHeight: 92)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(ShellPalette.panelAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                        .stroke(ShellPalette.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))

        }
    }

    private var issueComposerActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l("Target", "대상"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ShellPalette.text)

            if let company = store.issueComposerCompany {
                ShellTag(text: company.name, tint: ShellPalette.accent)
            }
            if let goal = store.issueComposerGoals.first(where: { $0.id == (store.newIssueGoalID ?? store.issueComposerGoals.first?.id) }) {
                ShellTag(text: goal.title, tint: ShellPalette.accentWarm)
            }

            Text(
                l(
                    "Use a concrete title and short acceptance-focused description.",
                    "구체적인 제목과 짧은 수용 기준 중심 설명을 사용하세요."
                )
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ShellPalette.muted)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await store.createIssue() }
            } label: {
                Label(l("Create Issue", "이슈 만들기"), systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                store.issueComposerCompany == nil ||
                store.issueComposerGoals.isEmpty ||
                store.newIssueTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                store.newIssueDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }

    private var goalNodeGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
            ForEach(filteredGoals) { goal in
                GoalNodeCard(goal: goal, language: l, isSelected: store.selectedGoalID == goal.id) {
                    Task { await store.selectGoal(goal) }
                    presentedGoal = goal
                }
            }
        }
    }

    private var selectedGoalSummaryPanel: some View {
        Group {
            if let goal = store.selectedGoal {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.title)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(ShellPalette.text)
                            Text(goal.description)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ShellPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        StatusSummaryPill(text: l.status(goal.status), tint: statusTint(for: goal.status))
                    }

                    if !goal.successMetrics.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(l("Success Metrics", "성공 지표"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ShellPalette.text)
                            ForEach(goal.successMetrics, id: \.self) { metric in
                                StatusSummaryLine(
                                    text: metric,
                                    tint: ShellPalette.accent
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(l("Created Issues", "생성된 이슈"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ShellPalette.text)

                        if selectedGoalIssues.isEmpty {
                            Text(l("No issues created yet.", "아직 생성된 이슈가 없습니다."))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ShellPalette.muted)
                        } else {
                            ForEach(selectedGoalIssues.prefix(5)) { issue in
                                Button {
                                    withAnimation(ShellMotion.spring) {
                                        companySurface = .issues
                                    }
                                    Task { await store.selectIssue(issue) }
                                } label: {
                                    IssueSummaryRow(issue: issue, language: l)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            store.beginEditingGoal(goal)
                        } label: {
                            Label(l("Edit Goal", "목표 수정"), systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))

                        Button {
                            presentedGoal = goal
                        } label: {
                            Label(l("Open Detail", "상세 보기"), systemImage: "rectangle.expand.vertical")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))

                        Button(role: .destructive) {
                            Task { await store.deleteSelectedGoal() }
                        } label: {
                            Label(l("Delete Goal", "목표 삭제"), systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                    }
                }
                .padding(16)
                .shellInset()
            }
        }
    }

    private var companyCurrentIssuesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l("Recent Issues", "최근 이슈"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                Spacer()
                ShellTag(text: "\(filteredIssues.count)", tint: ShellPalette.accent)
            }

            if filteredIssues.isEmpty {
                EmptyStateView(
                    image: "square.stack.3d.down.right",
                    title: l("No issues yet", "아직 이슈가 없습니다"),
                    subtitle: l("Goals will decompose into issues and show up here.", "목표가 이슈로 분해되면 여기에 표시됩니다.")
                )
                .frame(height: 180)
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredIssues.prefix(5)) { issue in
                        Button {
                            withAnimation(ShellMotion.spring) {
                                companySurface = .issues
                            }
                            Task { await store.selectIssue(issue) }
                        } label: {
                            IssueSummaryRow(issue: issue, language: l, assignee: store.orgProfiles.first(where: { $0.id == issue.assigneeProfileId }))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .shellInset()
    }

    private var companyAgentWorkPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l("Agent Work", "에이전트 작업"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                Spacer()
            }

            if store.companyAgentDefinitions.isEmpty {
                EmptyStateView(
                    image: "person.2",
                    title: l("No agents yet", "아직 에이전트가 없습니다"),
                    subtitle: l("Add an agent to see current assignments.", "에이전트를 추가하면 현재 담당 이슈가 보입니다.")
                )
                .frame(height: 180)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.companyAgentDefinitions.prefix(5)) { agent in
                        AgentWorkSummaryRow(
                            agent: agent,
                            profile: store.orgProfiles.first(where: {
                                $0.companyId == agent.companyId && $0.executionAgentName == agent.agentCli && $0.roleName == agent.title
                            }),
                            issues: filteredIssues,
                            language: l
                        )
                    }
                }
            }
        }
        .padding(14)
        .shellInset()
    }

    private var companyRunningAgentsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l("Running Agents", "실행 중인 에이전트"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                Spacer()
                ShellTag(text: "\(runningSessions.count)", tint: ShellPalette.accentWarm)
            }

            if runningSessions.isEmpty {
                EmptyStateView(
                    image: "play.circle",
                    title: l("No live runs", "실행 중인 작업이 없습니다"),
                    subtitle: l("When the CEO loop dispatches work, live agent sessions appear here.", "CEO 루프가 작업을 배정하면 여기에서 실시간 세션이 보입니다.")
                )
                .frame(height: 180)
            } else {
                VStack(spacing: 8) {
                    ForEach(runningSessions.prefix(5)) { session in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(session.roleName ?? session.agentName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(ShellPalette.text)
                                Spacer()
                                StatusSummaryPill(text: l.status(session.status), tint: statusTint(for: session.status))
                            }
                            Text(runningSessionSummary(session))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ShellPalette.muted)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(ShellPalette.panelAlt)
                        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
                    }
                }
            }
        }
        .padding(14)
        .shellInset()
    }

    private var companyMeetingRoomPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ShellTag(text: l("Live Office", "라이브 오피스"), tint: ShellPalette.accent)
                ShellTag(text: "\(meetingRoomProjection.agents.count) \(l("agents", "에이전트"))", tint: ShellPalette.accentWarm)
                ShellTag(text: "\(meetingRoomProjection.reviewCount) \(l("reviews", "리뷰"))", tint: ShellPalette.warning)
                Spacer(minLength: 0)
                Button {
                    withAnimation(ShellMotion.spring) {
                        detailDrawerOpen.toggle()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text(detailDrawerOpen ? l("Hide Activity", "활동 숨김") : l("Activity", "활동"))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(detailDrawerOpen ? ShellPalette.text : ShellPalette.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(detailDrawerOpen ? ShellPalette.panelRaised : ShellPalette.panelAlt)
                    .overlay(
                        RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                            .stroke(detailDrawerOpen ? ShellPalette.accent.opacity(0.42) : ShellPalette.line, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(detailDrawerOpen ? l("Hide activity drawer", "활동 drawer 숨기기") : l("Show activity drawer", "활동 drawer 보기"))
            }

            meetingRoomAgendaStrip

            if layoutMode == .wide {
                HStack(alignment: .top, spacing: 12) {
                    meetingRoomFloorSurface
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                    if detailDrawerOpen {
                        meetingRoomActivityDrawer
                            .frame(width: 340, alignment: .topLeading)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    meetingRoomFloorSurface
                    if detailDrawerOpen {
                        meetingRoomActivityDrawer
                    }
                }
            }
        }
        .padding(12)
        .shellInset()
    }

    private var meetingRoomActivityDrawer: some View {
        VStack(alignment: .leading, spacing: 12) {
            meetingRoomEventWallZone
            meetingRoomReviewDeskZone
        }
    }

    @ViewBuilder
    private var meetingRoomAgendaStrip: some View {
        if layoutMode == .wide {
            HStack(alignment: .top, spacing: 8) {
                agendaSummaryRow(label: l("Agenda", "안건"), value: meetingRoomCurrentAgendaTitle, tint: ShellPalette.accent)
                agendaSummaryRow(label: l("State", "상태"), value: meetingRoomCurrentAgendaDetail, tint: ShellPalette.accentWarm)
                agendaSummaryRow(label: l("Next", "다음"), value: meetingRoomNextActionLabel, tint: ShellPalette.warning)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                agendaSummaryRow(label: l("Agenda", "안건"), value: meetingRoomCurrentAgendaTitle, tint: ShellPalette.accent)
                agendaSummaryRow(label: l("Next", "다음"), value: meetingRoomNextActionLabel, tint: ShellPalette.warning)
            }
        }
    }

    @ViewBuilder
    private var meetingRoomMapSurface: some View {
        if layoutMode == .wide {
            HStack(alignment: .top, spacing: 12) {
                MeetingRoomBrainGraphPane(
                    rootPath: store.selectedCompany?.rootPath,
                    language: store.language,
                    isCompact: layoutMode == .compact
                )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 12) {
                    meetingRoomCenterTableZone
                    meetingRoomReviewDeskZone
                }
                .frame(width: 336, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                MeetingRoomBrainGraphPane(
                    rootPath: store.selectedCompany?.rootPath,
                    language: store.language,
                    isCompact: layoutMode == .compact
                )
                meetingRoomCenterTableZone
            }
        }
    }

    @ViewBuilder
    private var meetingRoomMeetingSurface: some View {
        if layoutMode == .wide {
            HStack(alignment: .top, spacing: 12) {
                meetingRoomCenterTableZone
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                meetingRoomEventWallZone
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 12) {
                meetingRoomReviewDeskZone
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                MeetingRoomView(
                    projection: meetingRoomProjection,
                    language: store.language,
                    inboxCount: meetingRoomReviewItems.count + meetingRoomMessages.count,
                    isCompact: true
                )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                meetingRoomCenterTableZone
                meetingRoomEventWallZone
                meetingRoomReviewDeskZone
            }
        }
    }

    private var meetingRoomFloorSurface: some View {
        MeetingRoomView(
            projection: meetingRoomProjection,
            language: store.language,
            inboxCount: meetingRoomReviewItems.count + meetingRoomMessages.count,
            isCompact: layoutMode == .compact
        )
    }

    private func meetingRoomSurfaceButton(surface: MeetingRoomSurface, title: String, systemImage: String) -> some View {
        let isSelected = meetingRoomSurface == surface
        return Button {
            meetingRoomSurface = surface
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(isSelected ? ShellPalette.text : ShellPalette.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? ShellPalette.panelRaised : ShellPalette.panelAlt)
            .overlay(
                RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                    .stroke(isSelected ? ShellPalette.accent.opacity(0.42) : ShellPalette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityIdentifier("meeting-room-surface-\(surface.id)")
    }

    @ViewBuilder
    private func agendaSummaryRow(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ShellPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(ShellPalette.panelAlt)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
    }

    private var meetingRoomEventWallZone: some View {
        MeetingRoomZoneCard(
            title: l("Event Wall", "이벤트 월"),
            subtitle: l("Recent activity and pinned context.", "최근 활동과 고정된 컨텍스트를 봅니다."),
            tint: ShellPalette.accent
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if meetingRoomWallItems.isEmpty {
                    meetingRoomEmptyState(
                        title: l("No room events yet", "아직 방 이벤트가 없습니다"),
                        detail: l("Activity and shared context will pin to this wall as the company starts moving.", "회사가 움직이기 시작하면 활동과 공유 컨텍스트가 이 벽에 표시됩니다.")
                    )
                } else {
                    ForEach(meetingRoomWallItems, id: \.id) { item in
                        switch item {
                        case let .activity(activity):
                            MeetingRoomFeedRow(
                                eyebrow: activity.source.uppercased(),
                                title: userFacingActivityTitle(activity.title, language: l),
                                detail: userFacingActivityDetail(activity.detail ?? activity.source, language: l),
                                meta: relativeTimestamp(activity.createdAt),
                                tint: statusTint(for: activity.severity)
                            )
                        case let .message(message):
                            let target = message.toAgentName ?? l("room", "room")
                            MeetingRoomFeedRow(
                                eyebrow: "\(message.fromAgentName) → \(target)",
                                title: message.subject.isEmpty ? l("Agent message", "에이전트 메시지") : message.subject,
                                detail: message.body,
                                meta: relativeTimestamp(message.createdAt),
                                tint: message.kind.lowercased() == "escalation" ? ShellPalette.warning : ShellPalette.accent
                            )
                        case let .context(entry):
                            MeetingRoomFeedRow(
                                eyebrow: "\(entry.agentName) · \(entry.kind.uppercased())",
                                title: entry.title,
                                detail: entry.content,
                                meta: relativeTimestamp(entry.createdAt),
                                tint: entry.visibility == "company" ? ShellPalette.accentWarm : ShellPalette.accent
                            )
                        case let .synthetic(event):
                            MeetingRoomFeedRow(
                                eyebrow: event.eyebrow,
                                title: event.title,
                                detail: event.detail,
                                meta: relativeTimestamp(event.createdAt),
                                tint: event.tint
                            )
                        }
                    }
                }
            }
        }
    }

    private var meetingRoomCenterTableZone: some View {
        MeetingRoomZoneCard(
            title: l("Center Table", "중앙 테이블"),
            subtitle: l("Live agents and recent activity.", "실행 중인 에이전트와 최근 활동입니다."),
            tint: ShellPalette.accentWarm
        ) {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geometry in
                    let tableWidth = min(max(geometry.size.width * (layoutMode == .compact ? 0.56 : 0.48), 160), 248)

                    ZStack {
                        RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                            .fill(ShellPalette.panelDeeper)
                            .overlay(
                                RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                                    .stroke(ShellPalette.line, lineWidth: 1)
                            )

                        VStack(spacing: 18) {
                            HStack(spacing: 12) {
                                meetingRoomSeatSlot(meetingRoomTableSessions[safe: 0])
                                Spacer(minLength: 12)
                                meetingRoomSeatSlot(meetingRoomTableSessions[safe: 1])
                            }
                            HStack(spacing: 12) {
                                meetingRoomSeatSlot(meetingRoomTableSessions[safe: 2])
                                Spacer(minLength: 12)
                                meetingRoomSeatSlot(meetingRoomTableSessions[safe: 3])
                            }
                        }
                        .padding(12)

                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(ShellPalette.panelAlt)
                            .frame(width: tableWidth, height: 84)
                            .overlay(
                                VStack(spacing: 4) {
                                    Text(l("CENTER TABLE", "중앙 테이블"))
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .tracking(0.8)
                                        .foregroundStyle(ShellPalette.faint)
                                    if runningSessions.isEmpty {
                                        Text(l("No live agents", "실행 중인 에이전트 없음"))
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(ShellPalette.text)
                                        Text(l("Waiting for the next company dispatch.", "다음 회사 작업 배정을 기다리는 중입니다."))
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundStyle(ShellPalette.muted)
                                            .lineLimit(2)
                                    } else {
                                        Text("\(runningSessions.count) \(l("live agents", "실행 에이전트"))")
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(ShellPalette.text)
                                        Text(meetingRoomTableHeadline)
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundStyle(ShellPalette.muted)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .padding(.horizontal, 12)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(ShellPalette.lineStrong, lineWidth: 1)
                            )
                    }
                }
                .frame(height: 184)

                VStack(alignment: .leading, spacing: 8) {
                    Text(l("Latest Updates", "최근 업데이트"))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(ShellPalette.faint)

                    if meetingRoomLatestMessages.isEmpty {
                        meetingRoomEmptyState(
                            title: l("No agent messages yet", "아직 에이전트 메시지가 없습니다"),
                            detail: l("Agent updates will appear here.", "에이전트 업데이트가 여기에 표시됩니다.")
                        )
                    } else {
                        ForEach(meetingRoomLatestMessages) { message in
                            MeetingRoomFeedRow(
                                eyebrow: "\(message.fromAgentName) → \(message.toAgentName ?? l("room", "room"))",
                                title: message.subject.isEmpty ? l("Agent message", "에이전트 메시지") : message.subject,
                                detail: message.body,
                                meta: relativeTimestamp(message.createdAt),
                                tint: message.kind.lowercased() == "escalation" ? ShellPalette.warning : ShellPalette.accent
                            )
                        }
                    }
                }
            }
        }
    }

    private var meetingRoomReviewDeskZone: some View {
        MeetingRoomZoneCard(
            title: l("Reviews", "리뷰"),
            subtitle: l("What QA and CEO need to look at next.", "QA와 CEO가 다음에 봐야 할 대상을 보여줍니다."),
            tint: ShellPalette.warning
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if meetingRoomReviewDeskItems.isEmpty {
                    meetingRoomEmptyState(
                        title: l("No reviews waiting", "대기 중인 리뷰가 없습니다"),
                        detail: l("Review-ready work will appear here.", "리뷰 대기 작업이 여기에 표시됩니다.")
                    )
                } else {
                    ForEach(meetingRoomReviewDeskItems) { item in
                        MeetingRoomFeedRow(
                            eyebrow: item.pullRequestNumber.map { "PR #\($0)" } ?? l("Review Queue", "리뷰 큐"),
                            title: meetingRoomIssueTitle(for: item.issueId),
                            detail: meetingRoomReviewDetail(for: item),
                            meta: relativeTimestamp(item.updatedAt),
                            tint: reviewTint(item.status)
                        )
                    }
                }
            }
        }
    }

    private var companyDecisionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l("CEO Decisions", "CEO 결정"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                Spacer()
            }

            if visibleDecisions.isEmpty {
                EmptyStateView(
                    image: "point.topleft.down.curvedto.point.bottomright.up",
                    title: l("No decisions yet", "아직 결정이 없습니다"),
                    subtitle: l("CEO decisions will appear here.", "CEO 결정이 여기에 표시됩니다.")
                )
                .frame(height: 180)
            } else {
                VStack(spacing: 8) {
                    ForEach(visibleDecisions) { decision in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(userFacingDecisionTitle(decision.title, language: l))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ShellPalette.text)
                            Text(userFacingDecisionSummary(decision.summary, language: l))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ShellPalette.muted)
                                .lineLimit(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(ShellPalette.panelAlt)
                        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
                    }
                }
            }
        }
        .padding(14)
        .shellInset()
    }

    private var companyLinearPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l("Linear Mirror", "Linear 미러"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                Spacer()
                StatusSummaryPill(
                    text: (store.selectedCompany?.linearSyncEnabled ?? false) ? l("Enabled", "사용 중") : l("Optional", "선택 사항"),
                    tint: (store.selectedCompany?.linearSyncEnabled ?? false) ? ShellPalette.success : ShellPalette.warning
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                valueLine(label: l("Endpoint", "엔드포인트"), value: store.companyLinearEndpoint.isEmpty ? "https://api.linear.app/graphql" : store.companyLinearEndpoint)
                valueLine(label: l("Team", "팀"), value: store.companyLinearTeamID.isEmpty ? l("Not set", "미설정") : store.companyLinearTeamID)
                valueLine(label: l("Project", "프로젝트"), value: store.companyLinearProjectID.isEmpty ? l("Not set", "미설정") : store.companyLinearProjectID)

                if let message = store.companyLinearStatusMessage, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(l("Linear sync events and failures are listed here.", "Linear 동기화 이벤트와 실패를 여기에 표시합니다."))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                }
            }
        }
        .padding(14)
        .shellInset()
    }

    private var orgSelectionToolbar: some View {
        HStack(spacing: 12) {
            Text("\(store.selectedOrgProfileIDs.count) selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ShellPalette.muted)

            Spacer()

            Button(action: {
                store.clearOrgProfileSelection()
            }) {
                Text(l("Clear", "해제"))
            }
            .buttonStyle(ShellTopBarButtonStyle(prominent: false))

            Button(action: {
                store.showingOrgProfileBatchEdit = true
            }) {
                Text(l("Edit", "편집"))
            }
            .buttonStyle(ShellTopBarButtonStyle(prominent: false))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ShellPalette.panelAlt)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
    }

    private var organizationChartPanel: some View {
        let leader = store.orgProfiles.first(where: { $0.mergeAuthority }) ?? store.orgProfiles.first
        let others = store.orgProfiles.filter { $0.id != leader?.id }
        let qaProfiles = others.filter { profile in
            let capabilities = profile.capabilities.joined(separator: " ").lowercased()
            return capabilities.contains("qa") || capabilities.contains("review") || capabilities.contains("test") || capabilities.contains("verification")
        }
        let executionProfiles = others.filter { profile in !qaProfiles.contains(profile) }

        return VStack(alignment: .leading, spacing: 14) {
            if !store.selectedOrgProfileIDs.isEmpty {
                orgSelectionToolbar
            }

            Text(l("Team", "팀"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ShellPalette.text)

            if let leader {
                VStack(spacing: 14) {
                    HStack {
                        Spacer()
                        OrgChartNode(
                            profile: leader,
                            language: l,
                            isLeader: true,
                            isSelected: store.selectedOrgProfileIDs.contains(leader.id),
                            onTap: { store.toggleOrgProfileSelection(id: leader.id, shiftKey: NSEvent.modifierFlags.contains(.shift)) }
                        )
                        Spacer()
                    }

                    if !qaProfiles.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(qaProfiles) { profile in
                                OrgChartNode(
                                    profile: profile,
                                    language: l,
                                    isSelected: store.selectedOrgProfileIDs.contains(profile.id),
                                    onTap: { store.toggleOrgProfileSelection(id: profile.id, shiftKey: NSEvent.modifierFlags.contains(.shift)) }
                                )
                            }
                        }
                    }

                    if !executionProfiles.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                            ForEach(executionProfiles) { profile in
                                OrgChartNode(
                                    profile: profile,
                                    language: l,
                                    isSelected: store.selectedOrgProfileIDs.contains(profile.id),
                                    onTap: { store.toggleOrgProfileSelection(id: profile.id, shiftKey: NSEvent.modifierFlags.contains(.shift)) }
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .shellInset()
        .sheet(isPresented: $store.showingOrgProfileBatchEdit) {
            OrgProfileBatchEditSheet()
        }
    }

    private var agentSkillCardsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(l("Agent Skill Cards", "에이전트 스킬 카드"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                    Text(l("Work scope derived from skills and capability settings.", "스킬과 capability 설정에서 파생한 업무 범위입니다."))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                ShellTag(text: "\(store.agentSkillCards.count)", tint: ShellPalette.accentWarm)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 238), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(store.agentSkillCards) { card in
                    AgentSkillCardView(card: card, language: l) {
                        if let agent = store.companyAgentDefinitions.first(where: { $0.id == card.id }) {
                            store.beginEditingCompanyAgent(agent)
                        }
                    }
                }
            }
        }
        .padding(16)
        .shellInset()
    }

    private var organizationWorkPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l("Assignments", "할당된 작업"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ShellPalette.text)

            VStack(spacing: 8) {
                ForEach(store.companyAgentDefinitions) { agent in
                    AgentWorkSummaryRow(
                        agent: agent,
                        profile: store.orgProfiles.first(where: {
                            $0.companyId == agent.companyId && $0.executionAgentName == agent.agentCli && $0.roleName == agent.title
                        }),
                        issues: filteredIssues,
                        language: l
                    )
                }
            }
        }
        .padding(16)
        .shellInset()
    }

    private var selectedIssueDetailPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(l("Selected Issue", "선택된 이슈"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                Spacer()
                if let issue = store.selectedIssue {
                    StatusSummaryPill(text: l.status(issue.status), tint: statusTint(for: issue.status))
                }
            }

            if let issue = store.selectedIssue {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(userFacingIssueTitle(issue.title, language: l))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ShellPalette.text)

                        Text(userFacingIssueDescription(issue.description, language: l))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ShellPalette.text.opacity(0.84))
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            StatusSummaryPill(text: userFacingIssueKind(issue.kind, language: l), tint: ShellPalette.accentSoft)
                            if let assignee = store.selectedIssueAssignee {
                                StatusSummaryPill(text: assignee.roleName, tint: ShellPalette.accent)
                            }
                            if let linearIdentifier = issue.linearIssueIdentifier, !linearIdentifier.isEmpty {
                                StatusSummaryPill(text: linearIdentifier, tint: ShellPalette.accentWarm)
                            }
                            if let task = selectedIssueTask {
                                StatusSummaryPill(text: l.status(task.status), tint: statusTint(for: task.status))
                            }
                            if let reviewItem = store.selectedReviewQueueItem {
                                StatusSummaryPill(text: l.status(reviewItem.status), tint: reviewTint(reviewItem.status))
                            }
                        }

                        HStack(spacing: 8) {
                            Button(role: .destructive) {
                                Task { await store.deleteSelectedIssue() }
                            } label: {
                                Label(l("Delete Issue", "이슈 삭제"), systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                        }

                        if issue.linearIssueId != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(l("Linear", "Linear"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ShellPalette.text)
                                if let linearIdentifier = issue.linearIssueIdentifier, !linearIdentifier.isEmpty {
                                    valueLine(label: l("Issue", "이슈"), value: linearIdentifier)
                                }
                                if let linearIssueUrl = issue.linearIssueUrl, let url = URL(string: linearIssueUrl) {
                                    Link(destination: url) {
                                        Label(l("Open in Linear", "Linear에서 열기"), systemImage: "arrow.up.right.square")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundStyle(ShellPalette.accent)
                                }
                                if let lastSyncAt = issue.lastLinearSyncAt {
                                    valueLine(label: l("Last sync", "마지막 동기화"), value: relativeTimestamp(lastSyncAt))
                                }
                            }
                        }

                        if !issue.acceptanceCriteria.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(l("Acceptance", "수용 기준"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ShellPalette.text)
                                ForEach(Array(issue.acceptanceCriteria.prefix(3)), id: \.self) { criterion in
                                    StatusSummaryLine(text: criterion, tint: ShellPalette.success)
                                }
                                if issue.acceptanceCriteria.count > 3 {
                                    Text(l("+ \(issue.acceptanceCriteria.count - 3) more", "+ \(issue.acceptanceCriteria.count - 3)개 더"))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(ShellPalette.faint)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(l("Agent Execution", "에이전트 실행"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ShellPalette.text)
                            if store.issueExecutionDetails.isEmpty {
                                Text(l("No agent execution details have been captured for this issue yet.", "이 이슈에 대한 에이전트 실행 상세가 아직 없습니다."))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(ShellPalette.text.opacity(0.8))
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(ShellPalette.panelAlt)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                                            .stroke(ShellPalette.line, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(store.issueExecutionDetails) { detail in
                                        IssueExecutionDetailCard(
                                            detail: detail,
                                            language: l,
                                            updatedLabel: relativeTimestamp(detail.updatedAt)
                                        )
                                    }
                                }
                            }
                        }

                        if !selectedIssueContextEntries.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(l("Shared Notes", "공유 메모"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ShellPalette.text)
                                ForEach(Array(selectedIssueContextEntries.prefix(5))) { entry in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(entry.agentName) · \(entry.kind.uppercased())")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(ShellPalette.accent)
                                        Text(entry.content)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(ShellPalette.text.opacity(0.84))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(ShellPalette.panelAlt)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                                            .stroke(ShellPalette.line, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
                                }
                            }
                        }

                        if !selectedIssueMessages.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(l("Conversation", "대화"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ShellPalette.text)
                                ForEach(Array(selectedIssueMessages.prefix(5))) { message in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(message.fromAgentName) → \(message.toAgentName ?? "all") · \(message.kind)")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(message.kind == "escalation" ? ShellPalette.warning : ShellPalette.accent)
                                        Text(message.body)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(ShellPalette.text.opacity(0.84))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(ShellPalette.panelAlt)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                                            .stroke(ShellPalette.line, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
                                }
                            }
                        }
                    }
                }
            } else {
                EmptyStateView(
                    image: "text.alignleft",
                    title: l("Select an issue", "이슈를 선택하세요"),
                    subtitle: l("Choose an issue above to see its linked task and execution output.", "위에서 이슈를 선택하면 연결된 task와 실행 출력을 볼 수 있습니다.")
                )
                .frame(height: 190)
            }
        }
        .padding(14)
        .shellInset()
    }

    private func companyPageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ShellPalette.text)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ShellPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .shellInset()
    }

    private var meetingRoomTableHeadline: String {
        if let session = runningSessions.first {
            if let snippet = session.outputSnippet?.trimmingCharacters(in: .whitespacesAndNewlines), !snippet.isEmpty {
                return snippet
            }
            return meetingRoomIssueTitle(for: session.issueId)
        }
        return l("No active table notes.", "활성 테이블 메모가 없습니다.")
    }

    private func meetingRoomIssueTitle(for issueId: String?) -> String {
        guard let issueId,
              let issue = store.dashboard.issues.first(where: { $0.id == issueId }) else {
            return l("Unlinked issue", "연결된 이슈 없음")
        }
        return userFacingIssueTitle(issue.title, language: l)
    }

    private func meetingRoomReviewDetail(for item: ReviewQueueItemRecord) -> String {
        var fragments: [String] = [l.status(item.status)]

        if let mergeability = item.mergeability, !mergeability.isEmpty {
            fragments.append(mergeability)
        }

        if let checksSummary = item.checksSummary, !checksSummary.isEmpty {
            fragments.append(checksSummary)
        }

        if !item.requestedReviewers.isEmpty {
            fragments.append(item.requestedReviewers.joined(separator: ", "))
        }

        return fragments.joined(separator: " · ")
    }

    @ViewBuilder
    private func meetingRoomSeatSlot(_ session: RunningAgentSessionRecord?) -> some View {
        if let session {
            MeetingRoomSeatCard(
                title: session.roleName ?? session.agentName,
                subtitle: meetingRoomIssueTitle(for: session.issueId) + " · " + relativeTimestamp(session.updatedAt),
                status: l.status(session.status),
                tint: statusTint(for: session.status)
            )
        } else {
            Color.clear
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 56, maxHeight: 74)
        }
    }

    private func meetingRoomEmptyState(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(ShellPalette.text)
            Text(detail)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(ShellPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(ShellPalette.panelDeeper)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
    }

    private var operationsBanner: some View {
        let companyID = store.selectedCompany?.id
        let scopedMetrics = store.scopedOpsMetrics(companyID: companyID)
        let scopedIssues = store.dashboard.issues.filter { issue in
            companyID == nil || issue.companyId == companyID
        }
        let approvalNeededCount = scopedIssues.filter { $0.status == "WAITING_FOR_APPROVAL" }.count
        let blockedIssueCount = scopedIssues.filter { $0.status == "BLOCKED" }.count

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.selectedGoal?.title ?? l("Choose a goal", "목표를 선택하세요"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                        .lineLimit(2)

                    Text(store.selectedGoal?.description ?? store.selectedRepository?.localPath ?? l.text(.openOrCloneRepository))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    ShellStatusPill(
                        text: store.selectedIssue.map { l.status($0.status) } ?? l("IDLE", "대기"),
                        tint: statusTint(for: store.selectedIssue?.status ?? "IDLE")
                    )

                    if store.selectedWorkspace != nil, !store.availableBranches.isEmpty {
                        Picker(l("Current workspace base branch", "현재 워크스페이스 기준 브랜치"), selection: $store.pendingWorkspaceBaseBranch) {
                            ForEach(store.availableBranches, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                        .pickerStyle(.menu)

                        Button {
                            Task { await store.updateSelectedWorkspaceBaseBranch() }
                        } label: {
                            Label(l("Apply Branch", "브랜치 적용"), systemImage: "arrow.triangle.branch")
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                    }
                }
            }

            companyRuntimeSummaryStrip

            HStack(spacing: 8) {
                ShellTag(text: "\(l("Goals", "목표")) \(scopedMetrics.openGoals)", tint: ShellPalette.accentWarm)
                ShellTag(text: "\(l("Active Issues", "활성 이슈")) \(scopedMetrics.activeIssues)", tint: ShellPalette.accent)
                if approvalNeededCount > 0 {
                    ShellTag(text: "\(l("CEO Approval", "CEO 승인")) \(approvalNeededCount)", tint: ShellPalette.accentWarm)
                }
                ShellTag(text: "\(l("Blocked", "차단")) \(blockedIssueCount)", tint: ShellPalette.warning)
                ShellTag(text: "\(l("Merge", "병합")) \(scopedMetrics.readyToMergeCount)", tint: ShellPalette.success)
                Spacer()
            }

            HStack(spacing: 8) {
                ShellTag(text: "\(l("Main agent", "대표 에이전트")): \(workflowLeader)", tint: ShellPalette.accent)
                ShellTag(text: "\(l("Helpers", "도움")): \(workerAgents.count)", tint: ShellPalette.success)
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                .fill(ShellPalette.panelAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
    }

    private var companyActivityFeed: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l("Company Activity", "회사 활동"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                Spacer()
                if let runtime = store.selectedRuntime {
                    ShellTag(text: l.status(runtime.status), tint: companyRuntimeTint(runtime.status))
                }
            }

            if store.activity.isEmpty {
                EmptyStateView(
                    image: "waveform.path.ecg",
                    title: l("No activity yet", "아직 활동이 없습니다"),
                    subtitle: l("Planning, delegation, execution, and review events appear here.", "계획, 위임, 실행, 리뷰 이벤트를 표시합니다.")
                )
                .frame(height: 150)
            } else {
                CompanyActivityFeedList(items: visibleActivity, language: l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .shellInset()
    }

    private var surfaceSwitcher: some View {
        Picker(l("Surface", "화면"), selection: $goalSurface) {
            Text(l("Board", "보드")).tag(GoalSurface.board)
            Text(l("Canvas", "캔버스")).tag(GoalSurface.canvas)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var issueSurface: some View {
        switch goalSurface {
        case .board:
            issueBoard
        case .canvas:
            issueCanvas
        }
    }

    private var issueBoard: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(["PLANNED", "DELEGATED", "IN_PROGRESS", "IN_REVIEW", "BLOCKED", "DONE"], id: \.self) { status in
                    IssueBoardLaneView(
                        title: l.status(status),
                        tint: statusTint(for: status),
                        issues: filteredIssues.filter { $0.status == status },
                        assigneeProvider: { issue in
                            store.orgProfiles.first(where: { $0.id == issue.assigneeProfileId })
                        },
                        reviewProvider: { issue in
                            store.dashboard.reviewQueue.first(where: { $0.issueId == issue.id })
                        },
                        selectedIssueID: store.selectedIssueID,
                        language: l,
                        width: layoutMode == .compact ? 224 : 236
                    ) { issue in
                        Task { await store.selectIssue(issue) }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: layoutMode == .compact ? 420 : 540, alignment: .top)
        .clipped()
    }

    private var issueCanvas: some View {
        Group {
            if scrollsInternally {
                ScrollView {
                    issueCanvasGrid
                }
            } else {
                issueCanvasGrid
            }
        }
        .frame(minHeight: 260)
    }

    private var issueCanvasGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
            ForEach(filteredIssues) { issue in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text(userFacingIssueTitle(issue.title, language: l))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ShellPalette.text)
                        Spacer()
                        Circle()
                            .fill(statusTint(for: issue.status))
                            .frame(width: 10, height: 10)
                    }

                    Text(userFacingIssueDescription(issue.description, language: l))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .lineLimit(4)

                    if !issue.dependsOn.isEmpty {
                        Text("\(l("Depends on", "의존")): \(issue.dependsOn.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ShellPalette.faint)
                    }

                    HStack(spacing: 8) {
                        ShellTag(text: userFacingIssueKind(issue.kind, language: l), tint: ShellPalette.accent)
                        ShellTag(text: l.status(issue.status), tint: statusTint(for: issue.status))
                    }
                }
                .padding(14)
                .background(store.selectedIssueID == issue.id ? ShellPalette.panelRaised : ShellPalette.panelAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                        .stroke(store.selectedIssueID == issue.id ? ShellPalette.lineStrong : ShellPalette.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous))
                .onTapGesture {
                    Task { await store.selectIssue(issue) }
                }
            }
        }
    }

    private var composerSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShellSectionHeader(
                eyebrow: l.text(.compose),
                title: l.text(.newTask),
                subtitle: l.text(.newTaskSubtitle)
            )

            if layoutMode == .wide {
                HStack(alignment: .top, spacing: 12) {
                    composerInputs
                    composerActions
                        .frame(width: 248)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    composerInputs
                    composerActions
                }
            }
        }
        .padding(14)
        .shellInset()
    }

    private var composerInputs: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(l.text(.taskTitle), text: $store.newTaskTitle)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $store.newTaskPrompt)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 112)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(ShellPalette.panelAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                        .stroke(ShellPalette.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
        }
    }

    private var composerActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l("Main And Helper Agents", "대표 에이전트와 도움 에이전트"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ShellPalette.muted)

            Picker(l("Main Agent", "대표 에이전트"), selection: Binding(
                get: { workflowLeader },
                set: { store.setWorkflowLeadAgent($0) }
            )) {
                ForEach(store.dashboard.settings.availableAgents, id: \.self) { agent in
                    Text(agent).tag(agent)
                }
            }
            .pickerStyle(.menu)

            FlowLayout(items: store.dashboard.settings.availableAgents, selected: store.agentSelection) { agent in
                store.toggleWorkflowAgent(agent)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(l("How Work Flows", "일이 진행되는 방식"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)

                Text(l("The main agent receives the request and shares work with the selected helper agents. Each helper works in an isolated workspace.", "대표 에이전트가 요청을 받고 선택한 도움 에이전트와 일을 나눕니다. 각 도움 에이전트는 분리된 작업공간에서 안전하게 실행됩니다."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    ShellTag(text: "\(l("Main", "대표")): \(workflowLeader)", tint: ShellPalette.accent)
                    if workerAgents.isEmpty {
                        ShellTag(text: l("No helpers selected", "선택된 도움 에이전트 없음"), tint: ShellPalette.warning)
                    } else {
                        ShellTag(text: workerAgents.joined(separator: " · "), tint: ShellPalette.accentWarm)
                    }
                }
            }

            Text(l("Use Test Run only as a local preview. The main company path starts from a goal and lets agents keep working from there.", "테스트 실행은 로컬 미리보기 용도입니다. 회사의 기본 흐름은 목표를 입력하면 에이전트들이 이어서 일하는 방식입니다."))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ShellPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await store.createTask() }
            } label: {
                Label(l.text(.createTask), systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.selectedWorkspace == nil)
        }
    }

    private var taskRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ShellSectionHeader(
                    eyebrow: l.text(.queue),
                    title: l.text(.tasks),
                    subtitle: l.text(.tasksSubtitle)
                )
                Spacer()
                ShellTag(text: "\(filteredTasks.count)", tint: ShellPalette.accentWarm)
            }

            if filteredTasks.isEmpty {
                EmptyStateView(
                    image: "rectangle.stack.badge.plus",
                    title: l.text(.noTasks),
                    subtitle: l.text(.noTasksSubtitle)
                )
                .frame(height: 150)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(filteredTasks) { task in
                            TaskRailCard(task: task, language: l, isSelected: store.selectedTaskID == task.id) {
                                Task { await store.selectTask(task) }
                            }
                            .frame(width: layoutMode == .compact ? 240 : 250)
                        }
                    }
                }
            }
        }
    }

    private var tuiConsole: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l("Interactive TUI", "대화형 TUI"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                    Text(l("Run the same Cotor terminal experience inside the desktop app.", "데스크톱 앱 안에서 동일한 Cotor 터미널 경험을 실행합니다."))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()

                HStack(spacing: 8) {
                    if let session = store.activeTuiSession {
                        ShellStatusPill(text: l.status(session.status), tint: tuiStatusTint(session.status))
                    }

                    Button {
                        Task { await store.restartTuiSession() }
                    } label: {
                        Label(l("Restart", "재시작"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(ShellTopBarButtonStyle(prominent: false))

                    Button {
                        store.openSelectedLocation()
                    } label: {
                        Label(l.text(.openFolder), systemImage: "folder")
                    }
                    .buttonStyle(ShellTopBarButtonStyle(prominent: false))

                    if let session = store.activeTuiSession {
                        Button(role: .destructive) {
                            Task { await store.terminateTuiSession(session) }
                        } label: {
                            Label(l("Close", "닫기"), systemImage: "xmark")
                        }
                        .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                    }
                }
            }
            .padding(14)

            paneDivider

            Group {
                if store.isOffline {
                    EmptyStateView(
                        image: "wifi.slash",
                        title: l("Local app-server is unavailable", "로컬 app-server에 연결할 수 없습니다"),
                        subtitle: l("Start `cotor app-server` or run `cotor update`, then reopen a TUI session.", "`cotor app-server`를 실행하거나 `cotor update` 후 TUI 세션을 다시 여세요.")
                    )
                } else if let session = store.activeTuiSession {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            ShellTag(text: session.baseBranch, tint: ShellPalette.accentWarm)
                            if let pid = session.processId {
                                ShellTag(text: "pid \(pid)", tint: ShellPalette.success)
                            }
                            ShellTag(text: session.repositoryPath, tint: ShellPalette.accent)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        paneDivider

                        TerminalWebView(
                            sessionId: session.id,
                            baseURL: store.api.baseURL,
                            token: store.api.token
                        )
                            .frame(maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
                    }
                } else if store.selectedRepository != nil {
                    EmptyStateView(
                        image: "terminal",
                        title: l("Open a TUI session", "TUI 세션 열기"),
                        subtitle: l("Open a terminal session for the selected folder.", "선택한 폴더의 터미널 세션을 여세요.")
                    )
                    .padding(14)
                } else {
                    EmptyStateView(
                        image: "terminal",
                        title: l("Choose a folder", "폴더 선택"),
                        subtitle: l("Select or open a repository folder to start a terminal session.", "터미널 세션을 시작할 저장소 폴더를 선택하거나 여세요.")
                    )
                    .padding(14)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minHeight: layoutMode == .compact ? 420 : 520, maxHeight: .infinity)
        .shellInset()
    }

    private var detailDrawer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(ShellMotion.spring) {
                    detailDrawerOpen.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: detailDrawerOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ShellPalette.muted)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l("Detail Drawer", "상세 드로어"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ShellPalette.text)
                        Text(l("Diffs, files, ports, browser, review metadata", "변경점, 파일, 포트, 브라우저, 리뷰 메타데이터"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ShellPalette.muted)
                    }
                    Spacer()
                    if let item = store.selectedReviewQueueItem {
                        ShellTag(text: l.status(item.status), tint: reviewTint(item.status))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(ShellPalette.panelAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                        .stroke(ShellPalette.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
            }
            .buttonStyle(.plain)

            if detailDrawerOpen {
                InspectorPaneView(embedded: true)
                    .frame(minHeight: 320, maxHeight: 520)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func reviewTint(_ status: String) -> Color {
        switch status.uppercased() {
        case "READY_TO_MERGE", "MERGED":
            return ShellPalette.success
        case "FAILED_CHECKS", "CHANGES_REQUESTED":
            return ShellPalette.danger
        default:
            return ShellPalette.warning
        }
    }

    private func tuiStatusTint(_ status: String) -> Color {
        switch status.uppercased() {
        case "RUNNING":
            return ShellPalette.success
        case "STARTING":
            return ShellPalette.accent
        case "FAILED":
            return ShellPalette.danger
        default:
            return ShellPalette.warning
        }
    }

    private func tuiSessionTitle(_ session: TuiSessionRecord) -> String {
        let folderName = URL(fileURLWithPath: session.repositoryPath).lastPathComponent
        return folderName.isEmpty ? session.repositoryPath : folderName
    }

    private var paneDivider: some View {
        Rectangle()
            .fill(ShellPalette.line)
            .frame(height: 1)
    }
}

private struct CompanyCard: View {
    let company: CompanyRecord
    let runtime: CompanyRuntimeSnapshotRecord?
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(company.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                    Spacer()
                    ShellTag(
                        text: company.autonomyEnabled ? language("AUTO", "자동") : language("MANUAL", "수동"),
                        tint: company.autonomyEnabled ? ShellPalette.success : ShellPalette.warning
                    )
                }

                Text(userFacingPathLabel(company.rootPath))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    ShellTag(text: company.defaultBaseBranch, tint: ShellPalette.accentWarm)
                    if let runtime {
                        ShellTag(text: language.status(runtime.status), tint: companyRuntimeTint(runtime.status))
                        if runtime.isManuallyStopped {
                            ShellTag(text: language("Stopped manually", "수동 중지"), tint: ShellPalette.warning)
                        }
                        ShellTag(text: runtime.backendHealth.uppercased(), tint: companyRuntimeHealthTint(runtime.backendHealth))
                        if runtime.isBudgetPaused {
                            ShellTag(text: language("Cap reached", "상한 도달"), tint: ShellPalette.warning)
                        }
                        if let lastError = runtime.lastError, !lastError.isEmpty {
                            ShellTag(text: language("Needs attention", "주의 필요"), tint: ShellPalette.danger)
                        }
                    }
                }

                if let runtime, runtime.todaySpentCents > 0 || company.dailyBudgetCents != nil || company.monthlyBudgetCents != nil {
                    Text(
                        companySpendOverview(
                            company: company,
                            runtime: runtime,
                            language: language
                        )
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(2)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 12)
            .padding(.trailing, 12)
            .padding(.leading, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(isSelected ? ShellPalette.panelRaised : ShellPalette.panelAlt)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? ShellPalette.accent : ShellPalette.panelRaised)
                    .frame(width: 6)
                    .padding(.vertical, 12)
                    .padding(.leading, 12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                    .stroke(isSelected ? ShellPalette.lineStrong : ShellPalette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CompanyActivityFeedList: View {
    let items: [CompanyActivityItemRecord]
    let language: AppLanguage

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(items) { item in
                activityRow(item)
            }
        }
    }

    private func activityRow(_ item: CompanyActivityItemRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(companyActivityTint(item.severity))
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(userFacingActivityTitle(item.title, language: language))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                        .lineLimit(2)
                    Spacer()
                    Text(relativeTimestamp(item.createdAt))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ShellPalette.faint)
                }
                Text(userFacingActivityDetail(item.detail ?? item.source, language: language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(ShellPalette.panelAlt)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
    }
}

private struct CompanyReportItemRow: View {
    let item: CompanyDailyReportItemRecord
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(companyActivityTint(item.severity))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(userFacingIssueTitle(item.title, language: language))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if let status = item.status, !status.isEmpty {
                        ShellTag(text: language.status(status), tint: companyActivityTint(item.severity))
                    }
                    if let timestamp = item.timestamp {
                        Text(relativeTimestamp(timestamp))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ShellPalette.faint)
                    }
                }

                if let detail = item.detail, !detail.isEmpty {
                    Text(userFacingIssueDescription(detail, language: language))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let url = item.pullRequestUrl,
                   let link = URL(string: url) {
                    Link(destination: link) {
                        Label(language("Open pull request", "PR 열기"), systemImage: "arrow.up.right.square")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(ShellPalette.accent)
                }
            }
        }
        .padding(12)
        .background(ShellPalette.panelAlt)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
    }
}

private struct SessionStripItem: View {
    let title: String
    let subtitle: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minWidth: 138, alignment: .leading)
            .background(ShellPalette.panelAlt)
            .overlay(
                RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                    .stroke(tint.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private func companyRuntimeTint(_ status: String) -> Color {
    switch status.uppercased() {
    case "RUNNING":
        return ShellPalette.success
    case "FAILED":
        return ShellPalette.danger
    case "STOPPED":
        return ShellPalette.warning
    default:
        return ShellPalette.accent
    }
}

private func companyRuntimeHealthTint(_ health: String) -> Color {
    switch health.lowercased() {
    case "healthy":
        return ShellPalette.success
    case "stopped", "paused":
        return ShellPalette.warning
    case "starting", "degraded":
        return ShellPalette.warning
    case "failed", "error", "offline":
        return ShellPalette.danger
    default:
        return ShellPalette.accent
    }
}

private func companyActivityTint(_ kind: String) -> Color {
    switch kind.uppercased() {
    case "MERGE", "MERGED", "DONE":
        return ShellPalette.success
    case "FAILURE", "FAILED", "BLOCKED":
        return ShellPalette.danger
    case "RUNTIME", "RUN":
        return ShellPalette.accent
    default:
        return ShellPalette.accentWarm
    }
}

private func runtimeSpendSummary(
    label: String,
    spentCents: Int,
    capCents: Int?,
    language: AppLanguage
) -> String {
    let spent = usdCurrencyText(spentCents)
    guard let capCents, capCents > 0 else {
        return "\(label) \(spent)"
    }
    return "\(label) \(spent) / \(usdCurrencyText(capCents))"
}

private func companySpendOverview(
    company: CompanyRecord,
    runtime: CompanyRuntimeSnapshotRecord,
    language: AppLanguage
) -> String {
    [
        runtimeSpendSummary(
            label: language("Today", "오늘"),
            spentCents: runtime.todaySpentCents,
            capCents: company.dailyBudgetCents,
            language: language
        ),
        runtimeSpendSummary(
            label: language("Month", "월"),
            spentCents: runtime.monthSpentCents,
            capCents: company.monthlyBudgetCents,
            language: language
        )
    ].joined(separator: " · ")
}

private func usdCurrencyText(_ cents: Int?) -> String {
    guard let cents else { return "—" }
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = cents % 100 == 0 ? 0 : 2
    return formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? String(format: "$%.2f", Double(cents) / 100.0)
}

private func userFacingPathLabel(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }
    if trimmed.contains("://") {
        return trimmed
    }
    let name = URL(fileURLWithPath: trimmed).lastPathComponent
    return name.isEmpty ? trimmed : name
}

private func userFacingIssueTitle(_ title: String, language: AppLanguage) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }

    if trimmed.hasPrefix("QA review ") {
        let nested = userFacingIssueTitle(String(trimmed.dropFirst("QA review ".count)), language: language)
        return language("QA review · \(nested)", "QA 검토 · \(nested)")
    }
    if trimmed.hasPrefix("CEO approve ") {
        let nested = userFacingIssueTitle(String(trimmed.dropFirst("CEO approve ".count)), language: language)
        return language("CEO approval · \(nested)", "CEO 확인 · \(nested)")
    }
    if trimmed.hasPrefix("CEO plan and delegate ") {
        let goal = quotedGoal(in: trimmed) ?? trailingGoal(after: " ", in: trimmed)
        return issueTitle("CEO planning", "CEO 작업 분배", goal: goal, language: language)
    }
    if trimmed.hasPrefix("Restore GitHub publishing for ") {
        let nested = userFacingIssueTitle(
            String(trimmed.dropFirst("Restore GitHub publishing for ".count)),
            language: language
        )
        return language("Connect GitHub · \(nested)", "GitHub 연결 설정 · \(nested)")
    }

    let goal = quotedGoal(in: trimmed) ?? trailingGoal(after: " for ", in: trimmed)
    if trimmed.hasPrefix("Deliver the first implementation slice for ") ||
        trimmed.hasPrefix("Build the first working change for ") {
        return issueTitle("First working change", "첫 작업 만들기", goal: goal, language: language)
    }
    if trimmed.hasPrefix("Advance a second branchable improvement slice for ") ||
        trimmed.hasPrefix("Improve another small part of ") {
        return issueTitle("Improve another part", "다음 부분 개선", goal: goal, language: language)
    }
    if trimmed.hasPrefix("Harden the integration and failure-handling path for ") ||
        (trimmed.hasPrefix("Make ") && trimmed.hasSuffix(" more reliable")) {
        return issueTitle("Improve reliability", "안정성 개선", goal: goal, language: language)
    }
    if trimmed.hasPrefix("Prepare validation evidence and residual-risk callouts for ") ||
        trimmed.hasPrefix("Check the result and write down any remaining risks for ") {
        return issueTitle("Check results and risks", "결과와 위험 확인", goal: goal, language: language)
    }
    return trimmed
}

private func userFacingMemoryEvent(_ event: String, language: AppLanguage) -> String {
    let trimmed = event.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }
    if trimmed.hasPrefix("Started issue run: ") {
        let title = userFacingIssueTitle(String(trimmed.dropFirst("Started issue run: ".count)), language: language)
        return language("Started: \(title)", "시작: \(title)")
    }
    if trimmed.hasPrefix("Delegated issue: ") {
        let remainder = String(trimmed.dropFirst("Delegated issue: ".count))
        let title = remainder.components(separatedBy: " -> ").first ?? remainder
        return language(
            "Assigned: \(userFacingIssueTitle(title, language: language))",
            "배정: \(userFacingIssueTitle(title, language: language))"
        )
    }
    if trimmed.hasPrefix("Created infra issue: ") {
        let title = String(trimmed.dropFirst("Created infra issue: ".count))
        return language(
            "Created connection task: \(userFacingIssueTitle(title, language: language))",
            "연결 작업 생성: \(userFacingIssueTitle(title, language: language))"
        )
    }
    if trimmed.hasPrefix("Blocked code issue: ") {
        let reason = String(trimmed.dropFirst("Blocked code issue: ".count))
        return language(
            "Code work blocked: \(userFacingIssueDescription(reason, language: language))",
            "코드 작업 차단: \(userFacingIssueDescription(reason, language: language))"
        )
    }
    return userFacingIssueTitle(trimmed, language: language)
}

private func userFacingIssueDescription(_ description: String, language: AppLanguage) -> String {
    let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }

    if trimmed.hasPrefix("CEO planning issue for the company goal.") {
        return language(
            "CEO is turning the goal into team work.",
            "CEO가 목표를 팀 작업으로 나누는 준비입니다."
        )
    }

    if trimmed.hasPrefix("QA review issue for a concrete pull request.") {
        if let executionIssue = labeledLineValue("Execution issue:", in: trimmed) {
            let title = userFacingIssueTitle(executionIssue, language: language)
            return language("QA is reviewing \(title).", "QA 검토 중: \(title)")
        }
        return language("QA is reviewing the finished work.", "QA가 완료된 작업을 검토합니다.")
    }

    if trimmed.contains("GitHub publishing is required before this code issue can continue.") ||
        trimmed.contains("GitHub PR mode requires an existing origin remote.") ||
        trimmed.contains("GitHub is not connected.") {
        return language(
            "Connect an existing GitHub repository before starting PR-based code work. Cotor will not create one automatically.",
            "PR 기반 코드 작업을 시작하려면 기존 GitHub 저장소를 먼저 연결해야 합니다. Cotor가 저장소를 자동으로 만들지는 않습니다."
        )
    }

    if trimmed.contains("Owned subtasks:") || trimmed.contains("Shared checklist:") || trimmed.hasPrefix("Goal:") {
        let role = labeledLineValue("Role:", in: trimmed)
        let phase = labeledLineValue("Phase:", in: trimmed)
        let focus = labeledLineValue("Focus:", in: trimmed)

        var parts: [String] = []
        if let role {
            parts.append(language("\(role) owns this work.", "\(role)이(가) 맡은 작업입니다."))
        }
        if let phase {
            parts.append(language("Stage: \(plainPhaseLabel(phase, language: language)).", "단계: \(plainPhaseLabel(phase, language: language))."))
        }
        if let focus, !containsInternalMemoryDetail(focus) {
            parts.append(language("Focus is already set.", "작업 방향이 정해져 있습니다."))
        }
        return parts.isEmpty
            ? language("Assigned team work with checks prepared.", "검증까지 준비된 팀 작업입니다.")
            : parts.joined(separator: " ")
    }

    if containsInternalMemoryDetail(trimmed) {
        return language("Details available in the issue record.", "세부 정보는 이슈 기록에서 확인할 수 있습니다.")
    }
    return trimmed
}

private func userFacingIssueKind(_ kind: String, language: AppLanguage) -> String {
    switch kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "code":
        return language("Code work", "코드 작업")
    case "infra":
        return language("Connection", "연결 문제")
    case "execution":
        return language("Team work", "팀 작업")
    case "planning":
        return language("Planning", "계획")
    case "review":
        return language("Review", "검토")
    case "approval":
        return language("Approval", "승인")
    default:
        return kind.isEmpty ? "—" : kind
    }
}

private func userFacingDecisionTitle(_ title: String, language: AppLanguage) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }
    if trimmed == "Fallback planned execution graph" {
        return language("Fallback execution plan", "기본 실행 계획")
    }
    return trimmed
}

private func userFacingDecisionSummary(_ summary: String, language: AppLanguage) -> String {
    let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }
    if trimmed.contains("Fallback planner decomposed") {
        return language(
            "CEO planning needed a fallback, so Cotor split the goal into clear team issues.",
            "CEO 계획이 막혀 기본 계획으로 목표를 팀 이슈로 나눴습니다."
        )
    }
    if containsInternalMemoryDetail(trimmed) {
        return language("Details available in the issue record.", "세부 정보는 이슈 기록에서 확인할 수 있습니다.")
    }
    return trimmed
}

private func userFacingActivityTitle(_ title: String, language: AppLanguage) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }
    switch trimmed {
    case "Created infra issue":
        return language("Created connection task", "연결 작업 생성")
    case "Blocked code issue":
        return language("Code work blocked", "코드 작업 차단")
    case "Unblocked code issue":
        return language("Code work unblocked", "코드 작업 재개")
    case "Resolved infra issue":
        return language("Connection task resolved", "연결 작업 해결")
    default:
        return userFacingIssueTitle(trimmed, language: language)
    }
}

private func userFacingActivityDetail(_ detail: String, language: AppLanguage) -> String {
    let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }
    if trimmed.hasPrefix("Restore GitHub publishing for ") {
        return userFacingIssueTitle(trimmed, language: language)
    }
    if trimmed.contains("GitHub publishing is required before this code issue can continue.") ||
        trimmed.contains("GitHub is not connected.") ||
        trimmed.contains("GitHub PR mode requires an existing origin remote.") {
        return userFacingIssueDescription(trimmed, language: language)
    }
    if trimmed.contains("Fallback planner decomposed") {
        return userFacingDecisionSummary(trimmed, language: language)
    }
    if trimmed.contains("Owned subtasks:") || trimmed.hasPrefix("Goal:") || trimmed.hasPrefix("QA review issue for") {
        return userFacingIssueDescription(trimmed, language: language)
    }
    if containsInternalMemoryDetail(trimmed) {
        return language("Details available in the issue record.", "세부 정보는 이슈 기록에서 확인할 수 있습니다.")
    }
    return trimmed
}

private func containsInternalMemoryDetail(_ value: String) -> Bool {
    let lowered = value.lowercased()
    return lowered.contains("/users/")
        || lowered.contains("graphify ")
        || lowered.contains("graphify=")
        || lowered.contains(".json")
}

private func labeledLineValue(_ label: String, in value: String) -> String? {
    let lines = value.split(whereSeparator: \.isNewline).map(String.init)
    for (index, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(label) {
            let inline = trimmed.dropFirst(label.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !inline.isEmpty {
                return inline
            }
            let nextIndex = index + 1
            guard nextIndex < lines.count else { return nil }
            let next = lines[nextIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            return next.isEmpty ? nil : next
        }
    }
    return nil
}

private func plainPhaseLabel(_ phase: String, language: AppLanguage) -> String {
    switch phase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "planning":
        return language("planning", "계획")
    case "execution":
        return language("execution", "실행")
    case "review":
        return language("review", "검토")
    case "approval":
        return language("approval", "승인")
    default:
        return phase
    }
}

private func quotedGoal(in value: String) -> String? {
    guard let firstQuote = value.firstIndex(of: "\"") else { return nil }
    let afterFirst = value.index(after: firstQuote)
    guard let secondQuote = value[afterFirst...].firstIndex(of: "\"") else { return nil }
    let goal = String(value[afterFirst..<secondQuote]).trimmingCharacters(in: .whitespacesAndNewlines)
    return goal.isEmpty ? nil : goal
}

private func trailingGoal(after marker: String, in value: String) -> String? {
    guard let markerRange = value.range(of: marker, options: [.backwards]) else { return nil }
    let goal = value[markerRange.upperBound...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return goal.isEmpty ? nil : goal
}

private func issueTitle(_ english: String, _ korean: String, goal: String?, language: AppLanguage) -> String {
    guard let goal, !goal.isEmpty else {
        return language(english, korean)
    }
    return language("\(english) · \(goal)", "\(korean) · \(goal)")
}

private func relativeTimestamp(_ value: Int64) -> String {
    guard value > 0 else { return "—" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    let date = Date(timeIntervalSince1970: TimeInterval(value) / 1000)
    return formatter.localizedString(for: date, relativeTo: Date())
}

private struct TerminalPreviewSurface: View {
    let transcript: String
    let language: AppLanguage

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(
                    transcript.isEmpty
                        ? language("Waiting for the TUI session to start...", "TUI 세션이 시작되기를 기다리는 중입니다...")
                        : transcript
                )
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ShellPalette.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .id("terminal-preview-bottom")
            }
            .background(ShellPalette.panelAlt)
            .onChange(of: transcript) { _, _ in
                withAnimation(ShellMotion.spring) {
                    proxy.scrollTo("terminal-preview-bottom", anchor: .bottom)
                }
            }
        }
    }
}

private struct TaskRailCard: View {
    let task: TaskRecord
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(userFacingIssueTitle(task.title, language: language))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Circle()
                        .fill(statusTint(for: task.status))
                        .frame(width: 8, height: 8)
                }

                Text(userFacingIssueDescription(task.prompt, language: language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(3)

                HStack {
                    Text(task.agents.joined(separator: " · "))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ShellPalette.faint)
                        .lineLimit(1)
                    Spacer()
                    Text(language.status(task.status))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ShellPalette.muted)
                }
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .leading)
            .background(isSelected ? ShellPalette.panelRaised : ShellPalette.panelAlt)
            .overlay(
                RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                    .stroke(isSelected ? ShellPalette.lineStrong : ShellPalette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct IssueBoardLaneView: View {
    let title: String
    let tint: Color
    let issues: [IssueRecord]
    let assigneeProvider: (IssueRecord) -> OrgAgentProfileRecord?
    let reviewProvider: (IssueRecord) -> ReviewQueueItemRecord?
    let selectedIssueID: String?
    let language: AppLanguage
    let width: CGFloat
    let onSelect: (IssueRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                Spacer()
                ShellTag(text: "\(issues.count)", tint: tint)
            }

            if issues.isEmpty {
                EmptyStateView(
                    image: "tray",
                    title: language("No issues", "이슈 없음"),
                    subtitle: language("The CEO agent has nothing queued in this lane right now.", "이 lane에는 현재 CEO 에이전트가 배치한 이슈가 없습니다.")
                )
                .frame(maxWidth: .infinity, minHeight: 176, maxHeight: 176)
            } else {
                ScrollView(.vertical, showsIndicators: issues.count > 2) {
                    LazyVStack(spacing: 8) {
                        ForEach(issues) { issue in
                            IssueBoardCard(
                                issue: issue,
                                assignee: assigneeProvider(issue),
                                reviewItem: reviewProvider(issue),
                                language: language,
                                isSelected: selectedIssueID == issue.id
                            ) {
                                onSelect(issue)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(12)
        .background(ShellPalette.panelAlt)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous))
    }
}

private struct IssueBoardCard: View {
    let issue: IssueRecord
    let assignee: OrgAgentProfileRecord?
    let reviewItem: ReviewQueueItemRecord?
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(userFacingIssueTitle(issue.title, language: language))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ShellPalette.text)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            ShellTag(text: userFacingIssueKind(issue.kind, language: language), tint: ShellPalette.accentSoft)
                            ShellTag(text: language.status(issue.status), tint: statusTint(for: issue.status))
                        }
                    }
                    Spacer(minLength: 8)
                    Circle()
                        .fill(statusTint(for: issue.status))
                        .frame(width: 8, height: 8)
                }

                Text(userFacingIssueDescription(issue.description, language: language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    if let assignee {
                        ShellTag(text: assignee.roleName, tint: ShellPalette.accent)
                    }
                    ShellTag(text: "P\(issue.priority)", tint: ShellPalette.accentWarm)
                    Spacer()
                }

                if !issue.dependsOn.isEmpty {
                    HStack(spacing: 8) {
                        ShellTag(text: "\(issue.dependsOn.count) \(language("deps", "의존"))", tint: ShellPalette.warning)
                        Spacer()
                    }
                }

                if let reviewItem {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(language("Review Queue", "리뷰 큐"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(ShellPalette.faint)
                        HStack(spacing: 8) {
                            ShellTag(text: language.status(reviewItem.status), tint: reviewTint(reviewItem.status))
                            if let mergeability = reviewItem.mergeability, !mergeability.isEmpty {
                                ShellTag(text: mergeability, tint: ShellPalette.success)
                            }
                        }
                        if let checksSummary = reviewItem.checksSummary, !checksSummary.isEmpty {
                            Text(checksSummary)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(ShellPalette.muted)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? ShellPalette.panelRaised : ShellPalette.panel)
            .overlay(
                RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                    .stroke(isSelected ? ShellPalette.lineStrong : ShellPalette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
            .contentShape(Rectangle())
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
    }

    private func reviewTint(_ status: String) -> Color {
        switch status.uppercased() {
        case "READY_TO_MERGE", "MERGED":
            return ShellPalette.success
        case "FAILED_CHECKS", "CHANGES_REQUESTED":
            return ShellPalette.danger
        default:
            return ShellPalette.warning
        }
    }
}

private struct RunTabButton: View {
    let run: RunRecord
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusTint(for: run.status))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.agentName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                    Text(language.status(run.status))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? ShellPalette.panelRaised : ShellPalette.panelAlt)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? ShellPalette.lineStrong : ShellPalette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct InspectorPaneView: View {
    @EnvironmentObject private var store: DesktopStore
    var embedded: Bool = false
    private var l: AppLanguage { store.language }

    var body: some View {
        Group {
            inspectorContent
        }
        .modifier(InspectorContainerModifier(embedded: embedded))
    }

    private var inspectorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.selectedIssue?.title ?? store.selectedRun?.agentName ?? l.text(.inspect))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ShellPalette.text)
                    Text(
                        store.selectedReviewQueueItem.map { l.status($0.status) }
                            ?? store.selectedTask?.title
                            ?? l.text(.inspectorSubtitle)
                    )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                        .lineLimit(2)
                }

                Spacer()

                if let selectedTask = store.selectedTask, !selectedTask.agents.isEmpty {
                    Menu(store.selectedAgentName ?? l.text(.selectAgent)) {
                        ForEach(selectedTask.agents, id: \.self) { agent in
                            Button(agent) {
                                Task { await store.selectAgent(agent) }
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                }
            }

            inspectorMetadata
            if store.selectedIssue == nil {
                inspectorTabBar
                Group {
                    switch store.inspectorTab {
                    case .changes:
                        ChangesView(language: l, patch: store.changes.patch, files: store.changes.changedFiles)
                    case .files:
                        FilesView(language: l, nodes: store.files)
                    case .ports:
                        PortsView(language: l, ports: store.ports) { port in
                            store.openPort(port)
                        }
                    case .browser:
                        BrowserView(language: l, url: store.browserURL)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var inspectorTabBar: some View {
        HStack(spacing: 8) {
            ForEach(InspectorTab.allCases) { tab in
                Button {
                    store.inspectorTab = tab
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: inspectorIcon(for: tab))
                        Text(l.inspectorTab(tab))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ShellPalette.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(store.inspectorTab == tab ? ShellPalette.panelRaised : ShellPalette.panelAlt)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(store.inspectorTab == tab ? ShellPalette.lineStrong : ShellPalette.line, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var inspectorMetadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let issue = store.selectedIssue {
                metadataRow(label: l("Issue Status", "이슈 상태"), value: l.status(issue.status))
                metadataRow(label: l("Issue Kind", "이슈 종류"), value: userFacingIssueKind(issue.kind, language: l))
                metadataRow(label: l("Risk", "리스크"), value: issue.riskLevel)
                if let assignee = store.selectedIssueAssignee {
                    metadataRow(label: l("Assignee", "담당"), value: "\(assignee.roleName) · \(assignee.executionAgentName)")
                }
                if !issue.acceptanceCriteria.isEmpty {
                    metadataRow(label: l("Acceptance", "수용 기준"), value: issue.acceptanceCriteria.joined(separator: " · "))
                }
            }

            if let reviewItem = store.selectedReviewQueueItem {
                metadataRow(label: l("Review Queue", "리뷰 큐"), value: l.status(reviewItem.status))
                if let branchName = reviewItem.branchName, !branchName.isEmpty {
                    metadataRow(label: l.text(.branch), value: branchName)
                }
                if let worktreePath = reviewItem.worktreePath, !worktreePath.isEmpty {
                    metadataRow(label: l.text(.worktree), value: worktreePath)
                }
                if let pullRequestUrl = reviewItem.pullRequestUrl, !pullRequestUrl.isEmpty {
                    metadataRow(label: l.text(.pullRequest), value: pullRequestUrl)
                }
                if let pullRequestState = reviewItem.pullRequestState, !pullRequestState.isEmpty {
                    metadataRow(label: l("PR State", "PR 상태"), value: l.status(pullRequestState))
                }
                if let mergeability = reviewItem.mergeability, !mergeability.isEmpty {
                    metadataRow(label: l("Mergeability", "머지 가능성"), value: mergeability)
                }
                if let checksSummary = reviewItem.checksSummary, !checksSummary.isEmpty {
                    metadataRow(label: l("Checks", "체크"), value: checksSummary)
                }
                if !reviewItem.requestedReviewers.isEmpty {
                    metadataRow(label: l("Reviewers", "리뷰어"), value: reviewItem.requestedReviewers.joined(separator: ", "))
                }
                if let qaVerdict = reviewItem.qaVerdict, !qaVerdict.isEmpty {
                    metadataRow(label: l("QA Verdict", "QA 판정"), value: l.status(qaVerdict))
                }
                if let qaFeedback = reviewItem.qaFeedback, !qaFeedback.isEmpty {
                    metadataRow(label: l("QA Feedback", "QA 피드백"), value: qaFeedback)
                }
                if let ceoVerdict = reviewItem.ceoVerdict, !ceoVerdict.isEmpty {
                    metadataRow(label: l("CEO Verdict", "CEO 판정"), value: l.status(ceoVerdict))
                }
                if let ceoFeedback = reviewItem.ceoFeedback, !ceoFeedback.isEmpty {
                    metadataRow(label: l("CEO Feedback", "CEO 피드백"), value: ceoFeedback)
                }
                if let mergeCommitSha = reviewItem.mergeCommitSha, !mergeCommitSha.isEmpty {
                    metadataRow(label: l("Merge Commit", "머지 커밋"), value: mergeCommitSha)
                }
            }

            if let run = store.selectedRun {
                metadataRow(label: l.text(.branch), value: run.branchName)
                metadataRow(label: l.text(.base), value: run.baseBranch)
                metadataRow(label: l.text(.worktree), value: run.worktreePath)
                if let publish = run.publish {
                    if let commitSha = publish.commitSha, !commitSha.isEmpty {
                        metadataRow(label: l.text(.commit), value: commitSha)
                    }
                    if let pushedBranch = publish.pushedBranch, !pushedBranch.isEmpty {
                        metadataRow(label: l.text(.pushedBranch), value: pushedBranch)
                    }
                    if let pullRequestUrl = publish.pullRequestUrl, !pullRequestUrl.isEmpty {
                        metadataRow(label: l.text(.pullRequest), value: pullRequestUrl)
                    }
                    if let pullRequestState = publish.pullRequestState, !pullRequestState.isEmpty {
                        metadataRow(label: l("PR State", "PR 상태"), value: l.status(pullRequestState))
                    }
                    if let reviewState = publish.reviewState, !reviewState.isEmpty {
                        metadataRow(label: l("Publish Review", "퍼블리시 리뷰"), value: reviewState)
                    }
                    if let checksSummary = publish.checksSummary, !checksSummary.isEmpty {
                        metadataRow(label: l("Publish Checks", "퍼블리시 체크"), value: checksSummary)
                    }
                    if let mergeability = publish.mergeability, !mergeability.isEmpty {
                        metadataRow(label: l("Publish Mergeability", "퍼블리시 머지 가능성"), value: mergeability)
                    }
                    if let publishError = publish.error, !publishError.isEmpty {
                        metadataRow(label: l.text(.publishError), value: publishError)
                    }
                }
            } else if store.selectedIssue == nil {
                Text(l.text(.selectTaskAndAgent))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ShellPalette.muted)
            }
        }
        .padding(14)
        .shellInset()
    }

    private func metadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(ShellPalette.faint)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ShellPalette.text)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private func inspectorIcon(for tab: InspectorTab) -> String {
        switch tab {
        case .changes:
            return "arrow.triangle.branch"
        case .files:
            return "doc.text"
        case .ports:
            return "plugs.connected"
        case .browser:
            return "globe"
        }
    }
}

private struct InspectorContainerModifier: ViewModifier {
    let embedded: Bool

    func body(content: Content) -> some View {
        if embedded {
            content
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                        .fill(ShellPalette.panel)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                        .stroke(ShellPalette.line, lineWidth: 1)
                )
        } else {
            content.shellCard()
        }
    }
}

private struct ChangesView: View {
    let language: AppLanguage
    let patch: String
    let files: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if files.isEmpty, patch.isEmpty {
                EmptyStateView(
                    image: "arrow.triangle.branch",
                    title: language.text(.noChanges),
                    subtitle: language.text(.noChangesSubtitle)
                )
            } else {
                if !files.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(files, id: \.self) { file in
                                ShellTag(text: file, tint: ShellPalette.accent)
                            }
                        }
                    }
                }

                ScrollView {
                    Text(patch)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShellPalette.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .shellInset()
            }
        }
    }
}

private struct FilesView: View {
    let language: AppLanguage
    let nodes: [FileTreeNodePayload]

    var body: some View {
        if nodes.isEmpty {
            EmptyStateView(
                image: "doc.text.magnifyingglass",
                title: language.text(.noFileTree),
                subtitle: language.text(.noFileTreeSubtitle)
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    OutlineGroup(nodes, children: \.optionalChildren) { node in
                        HStack(spacing: 10) {
                            Image(systemName: node.isDirectory ? "folder.fill" : "doc.text")
                                .foregroundStyle(node.isDirectory ? ShellPalette.accentWarm : ShellPalette.accent)
                            Text(node.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ShellPalette.text)
                            Spacer()
                            if let size = node.sizeBytes, !node.isDirectory {
                                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(ShellPalette.muted)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(14)
            }
            .shellInset()
        }
    }
}

private struct PortsView: View {
    let language: AppLanguage
    let ports: [PortEntryPayload]
    let onOpen: (PortEntryPayload) -> Void

    var body: some View {
        if ports.isEmpty {
            EmptyStateView(
                image: "plugs.connected",
                title: language.text(.noPorts),
                subtitle: language.text(.noPortsSubtitle)
            )
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(ports) { port in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(port.label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(ShellPalette.text)
                                Text(port.url)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(ShellPalette.muted)
                            }

                            Spacer()

                            Button(language.text(.open)) {
                                onOpen(port)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(14)
                        .shellInset()
                    }
                }
            }
        }
    }
}

private struct BrowserView: View {
    let language: AppLanguage
    let url: URL?

    var body: some View {
        if let url {
            WebView(url: url)
                .shellInset()
        } else {
            EmptyStateView(
                image: "globe",
                title: language.text(.browserIdle),
                subtitle: language.text(.browserIdleSubtitle)
            )
        }
    }
}

private struct CloneRepositorySheet: View {
    @EnvironmentObject private var store: DesktopStore
    @Environment(\.dismiss) private var dismiss
    private var l: AppLanguage { store.language }

    var body: some View {
        ZStack {
            ShellCanvas()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ShellSectionHeader(
                        eyebrow: l.text(.clone),
                        title: l.text(.cloneRepository),
                        subtitle: l.text(.cloneRepositorySubtitle)
                    )
                    Spacer(minLength: 12)
                    ModalCloseButton(accessibilityLabel: l("Close clone dialog", "복제 창 닫기")) {
                        dismiss()
                    }
                }

                TextField(l.text(.cloneRepositoryPlaceholder), text: $store.cloneURLInput)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Spacer()
                    Button(l.text(.cancel)) { dismiss() }
                    Button {
                        Task {
                            await store.submitCloneRepository()
                            dismiss()
                        }
                    } label: {
                        Label(l.text(.clone), systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(width: 540)
            .shellCard()
            .padding(24)
        }
    }
}

private struct IssueExecutionDetailCard: View {
    let detail: IssueAgentExecutionDetailRecord
    let language: AppLanguage
    let updatedLabel: String
    @State private var showInternalPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(detail.roleName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ShellPalette.text)
                        ShellTag(text: detail.agentCli, tint: ShellPalette.accent)
                    }
                    Text(detail.agentName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ShellPalette.text.opacity(0.78))
                    if let model = detail.model, !model.isEmpty {
                        Text(model)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ShellPalette.text.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                StatusSummaryPill(text: language.status(detail.taskStatus), tint: statusTint(detail.taskStatus))
                if let runStatus = detail.runStatus {
                    StatusSummaryPill(text: language.status(runStatus), tint: statusTint(runStatus))
                }
            }

            if let branchName = detail.branchName, !branchName.isEmpty {
                Text("branch · \(branchName)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ShellPalette.text.opacity(0.78))
            }

            HStack(spacing: 8) {
                if let backendKind = detail.backendKind, !backendKind.isEmpty {
                    ShellTag(text: backendKind, tint: ShellPalette.accentSoft)
                }
                if let processId = detail.processId {
                    ShellTag(text: "pid \(processId)", tint: ShellPalette.success)
                }
            }

            assignmentSummaryBlock()

            DisclosureGroup(isExpanded: $showInternalPrompt) {
                executionBlock(
                    title: language == .korean ? "고급 작업 원문" : "Advanced Task Prompt",
                    text: detail.assignedPrompt,
                    tint: ShellPalette.warning
                )
            } label: {
                Label(
                    language == .korean ? "고급 정보 보기" : "Show Advanced Details",
                    systemImage: "chevron.right.circle"
                )
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ShellPalette.text.opacity(0.78))
            }

            if let stdout = detail.stdout, !stdout.isEmpty {
                executionBlock(
                    title: "stdout",
                    text: stdout,
                    tint: ShellPalette.success
                )
            }

            if let stderr = detail.stderr, !stderr.isEmpty {
                executionBlock(
                    title: "stderr",
                    text: stderr,
                    tint: ShellPalette.warning
                )
            }

            if let publishSummary = detail.publishSummary, !publishSummary.isEmpty {
                executionBlock(
                    title: language == .korean ? "퍼블리시 요약" : "Publish Summary",
                    text: publishSummary,
                    tint: ShellPalette.accentWarm
                )
            }

            HStack(spacing: 8) {
                if let pullRequestUrl = detail.pullRequestUrl,
                   let url = URL(string: pullRequestUrl)
                {
                    Link(destination: url) {
                        Label(
                            language == .korean ? "PR 열기" : "Open PR",
                            systemImage: "arrow.up.right.square"
                        )
                        .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(ShellPalette.accent)
                }
                Spacer(minLength: 0)
                Text((language == .korean ? "업데이트" : "Updated") + " · " + updatedLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ShellPalette.text.opacity(0.72))
            }
        }
        .padding(12)
        .background(ShellPalette.panelAlt)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
    }

    @ViewBuilder
    private func assignmentSummaryBlock() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language == .korean ? "작업 지시 요약" : "Task Brief")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ShellPalette.accent)
            Text(assignmentSummary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ShellPalette.text.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShellPalette.panelRaised)
        .overlay(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
    }

    private var assignmentSummary: String {
        let lines = detail.assignedPrompt
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let taskLine = lines.first { line in
            line.hasPrefix("- ") &&
                !line.contains("rootPath:") &&
                !line.contains("graphify") &&
                !line.contains(".json") &&
                !line.contains("Do not ") &&
                !line.contains("Rules") &&
                !line.contains("Company memory") &&
                !line.contains("Workflow memory") &&
                !line.contains("Agent memory")
        }?.dropFirst(2)

        if let taskLine, !taskLine.isEmpty {
            return language == .korean
                ? "담당 에이전트가 이 이슈의 검증과 후속 작업을 처리합니다."
                : "The assigned agent is handling validation and follow-up for this issue."
        }
        return language == .korean
            ? "담당 에이전트가 이 이슈의 다음 실행 단계를 준비합니다."
            : "The assigned agent is preparing the next execution step for this issue."
    }

    @ViewBuilder
    private func executionBlock(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            ScrollView {
                Text(text)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ShellPalette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(minHeight: 76, maxHeight: 132)
            .background(ShellPalette.panelRaised)
            .overlay(
                RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                    .stroke(ShellPalette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
        }
    }

    private func statusTint(_ status: String) -> Color {
        switch status.uppercased() {
        case "RUNNING", "IN_PROGRESS":
            return ShellPalette.accent
        case "COMPLETED", "DONE", "MERGED", "READY_FOR_CEO", "READY_TO_MERGE", "PASS", "APPROVE":
            return ShellPalette.success
        case "FAILED", "BLOCKED", "WAITING_FOR_APPROVAL", "CHANGES_REQUESTED", "FAILED_CHECKS":
            return ShellPalette.warning
        default:
            return ShellPalette.accentSoft
        }
    }
}

struct OrgProfileBatchEditPayloadDraft: Equatable {
    let agentCli: String?
    let model: String?
    let specialties: [String]?
    let enabled: Bool?

    static func build(
        batchAgent: String,
        batchModel: String,
        batchCapabilities: String,
        batchEnabled: Bool?
    ) -> OrgProfileBatchEditPayloadDraft {
        let trimmedAgent = batchAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = batchModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedSpecialties = batchCapabilities
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return OrgProfileBatchEditPayloadDraft(
            agentCli: trimmedAgent.isEmpty ? nil : trimmedAgent,
            model: trimmedModel.isEmpty ? nil : trimmedModel,
            specialties: batchCapabilities.isEmpty ? nil : parsedSpecialties,
            enabled: batchEnabled
        )
    }

    static func modelAfterAgentSelection() -> String {
        ""
    }
}

private struct OrgProfileBatchEditSheet: View {
    @EnvironmentObject private var store: DesktopStore
    @Environment(\.dismiss) private var dismiss
    @State private var batchAgent: String = ""
    @State private var batchModel: String = ""
    @State private var batchCapabilities: String = ""
    @State private var batchEnabled: Bool? = nil
    private var l: AppLanguage { store.language }
    private var batchModelAgentCli: String {
        if !batchAgent.isEmpty {
            return batchAgent
        }
        let selectedAgents = store.selectedBatchEditableAgents
            .map { $0.agentCli.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let normalizedAgents = Set(selectedAgents.map { $0.lowercased() })
        return normalizedAgents.count == 1 ? selectedAgents.first ?? "" : ""
    }

    private var batchModelOptions: [String] {
        store.modelOptions(for: batchModelAgentCli)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Selected profiles summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(store.selectedBatchEditableAgents.count) \(l("agents selected", "개 에이전트 선택됨"))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ShellPalette.text.opacity(0.84))

                        ForEach(store.selectedBatchEditableAgents) { profile in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(profile.enabled ? ShellPalette.success : ShellPalette.warning)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ShellPalette.text)
                                    Text("\(profile.agentCli) · \(profile.specialties.joined(separator: " · "))")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(ShellPalette.text.opacity(0.8))
                                        .lineLimit(1)
                                }
                                Spacer()
                                ShellTag(
                                    text: profile.enabled ? l("ON", "활성") : l("OFF", "비활성"),
                                    tint: profile.enabled ? ShellPalette.success : ShellPalette.warning
                                )
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(ShellPalette.panelAlt)
                            .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
                        }
                    }

                    Divider()

                    // Batch actions
                    VStack(alignment: .leading, spacing: 12) {
                        Text(l("Batch Actions", "일괄 작업"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ShellPalette.text)

                        // Enable / Disable All
                        HStack(spacing: 8) {
                            Button {
                                batchEnabled = true
                            } label: {
                                Label(l("Enable All", "전체 활성화"), systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ShellTopBarButtonStyle(prominent: false))

                            Button {
                                batchEnabled = false
                            } label: {
                                Label(l("Disable All", "전체 비활성화"), systemImage: "xmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                        }

                        // Agent picker
                        if !store.availableCliAgents.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(l("Change Execution Agent", "실행 에이전트 변경"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ShellPalette.muted)

                                Picker(l("Execution Agent", "실행 에이전트"), selection: $batchAgent) {
                                    Text(l("No change", "변경 없음")).tag("")
                                    ForEach(store.availableCliAgents, id: \.self) { agent in
                                        Text(agent).tag(agent)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(l("Model Override", "모델 오버라이드"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ShellPalette.muted)

                            if !batchModelOptions.isEmpty {
                                Picker(l("Model Override", "모델 오버라이드"), selection: $batchModel) {
                                    Text(l("No change", "변경 없음")).tag("")
                                    ForEach(batchModelOptions, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                                .pickerStyle(.menu)
                            } else {
                                TextField(
                                    store.defaultModel(for: batchModelAgentCli) ?? l("No change", "변경 없음"),
                                    text: $batchModel
                                )
                                .textFieldStyle(.roundedBorder)
                            }
                        }

                        // Capabilities
                        VStack(alignment: .leading, spacing: 6) {
                            Text(l("Capabilities (comma separated)", "역량 (쉼표로 구분)"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ShellPalette.muted)

                            TextField(l("e.g. qa, review, deploy", "예: qa, review, deploy"), text: $batchCapabilities)
                                .textFieldStyle(.roundedBorder)

                            HStack(spacing: 8) {
                                Button {
                                    batchCapabilities = ""
                                } label: {
                                    Label(l("Clear", "지우기"), systemImage: "xmark")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(ShellTopBarButtonStyle(prominent: false))
                            }
                        }
                    }

                    Divider()

                    // Apply button
                    Button {
                        applyBatchChanges()
                    } label: {
                        Label(l("Apply Changes", "변경 적용"), systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
            .navigationTitle(l("Batch Edit Agents", "에이전트 일괄 수정"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalCloseButton(accessibilityLabel: l("Close batch edit", "일괄 수정 닫기")) {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .onAppear {
            batchAgent = ""
            batchModel = ""
            batchCapabilities = ""
            batchEnabled = nil
        }
        .onChange(of: batchAgent) { _, _ in
            batchModel = OrgProfileBatchEditPayloadDraft.modelAfterAgentSelection()
        }
    }

    private func applyBatchChanges() {
        let payload = OrgProfileBatchEditPayloadDraft.build(
            batchAgent: batchAgent,
            batchModel: batchModel,
            batchCapabilities: batchCapabilities,
            batchEnabled: batchEnabled
        )
        Task {
            let didApply = await store.batchUpdateSelectedCompanyAgents(
                agentCli: payload.agentCli,
                model: payload.model,
                specialties: payload.specialties,
                enabled: payload.enabled
            )
            if didApply {
                dismiss()
            }
        }
    }
}

private struct EmptyStateView: View {
    let image: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(ShellPalette.accent.opacity(0.14))
                    .frame(width: 48, height: 48)
                Image(systemName: image)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ShellPalette.accentWarm)
            }

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ShellPalette.text)

            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ShellPalette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
        .shellInset()
    }
}

private struct FlowLayout: View {
    let items: [String]
    let selected: Set<String>
    let action: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    action(item)
                } label: {
                    Text(item)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.86)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(selected.contains(item) ? ShellPalette.accentSoft : ShellPalette.panelAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(selected.contains(item) ? ShellPalette.lineStrong : ShellPalette.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(ShellPalette.text)
                .font(.system(size: 12, weight: .semibold))
            }
        }
    }
}

private struct DesktopCommandMenu: Commands {
    @ObservedObject var store: DesktopStore
    private var l: AppLanguage { store.language }

    var body: some Commands {
        CommandMenu(l.text(.cotorMenu)) {
            Button(l.text(.refreshDashboard)) {
                Task { await store.refreshDashboard() }
            }
            .keyboardShortcut("r", modifiers: [.command])

            Button(l.text(.openRepository)) {
                Task { await store.openRepositoryPicker() }
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button(l.text(.cloneRepositoryMenu)) {
                store.showingCloneSheet = true
            }
            .keyboardShortcut("l", modifiers: [.command])

            Button(store.language("Help & Commands", "도움말과 명령어")) {
                Task { await store.openHelpGuide() }
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])

            Button(l.text(.createTaskMenu)) {
                Task { await store.createTask() }
            }
            .keyboardShortcut("t", modifiers: [.command])

            Button(l.text(.openFolder)) {
                store.openSelectedLocation()
            }

            Divider()

            Button("English") {
                store.setLanguage(.english)
            }

            Button("한국어") {
                store.setLanguage(.korean)
            }
        }

        CommandMenu(l.text(.inspectorMenu)) {
            Button(l.text(.showChanges)) {
                store.inspectorTab = .changes
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button(l.text(.showFiles)) {
                store.inspectorTab = .files
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button(l.text(.showPorts)) {
                store.inspectorTab = .ports
            }
            .keyboardShortcut("3", modifiers: [.command])

            Button(l.text(.showBrowser)) {
                store.inspectorTab = .browser
            }
            .keyboardShortcut("4", modifiers: [.command])

            Divider()

            Button(l.text(.filesTab)) {
                store.inspectorTab = .files
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button(l.text(.browserTab)) {
                store.inspectorTab = .browser
            }
            .keyboardShortcut("b", modifiers: [.command])
        }
    }
}

private func localizedSourceKind(_ sourceKind: String, language: AppLanguage) -> String {
    switch sourceKind.uppercased() {
    case "LOCAL":
        return language("Local", "로컬")
    case "CLONED":
        return language("Cloned", "복제됨")
    default:
        return sourceKind
    }
}

private func matches(query: String, values: [String?]) -> Bool {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !needle.isEmpty else { return true }

    return values.contains { value in
        guard let value else { return false }
        return value.lowercased().contains(needle)
    }
}

private func statusTint(for status: String) -> Color {
    switch status.uppercased() {
    case "DONE", "COMPLETED", "SUCCESS", "MERGED":
        return ShellPalette.success
    case "FAILED", "ERROR", "BLOCKED", "FAILED_CHECKS", "CHANGES_REQUESTED":
        return ShellPalette.danger
    case "RUNNING", "QUEUED", "PLANNED", "BACKLOG", "DELEGATED", "IN_PROGRESS", "IN_REVIEW", "AWAITING_QA", "AWAITING_REVIEW", "READY_TO_MERGE", "WAITING_FOR_APPROVAL", "STARTING":
        return ShellPalette.warning
    default:
        return ShellPalette.accent
    }
}

private struct DesktopHelpGuideSheet: View {
    @EnvironmentObject private var store: DesktopStore

    var body: some View {
        ZStack {
            ShellCanvas().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center) {
                        Text(store.language("Help & Commands", "도움말과 명령"))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(ShellPalette.faint)
                        Spacer()
                        Button {
                            store.showingHelpGuide = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(ShellPalette.text)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .background(ShellPalette.panelAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityLabel(store.language("Close help", "도움말 닫기"))
                    }
                    if let guide = store.helpGuide {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(guide.title)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(ShellPalette.text)
                            Text(guide.subtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShellPalette.muted)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(shellCardBackground)

                        HelpGuideSectionCard(
                            title: store.language("Quick Start", "빠른 시작"),
                            subtitle: store.language("The fastest commands to orient yourself.", "가장 빨리 시작할 수 있는 명령들입니다."),
                            items: guide.quickStart
                        )

                        ForEach(guide.sections) { section in
                            HelpGuideSectionCard(title: section.title, subtitle: section.summary, items: section.items)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            ShellSectionHeader(eyebrow: store.language("Topics", "주제"), title: store.language("Topic Guides", "주제별 도움말"), subtitle: store.language("Jump to focused help modes.", "집중된 도움말 모드로 바로 이동합니다."))
                            ForEach(guide.topics) { topic in
                                VStack(alignment: .leading, spacing: 6) {
                                    ShellTag(text: topic.command, tint: ShellPalette.accent)
                                    Text(topic.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(ShellPalette.text)
                                    Text(topic.description)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(ShellPalette.muted)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(shellCardBackground)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            ShellSectionHeader(eyebrow: "AI", title: store.language("AI Usage Guide", "AI 사용 안내"), subtitle: store.language("Narrative guidance for new operators.", "처음 쓰는 사람도 따라갈 수 있는 줄글 안내입니다."))
                            Text(guide.aiNarrative)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShellPalette.text)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(shellCardBackground)
                            Text(guide.footer)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ShellPalette.muted)
                        }
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity, minHeight: 280)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 760, height: 640)
    }

    private var shellCardBackground: some View {
        RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
            .fill(ShellPalette.panel)
            .overlay(
                RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                    .stroke(ShellPalette.line, lineWidth: 1)
            )
    }
}

private struct HelpGuideSectionCard: View {
    let title: String
    let subtitle: String
    let items: [HelpGuideItemPayload]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShellSectionHeader(eyebrow: "CLI", title: title, subtitle: subtitle)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.command)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ShellPalette.text)
                    Text(item.description)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ShellPalette.muted)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ShellPalette.panelAlt)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ShellPalette.line, lineWidth: 1)
                        )
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                .fill(ShellPalette.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                        .stroke(ShellPalette.line, lineWidth: 1)
                )
        )
    }
}
