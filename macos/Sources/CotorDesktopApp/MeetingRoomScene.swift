import CoreGraphics
import Foundation

enum MeetingRoomSpriteAction: String, Hashable {
    case sitting
    case typing
    case walking
    case reviewing
    case talking
    case blocked
}

enum MeetingRoomSceneKeyframeKind: String, Hashable {
    case issueCreated
    case issueAssigned
    case agentTyping
    case a2aMessage
    case reviewRequested
    case mergeCompleted
    case blockedJump
    case costPaused

    var usesScheduler: Bool {
        switch self {
        case .issueCreated, .issueAssigned, .agentTyping, .a2aMessage, .reviewRequested:
            return true
        case .mergeCompleted, .blockedJump, .costPaused:
            return false
        }
    }
}

struct MeetingRoomRenderPlan: Hashable {
    enum Mode: String, Hashable {
        case full
        case simplified
        case grouped

        var label: String {
            switch self {
            case .full:
                return "FULL"
            case .simplified:
                return "LOW"
            case .grouped:
                return "GROUPED"
            }
        }
    }

    let mode: Mode
    let visibleAgents: [MeetingRoomProjectionAgent]
    let hiddenAgentCount: Int
    let visibleFlows: [MeetingRoomFlowItem]
    let shouldAnimate: Bool
    let frameInterval: TimeInterval

    var animationKey: String {
        [
            mode.rawValue,
            visibleAgents.map { "\($0.id):\($0.visualState.rawValue):\($0.currentIssueId ?? "-")" }.joined(separator: "|"),
            visibleFlows.map { "\($0.id):\($0.kind.rawValue):\($0.progress)" }.joined(separator: "|"),
        ].joined(separator: "::")
    }

    static func build(
        projection: MeetingRoomProjection,
        isCompact: Bool,
        reduceMotion: Bool,
        lowResourceMode: Bool,
        isSceneActive: Bool
    ) -> MeetingRoomRenderPlan {
        let agentCount = projection.agents.count
        let mode: Mode
        if agentCount >= 50 {
            mode = .grouped
        } else if agentCount >= 20 || lowResourceMode || reduceMotion || isCompact {
            mode = .simplified
        } else {
            mode = .full
        }

        let maxAgents: Int
        let maxFlows: Int
        switch mode {
        case .full:
            maxAgents = agentCount
            maxFlows = 8
        case .simplified:
            maxAgents = min(agentCount, isCompact ? 10 : 20)
            maxFlows = 6
        case .grouped:
            maxAgents = min(agentCount, 12)
            maxFlows = 6
        }

        let prioritizedAgents = projection.agents.sorted { lhs, rhs in
            if lhs.visualState.renderPriority != rhs.visualState.renderPriority {
                return lhs.visualState.renderPriority > rhs.visualState.renderPriority
            }
            return lhs.id < rhs.id
        }
        let visibleAgents = Array(prioritizedAgents.prefix(maxAgents))
        let visibleFlows = Array(projection.flows.prefix(maxFlows))
        let hasLiveMotion = visibleAgents.contains { agent in
            switch agent.visualState {
            case .running, .review:
                return true
            case .idle, .blocked, .failed, .done, .costBlocked:
                return false
            }
        }
        let hasActiveFlow = visibleFlows.contains { flow in
            switch flow.kind {
            case .goalToIssue, .issueToAgent, .agentWorking, .a2aMessage, .agentToReview:
                return true
            case .reviewToMerge, .blocked, .costBlocked:
                return false
            }
        }
        let hasActiveMotion = hasLiveMotion || hasActiveFlow
        let shouldAnimate = isSceneActive &&
            !reduceMotion &&
            !lowResourceMode &&
            mode == .full &&
            agentCount < 20 &&
            hasActiveMotion

        return MeetingRoomRenderPlan(
            mode: mode,
            visibleAgents: visibleAgents,
            hiddenAgentCount: max(0, agentCount - visibleAgents.count),
            visibleFlows: visibleFlows,
            shouldAnimate: shouldAnimate,
            frameInterval: shouldAnimate ? (1.0 / 15.0) : 1.0
        )
    }
}

struct PixelOfficeLayout: Hashable {
    let size: CGSize
    let isCompact: Bool
    let mode: MeetingRoomRenderPlan.Mode

    var grid: CGFloat { 8 }

    func snapped(_ value: CGFloat) -> CGFloat {
        (value / grid).rounded() * grid
    }

    func snapped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: snapped(point.x), y: snapped(point.y))
    }

    func zonePoint(_ zone: MeetingRoomOfficeZone) -> CGPoint {
        let point: (CGFloat, CGFloat)
        switch zone {
        case .agentDesk:
            point = (0.52, 0.62)
        case .planningBoard:
            point = (0.24, 0.23)
        case .reviewDesk:
            point = (0.78, 0.34)
        case .blockerZone:
            point = (0.16, 0.75)
        case .costPanel:
            point = (0.84, 0.18)
        case .activityWall:
            point = (0.52, 0.16)
        case .mergeLane:
            point = (0.82, 0.78)
        }
        return snapped(CGPoint(x: size.width * point.0, y: size.height * point.1))
    }

    func deskPoint(for agent: MeetingRoomProjectionAgent, index: Int, count: Int) -> CGPoint {
        let role = agent.role.lowercased()
        if role.contains("ceo") || role.contains("lead") {
            return snapped(CGPoint(x: size.width * 0.30, y: size.height * 0.40))
        }
        if role.contains("qa") || role.contains("review") {
            return snapped(CGPoint(x: size.width * 0.70, y: size.height * 0.48))
        }
        if role.contains("ux") || role.contains("ui") || role.contains("design") || role.contains("product") {
            return snapped(CGPoint(x: size.width * 0.38, y: size.height * 0.48))
        }

        let columns = max(2, min(isCompact ? 3 : 4, Int(ceil(sqrt(Double(max(1, count)))))))
        let row = index / columns
        let column = index % columns
        let rowCount = max(1, Int(ceil(Double(max(1, count)) / Double(columns))))
        let x = 0.30 + 0.34 * CGFloat(column) / CGFloat(max(1, columns - 1))
        let y = 0.60 + 0.22 * CGFloat(row) / CGFloat(max(1, rowCount - 1))
        return snapped(CGPoint(x: size.width * x, y: size.height * y))
    }

    func targetPoint(for agent: MeetingRoomProjectionAgent, index: Int, count: Int) -> CGPoint {
        switch agent.zone {
        case .agentDesk:
            return deskPoint(for: agent, index: index, count: count)
        case .reviewDesk, .blockerZone, .costPanel:
            let base = zonePoint(agent.zone)
            let offset = CGFloat(index % 4) * 14 - 21
            return snapped(CGPoint(x: base.x + offset, y: base.y + CGFloat(index % 2) * 18))
        case .planningBoard, .activityWall, .mergeLane:
            return zonePoint(agent.zone)
        }
    }
}

struct MeetingRoomSceneAgent: Identifiable, Hashable {
    let id: String
    let projection: MeetingRoomProjectionAgent
    let action: MeetingRoomSpriteAction
    let fromPoint: CGPoint
    let targetPoint: CGPoint
    let movementStartedAt: TimeInterval
    let movementDuration: TimeInterval
    let isSimplified: Bool

    func point(at time: TimeInterval, animate: Bool) -> CGPoint {
        guard animate, action == .walking, movementDuration > 0 else {
            return targetPoint
        }
        let raw = CGFloat((time - movementStartedAt) / movementDuration)
        let progress = min(1, max(0, raw))
        let eased = progress * progress * (3 - 2 * progress)
        return CGPoint(
            x: fromPoint.x + (targetPoint.x - fromPoint.x) * eased,
            y: fromPoint.y + (targetPoint.y - fromPoint.y) * eased
        )
    }
}

struct MeetingRoomSceneIssueCard: Identifiable, Hashable {
    let id: String
    let title: String
    let status: String
    let zone: MeetingRoomOfficeZone
    let point: CGPoint
    let flow: MeetingRoomFlowItem?
}

struct MeetingRoomSceneKeyframe: Identifiable, Hashable {
    let id: String
    let kind: MeetingRoomSceneKeyframeKind
    let title: String
    let detail: String
    let issueId: String?
    let flow: MeetingRoomFlowItem?
    let fromZone: MeetingRoomOfficeZone
    let toZone: MeetingRoomOfficeZone
    let fromPoint: CGPoint
    let toPoint: CGPoint
    let fromAgentId: String?
    let toAgentId: String?
    let startedAt: TimeInterval
    let duration: TimeInterval

    var usesScheduler: Bool {
        kind.usesScheduler
    }

    func point(at time: TimeInterval, animate: Bool) -> CGPoint {
        guard animate, duration > 0 else {
            return toPoint
        }
        let raw = CGFloat((time - startedAt) / duration)
        let progress = min(1, max(0, raw))
        let eased = progress * progress * (3 - 2 * progress)
        return CGPoint(
            x: fromPoint.x + (toPoint.x - fromPoint.x) * eased,
            y: fromPoint.y + (toPoint.y - fromPoint.y) * eased
        )
    }
}

struct MeetingRoomSceneState: Hashable {
    let projectionIdentity: Int
    let layout: PixelOfficeLayout
    let renderPlan: MeetingRoomRenderPlan
    let agents: [MeetingRoomSceneAgent]
    let issueCards: [MeetingRoomSceneIssueCard]
    let keyframes: [MeetingRoomSceneKeyframe]
    let startedAt: TimeInterval

    var shouldAnimate: Bool {
        renderPlan.shouldAnimate && keyframes.contains { $0.usesScheduler }
    }

    var frameInterval: TimeInterval {
        shouldAnimate ? (1.0 / 15.0) : 1.0
    }

    var cacheKey: String {
        [
            "\(projectionIdentity)",
            "\(Int(layout.size.width))x\(Int(layout.size.height))",
            layout.mode.rawValue,
            renderPlan.animationKey,
        ].joined(separator: "::")
    }
}

enum MeetingRoomSceneReducer {
    static func reduce(
        previous: MeetingRoomSceneState?,
        projection: MeetingRoomProjection,
        layout: PixelOfficeLayout,
        isCompact: Bool,
        reduceMotion: Bool,
        lowResourceMode: Bool,
        isSceneActive: Bool,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) -> MeetingRoomSceneState {
        let plan = MeetingRoomRenderPlan.build(
            projection: projection,
            isCompact: isCompact,
            reduceMotion: reduceMotion,
            lowResourceMode: lowResourceMode,
            isSceneActive: isSceneActive
        )
        let previousAgentsById = Dictionary(uniqueKeysWithValues: (previous?.agents ?? []).map { ($0.id, $0) })
        let sceneAgents = plan.visibleAgents.enumerated().map { index, agent in
            let target = layout.targetPoint(for: agent, index: index, count: plan.visibleAgents.count)
            let previousAgent = previousAgentsById[agent.id]
            let from = previousAgent?.targetPoint ?? layout.deskPoint(for: agent, index: index, count: plan.visibleAgents.count)
            let moved = distance(from, target) > 4
            let action = spriteAction(for: agent, moved: moved && !reduceMotion && !lowResourceMode)
            return MeetingRoomSceneAgent(
                id: agent.id,
                projection: agent,
                action: action,
                fromPoint: from,
                targetPoint: target,
                movementStartedAt: moved ? now : (previousAgent?.movementStartedAt ?? now),
                movementDuration: moved ? 1.25 : 0,
                isSimplified: plan.mode != .full
            )
        }
        let agentsByRole = Dictionary(sceneAgents.map { ($0.projection.role.normalizedSceneKey, $0) }, uniquingKeysWith: { first, _ in first })
        let agentsByCli = Dictionary(sceneAgents.map { ($0.projection.cli.normalizedSceneKey, $0) }, uniquingKeysWith: { first, _ in first })
        let keyframes = plan.visibleFlows.map { flow in
            keyframe(
                for: flow,
                agentsByRole: agentsByRole,
                agentsByCli: agentsByCli,
                layout: layout,
                previous: previous,
                now: now
            )
        }
        let flowByIssueId = Dictionary(plan.visibleFlows.compactMap { flow in
            flow.issueId.map { ($0, flow) }
        }, uniquingKeysWith: { first, _ in first })
        let issueCards = projection.issues.prefix(plan.mode == .full ? 14 : 8).enumerated().map { index, issue in
            let zone = issueZone(for: issue)
            let base = layout.zonePoint(zone)
            let offset = cardOffset(index: index, mode: plan.mode)
            return MeetingRoomSceneIssueCard(
                id: issue.id,
                title: issue.title,
                status: issue.status,
                zone: zone,
                point: layout.snapped(CGPoint(x: base.x + offset.x, y: base.y + offset.y)),
                flow: flowByIssueId[issue.id]
            )
        }
        return MeetingRoomSceneState(
            projectionIdentity: projection.hashValue,
            layout: layout,
            renderPlan: plan,
            agents: sceneAgents,
            issueCards: issueCards,
            keyframes: keyframes,
            startedAt: previous?.startedAt ?? now
        )
    }

    private static func spriteAction(for agent: MeetingRoomProjectionAgent, moved: Bool) -> MeetingRoomSpriteAction {
        if moved {
            return .walking
        }
        if agent.messageCount > 0 {
            return .talking
        }
        switch agent.visualState {
        case .idle, .done:
            return .sitting
        case .running:
            return .typing
        case .review:
            return .reviewing
        case .blocked, .failed, .costBlocked:
            return .blocked
        }
    }

    private static func keyframe(
        for flow: MeetingRoomFlowItem,
        agentsByRole: [String: MeetingRoomSceneAgent],
        agentsByCli: [String: MeetingRoomSceneAgent],
        layout: PixelOfficeLayout,
        previous: MeetingRoomSceneState?,
        now: TimeInterval
    ) -> MeetingRoomSceneKeyframe {
        let kind = keyframeKind(for: flow.kind)
        let existing = previous?.keyframes.first { $0.id == flow.id }
        let agentEndpoints = a2aEndpoints(for: flow, agentsByRole: agentsByRole, agentsByCli: agentsByCli)
        let fromPoint = agentEndpoints?.from.targetPoint ?? layout.zonePoint(flow.from)
        let toPoint = agentEndpoints?.to.targetPoint ?? layout.zonePoint(flow.to)
        return MeetingRoomSceneKeyframe(
            id: flow.id,
            kind: kind,
            title: flow.title,
            detail: flow.detail,
            issueId: flow.issueId,
            flow: flow,
            fromZone: flow.from,
            toZone: flow.to,
            fromPoint: fromPoint,
            toPoint: toPoint,
            fromAgentId: agentEndpoints?.from.id,
            toAgentId: agentEndpoints?.to.id,
            startedAt: existing?.startedAt ?? now,
            duration: keyframeDuration(for: kind)
        )
    }

    private static func keyframeKind(for flowKind: MeetingRoomFlowKind) -> MeetingRoomSceneKeyframeKind {
        switch flowKind {
        case .goalToIssue:
            return .issueCreated
        case .issueToAgent:
            return .issueAssigned
        case .agentWorking:
            return .agentTyping
        case .a2aMessage:
            return .a2aMessage
        case .agentToReview:
            return .reviewRequested
        case .reviewToMerge:
            return .mergeCompleted
        case .blocked:
            return .blockedJump
        case .costBlocked:
            return .costPaused
        }
    }

    private static func keyframeDuration(for kind: MeetingRoomSceneKeyframeKind) -> TimeInterval {
        switch kind {
        case .a2aMessage:
            return 1.4
        case .issueCreated, .issueAssigned, .reviewRequested:
            return 1.2
        case .agentTyping:
            return 0.8
        case .mergeCompleted, .blockedJump, .costPaused:
            return 0
        }
    }

    private static func a2aEndpoints(
        for flow: MeetingRoomFlowItem,
        agentsByRole: [String: MeetingRoomSceneAgent],
        agentsByCli: [String: MeetingRoomSceneAgent]
    ) -> (from: MeetingRoomSceneAgent, to: MeetingRoomSceneAgent)? {
        guard flow.kind == .a2aMessage else {
            return nil
        }
        let parts = flow.title.components(separatedBy: "→").map { $0.normalizedSceneKey }
        guard parts.count == 2 else {
            return nil
        }
        let from = agentsByRole[parts[0]] ?? agentsByCli[parts[0]]
        let to = agentsByRole[parts[1]] ?? agentsByCli[parts[1]]
        guard let from, let to else {
            return nil
        }
        return (from, to)
    }

    private static func issueZone(for issue: MeetingRoomIssueSummary) -> MeetingRoomOfficeZone {
        let status = issue.status.uppercased()
        if status.contains("BLOCK") || status.contains("FAIL") {
            return .blockerZone
        }
        if status.contains("REVIEW") || issue.pullRequestState?.uppercased() == "OPEN" {
            return .reviewDesk
        }
        if status == "DONE" || status == "MERGED" || issue.pullRequestState?.uppercased() == "MERGED" {
            return .mergeLane
        }
        if status.contains("PROGRESS") || status.contains("RUN") {
            return .agentDesk
        }
        return .planningBoard
    }

    private static func cardOffset(index: Int, mode: MeetingRoomRenderPlan.Mode) -> CGPoint {
        let columns = mode == .full ? 3 : 2
        let column = index % columns
        let row = index / columns
        return CGPoint(x: CGFloat(column - 1) * 32, y: CGFloat(row) * 18)
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

private extension MeetingRoomVisualState {
    var renderPriority: Int {
        switch self {
        case .running:
            return 700
        case .review:
            return 600
        case .blocked, .failed, .costBlocked:
            return 500
        case .done:
            return 300
        case .idle:
            return 100
        }
    }
}

private extension String {
    var normalizedSceneKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
