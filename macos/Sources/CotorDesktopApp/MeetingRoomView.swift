import SwiftUI

extension MeetingRoomOfficeZone: Identifiable {
    var id: String { rawValue }
}

struct MeetingRoomView: View {
    let projection: MeetingRoomProjection
    let language: AppLanguage
    let inboxCount: Int
    let isCompact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("meetingRoomLowResourceMode") private var lowResourceMode = false
    @State private var sceneState: MeetingRoomSceneState?
    @State private var selectedAgent: MeetingRoomProjectionAgent?
    @State private var selectedIssue: MeetingRoomIssueSummary?
    @State private var selectedFlow: MeetingRoomFlowItem?
    @State private var selectedZone: MeetingRoomOfficeZone?

    private var sceneMemoryKey: String {
        projection.companyId ?? "all-companies"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            GeometryReader { geometry in
                let plan = MeetingRoomRenderPlan.build(
                    projection: projection,
                    isCompact: isCompact,
                    reduceMotion: reduceMotion,
                    lowResourceMode: lowResourceMode,
                    isSceneActive: scenePhase == .active
                )
                let layout = PixelOfficeLayout(size: geometry.size, isCompact: isCompact, mode: plan.mode)
                let ledger = MeetingRoomSceneMemoryStore.ledger(for: sceneMemoryKey)
                let state = MeetingRoomSceneReducer.reduce(
                    previous: sceneState,
                    projection: projection,
                    layout: layout,
                    isCompact: isCompact,
                    reduceMotion: reduceMotion,
                    lowResourceMode: lowResourceMode,
                    isSceneActive: scenePhase == .active,
                    ledger: ledger
                )

                officeStage(state: state)
                    .onAppear {
                        sceneState = state
                        MeetingRoomSceneMemoryStore.remember(state.nextLedger, for: sceneMemoryKey)
                    }
                    .onChange(of: state.cacheKey) { _, _ in
                        sceneState = state
                        MeetingRoomSceneMemoryStore.remember(state.nextLedger, for: sceneMemoryKey)
                    }
            }
            .frame(height: isCompact ? 380 : 560)
        }
        .sheet(item: $selectedAgent) { agent in
            MeetingRoomProjectionAgentSheet(agent: agent, language: language)
        }
        .sheet(item: $selectedIssue) { issue in
            MeetingRoomProjectionIssueSheet(issue: issue, language: language)
        }
        .sheet(item: $selectedFlow) { flow in
            MeetingRoomProjectionFlowSheet(
                flow: flow,
                issue: projection.issues.first { $0.id == flow.issueId },
                language: language
            )
        }
        .sheet(item: $selectedZone) { zone in
            MeetingRoomProjectionZoneSheet(
                zone: zone,
                projection: projection,
                language: language
            )
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ShellTag(text: language("Live Office", "라이브 오피스"), tint: ShellPalette.accent)
            ShellTag(text: "\(language("Agents", "에이전트")) \(projection.agents.count)", tint: ShellPalette.accentWarm)
            ShellTag(text: "\(language("Running", "작업 중")) \(projection.agents.filter { $0.visualState == .running }.count)", tint: ShellPalette.success)
            ShellTag(text: "\(language("Review", "리뷰")) \(projection.reviewCount)", tint: ShellPalette.warning)
            if projection.isCostBlocked {
                ShellTag(text: language("COST PAUSED", "비용 일시정지"), tint: ShellPalette.warning)
            }
            Spacer(minLength: 0)
            Text("\(projection.runtimeStatus) · \(projection.runtimeBackendHealth)")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(ShellPalette.muted)
                .lineLimit(1)
            Button {
                lowResourceMode.toggle()
            } label: {
                Image(systemName: lowResourceMode ? "bolt.slash.fill" : "bolt.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(lowResourceMode ? ShellPalette.warning : ShellPalette.success)
                    .frame(width: 24, height: 22)
                    .background(ShellPalette.panelAlt)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(ShellPalette.line, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lowResourceMode ? language("Disable low resource mode", "저자원 모드 끄기") : language("Enable low resource mode", "저자원 모드 켜기"))
        }
        .accessibilityElement(children: .combine)
    }

    private func officeStage(state: MeetingRoomSceneState) -> some View {
        ZStack {
            PixelOfficeCanvas(
                projection: projection,
                layout: state.layout,
                language: language,
                inboxCount: inboxCount
            )

            if state.shouldAnimate {
                TimelineView(.periodic(from: .now, by: state.frameInterval)) { timeline in
                    spriteLayer(state: state, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                spriteLayer(state: state, time: state.startedAt)
            }

            hitTargetLayer(state: state)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ShellPalette.lineStrong.opacity(0.72), lineWidth: 1)
        )
        .animation(state.shouldAnimate ? .easeInOut(duration: 0.18) : nil, value: state.cacheKey)
    }

    private func spriteLayer(state: MeetingRoomSceneState, time: TimeInterval) -> some View {
        ZStack {
            ForEach(state.interactions) { interaction in
                PixelOfficeInteractionRouteView(interaction: interaction)
                    .frame(width: state.layout.size.width, height: state.layout.size.height)
                    .zIndex(1)
            }

            ForEach(state.keyframes) { keyframe in
                PixelOfficeKeyframeView(
                    keyframe: keyframe,
                    language: language,
                    time: time,
                    animate: state.shouldAnimate
                ) {
                    if let flow = keyframe.flow {
                        selectedFlow = flow
                    }
                }
            }

            ForEach(state.issueCards) { card in
                PixelIssueCardView(card: card, language: language) {
                    selectedIssue = projection.issues.first { $0.id == card.id }
                }
                .position(card.point(at: time, animate: state.shouldAnimate && card.interaction != nil))
                .zIndex(2)
            }

            ForEach(state.agents) { sceneAgent in
                PixelAgentSprite(
                    sceneAgent: sceneAgent,
                    language: language,
                    phase: time,
                    animate: state.shouldAnimate
                ) {
                    selectedAgent = sceneAgent.projection
                }
                .position(sceneAgent.point(at: time, animate: state.shouldAnimate))
                .zIndex(agentZIndex(sceneAgent))
            }

            if state.renderPlan.hiddenAgentCount > 0 {
                groupedAgentsBadge(count: state.renderPlan.hiddenAgentCount, layout: state.layout)
                    .zIndex(10)
            }
        }
    }

    private func hitTargetLayer(state: MeetingRoomSceneState) -> some View {
        ZStack {
            ForEach(zoneButtons(layout: state.layout), id: \.zone) { item in
                Button {
                    selectedZone = item.zone
                } label: {
                    HStack(spacing: 5) {
                        Text(item.title)
                        Text("\(item.count)")
                            .foregroundStyle(zoneTint(item.zone))
                    }
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(ShellPalette.text)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(ShellPalette.panel.opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(zoneTint(item.zone).opacity(0.46), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                .buttonStyle(.plain)
                .position(item.point)
                .accessibilityLabel("\(item.title), \(item.count)")
            }
        }
    }

    private func groupedAgentsBadge(count: Int, layout: PixelOfficeLayout) -> some View {
        Button {
            selectedZone = .agentDesk
        } label: {
            VStack(spacing: 2) {
                Text("+\(count)")
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                Text(language("cluster", "클러스터"))
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
            }
            .foregroundStyle(ShellPalette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(ShellPalette.panelRaised.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(ShellPalette.warning.opacity(0.55), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .position(layout.zonePoint(.agentDesk))
        .accessibilityLabel(language("\(count) grouped agents", "\(count)명 에이전트 클러스터"))
    }

    private func zoneButtons(layout: PixelOfficeLayout) -> [MeetingRoomZoneButton] {
        [
            MeetingRoomZoneButton(zone: .planningBoard, title: language("Board", "보드"), count: planningCount, point: layout.zonePoint(.planningBoard)),
            MeetingRoomZoneButton(zone: .reviewDesk, title: language("Review", "리뷰"), count: projection.reviewCount, point: layout.zonePoint(.reviewDesk)),
            MeetingRoomZoneButton(zone: .blockerZone, title: language("Blocked", "차단"), count: projection.blockedIssueCount, point: layout.zonePoint(.blockerZone)),
            MeetingRoomZoneButton(zone: .activityWall, title: language("Activity", "활동"), count: projection.activityCount, point: layout.zonePoint(.activityWall)),
            MeetingRoomZoneButton(zone: .mergeLane, title: language("Merge", "머지"), count: mergeCount, point: layout.zonePoint(.mergeLane)),
        ]
    }

    private var planningCount: Int {
        projection.issues.filter { issue in
            let status = issue.status.uppercased()
            return status.contains("PLAN") || status.contains("BACKLOG") || status.contains("TODO")
        }.count
    }

    private var mergeCount: Int {
        projection.issues.filter { issue in
            issue.status.uppercased() == "DONE" || issue.pullRequestState?.uppercased() == "MERGED"
        }.count
    }

    private func agentZIndex(_ agent: MeetingRoomSceneAgent) -> Double {
        switch agent.projection.visualState {
        case .running:
            return 8
        case .review:
            return 7
        case .blocked, .failed, .costBlocked:
            return 6
        case .done:
            return 5
        case .idle:
            return 4
        }
    }

    private func zoneTint(_ zone: MeetingRoomOfficeZone) -> Color {
        switch zone {
        case .agentDesk, .activityWall:
            return ShellPalette.accent
        case .planningBoard:
            return ShellPalette.accentWarm
        case .reviewDesk, .costPanel:
            return ShellPalette.warning
        case .blockerZone:
            return ShellPalette.danger
        case .mergeLane:
            return ShellPalette.success
        }
    }
}

private struct PixelOfficeCanvas: View {
    let projection: MeetingRoomProjection
    let layout: PixelOfficeLayout
    let language: AppLanguage
    let inboxCount: Int

    var body: some View {
        Canvas { context, size in
            drawRoom(context: &context, size: size)
            drawZones(context: &context)
            drawFurniture(context: &context)
            drawLabels(context: &context)
        }
        .accessibilityHidden(true)
    }

    private func drawRoom(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.07, green: 0.08, blue: 0.10)))

        let wall = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.22)
        context.fill(Path(wall), with: .color(Color(red: 0.12, green: 0.11, blue: 0.12)))

        let floor = CGRect(x: 0, y: wall.maxY, width: size.width, height: size.height - wall.maxY)
        context.fill(Path(floor), with: .color(Color(red: 0.22, green: 0.18, blue: 0.14)))

        let tile: CGFloat = 32
        var y = layout.snapped(floor.minY)
        var row = 0
        while y < floor.maxY {
            var x: CGFloat = 0
            var column = 0
            while x < floor.maxX {
                let rect = CGRect(x: x, y: y, width: tile, height: tile)
                let opacity = (row + column).isMultiple(of: 2) ? 0.07 : 0.035
                context.fill(Path(rect), with: .color(Color.white.opacity(opacity)))
                x += tile
                column += 1
            }
            y += tile
            row += 1
        }

        for index in 0...Int(size.width / 8) {
            let x = CGFloat(index) * 8
            context.fill(Path(CGRect(x: x, y: floor.minY, width: 1, height: floor.height)), with: .color(Color.black.opacity(index.isMultiple(of: 4) ? 0.10 : 0.035)))
        }
        for index in 0...Int(size.height / 8) {
            let y = CGFloat(index) * 8
            context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color.black.opacity(index.isMultiple(of: 4) ? 0.10 : 0.035)))
        }

        context.stroke(
            Path(roundedRect: CGRect(x: 8, y: 8, width: size.width - 16, height: size.height - 16), cornerRadius: 6),
            with: .color(ShellPalette.lineStrong.opacity(0.65)),
            lineWidth: 2
        )
    }

    private func drawZones(context: inout GraphicsContext) {
        zonePlate(.planningBoard, size: CGSize(width: 150, height: 86), tint: ShellPalette.accentWarm, context: &context)
        zonePlate(.activityWall, size: CGSize(width: 190, height: 54), tint: ShellPalette.accent, context: &context)
        zonePlate(.reviewDesk, size: CGSize(width: 150, height: 92), tint: ShellPalette.warning, context: &context)
        zonePlate(.blockerZone, size: CGSize(width: 134, height: 76), tint: ShellPalette.danger, context: &context)
        zonePlate(.mergeLane, size: CGSize(width: 150, height: 78), tint: ShellPalette.success, context: &context)
        zonePlate(.costPanel, size: CGSize(width: 128, height: 50), tint: ShellPalette.warning, context: &context)
    }

    private func zonePlate(_ zone: MeetingRoomOfficeZone, size: CGSize, tint: Color, context: inout GraphicsContext) {
        let point = layout.zonePoint(zone)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(tint.opacity(0.12)))
        context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(tint.opacity(0.50)), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
    }

    private func drawFurniture(context: inout GraphicsContext) {
        drawPlanningBoard(context: &context)
        drawDeskGrid(context: &context)
        drawReviewDesk(context: &context)
        drawBlockerCorner(context: &context)
        drawMergeLane(context: &context)
        drawPlants(context: &context)
        drawInbox(context: &context)
    }

    private func drawPlanningBoard(context: inout GraphicsContext) {
        let point = layout.zonePoint(.planningBoard)
        let board = CGRect(x: point.x - 64, y: point.y - 32, width: 128, height: 58)
        context.fill(Path(roundedRect: board, cornerRadius: 3), with: .color(Color(red: 0.14, green: 0.19, blue: 0.19)))
        context.stroke(Path(roundedRect: board, cornerRadius: 3), with: .color(ShellPalette.accentWarm.opacity(0.7)), lineWidth: 2)
        for index in 0..<9 {
            let x = board.minX + 10 + CGFloat(index % 3) * 35
            let y = board.minY + 10 + CGFloat(index / 3) * 15
            context.fill(Path(CGRect(x: x, y: y, width: 25, height: 9)), with: .color(index.isMultiple(of: 2) ? ShellPalette.accentWarm.opacity(0.72) : ShellPalette.warning.opacity(0.66)))
        }
    }

    private func drawDeskGrid(context: inout GraphicsContext) {
        let points = [
            CGPoint(x: layout.size.width * 0.30, y: layout.size.height * 0.60),
            CGPoint(x: layout.size.width * 0.46, y: layout.size.height * 0.60),
            CGPoint(x: layout.size.width * 0.62, y: layout.size.height * 0.60),
            CGPoint(x: layout.size.width * 0.30, y: layout.size.height * 0.78),
            CGPoint(x: layout.size.width * 0.46, y: layout.size.height * 0.78),
            CGPoint(x: layout.size.width * 0.62, y: layout.size.height * 0.78),
        ].map(layout.snapped)
        for point in points {
            drawDesk(at: point, context: &context)
        }
        drawConferenceTable(context: &context)
    }

    private func drawDesk(at point: CGPoint, context: inout GraphicsContext) {
        let top = CGRect(x: point.x - 42, y: point.y - 16, width: 84, height: 26)
        context.fill(Path(top), with: .color(Color(red: 0.30, green: 0.18, blue: 0.10)))
        context.fill(Path(CGRect(x: top.minX + 10, y: top.minY - 9, width: 28, height: 14)), with: .color(ShellPalette.panelRaised))
        context.fill(Path(CGRect(x: top.minX + 56, y: top.minY + 7, width: 8, height: 8)), with: .color(ShellPalette.accentWarm))
        context.fill(Path(CGRect(x: top.minX + 8, y: top.maxY, width: 6, height: 16)), with: .color(Color.black.opacity(0.38)))
        context.fill(Path(CGRect(x: top.maxX - 14, y: top.maxY, width: 6, height: 16)), with: .color(Color.black.opacity(0.38)))
    }

    private func drawConferenceTable(context: inout GraphicsContext) {
        let point = CGPoint(x: layout.size.width * 0.30, y: layout.size.height * 0.40)
        let table = CGRect(x: point.x - 62, y: point.y - 18, width: 124, height: 36)
        context.fill(Path(roundedRect: table, cornerRadius: 4), with: .color(Color(red: 0.28, green: 0.15, blue: 0.09)))
        context.stroke(Path(roundedRect: table, cornerRadius: 4), with: .color(ShellPalette.warning.opacity(0.34)), lineWidth: 1)
        for index in 0..<6 {
            let x = table.minX + 14 + CGFloat(index) * 20
            context.fill(Path(CGRect(x: x, y: table.minY - 12, width: 14, height: 8)), with: .color(ShellPalette.panelRaised))
            context.fill(Path(CGRect(x: x, y: table.maxY + 4, width: 14, height: 8)), with: .color(ShellPalette.panelRaised))
        }
    }

    private func drawReviewDesk(context: inout GraphicsContext) {
        let point = layout.zonePoint(.reviewDesk)
        let desk = CGRect(x: point.x - 58, y: point.y - 20, width: 116, height: 40)
        context.fill(Path(desk), with: .color(Color(red: 0.26, green: 0.21, blue: 0.12)))
        context.stroke(Path(desk), with: .color(ShellPalette.warning.opacity(0.65)), lineWidth: 2)
        for index in 0..<4 {
            context.fill(
                Path(CGRect(x: desk.minX + 14 + CGFloat(index) * 23, y: desk.minY + 10, width: 16, height: 20)),
                with: .color(index.isMultiple(of: 2) ? ShellPalette.success.opacity(0.64) : ShellPalette.warning.opacity(0.72))
            )
        }
    }

    private func drawBlockerCorner(context: inout GraphicsContext) {
        let point = layout.zonePoint(.blockerZone)
        let rect = CGRect(x: point.x - 52, y: point.y - 26, width: 104, height: 52)
        context.fill(Path(rect), with: .color(ShellPalette.danger.opacity(0.18)))
        context.stroke(Path(rect), with: .color(ShellPalette.danger.opacity(0.62)), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        context.fill(Path(CGRect(x: rect.minX + 12, y: rect.minY + 12, width: 18, height: 18)), with: .color(ShellPalette.danger.opacity(0.72)))
    }

    private func drawMergeLane(context: inout GraphicsContext) {
        let point = layout.zonePoint(.mergeLane)
        let rect = CGRect(x: point.x - 62, y: point.y - 20, width: 124, height: 40)
        context.fill(Path(rect), with: .color(ShellPalette.success.opacity(0.14)))
        for index in 0..<5 {
            context.fill(Path(CGRect(x: rect.minX + 10 + CGFloat(index) * 22, y: rect.midY - 5, width: 14, height: 10)), with: .color(ShellPalette.success.opacity(0.68)))
        }
    }

    private func drawPlants(context: inout GraphicsContext) {
        let points = [
            CGPoint(x: layout.size.width * 0.08, y: layout.size.height * 0.30),
            CGPoint(x: layout.size.width * 0.92, y: layout.size.height * 0.88),
        ].map(layout.snapped)
        for point in points {
            context.fill(Path(CGRect(x: point.x - 7, y: point.y + 6, width: 14, height: 14)), with: .color(Color(red: 0.46, green: 0.27, blue: 0.12)))
            context.fill(Path(CGRect(x: point.x - 14, y: point.y - 10, width: 10, height: 18)), with: .color(ShellPalette.success.opacity(0.78)))
            context.fill(Path(CGRect(x: point.x - 2, y: point.y - 18, width: 12, height: 26)), with: .color(ShellPalette.success.opacity(0.86)))
            context.fill(Path(CGRect(x: point.x + 9, y: point.y - 8, width: 8, height: 16)), with: .color(ShellPalette.success.opacity(0.72)))
        }
    }

    private func drawInbox(context: inout GraphicsContext) {
        let rect = CGRect(x: layout.size.width * 0.50 - 58, y: layout.size.height - 58, width: 116, height: 38)
        context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(ShellPalette.panelRaised.opacity(0.72)))
        context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(ShellPalette.accentWarm.opacity(0.34)), lineWidth: 1)
        context.draw(
            Text("\(language("INBOX", "받은 요청")) \(inboxCount)")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(ShellPalette.text),
            at: CGPoint(x: rect.midX, y: rect.midY),
            anchor: .center
        )
    }

    private func drawLabels(context: inout GraphicsContext) {
        let labels: [(String, MeetingRoomOfficeZone, Color)] = [
            (language("PLANNING", "기획"), .planningBoard, ShellPalette.accentWarm),
            (language("ACTIVITY", "활동"), .activityWall, ShellPalette.accent),
            (language("REVIEW", "리뷰"), .reviewDesk, ShellPalette.warning),
            (language("BLOCKED", "차단"), .blockerZone, ShellPalette.danger),
            (language("MERGE", "머지"), .mergeLane, ShellPalette.success),
        ]
        for (text, zone, tint) in labels {
            let point = layout.zonePoint(zone)
            context.draw(
                Text(text)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(tint),
                at: CGPoint(x: point.x, y: point.y - 44),
                anchor: .center
            )
        }
        context.draw(
            Text("\(projection.activeIssueCount) \(language("active", "활성")) · \(projection.blockedIssueCount) \(language("blocked", "차단"))")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(ShellPalette.muted),
            at: CGPoint(x: layout.size.width * 0.50, y: 22),
            anchor: .center
        )
    }
}

private struct PixelOfficeInteractionRouteView: View {
    let interaction: MeetingRoomSceneInteraction

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            path.move(to: interaction.fromPoint)
            let mid = CGPoint(
                x: (interaction.fromPoint.x + interaction.toPoint.x) / 2,
                y: min(interaction.fromPoint.y, interaction.toPoint.y) - 24
            )
            path.addQuadCurve(to: interaction.toPoint, control: mid)
            context.stroke(
                path,
                with: .color(tint.opacity(interaction.isFresh ? 0.64 : 0.24)),
                style: StrokeStyle(lineWidth: interaction.isFresh ? 2 : 1, lineCap: .round, dash: interaction.isFresh ? [7, 4] : [3, 5])
            )
            if interaction.isFresh {
                context.fill(Path(ellipseIn: CGRect(x: interaction.toPoint.x - 4, y: interaction.toPoint.y - 4, width: 8, height: 8)), with: .color(tint.opacity(0.8)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var tint: Color {
        switch interaction.event.kind {
        case .ceoApprovalRequested, .approvalGranted, .costPaused:
            return ShellPalette.warning
        case .qaReviewRequested, .changesRequested:
            return ShellPalette.accentWarm
        case .blockedEscalation:
            return ShellPalette.danger
        case .mergeCompleted:
            return ShellPalette.success
        case .issueAssigned, .handoff, .meeting, .workStarted:
            return ShellPalette.accent
        }
    }
}

private struct PixelOfficeKeyframeView: View {
    let keyframe: MeetingRoomSceneKeyframe
    let language: AppLanguage
    let time: TimeInterval
    let animate: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(tint.opacity(0.20))
                    .frame(width: 72, height: 18)
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .black))
                    Text(label)
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(ShellPalette.text)
            }
        }
        .buttonStyle(.plain)
        .position(keyframe.point(at: time, animate: animate && keyframe.usesScheduler))
        .accessibilityLabel("\(label): \(keyframe.title)")
    }

    private var label: String {
        switch keyframe.kind {
        case .issueCreated:
            return language("CARD", "카드")
        case .issueAssigned:
            return language("ASSIGN", "배정")
        case .agentTyping:
            return language("TYPE", "타이핑")
        case .a2aMessage:
            return language("MSG", "메시지")
        case .reviewRequested:
            return language("REVIEW", "리뷰")
        case .mergeCompleted:
            return language("MERGE", "머지")
        case .blockedJump:
            return language("BLOCK", "차단")
        case .costPaused:
            return language("COST", "비용")
        }
    }

    private var icon: String {
        switch keyframe.kind {
        case .issueCreated:
            return "doc.badge.plus"
        case .issueAssigned:
            return "arrow.right.to.line.compact"
        case .agentTyping:
            return "keyboard.fill"
        case .a2aMessage:
            return "envelope.fill"
        case .reviewRequested:
            return "checklist"
        case .mergeCompleted:
            return "arrow.triangle.merge"
        case .blockedJump:
            return "exclamationmark.triangle.fill"
        case .costPaused:
            return "pause.circle.fill"
        }
    }

    private var tint: Color {
        switch keyframe.kind {
        case .issueCreated, .issueAssigned, .a2aMessage:
            return ShellPalette.accentWarm
        case .agentTyping, .mergeCompleted:
            return ShellPalette.success
        case .reviewRequested, .costPaused:
            return ShellPalette.warning
        case .blockedJump:
            return ShellPalette.danger
        }
    }
}

private struct PixelIssueCardView: View {
    let card: MeetingRoomSceneIssueCard
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(statusLabel)
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundStyle(tint)
                Text(roomLine(card.title, limit: 16))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(ShellPalette.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(width: 90, alignment: .leading)
            .background(ShellPalette.panelRaised.opacity(0.88))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(tint.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(statusLabel): \(card.title)")
    }

    private var statusLabel: String {
        let status = card.status.uppercased()
        if status.contains("REVIEW") {
            return language("REVIEW", "리뷰")
        }
        if status.contains("PROGRESS") {
            return language("RUN", "작업")
        }
        if status.contains("BLOCK") || status.contains("FAIL") {
            return language("BLOCK", "차단")
        }
        if status == "DONE" || status == "MERGED" {
            return language("DONE", "완료")
        }
        return language("PLAN", "계획")
    }

    private var tint: Color {
        switch card.zone {
        case .planningBoard:
            return ShellPalette.accentWarm
        case .agentDesk, .activityWall:
            return ShellPalette.accent
        case .reviewDesk, .costPanel:
            return ShellPalette.warning
        case .blockerZone:
            return ShellPalette.danger
        case .mergeLane:
            return ShellPalette.success
        }
    }
}

private struct PixelAgentSprite: View {
    let sceneAgent: MeetingRoomSceneAgent
    let language: AppLanguage
    let phase: TimeInterval
    let animate: Bool
    let action: () -> Void

    private var agent: MeetingRoomProjectionAgent { sceneAgent.projection }
    private var block: CGFloat { sceneAgent.isSimplified ? 3 : 4 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if showsBubble {
                    Text(roomLine(bubbleText, limit: sceneAgent.isSimplified ? 12 : 18))
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundStyle(ShellPalette.text)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(ShellPalette.panelRaised.opacity(0.94))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(stateTint.opacity(0.36), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                } else {
                    Color.clear.frame(height: 14)
                }

                ZStack(alignment: .topTrailing) {
                    bodyPixels
                    stateBadge
                        .offset(x: 8, y: -4)
                }

                VStack(spacing: 1) {
                    Text(shortRole)
                        .font(.system(size: sceneAgent.isSimplified ? 8 : 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(ShellPalette.text)
                        .lineLimit(1)
                    Text(shortStatus)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(ShellPalette.muted)
                        .lineLimit(1)
                }
                .frame(width: sceneAgent.isSimplified ? 54 : 70)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(agent.role), \(agent.status), \(agent.actionLine)")
    }

    private var bodyPixels: some View {
        let step = animate ? keyframeStep : 0
        let blink = animate && Int(phase * 2 + Double(abs(agent.id.hashValue % 5))).isMultiple(of: 9)
        let typing = sceneAgent.action == .typing

        return ZStack(alignment: .bottom) {
            if sceneAgent.action == .sitting || sceneAgent.action == .typing {
                pixelDesk
                    .offset(y: block * 10)
            }

            VStack(spacing: 0) {
                head(blink: blink)
                torso(step: step)
                legs(step: step)
            }
            .offset(y: animate && sceneAgent.action == .walking ? abs(step) * -block : 0)

            if typing {
                keyboard
                    .offset(y: block * 10)
            }
        }
        .frame(width: block * 16, height: block * 19)
    }

    private func head(blink: Bool) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(skinTint)
                .frame(width: block * 7, height: block * 6)
                .offset(y: block * 2)

            Rectangle()
                .fill(hairTint)
                .frame(width: block * 8, height: block * 2)
            HStack(spacing: block * 4) {
                Rectangle()
                    .fill(hairTint)
                    .frame(width: block, height: block * 3)
                Rectangle()
                    .fill(hairTint)
                    .frame(width: block, height: block * 3)
            }
            .offset(y: block * 2)

            HStack(spacing: block * 2) {
                eye(blink: blink, left: true)
                eye(blink: blink, left: false)
            }
            .offset(y: block * 4)

            mouth
                .offset(y: block * 6)

            headwear
        }
        .frame(width: block * 10, height: block * 9)
    }

    private func torso(step: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(outfitTint)
                .frame(width: block * 7, height: block * 6)
            Rectangle()
                .fill(stateTint.opacity(0.75))
                .frame(width: block * 2, height: block * 2)
                .offset(y: block * -1)
            HStack(spacing: block * 7) {
                Rectangle()
                    .fill(skinTint)
                    .frame(width: block, height: block * 5)
                    .offset(y: sceneAgent.action == .typing ? block * 2 : step * block)
                Rectangle()
                    .fill(skinTint)
                    .frame(width: block, height: block * 5)
                    .offset(y: sceneAgent.action == .typing ? block * 2 : -step * block)
            }
        }
        .frame(width: block * 11, height: block * 6)
    }

    private func legs(step: CGFloat) -> some View {
        HStack(spacing: block * 2) {
            Rectangle()
                .fill(ShellPalette.panelDeeper)
                .frame(width: block * 2, height: block * 4)
                .offset(y: sceneAgent.action == .walking ? max(0, step) * block : 0)
            Rectangle()
                .fill(ShellPalette.panelDeeper)
                .frame(width: block * 2, height: block * 4)
                .offset(y: sceneAgent.action == .walking ? max(0, -step) * block : 0)
        }
        .frame(height: block * 4)
    }

    private func eye(blink: Bool, left: Bool) -> some View {
        Group {
            if blink {
                Rectangle().frame(width: block, height: 1)
            } else {
                switch agent.expression {
                case .focused:
                    Rectangle().frame(width: block, height: block * 2)
                case .talking:
                    Rectangle().frame(width: block * 2, height: block)
                case .happy:
                    Rectangle()
                        .frame(width: block * 2, height: 1)
                        .rotationEffect(.degrees(left ? 15 : -15))
                case .confused:
                    Rectangle().frame(width: left ? block : block * 2, height: block)
                case .sad:
                    Rectangle()
                        .frame(width: block * 2, height: 1)
                        .rotationEffect(.degrees(left ? -12 : 12))
                case .warning:
                    Rectangle().frame(width: block * 2, height: block * 2)
                case .idle:
                    Rectangle().frame(width: block, height: block)
                }
            }
        }
        .foregroundStyle(ShellPalette.text)
    }

    @ViewBuilder
    private var mouth: some View {
        switch agent.expression {
        case .happy:
            Rectangle().fill(stateTint).frame(width: block * 3, height: block)
        case .talking:
            Rectangle().fill(stateTint).frame(width: block * 2, height: block * 2)
        case .confused, .warning:
            Rectangle().fill(stateTint).frame(width: block * 2, height: block)
        case .sad:
            Rectangle().fill(stateTint.opacity(0.7)).frame(width: block * 3, height: 1)
        case .focused:
            Rectangle().fill(stateTint).frame(width: block * 3, height: block)
        case .idle:
            Rectangle().fill(stateTint.opacity(0.75)).frame(width: block * 2, height: 1)
        }
    }

    @ViewBuilder
    private var headwear: some View {
        if lowerRole.contains("ceo") || lowerRole.contains("lead") {
            HStack(spacing: 0) {
                PixelTriangle()
                    .fill(ShellPalette.warning)
                    .frame(width: block * 2, height: block * 2)
                PixelTriangle()
                    .fill(ShellPalette.warning)
                    .frame(width: block * 3, height: block * 3)
                PixelTriangle()
                    .fill(ShellPalette.warning)
                    .frame(width: block * 2, height: block * 2)
            }
            .offset(y: -block)
        } else if lowerRole.contains("builder") || lowerRole.contains("engineer") || lowerRole.contains("backend") {
            Rectangle()
                .fill(ShellPalette.panelRaised)
                .frame(width: block * 6, height: block)
                .offset(y: block)
        } else if lowerRole.contains("ux") || lowerRole.contains("design") || lowerRole.contains("ui") || lowerRole.contains("product") {
            Rectangle()
                .fill(ShellPalette.accentWarm)
                .frame(width: block * 5, height: block)
                .rotationEffect(.degrees(-8))
                .offset(y: block)
        } else if lowerRole.contains("qa") || lowerRole.contains("review") {
            Rectangle()
                .fill(ShellPalette.warning)
                .frame(width: block * 4, height: block)
                .offset(y: block)
        }
    }

    private var keyboard: some View {
        HStack(spacing: 1) {
            ForEach(0..<6, id: \.self) { index in
                Rectangle()
                    .fill(index.isMultiple(of: 2) ? stateTint : ShellPalette.lineStrong)
                    .frame(width: block, height: block)
            }
        }
        .padding(3)
        .background(ShellPalette.panelDeeper)
    }

    private var pixelDesk: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(red: 0.30, green: 0.18, blue: 0.10))
                .frame(width: block * 14, height: block * 4)
            HStack(spacing: block * 9) {
                Rectangle().fill(Color.black.opacity(0.42)).frame(width: block, height: block * 3)
                Rectangle().fill(Color.black.opacity(0.42)).frame(width: block, height: block * 3)
            }
        }
        .accessibilityHidden(true)
    }

    private var stateBadge: some View {
        Image(systemName: stateIcon)
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(ShellPalette.text)
            .padding(3)
            .background(stateTint.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }

    private var showsBubble: Bool {
        if sceneAgent.speechText != nil {
            return true
        }
        switch sceneAgent.action {
        case .blocked, .reviewing, .talking, .listening, .approving, .celebrating:
            return true
        case .typing, .walking, .sitting:
            return agent.visualState == .failed || agent.visualState == .costBlocked
        }
    }

    private var bubbleText: String {
        guard let speech = sceneAgent.speechText else {
            return agent.actionLine
        }
        switch speech {
        case "Approval requested":
            return language("Approval requested", "승인 요청합니다")
        case "Reviewing approval":
            return language("Reviewing approval", "승인 검토 중")
        case "Please review":
            return language("Please review", "검토 부탁합니다")
        case "Reviewing now":
            return language("Reviewing now", "검토합니다")
        case "Changes requested":
            return language("Changes requested", "수정 요청합니다")
        case "Please revise":
            return language("Please revise", "수정해 주세요")
        case "Need help":
            return language("Need help", "도움이 필요합니다")
        case "Checking blocker":
            return language("Checking blocker", "막힘 확인 중")
        case "Handoff update":
            return language("Handoff update", "인수인계합니다")
        case "Received":
            return language("Received", "확인했습니다")
        case "Feedback sync":
            return language("Feedback sync", "피드백 공유")
        case "Plan sync":
            return language("Plan sync", "계획 회의")
        case "Syncing":
            return language("Syncing", "회의 중")
        case "Taking this":
            return language("Taking this", "맡겠습니다")
        case "Assigned":
            return language("Assigned", "배정됨")
        case "Working on it":
            return language("Working on it", "작업 중")
        case "Approved":
            return language("Approved", "승인했습니다")
        case "Merged":
            return language("Merged", "머지 완료")
        case "Cost pause":
            return language("Cost pause", "비용 일시정지")
        case "Paused":
            return language("Paused", "일시정지")
        default:
            return speech
        }
    }

    private var keyframeStep: CGFloat {
        switch sceneAgent.action {
        case .walking:
            guard sceneAgent.movementDuration > 0 else { return 0 }
            let raw = CGFloat((phase - sceneAgent.movementStartedAt) / sceneAgent.movementDuration)
            let progress = min(1, max(0, raw))
            return progress < 0.5 ? progress * 2 : (1 - progress) * -2
        case .typing:
            return Int(phase * 6).isMultiple(of: 2) ? 1 : -1
        case .talking, .listening, .approving, .reviewing:
            return Int(phase * 3).isMultiple(of: 2) ? 0.5 : 0
        case .sitting, .blocked, .celebrating:
            return 0
        }
    }

    private var shortRole: String {
        let trimmed = agent.role.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return language("Agent", "에이전트")
        }
        if lowerRole.contains("product") {
            return language("Planner", "기획자")
        }
        if lowerRole.contains("ux") || lowerRole.contains("ui") || lowerRole.contains("design") {
            return "UX"
        }
        if lowerRole.contains("backend") {
            return "Backend"
        }
        if lowerRole.contains("builder") || lowerRole.contains("engineer") {
            return "Builder"
        }
        return String(trimmed.prefix(12))
    }

    private var shortStatus: String {
        switch agent.visualState {
        case .idle:
            return language("IDLE", "대기")
        case .running:
            return sceneAgent.action == .typing ? language("TYPE", "타이핑") : language("RUN", "작업")
        case .review:
            return sceneAgent.action == .approving ? language("APPROVE", "승인") : language("REVIEW", "리뷰")
        case .blocked:
            return language("BLOCK", "차단")
        case .failed:
            return language("FAIL", "실패")
        case .done:
            return language("DONE", "완료")
        case .costBlocked:
            return language("COST", "비용")
        }
    }

    private var lowerRole: String {
        agent.role.lowercased()
    }

    private var stateTint: Color {
        switch agent.visualState {
        case .idle:
            return ShellPalette.faint
        case .running:
            return ShellPalette.success
        case .review:
            return ShellPalette.warning
        case .blocked, .failed:
            return ShellPalette.danger
        case .done:
            return ShellPalette.success
        case .costBlocked:
            return ShellPalette.warning
        }
    }

    private var skinTint: Color {
        if lowerRole.contains("ceo") || lowerRole.contains("lead") {
            return Color(red: 0.93, green: 0.70, blue: 0.48)
        }
        if lowerRole.contains("qa") || lowerRole.contains("review") {
            return Color(red: 0.82, green: 0.65, blue: 0.48)
        }
        if lowerRole.contains("product") || lowerRole.contains("ux") {
            return Color(red: 0.95, green: 0.74, blue: 0.55)
        }
        return Color(red: 0.88, green: 0.67, blue: 0.50)
    }

    private var hairTint: Color {
        if lowerRole.contains("ceo") || lowerRole.contains("lead") {
            return Color(red: 0.38, green: 0.24, blue: 0.13)
        }
        if lowerRole.contains("ux") || lowerRole.contains("design") || lowerRole.contains("ui") {
            return Color(red: 0.72, green: 0.49, blue: 0.26)
        }
        if lowerRole.contains("product") {
            return Color(red: 0.18, green: 0.16, blue: 0.20)
        }
        return Color(red: 0.25, green: 0.17, blue: 0.12)
    }

    private var outfitTint: Color {
        if lowerRole.contains("ceo") || lowerRole.contains("lead") {
            return Color(red: 0.34, green: 0.18, blue: 0.22)
        }
        if lowerRole.contains("product") {
            return Color(red: 0.22, green: 0.38, blue: 0.66)
        }
        if lowerRole.contains("builder") || lowerRole.contains("backend") || lowerRole.contains("engineer") {
            return Color(red: 0.18, green: 0.48, blue: 0.48)
        }
        if lowerRole.contains("ux") || lowerRole.contains("design") || lowerRole.contains("ui") {
            return Color(red: 0.38, green: 0.62, blue: 0.38)
        }
        if lowerRole.contains("qa") || lowerRole.contains("review") {
            return Color(red: 0.35, green: 0.53, blue: 0.78)
        }
        return Color(red: 0.40, green: 0.52, blue: 0.38)
    }

    private var stateIcon: String {
        switch agent.visualState {
        case .idle:
            return "chair"
        case .running:
            return "keyboard.fill"
        case .review:
            return "checklist"
        case .blocked:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .done:
            return "checkmark.seal.fill"
        case .costBlocked:
            return "pause.circle.fill"
        }
    }
}

private struct PixelTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct MeetingRoomZoneButton {
    let zone: MeetingRoomOfficeZone
    let title: String
    let count: Int
    let point: CGPoint
}

private struct MeetingRoomProjectionAgentSheet: View {
    let agent: MeetingRoomProjectionAgent
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(agent.role)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(ShellPalette.text)
            HStack(spacing: 8) {
                ShellTag(text: agent.visualState.rawValue.uppercased(), tint: ShellPalette.accent)
                ShellTag(text: agent.zone.rawValue, tint: ShellPalette.warning)
                if let pullRequestState = agent.pullRequestState {
                    ShellTag(text: "PR \(pullRequestState)", tint: ShellPalette.success)
                }
            }
            detail(language("Current work", "현재 작업"), agent.currentIssueTitle ?? agent.detailLine)
            detail(language("Runtime state", "런타임 상태"), agent.status)
            detail(language("Office action", "오피스 동작"), agent.actionLine)
            detail(language("Log summary", "로그 요약"), agent.detailLine)
            ProgressView(value: agent.progress)
                .tint(ShellPalette.success)
        }
        .padding(22)
        .frame(width: 420, alignment: .topLeading)
        .background(ShellPalette.panel)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(ShellPalette.faint)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ShellPalette.text)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(ShellPalette.panelAlt)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct MeetingRoomProjectionIssueSheet: View {
    let issue: MeetingRoomIssueSummary
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(issue.title)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(ShellPalette.text)
            HStack(spacing: 8) {
                ShellTag(text: issue.status, tint: issue.status.uppercased().contains("BLOCK") ? ShellPalette.danger : ShellPalette.accent)
                ShellTag(text: issue.kind, tint: ShellPalette.accentWarm)
                if let pullRequestState = issue.pullRequestState {
                    ShellTag(text: "PR \(pullRequestState)", tint: ShellPalette.success)
                }
            }
            detail(language("Issue id", "이슈 ID"), issue.id)
            detail(language("Assignee", "담당"), issue.assigneeProfileId ?? "-")
            if let transitionReason = issue.transitionReason {
                detail(language("Reason", "이유"), transitionReason)
            }
            if let pullRequest = pullRequestSummary {
                detail(language("Pull request", "PR"), pullRequest)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 480, height: 340)
        .background(ShellPalette.panel)
    }

    private var pullRequestSummary: String? {
        guard issue.pullRequestNumber != nil || issue.pullRequestUrl != nil || issue.pullRequestState != nil else {
            return nil
        }
        return [
            issue.pullRequestNumber.map { "#\($0)" },
            issue.pullRequestState,
            issue.pullRequestUrl,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(ShellPalette.faint)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ShellPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(ShellPalette.panelAlt)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct MeetingRoomProjectionFlowSheet: View {
    let flow: MeetingRoomFlowItem
    let issue: MeetingRoomIssueSummary?
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(issue?.title ?? flow.title)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(ShellPalette.text)
            HStack(spacing: 8) {
                ShellTag(text: flow.kind.rawValue, tint: ShellPalette.accentWarm)
                if let issue {
                    ShellTag(text: issue.status, tint: issue.status.uppercased().contains("BLOCK") ? ShellPalette.danger : ShellPalette.accent)
                }
                if let pullRequestState = issue?.pullRequestState {
                    ShellTag(text: "PR \(pullRequestState)", tint: ShellPalette.success)
                }
            }
            detail(language("Issue", "이슈"), issueSummary)
            detail(language("Movement", "이동"), "\(flow.from.rawValue) -> \(flow.to.rawValue)")
            detail(language("Detail", "상세"), flow.detail)
            if let pullRequest = pullRequestSummary {
                detail(language("Pull request", "PR"), pullRequest)
            }
            ProgressView(value: flow.progress)
                .tint(ShellPalette.accentWarm)
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 500, height: 380)
        .background(ShellPalette.panel)
    }

    private var issueSummary: String {
        guard let issue else {
            return flow.issueId ?? "-"
        }
        return [
            issue.kind,
            issue.id,
            issue.assigneeProfileId.map { "assignee=\($0)" },
            issue.transitionReason.map { "reason=\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var pullRequestSummary: String? {
        guard let issue, issue.pullRequestNumber != nil || issue.pullRequestUrl != nil || issue.pullRequestState != nil else {
            return nil
        }
        return [
            issue.pullRequestNumber.map { "#\($0)" },
            issue.pullRequestState,
            issue.pullRequestUrl,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(ShellPalette.faint)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ShellPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(ShellPalette.panelAlt)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct MeetingRoomProjectionZoneSheet: View {
    let zone: MeetingRoomOfficeZone
    let projection: MeetingRoomProjection
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(ShellPalette.text)
            Text(summary)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ShellPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            if lines.isEmpty {
                Text(language("Nothing is pinned in this office zone yet.", "아직 이 오피스 구역에 표시할 항목이 없습니다."))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(ShellPalette.muted)
            } else {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShellPalette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(ShellPalette.panelAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 480, height: 360)
        .background(ShellPalette.panel)
    }

    private var title: String {
        switch zone {
        case .agentDesk:
            return language("Agent desks", "에이전트 자리")
        case .planningBoard:
            return language("Planning board", "기획 보드")
        case .reviewDesk:
            return language("Reviews", "리뷰")
        case .blockerZone:
            return language("Blocker zone", "차단 구역")
        case .costPanel:
            return language("Cost panel", "비용 패널")
        case .activityWall:
            return language("Activity", "활동")
        case .mergeLane:
            return language("Merge", "머지")
        }
    }

    private var summary: String {
        switch zone {
        case .costPanel:
            return language(
                "Today \(projection.todaySpentCents)c, month \(projection.monthSpentCents)c, paused \(projection.isCostBlocked).",
                "오늘 \(projection.todaySpentCents)c, 월 \(projection.monthSpentCents)c, 일시정지 \(projection.isCostBlocked)."
            )
        case .reviewDesk:
            return language("\(projection.reviewCount) review item(s) are waiting.", "\(projection.reviewCount)개 리뷰 항목이 대기 중입니다.")
        case .blockerZone:
            return language("\(projection.blockedIssueCount) blocked issue(s).", "\(projection.blockedIssueCount)개 이슈가 차단되었습니다.")
        default:
            return language("This zone is rendered from the latest app-server company snapshot.", "이 영역은 최신 app-server 회사 snapshot에서 렌더링됩니다.")
        }
    }

    private var lines: [String] {
        switch zone {
        case .costPanel:
            return [
                "runtime=\(projection.runtimeStatus)",
                "backend=\(projection.runtimeBackendHealth)",
                "costBlocked=\(projection.isCostBlocked)",
            ]
        case .reviewDesk:
            let reviews = projection.reviews.prefix(6).map { review in
                [
                    "issue=\(review.issueId)",
                    "status=\(review.status)",
                    review.pullRequestNumber.map { "PR #\($0)" },
                    review.pullRequestState,
                    review.checksSummary.map { "checks=\($0)" },
                    review.mergeability.map { "merge=\($0)" },
                ]
                .compactMap { $0 }
                .joined(separator: " · ")
            }
            if !reviews.isEmpty {
                return reviews
            }
            return Array(projection.flows.filter { $0.to == .reviewDesk }.map { $0.title }.prefix(6))
        case .blockerZone:
            return Array(
                projection.issues
                    .filter { issue in
                        let status = issue.status.uppercased()
                        return status.contains("BLOCK") || status.contains("FAIL")
                    }
                    .map { issue in
                        [issue.title, issue.status, issue.transitionReason]
                            .compactMap { $0 }
                            .joined(separator: " · ")
                    }
                    .prefix(6)
            )
        case .activityWall:
            return ["activityCount=\(projection.activityCount)", "prStates=\(projection.pullRequestStates.joined(separator: ", "))"]
        case .agentDesk:
            return Array(projection.agents.map { "\($0.role): \($0.status)" }.prefix(8))
        case .planningBoard:
            return Array(projection.issues.filter { $0.status.uppercased().contains("PLAN") }.map { $0.title }.prefix(8))
        case .mergeLane:
            return Array(projection.issues.filter { $0.status.uppercased() == "DONE" || $0.pullRequestState?.uppercased() == "MERGED" }.map { $0.title }.prefix(8))
        }
    }
}

private func roomLine(_ value: String, limit: Int) -> String {
    let trimmed = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count <= limit {
        return trimmed
    }
    return String(trimmed.prefix(max(1, limit - 1))) + "..."
}
