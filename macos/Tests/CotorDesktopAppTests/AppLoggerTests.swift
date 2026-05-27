import Foundation
import Testing
@testable import CotorDesktopApp

struct AppLoggerTests {
    @Test
    func resolvedLogURLHonorsExplicitLogPath() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cotor-app-logger-\(UUID().uuidString)", isDirectory: true)
        let explicitURL = directory.appendingPathComponent("custom-desktop.log")

        let resolved = AppLogger.resolvedLogURL(
            processEnvironment: ["COTOR_DESKTOP_APP_LOG_PATH": explicitURL.path]
        )

        #expect(resolved.path == explicitURL.path)
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test
    func resolvedLogURLHonorsAppHomeOverride() {
        let appHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("cotor-app-home-\(UUID().uuidString)", isDirectory: true)

        let resolved = AppLogger.resolvedLogURL(
            processEnvironment: ["COTOR_DESKTOP_APP_HOME": appHome.path]
        )

        #expect(resolved.path == appHome.appendingPathComponent("runtime/desktop-app.log").path)
        #expect(FileManager.default.fileExists(atPath: appHome.appendingPathComponent("runtime").path))
    }

    @Test
    func resolvedLogURLUsesTemporaryDirectoryUnderXCTest() {
        let resolved = AppLogger.resolvedLogURL(
            processEnvironment: ["XCTestConfigurationFilePath": "/tmp/cotor-tests.xctestconfiguration"]
        )

        #expect(resolved.path.contains("/CotorDesktopTests/"))
        #expect(resolved.path.hasSuffix("/runtime/desktop-app.log"))
        #expect(!resolved.path.contains("/Library/Application Support/CotorDesktop/runtime/desktop-app.log"))
    }

    @Test
    func activeLoggerPathIsIsolatedDuringSwiftTests() {
        #expect(AppLogger.path().contains("/CotorDesktopTests/"))
        #expect(!AppLogger.path().contains("/Library/Application Support/CotorDesktop/runtime/desktop-app.log"))
    }
}
