import Foundation
import Testing
@testable import CotorDesktopApp

struct MeetingRoomBrainGraphTests {
    @Test
    func decodesGraphifyGraphAndKeepsMostConnectedNodes() throws {
        let graph = try MeetingRoomBrainGraph.decode(data: sampleGraphData())

        #expect(graph.totalNodeCount == 3)
        #expect(graph.totalLinkCount == 2)
        #expect(graph.nodes.map(\.id) == ["controller", "view", "service"])
        #expect(graph.links.count == 2)
        #expect(graph.nodes.first?.degree == 2)
        #expect(graph.communityCount == 2)
    }

    @Test
    func nodeDisplayFieldsHideRawRepositoryPathDetails() throws {
        let graph = try MeetingRoomBrainGraph.decode(data: sampleGraphData())
        let controller = try #require(graph.nodes.first { $0.id == "controller" })

        #expect(controller.displaySourceName == "AppServer.kt")
        #expect(controller.displayLocationLine == "5413")
    }

    @Test
    func graphFileURLUsesSelectedCompanyRootPath() {
        let url = MeetingRoomBrainGraph.graphFileURL(rootPath: "/tmp/cotor-company")

        #expect(url.path == "/tmp/cotor-company/graphify-out/graph.json")
    }

    @Test
    func loadFallsBackToPlainFolderMapWhenGraphifyOutputIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cotor-map-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "# Test workspace".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let sourceDirectory = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try "fun main() = Unit".write(to: sourceDirectory.appendingPathComponent("Main.kt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dist", isDirectory: true), withIntermediateDirectories: true)

        let graph = try MeetingRoomBrainGraph.load(rootPath: root.path)

        #expect(graph.isFallback)
        #expect(graph.nodes.contains { $0.displaySourceName == "README.md" })
        #expect(graph.nodes.contains { $0.displaySourceName == "src" })
        #expect(!graph.nodes.contains { $0.displaySourceName == "dist" })
        #expect(graph.links.contains { $0.source == "workspace-root" })
    }

    private func sampleGraphData() throws -> Data {
        let json = """
        {
          "directed": false,
          "multigraph": false,
          "graph": {},
          "nodes": [
            {"id":"view","label":"MeetingRoomView","file_type":"code","source_file":"MeetingRoomView.swift","source_location":"L1","community":1},
            {"id":"controller","label":"ContentView","file_type":"code","source_file":"src/main/kotlin/com/cotor/app/AppServer.kt","source_location":"L5413","community":1},
            {"id":"service","label":"GraphService","file_type":"code","source_file":"GraphService.swift","source_location":"L12","community":2}
          ],
          "links": [
            {"source":"controller","target":"view","relation":"renders","weight":1.0,"confidence_score":1.0,"confidence":"EXTRACTED"},
            {"source":"controller","target":"service","relation":"loads","weight":0.8,"confidence_score":0.8,"confidence":"INFERRED"}
          ]
        }
        """
        return try #require(json.data(using: .utf8))
    }
}
