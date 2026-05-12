// swift-tools-version: 6.0
import Foundation
import PackageDescription

// A plain Swift Package keeps the first macOS client easy to build from the repo
// without introducing an Xcode project as an additional source of truth.
let testingFrameworkPath = [
    ProcessInfo.processInfo.environment["DEVELOPER_DIR"].map { "\($0)/Library/Developer/Frameworks" },
    "/Applications/Xcode.app/Contents/Developer/Library/Developer/Frameworks",
    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
]
    .compactMap { $0 }
    .first { FileManager.default.fileExists(atPath: "\($0)/Testing.framework") }
let testingSwiftSettings: [SwiftSetting] = testingFrameworkPath.map {
    [.unsafeFlags(["-F", $0, "-Xfrontend", "-disable-cross-import-overlays"])]
} ?? []
let testingLinkerSettings: [LinkerSetting] = testingFrameworkPath.map {
    [
        .unsafeFlags([
            "-F", $0,
            "-framework", "Testing",
            "-Xlinker", "-rpath",
            "-Xlinker", $0
        ])
    ]
} ?? []

let package = Package(
    name: "CotorDesktop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CotorDesktopApp", targets: ["CotorDesktopApp"])
    ],
    targets: [
        .executableTarget(
            name: "CotorDesktopApp",
            path: "Sources/CotorDesktopApp",
            resources: [
                .copy("Resources/Brand"),
                .copy("Resources/Terminal")
            ]
        ),
        .testTarget(
            name: "CotorDesktopAppTests",
            dependencies: ["CotorDesktopApp"],
            path: "Tests/CotorDesktopAppTests",
            swiftSettings: testingSwiftSettings,
            linkerSettings: testingLinkerSettings
        )
    ]
)
