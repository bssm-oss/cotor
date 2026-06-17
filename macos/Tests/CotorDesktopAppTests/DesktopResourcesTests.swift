import Foundation
import Testing
@testable import CotorDesktopApp

struct DesktopResourcesTests {
    @Test
    func installedAppResourceBundleIsResolvedFromContentsResources() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cotor-resources-installed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let appBundle = tmpDir.appendingPathComponent("Cotor Desktop.app", isDirectory: true)
        let resourceBundle = appBundle
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("CotorDesktop_CotorDesktopApp.bundle", isDirectory: true)
        let brandDir = resourceBundle.appendingPathComponent("Brand", isDirectory: true)
        try FileManager.default.createDirectory(at: brandDir, withIntermediateDirectories: true)
        let logo = brandDir.appendingPathComponent("CotorHeaderMark.png", isDirectory: false)
        try Data("logo".utf8).write(to: logo)

        let resolved = DesktopResources.url(
            forResource: "CotorHeaderMark",
            withExtension: "png",
            subdirectory: "Brand",
            mainBundleURL: appBundle,
            mainResourceURL: appBundle.appendingPathComponent("Contents/Resources", isDirectory: true),
            executablePath: appBundle.appendingPathComponent("Contents/MacOS/CotorDesktopBinary").path,
            sourceFilePath: tmpDir.appendingPathComponent("DesktopResources.swift").path
        )

        #expect(resolved == logo.standardizedFileURL)
    }

    @Test
    func swiftPMAdjacentResourceBundleIsResolvedForSourceBuilds() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cotor-resources-swiftpm-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let buildDir = tmpDir.appendingPathComponent("release", isDirectory: true)
        let resourceBundle = buildDir.appendingPathComponent("CotorDesktop_CotorDesktopApp.bundle", isDirectory: true)
        let terminalDir = resourceBundle.appendingPathComponent("Terminal", isDirectory: true)
        try FileManager.default.createDirectory(at: terminalDir, withIntermediateDirectories: true)
        let terminalHTML = terminalDir.appendingPathComponent("terminal.html", isDirectory: false)
        try Data("<html></html>".utf8).write(to: terminalHTML)

        let resolved = DesktopResources.url(
            forResource: "terminal",
            withExtension: "html",
            subdirectory: "Terminal",
            mainBundleURL: tmpDir.appendingPathComponent("CotorDesktopPackageTests.xctest", isDirectory: true),
            mainResourceURL: nil,
            executablePath: buildDir.appendingPathComponent("CotorDesktopApp").path,
            sourceFilePath: tmpDir.appendingPathComponent("DesktopResources.swift").path
        )

        #expect(resolved == terminalHTML.standardizedFileURL)
    }
}
