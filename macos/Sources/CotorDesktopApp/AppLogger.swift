import Foundation


// MARK: - File Overview
// AppLogger belongs to the native macOS client layer for the Cotor desktop application.
// It collects declarations centered on app logger so the native shell code stays easier to navigate.
// Start with this file when tracing how the desktop client presents, stores, or moves state in this area.

enum AppLogger {
    private static let logURL: URL = {
        resolvedLogURL()
    }()

    internal static func resolvedLogURL(
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let explicitPath = nonEmpty(processEnvironment["COTOR_DESKTOP_APP_LOG_PATH"]) {
            let url = URL(fileURLWithPath: explicitPath)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return url
        }

        let appHome = nonEmpty(processEnvironment["COTOR_DESKTOP_APP_HOME"])
            ?? nonEmpty(processEnvironment["COTOR_APP_HOME"])
        let baseDir = appHome.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? defaultLogBaseDirectory(processEnvironment: processEnvironment)
        let dir = baseDir.appendingPathComponent("runtime", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("desktop-app.log")
    }

    private static func defaultLogBaseDirectory(processEnvironment: [String: String]) -> URL {
        if isRunningUnderXCTest(processEnvironment: processEnvironment) {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("CotorDesktopTests", isDirectory: true)
                .appendingPathComponent(String(ProcessInfo.processInfo.processIdentifier), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("CotorDesktop", isDirectory: true)
    }

    private static func isRunningUnderXCTest(processEnvironment: [String: String]) -> Bool {
        processEnvironment["XCTestConfigurationFilePath"] != nil
            || processEnvironment["XCTestBundlePath"] != nil
            || CommandLine.arguments.contains { $0.contains(".xctest") }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func info(_ message: String) {
        write(level: "INFO", message: message)
    }

    static func warning(_ message: String) {
        write(level: "WARN", message: message)
    }

    static func error(_ message: String) {
        write(level: "ERROR", message: message)
    }

    static func path() -> String {
        logURL.path
    }

    private static func write(level: String, message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = "[\(formatter.string(from: Date()))] [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path) == false {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try? handle.close()
        }
    }
}
