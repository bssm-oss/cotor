import CoreGraphics
import Foundation

enum MeetingRoomSpriteAction: String, Hashable {
    case sitting
    case typing
    case walking
    case reviewing
    case talking
    case listening
    case approving
    case blocked
    case celebrating
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
        case .issueCreated, .issueAssigned, .agentTyping, .reviewRequested:
            return true
        case .a2aMessage, .mergeCompleted, .blockedJump, .costPaused:
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
    let visibleInteractions: [MeetingRoomInteractionEvent]
    let shouldAnimate: Bool
    let frameInterval: TimeInterval

    var animationKey: String {
        [
            mode.rawValue,
            visibleAgents.map { "\($0.id):\($0.visualState.rawValue):\($0.currentIssueId ?? "-")" }.joined(separator: "|"),
            visibleInteractions.map { "\($0.id):\($0.kind.rawValue):\($0.occurredAt)" }.joined(separator: "|"),
            visibleFlows.map { "\($0.id):\($0.kind.rawValue):\($0.progress)" }.joined(separator: "|"),
        ].joined(separator: "::")
    }

    static func build(
        projection: MeetingRoomProjection,
        isCompact: Bool,
        reduceMotion: Bool,
        lowResourceMode: Bool,
        isSceneActive: Bool,
        seenEventIds: Set<String> = []
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
        let maxInteractions: Int
        switch mode {
        case .full:
            maxAgents = agentCount
            maxFlows = 5
            maxInteractions = 8
        case .simplified:
            maxAgents = min(agentCount, isCompact ? 10 : 20)
            maxFlows = 4
            maxInteractions = 5
        case .grouped:
            maxAgents = min(agentCount, 12)
            maxFlows = 3
            maxInteractions = 4
        }

        let visibleInteractions = Array(projection.interactions.prefix(maxInteractions))
        let interactionAgentIds = Set(visibleInteractions.flatMap(\.agentIds))
        let priorityByAgentId = visibleInteractions.reduce(into: [String: Int]()) { result, event in
            for agentId in event.agentIds {
                result[agentId] = max(result[agentId] ?? 0, event.priority)
            }
        }
        let prioritizedAgents = projection.agents.sorted { lhs, rhs in
            let lhsEventPriority = priorityByAgentId[lhs.id] ?? 0
            let rhsEventPriority = priorityByAgentId[rhs.id] ?? 0
            if lhsEventPriority != rhsEventPriority {
                return lhsEventPriority > rhsEventPriority
            }
            if interactionAgentIds.contains(lhs.id) != interactionAgentIds.contains(rhs.id) {
                return interactionAgentIds.contains(lhs.id)
            }
            if lhs.visualState.renderPriority != rhs.visualState.renderPriority {
                return lhs.visualState.renderPriority > rhs.visualState.renderPriority
            }
            return lhs.id < rhs.id
        }
        let visibleAgents = Array(prioritizedAgents.prefix(maxAgents))
        let visibleAgentIds = Set(visibleAgents.map(\.id))
        let filteredInteractions = visibleInteractions.filter { event in
            event.agentIds.isEmpty || !Set(event.agentIds).isDisjoint(with: visibleAgentIds)
        }
        let visibleFlows = Array(
            projection.flows
                .filter { $0.kind != .a2aMessage && $0.kind != .agentToReview }
                .prefix(maxFlows)
        )
        let hasFreshInteraction = filteredInteractions.contains { event in
            event.drivesSceneScheduler && !seenEventIds.contains(event.id)
        }
        let shouldAnimate = isSceneActive &&
            !reduceMotion &&
            !lowResourceMode &&
            mode == .full &&
            agentCount < 20 &&
            hasFreshInteraction

        return MeetingRoomRenderPlan(
            mode: mode,
            visibleAgents: visibleAgents,
            hiddenAgentCount: max(0, agentCount - visibleAgents.count),
            visibleFlows: visibleFlows,
            visibleInteractions: filteredInteractions,
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
            point = (0.22, 0.22)
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

    func centerTablePoint(index: Int = 0, count: Int = 1) -> CGPoint {
        let offsets = huddleOffsets(index: index, count: count, radius: isCompact ? 30 : 48)
        return snapped(CGPoint(x: size.width * 0.50 + offsets.x, y: size.height * 0.43 + offsets.y))
    }

    func deskPoint(for agent: MeetingRoomProjectionAgent, index: Int, count: Int) -> CGPoint {
        let role = agent.role.lowercased()
        if role.contains("ceo") || role.contains("lead") {
            return snapped(CGPoint(x: size.width * 0.30, y: size.height * 0.39))
        }
        if role.contains("qa") || role.contains("review") {
            return snapped(CGPoint(x: size.width * 0.71, y: size.height * 0.49))
        }
        if role.contains("ux") || role.contains("ui") || role.contains("design") || role.contains("product") {
            return snapped(CGPoint(x: size.width * 0.38, y: size.height * 0.49))
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

    func talkPoint(near point: CGPoint, index: Int = 0) -> CGPoint {
        let offsets = [
            CGPoint(x: -48, y: 36),
            CGPoint(x: 48, y: 36),
            CGPoint(x: -48, y: -34),
            CGPoint(x: 48, y: -34),
        ]
        let offset = offsets[index % offsets.count]
        return snapped(CGPoint(x: point.x + offset.x, y: point.y + offset.y))
    }

    func cardPoint(for event: MeetingRoomInteractionEvent, fallbackZone: MeetingRoomOfficeZone) -> CGPoint {
        switch event.kind {
        case .ceoApprovalRequested, .approvalGranted:
            return snapped(CGPoint(x: zonePoint(.agentDesk).x - size.width * 0.20, y: zonePoint(.agentDesk).y - size.height * 0.22))
        case .qaReviewRequested, .changesRequested:
            return zonePoint(.reviewDesk)
        case .blockedEscalation:
            return zonePoint(.blockerZone)
        case .mergeCompleted:
            return zonePoint(.mergeLane)
        case .costPaused:
            return zonePoint(.costPanel)
        case .meeting:
            return centerTablePoint()
        case .issueAssigned:
            return zonePoint(.planningBoard)
        case .workStarted, .handoff:
            return zonePoint(fallbackZone)
        }
    }

    private func huddleOffsets(index: Int, count: Int, radius: CGFloat) -> CGPoint {
        guard count > 1 else { return CGPoint(x: 0, y: radius * 0.55) }
        let angle = (Double(index) / Double(max(1, count))) * Double.pi * 2.0 + Double.pi / 2.0
        return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius * 0.62)
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
    let speechText: String?
    let focusEvent: MeetingRoomInteractionEvent?
    let isFreshInteraction: Bool

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
    let fromPoint: CGPoint
    let targetPoint: CGPoint
    let movementStartedAt: TimeInterval
    let movementDuration: TimeInterval
    let flow: MeetingRoomFlowItem?
    let interaction: MeetingRoomInteractionEvent?

    var point: CGPoint { targetPoint }

    func point(at time: TimeInterval, animate: Bool) -> CGPoint {
        guard animate, movementDuration > 0 else {
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

struct MeetingRoomSceneInteraction: Identifiable, Hashable {
    let id: String
    let event: MeetingRoomInteractionEvent
    let fromPoint: CGPoint
    let toPoint: CGPoint
    let startedAt: TimeInterval
    let duration: TimeInterval
    let isFresh: Bool

    var usesScheduler: Bool {
        isFresh && event.drivesSceneScheduler
    }
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

struct MeetingRoomSceneLedger: Hashable {
    var seenEventIds: Set<String> = []
    var settledAgentPositions: [String: CGPoint] = [:]
    var lastProjectionFingerprint: Int?

    static let empty = MeetingRoomSceneLedger()

    func recording(events: [MeetingRoomInteractionEvent], agents: [MeetingRoomSceneAgent], projectionIdentity: Int) -> MeetingRoomSceneLedger {
        var next = self
        next.seenEventIds.formUnion(events.map(\.id))
        next.settledAgentPositions = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0.targetPoint) })
        next.lastProjectionFingerprint = projectionIdentity
        return next
    }
}

@MainActor
enum MeetingRoomSceneMemoryStore {
    private struct Entry {
        var ledger: MeetingRoomSceneLedger
        var updatedAt: TimeInterval
    }

    private static let defaultMaxEntries = 32
    private static let defaultTTLSeconds: TimeInterval = 30 * 60
    private static var ledgers: [String: Entry] = [:]

    static func ledger(for key: String, now: TimeInterval = Date().timeIntervalSince1970) -> MeetingRoomSceneLedger {
        pruneExpired(now: now)
        return ledgers[key]?.ledger ?? .empty
    }

    static func remember(_ ledger: MeetingRoomSceneLedger, for key: String, now: TimeInterval = Date().timeIntervalSince1970) {
        pruneExpired(now: now)
        ledgers[key] = Entry(ledger: ledger, updatedAt: now)
        pruneToCapacity(defaultMaxEntries)
    }

    static func reset(for key: String) {
        ledgers[key] = nil
    }

    static func pruneExpired(now: TimeInterval = Date().timeIntervalSince1970, maxAgeSeconds: TimeInterval = defaultTTLSeconds) {
        ledgers = ledgers.filter { _, entry in
            now - entry.updatedAt <= maxAgeSeconds
        }
    }

    static func pruneToCapacity(_ maxEntries: Int = defaultMaxEntries) {
        guard ledgers.count > maxEntries else { return }
        let keysToDrop = ledgers
            .sorted { $0.value.updatedAt < $1.value.updatedAt }
            .prefix(ledgers.count - maxEntries)
            .map(\.key)
        keysToDrop.forEach { ledgers[$0] = nil }
    }

    static func countForTesting() -> Int {
        ledgers.count
    }
}

struct MeetingRoomSceneState: Hashable {
    let projectionIdentity: Int
    let layout: PixelOfficeLayout
    let renderPlan: MeetingRoomRenderPlan
    let agents: [MeetingRoomSceneAgent]
    let issueCards: [MeetingRoomSceneIssueCard]
    let interactions: [MeetingRoomSceneInteraction]
    let keyframes: [MeetingRoomSceneKeyframe]
    let freshInteractionIds: Set<String>
    let nextLedger: MeetingRoomSceneLedger
    let startedAt: TimeInterval

    var shouldAnimate: Bool {
        renderPlan.shouldAnimate && !freshInteractionIds.isEmpty
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
            freshInteractionIds.sorted().joined(separator: "|"),
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
        ledger: MeetingRoomSceneLedger = .empty,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) -> MeetingRoomSceneState {
        let plan = MeetingRoomRenderPlan.build(
            projection: projection,
            isCompact: isCompact,
            reduceMotion: reduceMotion,
            lowResourceMode: lowResourceMode,
            isSceneActive: isSceneActive,
            seenEventIds: ledger.seenEventIds
        )
        let freshInteractionIds = Set(plan.visibleInteractions.filter { event in
            event.drivesSceneScheduler && !ledger.seenEventIds.contains(event.id)
        }.map(\.id))
        let previousAgentsById = Dictionary(uniqueKeysWithValues: (previous?.agents ?? []).map { ($0.id, $0) })
        let basePointByAgentId = Dictionary(uniqueKeysWithValues: plan.visibleAgents.enumerated().map { index, agent in
            (agent.id, layout.targetPoint(for: agent, index: index, count: plan.visibleAgents.count))
        })
        let interactionByAgentId = focusedInteractionByAgentId(plan.visibleInteractions, freshInteractionIds: freshInteractionIds)

        let sceneAgents = plan.visibleAgents.enumerated().map { index, agent in
            let baseTarget = basePointByAgentId[agent.id] ?? layout.targetPoint(for: agent, index: index, count: plan.visibleAgents.count)
            let focusEvent = interactionByAgentId[agent.id]
            let target = focusEvent.map {
                interactionTargetPoint(for: agent, event: $0, basePointByAgentId: basePointByAgentId, layout: layout)
            } ?? baseTarget
            let existing = previousAgentsById[agent.id]
            let from = existing?.targetPoint ?? ledger.settledAgentPositions[agent.id] ?? baseTarget
            let isFresh = focusEvent.map { freshInteractionIds.contains($0.id) } ?? false
            let shouldMove = isFresh && !reduceMotion && !lowResourceMode && distance(from, target) > 4
            let action = spriteAction(for: agent, focusEvent: focusEvent, isFresh: isFresh, moved: shouldMove)
            return MeetingRoomSceneAgent(
                id: agent.id,
                projection: agent,
                action: action,
                fromPoint: shouldMove ? from : target,
                targetPoint: target,
                movementStartedAt: shouldMove ? now : (existing?.movementStartedAt ?? now),
                movementDuration: shouldMove ? movementDuration(for: focusEvent?.kind) : 0,
                isSimplified: plan.mode != .full,
                speechText: speechText(for: agent.id, event: focusEvent, liveActivity: agent.liveActivity),
                focusEvent: focusEvent,
                isFreshInteraction: isFresh
            )
        }

        let sceneAgentsById = Dictionary(uniqueKeysWithValues: sceneAgents.map { ($0.id, $0) })
        let interactions = plan.visibleInteractions.map { event in
            let fromPoint = event.fromAgentId.flatMap { sceneAgentsById[$0]?.targetPoint } ?? event.agentIds.first.flatMap { sceneAgentsById[$0]?.targetPoint } ?? layout.zonePoint(.activityWall)
            let toPoint = event.toAgentId.flatMap { sceneAgentsById[$0]?.targetPoint } ?? event.agentIds.dropFirst().first.flatMap { sceneAgentsById[$0]?.targetPoint } ?? layout.cardPoint(for: event, fallbackZone: .activityWall)
            return MeetingRoomSceneInteraction(
                id: event.id,
                event: event,
                fromPoint: fromPoint,
                toPoint: toPoint,
                startedAt: previous?.interactions.first { $0.id == event.id }?.startedAt ?? now,
                duration: movementDuration(for: event.kind),
                isFresh: freshInteractionIds.contains(event.id)
            )
        }

        let keyframes = plan.visibleFlows.map { flow in
            keyframe(for: flow, layout: layout, previous: previous, now: now)
        }
        let flowByIssueId = Dictionary(plan.visibleFlows.compactMap { flow in
            flow.issueId.map { ($0, flow) }
        }, uniquingKeysWith: { first, _ in first })
        let interactionByIssueId = Dictionary(plan.visibleInteractions.compactMap { event in
            event.issueId.map { ($0, event) }
        }, uniquingKeysWith: { first, _ in first })
        let previousCardsById = Dictionary(uniqueKeysWithValues: (previous?.issueCards ?? []).map { ($0.id, $0) })
        let issueCards = projection.issues.prefix(plan.mode == .full ? 14 : 8).enumerated().map { index, issue in
            let zone = issueZone(for: issue)
            let base = layout.zonePoint(zone)
            let offset = cardOffset(index: index, mode: plan.mode)
            let staticPoint = layout.snapped(CGPoint(x: base.x + offset.x, y: base.y + offset.y))
            let event = interactionByIssueId[issue.id]
            let target = event.map { layout.cardPoint(for: $0, fallbackZone: zone) } ?? staticPoint
            let previousCard = previousCardsById[issue.id]
            let isFresh = event.map { freshInteractionIds.contains($0.id) } ?? false
            let from = previousCard?.targetPoint ?? staticPoint
            return MeetingRoomSceneIssueCard(
                id: issue.id,
                title: issue.title,
                status: issue.status,
                zone: zone,
                fromPoint: isFresh ? from : target,
                targetPoint: target,
                movementStartedAt: isFresh ? now : (previousCard?.movementStartedAt ?? now),
                movementDuration: isFresh ? 1.1 : 0,
                flow: flowByIssueId[issue.id],
                interaction: event
            )
        }

        let nextLedger = ledger.recording(
            events: plan.visibleInteractions,
            agents: sceneAgents,
            projectionIdentity: projection.hashValue
        )
        return MeetingRoomSceneState(
            projectionIdentity: projection.hashValue,
            layout: layout,
            renderPlan: plan,
            agents: sceneAgents,
            issueCards: issueCards,
            interactions: interactions,
            keyframes: keyframes,
            freshInteractionIds: freshInteractionIds,
            nextLedger: nextLedger,
            startedAt: previous?.startedAt ?? now
        )
    }

    private static func focusedInteractionByAgentId(
        _ interactions: [MeetingRoomInteractionEvent],
        freshInteractionIds: Set<String>
    ) -> [String: MeetingRoomInteractionEvent] {
        var result: [String: MeetingRoomInteractionEvent] = [:]
        for event in interactions.sorted(by: { lhs, rhs in
            let lhsFresh = freshInteractionIds.contains(lhs.id)
            let rhsFresh = freshInteractionIds.contains(rhs.id)
            if lhsFresh != rhsFresh {
                return lhsFresh
            }
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.occurredAt > rhs.occurredAt
        }) {
            for agentId in event.agentIds where result[agentId] == nil {
                result[agentId] = event
            }
        }
        return result
    }

    private static func interactionTargetPoint(
        for agent: MeetingRoomProjectionAgent,
        event: MeetingRoomInteractionEvent,
        basePointByAgentId: [String: CGPoint],
        layout: PixelOfficeLayout
    ) -> CGPoint {
        switch event.kind {
        case .ceoApprovalRequested, .approvalGranted:
            if event.toAgentId == agent.id {
                return basePointByAgentId[agent.id] ?? layout.zonePoint(.agentDesk)
            }
            let ceoPoint = event.toAgentId.flatMap { basePointByAgentId[$0] } ?? layout.zonePoint(.agentDesk)
            return layout.talkPoint(near: ceoPoint, index: 0)
        case .qaReviewRequested, .changesRequested:
            if event.toAgentId == agent.id {
                return basePointByAgentId[agent.id] ?? layout.zonePoint(.reviewDesk)
            }
            let qaPoint = event.toAgentId.flatMap { basePointByAgentId[$0] } ?? layout.zonePoint(.reviewDesk)
            return layout.talkPoint(near: qaPoint, index: 1)
        case .handoff:
            if event.toAgentId == agent.id {
                return basePointByAgentId[agent.id] ?? layout.centerTablePoint()
            }
            let targetPoint = event.toAgentId.flatMap { basePointByAgentId[$0] } ?? layout.centerTablePoint()
            return layout.talkPoint(near: targetPoint, index: 0)
        case .meeting:
            let ids = event.agentIds
            let index = ids.firstIndex(of: agent.id) ?? 0
            return layout.centerTablePoint(index: index, count: max(1, ids.count))
        case .blockedEscalation:
            if event.fromAgentId == agent.id {
                return layout.zonePoint(.blockerZone)
            }
            return layout.talkPoint(near: layout.zonePoint(.blockerZone), index: 1)
        case .issueAssigned:
            if event.toAgentId == agent.id {
                return layout.talkPoint(near: layout.zonePoint(.planningBoard), index: 1)
            }
            return layout.talkPoint(near: layout.zonePoint(.planningBoard), index: 0)
        case .workStarted:
            return basePointByAgentId[agent.id] ?? layout.zonePoint(.agentDesk)
        case .mergeCompleted:
            return event.fromAgentId == agent.id ? layout.talkPoint(near: layout.zonePoint(.mergeLane), index: 0) : layout.zonePoint(.mergeLane)
        case .costPaused:
            return event.fromAgentId == agent.id ? layout.talkPoint(near: layout.zonePoint(.costPanel), index: 0) : layout.zonePoint(.costPanel)
        }
    }

    private static func spriteAction(
        for agent: MeetingRoomProjectionAgent,
        focusEvent: MeetingRoomInteractionEvent?,
        isFresh: Bool,
        moved: Bool
    ) -> MeetingRoomSpriteAction {
        if moved {
            return .walking
        }
        guard let focusEvent else {
            return baseSpriteAction(for: agent)
        }
        switch focusEvent.kind {
        case .workStarted:
            return .typing
        case .ceoApprovalRequested:
            return focusEvent.toAgentId == agent.id ? .approving : .talking
        case .approvalGranted:
            return .celebrating
        case .qaReviewRequested, .changesRequested:
            return focusEvent.toAgentId == agent.id ? .reviewing : .talking
        case .handoff:
            return focusEvent.fromAgentId == agent.id ? .talking : .listening
        case .meeting:
            return focusEvent.fromAgentId == agent.id ? .talking : .listening
        case .blockedEscalation, .costPaused:
            return focusEvent.fromAgentId == agent.id ? .blocked : .listening
        case .issueAssigned:
            return focusEvent.toAgentId == agent.id ? .talking : .listening
        case .mergeCompleted:
            return isFresh ? .walking : .celebrating
        }
    }

    private static func baseSpriteAction(for agent: MeetingRoomProjectionAgent) -> MeetingRoomSpriteAction {
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

    private static func speechText(for agentId: String, event: MeetingRoomInteractionEvent?, liveActivity: String? = nil) -> String? {
        guard let event else { return liveActivity }
        if event.fromAgentId == agentId {
            return event.speechText
        }
        if event.toAgentId == agentId {
            switch event.kind {
            case .ceoApprovalRequested:
                return "Reviewing approval"
            case .qaReviewRequested:
                return "Reviewing now"
            case .changesRequested:
                return "Please revise"
            case .handoff:
                return "Received"
            case .blockedEscalation:
                return "Checking blocker"
            case .issueAssigned:
                return "Assigned"
            case .approvalGranted:
                return "Approved"
            case .meeting:
                return "Syncing"
            case .workStarted:
                return "Working on it"
            case .mergeCompleted:
                return "Merged"
            case .costPaused:
                return "Paused"
            }
        }
        if event.kind == .meeting {
            return "Syncing"
        }
        return nil
    }

    private static func keyframe(
        for flow: MeetingRoomFlowItem,
        layout: PixelOfficeLayout,
        previous: MeetingRoomSceneState?,
        now: TimeInterval
    ) -> MeetingRoomSceneKeyframe {
        let kind = keyframeKind(for: flow.kind)
        let existing = previous?.keyframes.first { $0.id == flow.id }
        let fromPoint = layout.zonePoint(flow.from)
        let toPoint = layout.zonePoint(flow.to)
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
            fromAgentId: nil,
            toAgentId: nil,
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
        case .issueCreated, .issueAssigned, .reviewRequested:
            return 1.2
        case .agentTyping:
            return 0.8
        case .a2aMessage, .mergeCompleted, .blockedJump, .costPaused:
            return 0
        }
    }

    private static func movementDuration(for kind: MeetingRoomInteractionKind?) -> TimeInterval {
        switch kind {
        case .meeting:
            return 1.4
        case .ceoApprovalRequested, .qaReviewRequested, .blockedEscalation, .handoff, .changesRequested:
            return 1.25
        case .issueAssigned, .workStarted:
            return 1.0
        case .approvalGranted, .mergeCompleted, .costPaused, nil:
            return 0
        }
    }

    private static func issueZone(for issue: MeetingRoomIssueSummary) -> MeetingRoomOfficeZone {
        let status = issue.status.uppercased()
        if status.contains("BLOCK") || status.contains("FAIL") {
            return .blockerZone
        }
        if status == "READY_FOR_CEO" || status.contains("REVIEW") || issue.pullRequestState?.uppercased() == "OPEN" {
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

private extension MeetingRoomInteractionEvent {
    var drivesSceneScheduler: Bool {
        guard kind.usesScheduler else {
            return false
        }
        if kind == .blockedEscalation && messageId == nil && reviewId == nil {
            return false
        }
        return true
    }
}

private extension String {
    var normalizedSceneKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
