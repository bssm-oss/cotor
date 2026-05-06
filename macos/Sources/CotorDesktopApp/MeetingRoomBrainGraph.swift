import Foundation
import SwiftUI

struct MeetingRoomBrainGraph: Hashable {
    static let maxVisibleNodes = 96

    let sourcePath: String?
    let isFallback: Bool
    let totalNodeCount: Int
    let totalLinkCount: Int
    let nodes: [MeetingRoomBrainGraphNode]
    let links: [MeetingRoomBrainGraphLink]
    let hiddenNodeCount: Int

    var communityCount: Int {
        Set(nodes.map(\.community)).count
    }

    var isEmpty: Bool {
        nodes.isEmpty
    }

    static func empty(sourcePath: String? = nil) -> MeetingRoomBrainGraph {
        MeetingRoomBrainGraph(
            sourcePath: sourcePath,
            isFallback: false,
            totalNodeCount: 0,
            totalLinkCount: 0,
            nodes: [],
            links: [],
            hiddenNodeCount: 0
        )
    }

    static func load(rootPath: String?) throws -> MeetingRoomBrainGraph {
        let graphPath = graphFileURL(rootPath: rootPath)
        if FileManager.default.fileExists(atPath: graphPath.path) {
            let data = try Data(contentsOf: graphPath)
            return try decode(data: data, sourcePath: graphPath.path)
        }
        if let fallback = fallback(rootPath: rootPath) {
            return fallback
        }
        throw MeetingRoomBrainGraphLoadError.missingMap
    }

    static func decode(data: Data, sourcePath: String? = nil) throws -> MeetingRoomBrainGraph {
        let document = try JSONDecoder().decode(MeetingRoomBrainGraphDocument.self, from: data)
        return build(from: document, sourcePath: sourcePath)
    }

    static func graphFileURL(rootPath: String?) -> URL {
        if let rootPath, !rootPath.isEmpty {
            return URL(fileURLWithPath: rootPath).appendingPathComponent("graphify-out/graph.json")
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("graphify-out/graph.json")
    }

    static func fallback(rootPath: String?) -> MeetingRoomBrainGraph? {
        guard let rootPath, !rootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        let rootName = rootURL.lastPathComponent.isEmpty ? "Workspace" : rootURL.lastPathComponent
        var candidates: [MeetingRoomBrainGraphNode] = [
            MeetingRoomBrainGraphNode(
                id: "workspace-root",
                label: rootName,
                fileType: "folder",
                sourceFile: rootName,
                sourceLocation: "",
                community: 0,
                degree: 0
            )
        ]
        var links: [MeetingRoomBrainGraphLink] = []
        var totalCandidateCount = 1

        let topLevel = prioritizedRepositoryEntries(in: rootURL)
        totalCandidateCount += topLevel.count

        for (index, entry) in topLevel.prefix(24).enumerated() where candidates.count < maxVisibleNodes {
            let node = fallbackNode(for: entry, relativeTo: rootURL, community: index + 1)
            candidates.append(node)
            links.append(
                MeetingRoomBrainGraphLink(
                    id: "workspace-root->\(node.id)",
                    source: "workspace-root",
                    target: node.id,
                    relation: "contains",
                    weight: node.fileType == "folder" ? 1.2 : 0.9,
                    confidenceScore: 1
                )
            )

            if node.fileType == "folder" {
                let childEntries = prioritizedRepositoryEntries(in: entry)
                totalCandidateCount += childEntries.count
                for child in childEntries.prefix(5) where candidates.count < maxVisibleNodes {
                    let childNode = fallbackNode(for: child, relativeTo: rootURL, community: index + 1)
                    candidates.append(childNode)
                    links.append(
                        MeetingRoomBrainGraphLink(
                            id: "\(node.id)->\(childNode.id)",
                            source: node.id,
                            target: childNode.id,
                            relation: "contains",
                            weight: childNode.fileType == "folder" ? 1.0 : 0.7,
                            confidenceScore: 1
                        )
                    )
                }
            }
        }

        let degree = links.reduce(into: [String: Int]()) { counts, link in
            counts[link.source, default: 0] += 1
            counts[link.target, default: 0] += 1
        }
        let nodes = candidates.map { node in
            MeetingRoomBrainGraphNode(
                id: node.id,
                label: node.label,
                fileType: node.fileType,
                sourceFile: node.sourceFile,
                sourceLocation: node.sourceLocation,
                community: node.community,
                degree: degree[node.id, default: 0]
            )
        }

        return MeetingRoomBrainGraph(
            sourcePath: rootURL.path,
            isFallback: true,
            totalNodeCount: totalCandidateCount,
            totalLinkCount: links.count,
            nodes: nodes,
            links: links,
            hiddenNodeCount: max(0, totalCandidateCount - nodes.count)
        )
    }

    private static func build(from document: MeetingRoomBrainGraphDocument, sourcePath: String?) -> MeetingRoomBrainGraph {
        var degree: [String: Int] = [:]
        for link in document.links {
            degree[link.source, default: 0] += 1
            degree[link.target, default: 0] += 1
        }

        let visibleRecords = document.nodes
            .sorted { lhs, rhs in
                let lhsDegree = degree[lhs.id, default: 0]
                let rhsDegree = degree[rhs.id, default: 0]
                if lhsDegree != rhsDegree { return lhsDegree > rhsDegree }
                if lhs.community != rhs.community { return lhs.community < rhs.community }
                return lhs.label < rhs.label
            }
            .prefix(maxVisibleNodes)

        let visibleIds = Set(visibleRecords.map(\.id))
        let nodes = visibleRecords.map { record in
            MeetingRoomBrainGraphNode(
                id: record.id,
                label: record.label,
                fileType: record.fileType,
                sourceFile: record.sourceFile,
                sourceLocation: record.sourceLocation,
                community: record.community,
                degree: degree[record.id, default: 0]
            )
        }
        let links = document.links
            .filter { visibleIds.contains($0.source) && visibleIds.contains($0.target) }
            .map { record in
                MeetingRoomBrainGraphLink(
                    id: "\(record.source)->\(record.target)->\(record.relation)",
                    source: record.source,
                    target: record.target,
                    relation: record.relation,
                    weight: record.weight,
                    confidenceScore: record.confidenceScore
                )
            }

        return MeetingRoomBrainGraph(
            sourcePath: sourcePath,
            isFallback: false,
            totalNodeCount: document.nodes.count,
            totalLinkCount: document.links.count,
            nodes: nodes,
            links: links,
            hiddenNodeCount: max(0, document.nodes.count - nodes.count)
        )
    }

    private static func prioritizedRepositoryEntries(in directory: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []
        return entries
            .filter { !ignoredRepositoryEntry($0) }
            .sorted { lhs, rhs in
                let lhsScore = repositoryEntryScore(lhs)
                let rhsScore = repositoryEntryScore(rhs)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
    }

    private static func fallbackNode(for url: URL, relativeTo rootURL: URL, community: Int) -> MeetingRoomBrainGraphNode {
        let relativePath = relativePath(for: url, rootURL: rootURL)
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return MeetingRoomBrainGraphNode(
            id: "workspace-\(relativePath)",
            label: displayLabel(for: url, isDirectory: isDirectory),
            fileType: isDirectory ? "folder" : "file",
            sourceFile: relativePath,
            sourceLocation: "",
            community: community,
            degree: 0
        )
    }

    private static func ignoredRepositoryEntry(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let ignored = [
            ".git",
            ".cotor",
            ".omx",
            ".gradle",
            ".idea",
            ".swiftpm",
            "build",
            "DerivedData",
            "dist",
            "graphify-out",
            "node_modules",
            "out",
            "tmp"
        ]
        return ignored.contains(name)
    }

    private static func repositoryEntryScore(_ url: URL) -> Int {
        let name = url.lastPathComponent
        let lowercasedName = name.lowercased()
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if ["readme.md", "readme.ko.md", "agents.md", "package.swift", "build.gradle.kts", "settings.gradle.kts", "package.json", "pyproject.toml", "cargo.toml"].contains(lowercasedName) {
            return 100
        }
        if ["src", "macos", "docs", "tests", "test", "shell", "formula"].contains(lowercasedName) {
            return 90
        }
        if isDirectory { return 70 }
        if lowercasedName.hasSuffix(".md") { return 62 }
        if lowercasedName.hasSuffix(".swift") || lowercasedName.hasSuffix(".kt") || lowercasedName.hasSuffix(".kts") {
            return 58
        }
        return 40
    }

    private static func displayLabel(for url: URL, isDirectory: Bool) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        guard !name.isEmpty else {
            return isDirectory ? "Folder" : "File"
        }
        return name
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    private static func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else {
            return url.lastPathComponent
        }
        let start = path.index(path.startIndex, offsetBy: rootPath.count)
        return String(path[start...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private enum MeetingRoomBrainGraphLoadError: Error {
    case missingMap
}

struct MeetingRoomBrainGraphNode: Identifiable, Hashable {
    let id: String
    let label: String
    let fileType: String
    let sourceFile: String
    let sourceLocation: String
    let community: Int
    let degree: Int

    var displaySourceName: String {
        let trimmed = sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Workspace item" }
        return (trimmed as NSString).lastPathComponent
    }

    var displayLocationLine: String? {
        let trimmed = sourceLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.first?.uppercased() == "L" {
            let line = String(trimmed.dropFirst())
            if !line.isEmpty, line.allSatisfy(\.isNumber) {
                return line
            }
        }
        return trimmed
    }
}

struct MeetingRoomBrainGraphLink: Identifiable, Hashable {
    let id: String
    let source: String
    let target: String
    let relation: String
    let weight: Double
    let confidenceScore: Double
}

private struct MeetingRoomBrainGraphDocument: Decodable {
    let nodes: [MeetingRoomBrainGraphNodeRecord]
    let links: [MeetingRoomBrainGraphLinkRecord]
}

private struct MeetingRoomBrainGraphNodeRecord: Decodable {
    let id: String
    let label: String
    let fileType: String
    let sourceFile: String
    let sourceLocation: String
    let community: Int

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case fileType = "file_type"
        case sourceFile = "source_file"
        case sourceLocation = "source_location"
        case community
    }
}

private struct MeetingRoomBrainGraphLinkRecord: Decodable {
    let source: String
    let target: String
    let relation: String
    let weight: Double
    let confidenceScore: Double

    enum CodingKeys: String, CodingKey {
        case source
        case target
        case relation
        case weight
        case confidenceScore = "confidence_score"
    }
}

struct MeetingRoomBrainGraphPane: View {
    let rootPath: String?
    let language: AppLanguage
    let isCompact: Bool

    @State private var graph = MeetingRoomBrainGraph.empty()
    @State private var loadError: String?
    @State private var selectedNode: MeetingRoomBrainGraphNode?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let loadError {
                MeetingRoomBrainGraphEmptyState(
                    title: language("No map found", "지도가 없습니다"),
                    detail: loadError
                )
                .frame(height: isCompact ? 320 : 460)
            } else if graph.isEmpty {
                MeetingRoomBrainGraphEmptyState(
                    title: language("No map items yet", "아직 지도 항목이 없습니다"),
                    detail: language("Open a company folder after its repository map is prepared.", "저장소 지도가 준비된 회사 폴더를 열면 여기에 표시됩니다.")
                )
                .frame(height: isCompact ? 320 : 460)
            } else {
                GeometryReader { geometry in
                    graphStage(size: geometry.size)
                }
                .frame(height: isCompact ? 360 : 500)
            }
        }
        .task(id: rootPath ?? "") {
            loadGraph()
        }
        .sheet(item: $selectedNode) { node in
            MeetingRoomBrainGraphNodeSheet(node: node, language: language)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ShellTag(text: "\(language("Items", "항목")) \(graph.totalNodeCount)", tint: ShellPalette.accent)
                ShellTag(text: "\(language("Connections", "연결")) \(graph.totalLinkCount)", tint: ShellPalette.accentWarm)
                ShellTag(text: "\(language("Areas", "영역")) \(graph.communityCount)", tint: ShellPalette.warning)
                if graph.hiddenNodeCount > 0 {
                    ShellTag(text: "+\(graph.hiddenNodeCount)", tint: ShellPalette.panelRaised)
                }
                Spacer(minLength: 0)
                Text(graph.isFallback ? language("Folder Map", "폴더 지도") : language("Map", "지도"))
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(ShellPalette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func loadGraph() {
        do {
            graph = try MeetingRoomBrainGraph.load(rootPath: rootPath)
            loadError = nil
        } catch {
            graph = .empty(sourcePath: MeetingRoomBrainGraph.graphFileURL(rootPath: rootPath).path)
            loadError = language(
                "The repository map is not ready yet. Prepare the map when you need this view.",
                "저장소 지도가 아직 준비되지 않았습니다. 이 보기가 필요할 때 지도를 준비하세요."
            )
        }
    }

    private func graphStage(size: CGSize) -> some View {
        let positions = graphPositions(size: size)
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ShellPalette.panelDeeper)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(ShellPalette.line, lineWidth: 1)
                )

            Canvas { context, _ in
                for link in graph.links {
                    guard let source = positions[link.source], let target = positions[link.target] else { continue }
                    var path = Path()
                    path.move(to: source)
                    path.addLine(to: target)
                    context.stroke(path, with: .color(ShellPalette.lineStrong.opacity(edgeOpacity(link))), lineWidth: edgeWidth(link))
                }
            }
            .accessibilityHidden(true)

            ForEach(graph.nodes) { node in
                mapNodeButton(node)
                    .position(positions[node.id] ?? CGPoint(x: size.width / 2, y: size.height / 2))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(graph.isFallback ? language("Workspace Map", "작업공간 지도") : language("Repository Map", "저장소 지도"))
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(ShellPalette.accentWarm)
                Text(
                    graph.isFallback
                        ? language(
                            "Key project files are available while the full map is prepared.",
                            "전체 지도를 준비하는 동안 주요 프로젝트 파일을 표시합니다."
                        )
                        : language(
                            "Key files and concepts from the selected workspace.",
                            "선택한 작업공간의 주요 파일과 개념입니다."
                        )
                )
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ShellPalette.muted)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: min(size.width * 0.46, 360), alignment: .leading)
            .background(ShellPalette.panel.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(ShellPalette.accentWarm.opacity(0.30), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .position(x: size.width * 0.26, y: size.height * 0.10)
        }
    }

    private func graphPositions(size: CGSize) -> [String: CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let communities = Array(Set(graph.nodes.map(\.community))).sorted()
        let communityIndex = Dictionary(uniqueKeysWithValues: communities.enumerated().map { ($0.element, $0.offset) })
        let communityCount = max(communities.count, 1)
        let groupedNodes = Dictionary(grouping: graph.nodes, by: \.community)
        let ringRadius = min(size.width, size.height) * 0.30
        var positions: [String: CGPoint] = [:]

        for community in communities {
            let index = communityIndex[community] ?? 0
            let clusterAngle = (Double(index) / Double(communityCount)) * Double.pi * 2
            let clusterCenter: CGPoint
            if communityCount == 1 || (graph.isFallback && community == 0) {
                clusterCenter = center
            } else {
                clusterCenter = CGPoint(
                    x: center.x + cos(clusterAngle) * ringRadius,
                    y: center.y + sin(clusterAngle) * ringRadius * 0.76
                )
            }
            let nodes = (groupedNodes[community] ?? []).sorted { lhs, rhs in
                if lhs.degree != rhs.degree { return lhs.degree > rhs.degree }
                return lhs.label < rhs.label
            }
            let clusterRadius = max(18, min(72, CGFloat(nodes.count) * 4.4))

            for (nodeIndex, node) in nodes.enumerated() {
                let nodeAngle = (Double(nodeIndex) / Double(max(nodes.count, 1))) * Double.pi * 2 + Double(deterministicHash(node.id) % 100) / 100.0
                let localRadius = nodes.count == 1 ? 0 : clusterRadius * (0.45 + CGFloat((nodeIndex % 4)) * 0.18)
                positions[node.id] = CGPoint(
                    x: clamp(clusterCenter.x + cos(nodeAngle) * localRadius, min: 24, max: size.width - 24),
                    y: clamp(clusterCenter.y + sin(nodeAngle) * localRadius, min: 24, max: size.height - 24)
                )
            }
        }

        return positions
    }

    private func mapNodeButton(_ node: MeetingRoomBrainGraphNode) -> some View {
        Button {
            selectedNode = node
        } label: {
            ZStack {
                Circle()
                    .fill(nodeTint(node).opacity(0.88))
                    .frame(width: nodeDiameter(node), height: nodeDiameter(node))
                    .overlay(Circle().stroke(Color.white.opacity(0.26), lineWidth: 1))
                if node.degree >= 8 {
                    Text(String(node.label.prefix(1)).uppercased())
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.92))
                }
            }
        }
        .buttonStyle(.plain)
        .help("\(node.label) · \(node.displaySourceName)")
        .accessibilityLabel("\(node.label), \(node.degree) connections")
    }

    private func nodeDiameter(_ node: MeetingRoomBrainGraphNode) -> CGFloat {
        min(26, max(8, 8 + CGFloat(node.degree) * 0.9))
    }

    private func nodeTint(_ node: MeetingRoomBrainGraphNode) -> Color {
        let palette = [ShellPalette.accent, ShellPalette.accentWarm, ShellPalette.warning, ShellPalette.success, ShellPalette.danger]
        return palette[abs(node.community) % palette.count]
    }

    private func edgeOpacity(_ link: MeetingRoomBrainGraphLink) -> Double {
        min(0.34, max(0.10, 0.10 + link.confidenceScore * 0.18))
    }

    private func edgeWidth(_ link: MeetingRoomBrainGraphLink) -> CGFloat {
        min(2.4, max(0.7, CGFloat(link.weight)))
    }

    private func deterministicHash(_ value: String) -> Int {
        value.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}

private struct MeetingRoomBrainGraphEmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(ShellPalette.muted)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ShellPalette.text)
            Text(detail)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ShellPalette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(18)
        .background(ShellPalette.panelDeeper)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ShellPalette.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MeetingRoomBrainGraphNodeSheet: View {
    let node: MeetingRoomBrainGraphNode
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ShellSectionHeader(
                eyebrow: language("Map Item", "지도 항목"),
                title: node.label,
                subtitle: node.displaySourceName
            )

            VStack(alignment: .leading, spacing: 8) {
                detailRow(language("Type", "유형"), node.fileType)
                detailRow(language("File", "파일"), node.displaySourceName)
                if let line = node.displayLocationLine {
                    detailRow(language("Line", "줄"), line)
                }
                detailRow(language("Area", "영역"), "\(node.community)")
                detailRow(language("Connections", "연결"), "\(node.degree)")
            }
        }
        .padding(20)
        .frame(width: 420, alignment: .topLeading)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(ShellPalette.faint)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ShellPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
