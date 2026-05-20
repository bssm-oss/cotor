import Foundation

enum DesktopResources {
    private static let swiftPMBundleName = "CotorDesktop_CotorDesktopApp.bundle"

    static func url(
        forResource name: String,
        withExtension fileExtension: String?,
        subdirectory: String? = nil
    ) -> URL? {
        url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: subdirectory,
            mainBundleURL: Bundle.main.bundleURL,
            mainResourceURL: Bundle.main.resourceURL,
            executablePath: CommandLine.arguments.first,
            sourceFilePath: #filePath
        )
    }

    static func url(
        forResource name: String,
        withExtension fileExtension: String?,
        subdirectory: String? = nil,
        mainBundleURL: URL,
        mainResourceURL: URL?,
        executablePath: String?,
        sourceFilePath: String,
        fileManager: FileManager = .default
    ) -> URL? {
        let fileName = fileExtension.map { "\(name).\($0)" } ?? name
        for root in resourceRootCandidates(
            mainBundleURL: mainBundleURL,
            mainResourceURL: mainResourceURL,
            executablePath: executablePath,
            sourceFilePath: sourceFilePath
        ) {
            let candidate = append(subdirectory: subdirectory, fileName: fileName, to: root)
            var isDirectory = ObjCBool(false)
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    static func resourceRootCandidates(
        mainBundleURL: URL,
        mainResourceURL: URL?,
        executablePath: String?,
        sourceFilePath: String
    ) -> [URL] {
        var candidates: [URL] = []

        if let mainResourceURL {
            candidates.append(mainResourceURL.appendingPathComponent(swiftPMBundleName, isDirectory: true))
        }

        candidates.append(
            mainBundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(swiftPMBundleName, isDirectory: true)
        )
        candidates.append(mainBundleURL.appendingPathComponent(swiftPMBundleName, isDirectory: true))

        if let executablePath, !executablePath.isEmpty {
            let executableURL = URL(fileURLWithPath: executablePath)
            let executableDirectory = executableURL.deletingLastPathComponent()
            candidates.append(executableDirectory.appendingPathComponent(swiftPMBundleName, isDirectory: true))
            candidates.append(
                executableDirectory
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(swiftPMBundleName, isDirectory: true)
            )
        }

        let sourceResources = URL(fileURLWithPath: sourceFilePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        candidates.append(sourceResources)

        return uniqueStandardizedURLs(candidates)
    }

    private static func append(subdirectory: String?, fileName: String, to root: URL) -> URL {
        guard let subdirectory, !subdirectory.isEmpty else {
            return root.appendingPathComponent(fileName, isDirectory: false)
        }
        return root
            .appendingPathComponent(subdirectory, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static func uniqueStandardizedURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var unique: [URL] = []

        for url in urls {
            let standardized = url.standardizedFileURL
            if seen.insert(standardized.path).inserted {
                unique.append(standardized)
            }
        }

        return unique
    }
}
