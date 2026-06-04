import SwiftUI

struct InspectorPaneView: View {
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
                            .buttonStyle(ShellTopBarButtonStyle(prominent: true))
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
