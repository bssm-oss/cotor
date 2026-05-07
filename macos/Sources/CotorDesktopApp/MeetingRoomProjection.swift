import Foundation

enum MeetingRoomVisualState: String, Hashable {
    case idle
    case running
    case review
    case blocked
    case failed
    case done
    case costBlocked
}

enum MeetingRoomExpression: String, Hashable {
    case idle
    case focused
    case talking
    case confused
    case sad
    case happy
    case warning
}

enum MeetingRoomOfficeZone: String, Hashable {
    case agentDesk
    case planningBoard
    case reviewDesk
    case blockerZone
    case costPanel
    case activityWall
    case mergeLane
}

enum MeetingRoomFlowKind: String, Hashable {
    case goalToIssue
    case issueToAgent
    case agentWorking
    case a2aMessage
    case agentToReview
    case reviewToMerge
    case blocked
    case costBlocked
}

struct MeetingRoomProjectionAgent: Identifiable, Hashable {
    let id: String
    let companyAgentId: String
    let name: String
    let role: String
    let cli: String
    let currentIssueId: String?
    let currentIssueTitle: String?
    let status: String
    let visualState: MeetingRoomVisualState
    let expression: MeetingRoomExpression
    let zone: MeetingRoomOfficeZone
    let actionLine: String
    let detailLine: String
    let progress: Double
    let messageCount: Int
    let pullRequestState: String?
}

struct MeetingRoomFlowItem: Identifiable, Hashable {
    let id: String
    let kind: MeetingRoomFlowKind
    let title: String
    let detail: String
    let issueId: String?
    let from: MeetingRoomOfficeZone
    let to: MeetingRoomOfficeZone
    let progress: Double
}

enum MeetingRoomInteractionKind: String, Hashable {
    case issueAssigned
    case workStarted
    case handoff
    case meeting
    case qaReviewRequested
    case ceoApprovalRequested
    case approvalGranted
    case changesRequested
    case blockedEscalation
    case mergeCompleted
    case costPaused

    var usesScheduler: Bool {
        switch self {
        case .issueAssigned, .workStarted, .handoff, .meeting, .qaReviewRequested, .ceoApprovalRequested, .changesRequested, .blockedEscalation:
            return true
        case .approvalGranted, .mergeCompleted, .costPaused:
            return false
        }
    }
}

struct MeetingRoomInteractionEvent: Identifiable, Hashable {
    let id: String
    let kind: MeetingRoomInteractionKind
    let title: String
    let detail: String
    let speechText: String
    let fromAgentId: String?
    let toAgentId: String?
    let participantAgentIds: [String]
    let issueId: String?
    let reviewId: String?
    let messageId: String?
    let occurredAt: Int64
    let priority: Int

    var agentIds: [String] {
        Array(([fromAgentId, toAgentId].compactMap { $0 } + participantAgentIds).deduplicated())
    }
}

struct MeetingRoomIssueSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let status: String
    let kind: String
    let assigneeProfileId: String?
    let pullRequestNumber: Int?
    let pullRequestUrl: String?
    let pullRequestState: String?
    let transitionReason: String?
}

struct MeetingRoomReviewSummary: Identifiable, Hashable {
    let id: String
    let issueId: String
    let status: String
    let branchName: String?
    let pullRequestNumber: Int?
    let pullRequestUrl: String?
    let pullRequestState: String?
    let checksSummary: String?
    let mergeability: String?
    let qaVerdict: String?
    let ceoVerdict: String?
}

struct MeetingRoomProjection: Hashable {
    static let maxIssueSummaries = 120
    static let maxReviewSummaries = 60

    let companyId: String?
    let agents: [MeetingRoomProjectionAgent]
    let flows: [MeetingRoomFlowItem]
    let interactions: [MeetingRoomInteractionEvent]
    let issues: [MeetingRoomIssueSummary]
    let reviews: [MeetingRoomReviewSummary]
    let runtimeStatus: String
    let runtimeBackendHealth: String
    let runningSessionCount: Int
    let todaySpentCents: Int
    let monthSpentCents: Int
    let isCostBlocked: Bool
    let activeIssueCount: Int
    let blockedIssueCount: Int
    let reviewCount: Int
    let activityCount: Int
    let pullRequestStates: [String]

    static func runtime(
        for companyId: String?,
        in runtimes: [CompanyRuntimeSnapshotRecord]
    ) -> CompanyRuntimeSnapshotRecord? {
        guard let companyId else { return nil }
        return runtimes.first { $0.companyId == companyId }
    }

    static func build(
        companyId: String?,
        agents allAgents: [CompanyAgentDefinitionRecord],
        goals allGoals: [GoalRecord] = [],
        goalDecisions allGoalDecisions: [GoalOrchestrationDecisionRecord] = [],
        orgProfiles allOrgProfiles: [OrgAgentProfileRecord] = [],
        issues allIssues: [IssueRecord],
        runningSessions allRunningSessions: [RunningAgentSessionRecord],
        reviewQueue allReviewQueue: [ReviewQueueItemRecord],
        runtime: CompanyRuntimeSnapshotRecord?,
        activity allActivity: [CompanyActivityItemRecord],
        messages allMessages: [AgentMessageRecord]
    ) -> MeetingRoomProjection {
        let scopedAgents = scoped(allAgents, companyId: companyId)
            .sorted { $0.displayOrder < $1.displayOrder }
        let scopedGoals = scoped(allGoals, companyId: companyId)
        let scopedGoalDecisions = scoped(allGoalDecisions, companyId: companyId)
        let scopedProfiles = scoped(allOrgProfiles, companyId: companyId)
        let scopedIssues = scoped(allIssues, companyId: companyId)
        let scopedSessions = scoped(allRunningSessions, companyId: companyId)
        let scopedReviews = scoped(allReviewQueue, companyId: companyId)
        let scopedActivity = scoped(allActivity, companyId: companyId)
        let scopedMessages = scoped(allMessages, companyId: companyId)
        let runtime = runtime ?? CompanyRuntimeSnapshotRecord(companyId: companyId)
        let issuesById = Dictionary(uniqueKeysWithValues: scopedIssues.map { ($0.id, $0) })
        let latestIssueByAssignee = Dictionary(
            grouping: scopedIssues.filter { $0.assigneeProfileId != nil },
            by: { $0.assigneeProfileId ?? "" }
        ).compactMapValues { issues in
            issues.sorted { $0.updatedAt > $1.updatedAt }.first
        }
        let latestIssueByNormalizedAssignee = Dictionary(
            grouping: scopedIssues.filter { $0.assigneeProfileId != nil },
            by: { ($0.assigneeProfileId ?? "").normalizedMeetingRoomKey }
        ).compactMapValues { issues in
            issues.sorted { $0.updatedAt > $1.updatedAt }.first
        }
        let profileByRole = Dictionary(
            scopedProfiles.map { ($0.roleName.normalizedMeetingRoomKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let sessionByAgentId = Dictionary(scopedSessions.map { ($0.agentId, $0) }, uniquingKeysWith: { first, _ in first })
        let sessionByAgentName = Dictionary(scopedSessions.map { ($0.agentName.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let messageCountByAgentKey = messageCountMap(messages: scopedMessages)
        let hasReviewWork = !scopedReviews.isEmpty
        let latestReviewIssue = scopedReviews
            .sorted { $0.updatedAt > $1.updatedAt }
            .lazy
            .compactMap { issuesById[$0.issueId] }
            .first
        let isCostBlocked = runtime.isBudgetPaused

        let projectedAgents = scopedAgents.map { agent in
            let profile = profileByRole[agent.title.normalizedMeetingRoomKey]
                ?? profileByRole[agent.agentCli.normalizedMeetingRoomKey]
            let session = sessionByAgentId[agent.id]
                ?? sessionByAgentName[agent.title.lowercased()]
            let assignmentKeys = [agent.id, agent.title, agent.agentCli, profile?.id, profile?.roleName, profile?.executionAgentName]
                .compactMap { $0 }
            let assignedIssue = assignmentKeys.lazy.compactMap { latestIssueByAssignee[$0] }.first
                ?? assignmentKeys.lazy.compactMap { latestIssueByNormalizedAssignee[$0.normalizedMeetingRoomKey] }.first
            let issue = session.flatMap { $0.issueId }.flatMap { issuesById[$0] } ?? assignedIssue ?? reviewIssue(for: agent, latestReviewIssue: latestReviewIssue)
            let messageCount = Set([agent.agentCli.normalizedMeetingRoomKey, agent.title.normalizedMeetingRoomKey])
                .reduce(0) { count, key in count + (messageCountByAgentKey[key] ?? 0) }

            let visualState = visualState(
                agent: agent,
                session: session,
                issue: issue,
                hasReviewWork: hasReviewWork,
                isCostBlocked: isCostBlocked
            )
            return MeetingRoomProjectionAgent(
                id: agent.id,
                companyAgentId: agent.id,
                name: agent.title,
                role: agent.title,
                cli: agent.agentCli,
                currentIssueId: issue?.id ?? session?.issueId,
                currentIssueTitle: issue?.title,
                status: session?.status ?? issue?.status ?? (agent.enabled ? "IDLE" : "PAUSED"),
                visualState: visualState,
                expression: messageCount > 0 ? .talking : expression(for: visualState),
                zone: zone(for: visualState),
                actionLine: actionLine(for: visualState, role: agent.title),
                detailLine: detailLine(agent: agent, session: session, issue: issue, reviewCount: scopedReviews.count, runtime: runtime),
                progress: progress(for: visualState, session: session, issue: issue, enabled: agent.enabled),
                messageCount: messageCount,
                pullRequestState: issue?.pullRequestState
            )
        }

        let interactions = buildInteractions(
            goals: scopedGoals,
            goalDecisions: scopedGoalDecisions,
            agents: projectedAgents,
            orgProfiles: scopedProfiles,
            issues: scopedIssues,
            runningSessions: scopedSessions,
            reviewQueue: scopedReviews,
            messages: scopedMessages,
            runtime: runtime
        )
        let flows = buildFlows(
            goals: scopedGoals,
            issues: scopedIssues,
            runningSessions: scopedSessions,
            reviewQueue: scopedReviews,
            messages: scopedMessages,
            runtime: runtime
        )
        let issueSummaries = scopedIssues
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxIssueSummaries)
            .map(MeetingRoomIssueSummary.init(issue:))
        let reviewSummaries = scopedReviews
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxReviewSummaries)
            .map(MeetingRoomReviewSummary.init(review:))

        return MeetingRoomProjection(
            companyId: companyId,
            agents: projectedAgents,
            flows: flows,
            interactions: interactions,
            issues: issueSummaries,
            reviews: reviewSummaries,
            runtimeStatus: runtime.status,
            runtimeBackendHealth: runtime.backendHealth,
            runningSessionCount: scopedSessions.count,
            todaySpentCents: runtime.todaySpentCents,
            monthSpentCents: runtime.monthSpentCents,
            isCostBlocked: isCostBlocked,
            activeIssueCount: scopedIssues.filter { !terminalStatuses.contains($0.status.uppercased()) }.count,
            blockedIssueCount: scopedIssues.filter { blockedStatuses.contains($0.status.uppercased()) }.count,
            reviewCount: scopedReviews.count,
            activityCount: scopedActivity.count,
            pullRequestStates: scopedIssues.compactMap(\.pullRequestState)
        )
    }

    private static let terminalStatuses: Set<String> = ["DONE", "MERGED", "CLOSED", "CANCELLED", "CANCELED"]
    private static let blockedStatuses: Set<String> = ["BLOCKED", "FAILED", "CHANGES_REQUESTED"]

    private static func messageCountMap(messages: [AgentMessageRecord]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for message in messages {
            counts[message.fromAgentName.normalizedMeetingRoomKey, default: 0] += 1
            if let toAgentName = message.toAgentName {
                counts[toAgentName.normalizedMeetingRoomKey, default: 0] += 1
            }
        }
        return counts
    }

    private static func scoped<T>(_ values: [T], companyId: String?) -> [T] {
        guard let companyId else { return values }
        return values.filter { value in
            switch value {
            case let agent as CompanyAgentDefinitionRecord:
                return agent.companyId == companyId
            case let goal as GoalRecord:
                return goal.companyId == companyId
            case let decision as GoalOrchestrationDecisionRecord:
                return decision.companyId == companyId
            case let profile as OrgAgentProfileRecord:
                return profile.companyId == companyId
            case let issue as IssueRecord:
                return issue.companyId == companyId
            case let session as RunningAgentSessionRecord:
                return session.companyId == companyId
            case let review as ReviewQueueItemRecord:
                return review.companyId == companyId
            case let activity as CompanyActivityItemRecord:
                return activity.companyId == companyId
            case let message as AgentMessageRecord:
                return message.companyId == companyId
            default:
                return true
            }
        }
    }

    private static func reviewIssue(
        for agent: CompanyAgentDefinitionRecord,
        latestReviewIssue: IssueRecord?
    ) -> IssueRecord? {
        let role = agent.title.lowercased()
        guard role.contains("qa") || role.contains("review") || role.contains("ceo") || role.contains("approval") else {
            return nil
        }
        return latestReviewIssue
    }

    private static func visualState(
        agent: CompanyAgentDefinitionRecord,
        session: RunningAgentSessionRecord?,
        issue: IssueRecord?,
        hasReviewWork: Bool,
        isCostBlocked: Bool
    ) -> MeetingRoomVisualState {
        if isCostBlocked {
            return .costBlocked
        }
        if let session {
            let status = session.status.uppercased()
            if status.contains("FAIL") || status.contains("ERROR") {
                return .failed
            }
            if status.contains("BLOCK") {
                return .blocked
            }
            if status.contains("DONE") || status.contains("COMPLETE") || status.contains("SUCCESS") {
                return .done
            }
            return .running
        }
        if let issue {
            let status = issue.status.uppercased()
            if status == "DONE" || issue.mergeResult?.uppercased() == "MERGED" || issue.pullRequestState?.uppercased() == "MERGED" {
                return .done
            }
            if status.contains("FAIL") {
                return .failed
            }
            if status.contains("BLOCK") || status == "CHANGES_REQUESTED" {
                return .blocked
            }
            if status.contains("REVIEW") || issue.qaVerdict != nil || issue.ceoVerdict != nil {
                return .review
            }
        }
        let role = agent.title.lowercased()
        if hasReviewWork && (role.contains("qa") || role.contains("review") || role.contains("ceo") || role.contains("approval")) {
            return .review
        }
        return .idle
    }

    private static func expression(for state: MeetingRoomVisualState) -> MeetingRoomExpression {
        switch state {
        case .idle:
            return .idle
        case .running:
            return .focused
        case .review:
            return .confused
        case .blocked:
            return .confused
        case .failed:
            return .sad
        case .done:
            return .happy
        case .costBlocked:
            return .warning
        }
    }

    private static func zone(for state: MeetingRoomVisualState) -> MeetingRoomOfficeZone {
        switch state {
        case .idle, .running, .done:
            return .agentDesk
        case .review:
            return .reviewDesk
        case .blocked, .failed:
            return .blockerZone
        case .costBlocked:
            return .costPanel
        }
    }

    private static func actionLine(for state: MeetingRoomVisualState, role: String) -> String {
        switch state {
        case .idle:
            return "ready at desk"
        case .running:
            return "typing on assigned work"
        case .review:
            return role.lowercased().contains("ceo") ? "checking approval" : "reviewing work"
        case .blocked:
            return "blocked, needs help"
        case .failed:
            return "failed, reading logs"
        case .done:
            return "done, handing off"
        case .costBlocked:
            return "paused by cost guardrail"
        }
    }

    private static func detailLine(
        agent: CompanyAgentDefinitionRecord,
        session: RunningAgentSessionRecord?,
        issue: IssueRecord?,
        reviewCount: Int,
        runtime: CompanyRuntimeSnapshotRecord
    ) -> String {
        if runtime.isBudgetPaused {
            return "Budget paused after \(runtime.todaySpentCents)c today."
        }
        if let session {
            return "\(session.status) · \(issue?.title ?? session.branchName)"
        }
        if let issue {
            return "\(issue.status) · \(issue.title)"
        }
        if reviewCount > 0 && agent.title.lowercased().contains("qa") {
            return "\(reviewCount) review item(s) waiting."
        }
        return agent.roleSummary
    }

    private static func progress(
        for state: MeetingRoomVisualState,
        session: RunningAgentSessionRecord?,
        issue: IssueRecord?,
        enabled: Bool
    ) -> Double {
        guard enabled else { return 0.05 }
        switch state {
        case .idle:
            return 0.12
        case .running:
            return session == nil ? 0.45 : 0.62
        case .review:
            return 0.74
        case .blocked:
            return 0.22
        case .failed:
            return 0.18
        case .done:
            return 1.0
        case .costBlocked:
            return 0.08
        }
    }

    private static func buildFlows(
        goals: [GoalRecord],
        issues: [IssueRecord],
        runningSessions: [RunningAgentSessionRecord],
        reviewQueue: [ReviewQueueItemRecord],
        messages: [AgentMessageRecord],
        runtime: CompanyRuntimeSnapshotRecord
    ) -> [MeetingRoomFlowItem] {
        var flows: [MeetingRoomFlowItem] = []
        let goalsById = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })
        let recentIssues = Array(issues.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(5))

        for issue in recentIssues.prefix(4) {
            guard let goal = goalsById[issue.goalId] else { continue }
            flows.append(
                MeetingRoomFlowItem(
                    id: "goal-\(goal.id)-issue-\(issue.id)",
                    kind: .goalToIssue,
                    title: goal.title,
                    detail: "Decomposed into: \(issue.title)",
                    issueId: issue.id,
                    from: .activityWall,
                    to: .planningBoard,
                    progress: 0.28
                )
            )
        }

        for issue in recentIssues {
            let status = issue.status.uppercased()
            if runtime.isBudgetPaused {
                flows.append(
                    MeetingRoomFlowItem(
                        id: "cost-\(issue.id)",
                        kind: .costBlocked,
                        title: issue.title,
                        detail: "Cost guardrail paused runtime.",
                        issueId: issue.id,
                        from: .costPanel,
                        to: .blockerZone,
                        progress: 0.12
                    )
                )
            } else if status.contains("BLOCK") || status.contains("FAIL") {
                flows.append(
                    MeetingRoomFlowItem(
                        id: "block-\(issue.id)",
                        kind: .blocked,
                        title: issue.title,
                        detail: issue.transitionReason ?? issue.providerBlockReasonFallback,
                        issueId: issue.id,
                        from: .agentDesk,
                        to: .blockerZone,
                        progress: 0.25
                    )
                )
            } else if status.contains("REVIEW") || issue.qaVerdict != nil || issue.ceoVerdict != nil {
                flows.append(
                    MeetingRoomFlowItem(
                        id: "review-\(issue.id)",
                        kind: .agentToReview,
                        title: issue.title,
                        detail: issue.pullRequestState ?? "review queue",
                        issueId: issue.id,
                        from: .agentDesk,
                        to: .reviewDesk,
                        progress: 0.72
                    )
                )
            } else if status == "DONE" || issue.pullRequestState?.uppercased() == "MERGED" || issue.mergeResult?.uppercased() == "MERGED" {
                flows.append(
                    MeetingRoomFlowItem(
                        id: "merge-\(issue.id)",
                        kind: .reviewToMerge,
                        title: issue.title,
                        detail: issue.pullRequestState ?? issue.mergeResult ?? "done",
                        issueId: issue.id,
                        from: .reviewDesk,
                        to: .mergeLane,
                        progress: 1.0
                    )
                )
            } else if status.contains("PLAN") || status.contains("BACKLOG") {
                flows.append(
                    MeetingRoomFlowItem(
                        id: "assign-\(issue.id)",
                        kind: .issueToAgent,
                        title: issue.title,
                        detail: "Issue is ready to dispatch.",
                        issueId: issue.id,
                        from: .planningBoard,
                        to: .agentDesk,
                        progress: 0.35
                    )
                )
            }
        }

        for session in runningSessions.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(4) {
            flows.append(
                MeetingRoomFlowItem(
                    id: "run-\(session.runId)",
                    kind: .agentWorking,
                    title: session.agentName,
                    detail: session.status,
                    issueId: session.issueId,
                    from: .planningBoard,
                    to: .agentDesk,
                    progress: 0.62
                )
            )
        }

        for message in messages.sorted(by: { $0.createdAt > $1.createdAt }).prefix(4) {
            let target = message.toAgentName ?? "room"
            flows.append(
                MeetingRoomFlowItem(
                    id: "a2a-\(message.id)",
                    kind: .a2aMessage,
                    title: "\(message.fromAgentName) → \(target)",
                    detail: message.body,
                    issueId: message.issueId,
                    from: .agentDesk,
                    to: message.kind.lowercased().contains("escalation") ? .blockerZone : .activityWall,
                    progress: 0.58
                )
            )
        }

        for review in reviewQueue.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(4) {
            flows.append(
                MeetingRoomFlowItem(
                    id: "queue-\(review.id)",
                    kind: review.pullRequestState?.uppercased() == "MERGED" ? .reviewToMerge : .agentToReview,
                    title: review.pullRequestUrl ?? review.branchName ?? review.issueId,
                    detail: review.status,
                    issueId: review.issueId,
                    from: .agentDesk,
                    to: review.pullRequestState?.uppercased() == "MERGED" ? .mergeLane : .reviewDesk,
                    progress: review.pullRequestState?.uppercased() == "MERGED" ? 1.0 : 0.78
                )
            )
        }

        return Array(flows.prefix(10))
    }

    private static func buildInteractions(
        goals: [GoalRecord],
        goalDecisions: [GoalOrchestrationDecisionRecord],
        agents: [MeetingRoomProjectionAgent],
        orgProfiles: [OrgAgentProfileRecord],
        issues: [IssueRecord],
        runningSessions: [RunningAgentSessionRecord],
        reviewQueue: [ReviewQueueItemRecord],
        messages: [AgentMessageRecord],
        runtime: CompanyRuntimeSnapshotRecord
    ) -> [MeetingRoomInteractionEvent] {
        let resolver = MeetingRoomAgentResolver(agents: agents, orgProfiles: orgProfiles)
        let issuesById = Dictionary(uniqueKeysWithValues: issues.map { ($0.id, $0) })
        var events: [MeetingRoomInteractionEvent] = []

        for session in runningSessions.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(6) {
            let agentId = resolver.agentId(for: session.agentId)
                ?? resolver.agentId(for: session.roleName)
                ?? resolver.agentId(for: session.agentName)
            let issue = session.issueId.flatMap { issuesById[$0] }
            events.append(
                MeetingRoomInteractionEvent(
                    id: "work-\(session.runId)",
                    kind: .workStarted,
                    title: issue?.title ?? session.agentName,
                    detail: session.outputSnippet ?? session.status,
                    speechText: "Working on it",
                    fromAgentId: agentId,
                    toAgentId: nil,
                    participantAgentIds: [agentId].compactMap { $0 },
                    issueId: session.issueId,
                    reviewId: nil,
                    messageId: nil,
                    occurredAt: session.updatedAt,
                    priority: 760
                )
            )
        }

        for review in reviewQueue.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(8) {
            let issue = issuesById[review.issueId]
            let owner = issue.flatMap { resolver.agentId(forIssue: $0) } ?? resolver.builderAgentId()
            let qa = resolver.qaAgentId()
            let ceo = resolver.ceoAgentId()
            let status = review.status.uppercased()
            let merged = review.pullRequestState?.uppercased() == "MERGED" || review.mergedAt != nil

            if merged || status == "MERGED" {
                events.append(
                    MeetingRoomInteractionEvent(
                        id: "merge-\(review.id)",
                        kind: .mergeCompleted,
                        title: issue?.title ?? review.issueId,
                        detail: review.pullRequestUrl ?? review.branchName ?? "Merged work",
                        speechText: "Merged",
                        fromAgentId: ceo ?? qa ?? owner,
                        toAgentId: nil,
                        participantAgentIds: [owner, qa, ceo].compactMap { $0 },
                        issueId: review.issueId,
                        reviewId: review.id,
                        messageId: nil,
                        occurredAt: review.mergedAt ?? review.updatedAt,
                        priority: 520
                    )
                )
            } else if status == "READY_FOR_CEO" || review.approvalIssueId != nil {
                events.append(
                    MeetingRoomInteractionEvent(
                        id: "ceo-approval-\(review.id)",
                        kind: .ceoApprovalRequested,
                        title: issue?.title ?? review.issueId,
                        detail: review.pullRequestUrl ?? review.branchName ?? review.status,
                        speechText: "Approval requested",
                        fromAgentId: owner,
                        toAgentId: ceo,
                        participantAgentIds: [owner, ceo].compactMap { $0 },
                        issueId: review.issueId,
                        reviewId: review.id,
                        messageId: nil,
                        occurredAt: review.updatedAt,
                        priority: 930
                    )
                )
            } else if status == "CHANGES_REQUESTED" || status == "FAILED_CHECKS" {
                events.append(
                    MeetingRoomInteractionEvent(
                        id: "changes-\(review.id)",
                        kind: .changesRequested,
                        title: issue?.title ?? review.issueId,
                        detail: review.qaFeedback ?? review.ceoFeedback ?? review.checksSummary ?? review.status,
                        speechText: "Changes requested",
                        fromAgentId: qa ?? ceo,
                        toAgentId: owner,
                        participantAgentIds: [owner, qa, ceo].compactMap { $0 },
                        issueId: review.issueId,
                        reviewId: review.id,
                        messageId: nil,
                        occurredAt: review.updatedAt,
                        priority: 880
                    )
                )
            } else if status.contains("QA") || status.contains("REVIEW") || status == "AWAITING_QA" {
                events.append(
                    MeetingRoomInteractionEvent(
                        id: "qa-review-\(review.id)",
                        kind: .qaReviewRequested,
                        title: issue?.title ?? review.issueId,
                        detail: review.pullRequestUrl ?? review.branchName ?? review.status,
                        speechText: "Please review",
                        fromAgentId: owner,
                        toAgentId: qa,
                        participantAgentIds: [owner, qa].compactMap { $0 },
                        issueId: review.issueId,
                        reviewId: review.id,
                        messageId: nil,
                        occurredAt: review.updatedAt,
                        priority: 900
                    )
                )
            } else if status == "READY_TO_MERGE" || review.ceoVerdict?.uppercased().contains("PASS") == true {
                events.append(
                    MeetingRoomInteractionEvent(
                        id: "approval-granted-\(review.id)",
                        kind: .approvalGranted,
                        title: issue?.title ?? review.issueId,
                        detail: review.ceoFeedback ?? review.status,
                        speechText: "Approved",
                        fromAgentId: ceo,
                        toAgentId: owner,
                        participantAgentIds: [owner, ceo].compactMap { $0 },
                        issueId: review.issueId,
                        reviewId: review.id,
                        messageId: nil,
                        occurredAt: review.ceoReviewedAt ?? review.updatedAt,
                        priority: 700
                    )
                )
            }
        }

        for message in messages.sorted(by: { $0.createdAt > $1.createdAt }).prefix(8) {
            let from = resolver.agentId(for: message.fromAgentName)
            let to = message.toAgentName.flatMap { resolver.agentId(for: $0) }
            let kind = message.kind.lowercased()
            let eventKind: MeetingRoomInteractionKind
            let speech: String
            let fallbackTarget: String?

            if kind.contains("escalation") {
                eventKind = .blockedEscalation
                speech = "Need help"
                fallbackTarget = resolver.ceoAgentId() ?? resolver.qaAgentId()
            } else if kind.contains("feedback") {
                eventKind = .meeting
                speech = "Feedback sync"
                fallbackTarget = nil
            } else if kind.contains("review.request") {
                eventKind = .qaReviewRequested
                speech = "Please review"
                fallbackTarget = resolver.qaAgentId()
            } else if kind.contains("approval") {
                eventKind = .ceoApprovalRequested
                speech = "Approval requested"
                fallbackTarget = resolver.ceoAgentId()
            } else {
                eventKind = .handoff
                speech = "Handoff update"
                fallbackTarget = nil
            }

            let target = to ?? fallbackTarget
            events.append(
                MeetingRoomInteractionEvent(
                    id: "message-\(message.id)",
                    kind: eventKind,
                    title: message.subject,
                    detail: message.body,
                    speechText: speech,
                    fromAgentId: from,
                    toAgentId: target,
                    participantAgentIds: [from, target].compactMap { $0 },
                    issueId: message.issueId,
                    reviewId: nil,
                    messageId: message.id,
                    occurredAt: message.createdAt,
                    priority: eventKind == .blockedEscalation ? 910 : 780
                )
            )
        }

        for issue in issues.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(8) {
            let status = issue.status.uppercased()
            let assignee = resolver.agentId(forIssue: issue)
            if runtime.isBudgetPaused {
                events.append(
                    MeetingRoomInteractionEvent(
                        id: "cost-\(issue.id)",
                        kind: .costPaused,
                        title: issue.title,
                        detail: "Cost guardrail paused runtime.",
                        speechText: "Cost pause",
                        fromAgentId: resolver.ceoAgentId(),
                        toAgentId: assignee,
                        participantAgentIds: [resolver.ceoAgentId(), assignee].compactMap { $0 },
                        issueId: issue.id,
                        reviewId: nil,
                        messageId: nil,
                        occurredAt: issue.updatedAt,
                        priority: 860
                    )
                )
            } else if status == "READY_FOR_CEO" || issue.kind.lowercased() == "approval" {
                events.append(
                    MeetingRoomInteractionEvent(
                        id: "issue-approval-\(issue.id)",
                        kind: .ceoApprovalRequested,
                        title: issue.title,
                        detail: issue.transitionReason ?? issue.pullRequestUrl ?? issue.status,
                        speechText: "Approval requested",
                        fromAgentId: assignee ?? resolver.builderAgentId(),
                        toAgentId: resolver.ceoAgentId(),
                        participantAgentIds: [assignee, resolver.ceoAgentId()].compactMap { $0 },
                        issueId: issue.id,
                        reviewId: nil,
                        messageId: nil,
                        occurredAt: issue.updatedAt,
                        priority: 890
                    )
                )
            } else if status.contains("BLOCK") || status.contains("FAIL") {
                events.append(
                    MeetingRoomInteractionEvent(
                        id: "blocked-\(issue.id)",
                        kind: .blockedEscalation,
                        title: issue.title,
                        detail: issue.transitionReason ?? issue.providerBlockReasonFallback,
                        speechText: "Need help",
                        fromAgentId: assignee,
                        toAgentId: resolver.ceoAgentId() ?? resolver.qaAgentId(),
                        participantAgentIds: [assignee, resolver.ceoAgentId(), resolver.qaAgentId()].compactMap { $0 },
                        issueId: issue.id,
                        reviewId: nil,
                        messageId: nil,
                        occurredAt: issue.updatedAt,
                        priority: 850
                    )
                )
            } else if status.contains("PLAN") || status == "DELEGATED" || status.contains("BACKLOG") {
                events.append(
                    MeetingRoomInteractionEvent(
                        id: "assign-\(issue.id)",
                        kind: .issueAssigned,
                        title: issue.title,
                        detail: issue.transitionReason ?? "Issue is ready to dispatch.",
                        speechText: "Taking this",
                        fromAgentId: resolver.planningAgentId(),
                        toAgentId: assignee,
                        participantAgentIds: [resolver.planningAgentId(), assignee].compactMap { $0 },
                        issueId: issue.id,
                        reviewId: nil,
                        messageId: nil,
                        occurredAt: issue.updatedAt,
                        priority: 620
                    )
                )
            }
        }

        for decision in goalDecisions.sorted(by: { $0.createdAt > $1.createdAt }).prefix(4) {
            let participants = decision.assignments
                .compactMap { assignmentTarget(from: $0) }
                .compactMap { resolver.agentId(for: $0) }
            let lead = resolver.ceoAgentId() ?? resolver.planningAgentId()
            if !participants.isEmpty {
                events.append(
                    MeetingRoomInteractionEvent(
                        id: "meeting-\(decision.id)",
                        kind: .meeting,
                        title: decision.title,
                        detail: decision.summary,
                        speechText: "Plan sync",
                        fromAgentId: lead,
                        toAgentId: nil,
                        participantAgentIds: Array(([lead].compactMap { $0 } + participants).deduplicated()),
                        issueId: decision.issueId,
                        reviewId: nil,
                        messageId: nil,
                        occurredAt: decision.createdAt,
                        priority: 740
                    )
                )
            }
        }

        let goalTitles = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0.title) })
        return Array(events
            .sorted {
                if $0.priority != $1.priority {
                    return $0.priority > $1.priority
                }
                return $0.occurredAt > $1.occurredAt
            }
            .map { event in
                guard event.title.isEmpty, let issueId = event.issueId, let issue = issuesById[issueId] else {
                    return event
                }
                return MeetingRoomInteractionEvent(
                    id: event.id,
                    kind: event.kind,
                    title: issue.title,
                    detail: goalTitles[issue.goalId] ?? event.detail,
                    speechText: event.speechText,
                    fromAgentId: event.fromAgentId,
                    toAgentId: event.toAgentId,
                    participantAgentIds: event.participantAgentIds,
                    issueId: event.issueId,
                    reviewId: event.reviewId,
                    messageId: event.messageId,
                    occurredAt: event.occurredAt,
                    priority: event.priority
                )
            }
            .deduplicatedById()
            .prefix(14))
    }

    private static func assignmentTarget(from assignment: String) -> String? {
        let separators = ["->", "→", ":"]
        for separator in separators where assignment.contains(separator) {
            return assignment.components(separatedBy: separator).last?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return assignment.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

private struct MeetingRoomAgentResolver {
    private let agents: [MeetingRoomProjectionAgent]
    private let idByKey: [String: String]

    init(agents: [MeetingRoomProjectionAgent], orgProfiles: [OrgAgentProfileRecord]) {
        self.agents = agents
        var map: [String: String] = [:]
        for agent in agents {
            [agent.id, agent.companyAgentId, agent.name, agent.role, agent.cli].forEach { value in
                map[value.normalizedMeetingRoomKey] = agent.id
            }
        }
        for profile in orgProfiles {
            let matched = agents.first {
                $0.role.normalizedMeetingRoomKey == profile.roleName.normalizedMeetingRoomKey ||
                    $0.cli.normalizedMeetingRoomKey == profile.executionAgentName.normalizedMeetingRoomKey ||
                    $0.id.normalizedMeetingRoomKey == profile.id.normalizedMeetingRoomKey
            }
            if let matched {
                [profile.id, profile.roleName, profile.executionAgentName].forEach { value in
                    map[value.normalizedMeetingRoomKey] = matched.id
                }
            }
        }
        idByKey = map
    }

    func agentId(for value: String?) -> String? {
        guard let key = value?.normalizedMeetingRoomKey, !key.isEmpty else { return nil }
        return idByKey[key] ?? agents.first { agent in
            agent.role.normalizedMeetingRoomKey.contains(key) ||
                key.contains(agent.role.normalizedMeetingRoomKey) ||
                agent.cli.normalizedMeetingRoomKey.contains(key)
        }?.id
    }

    func agentId(forIssue issue: IssueRecord) -> String? {
        agentId(for: issue.assigneeProfileId)
    }

    func ceoAgentId() -> String? {
        agents.first { agent in
            let role = agent.role.lowercased()
            return role.contains("ceo") || role.contains("lead") || role.contains("approval")
        }?.id ?? agents.first?.id
    }

    func qaAgentId() -> String? {
        agents.first { agent in
            let role = agent.role.lowercased()
            return role.contains("qa") || role.contains("review") || role.contains("test")
        }?.id
    }

    func builderAgentId() -> String? {
        agents.first { agent in
            let role = agent.role.lowercased()
            return role.contains("builder") || role.contains("engineer") || role.contains("backend")
        }?.id
    }

    func planningAgentId() -> String? {
        agents.first { agent in
            let role = agent.role.lowercased()
            return role.contains("product") || role.contains("ux") || role.contains("planner") || role.contains("ceo")
        }?.id ?? ceoAgentId()
    }
}

private extension MeetingRoomIssueSummary {
    init(issue: IssueRecord) {
        self.init(
            id: issue.id,
            title: issue.title,
            status: issue.status,
            kind: issue.kind,
            assigneeProfileId: issue.assigneeProfileId,
            pullRequestNumber: issue.pullRequestNumber,
            pullRequestUrl: issue.pullRequestUrl,
            pullRequestState: issue.pullRequestState,
            transitionReason: issue.transitionReason
        )
    }
}

private extension MeetingRoomReviewSummary {
    init(review: ReviewQueueItemRecord) {
        self.init(
            id: review.id,
            issueId: review.issueId,
            status: review.status,
            branchName: review.branchName,
            pullRequestNumber: review.pullRequestNumber,
            pullRequestUrl: review.pullRequestUrl,
            pullRequestState: review.pullRequestState,
            checksSummary: review.checksSummary,
            mergeability: review.mergeability,
            qaVerdict: review.qaVerdict,
            ceoVerdict: review.ceoVerdict
        )
    }
}

private extension String {
    var normalizedMeetingRoomKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}

private extension IssueRecord {
    var providerBlockReasonFallback: String {
        transitionReason ?? pullRequestState ?? "Blocked issue"
    }
}

private extension Array where Element == String {
    func deduplicated() -> [String] {
        var seen: Set<String> = []
        return filter { value in
            seen.insert(value).inserted
        }
    }
}

private extension Array where Element == MeetingRoomInteractionEvent {
    func deduplicatedById() -> [MeetingRoomInteractionEvent] {
        var seen: Set<String> = []
        return filter { event in
            seen.insert(event.id).inserted
        }
    }
}
