import Darwin
import Foundation


// MARK: - File Overview
// EmbeddedBackendLauncher belongs to the native macOS client layer for the Cotor desktop application.
// It collects declarations centered on embedded backend launcher so the native shell code stays easier to navigate.
// Start with this file when tracing how the desktop client presents, stores, or moves state in this area.

actor EmbeddedBackendLauncher {
    static let shared = EmbeddedBackendLauncher()

    private let port = 8787
    private var process: Process?
    private var stagedJarPath: String?
    private var shutdownRequested = false
    private let shutdownPollIntervalMs = 200

    func ensureRunning() async {
        if usesExternalServerConfiguration() {
            return
        }
        if shutdownRequested {
            return
        }
        await terminateStaleBundledBackendProcesses()
        cleanupStaleRuntimeJars()
        if await healthCheck() {
            return
        }
        if let process, process.isRunning {
            let becameHealthy = await waitForHealth(timeoutSeconds: 8)
            if becameHealthy {
                AppLogger.info("Embedded backend process recovered without restart.")
                return
            }
            AppLogger.error("Embedded backend process unhealthy. Restarting.")
            _ = await terminateCurrentProcess(timeoutSeconds: 2)
        }
        guard let javaPath = resolveJavaExecutablePath(),
              let jarPath = resolveBundledBackendJarPath() else {
            AppLogger.error("Embedded backend launch failed: missing java or bundled jar.")
            return
        }
        guard let runtimeJarPath = stageRuntimeBackendJar(sourcePath: jarPath) else {
            AppLogger.error("Embedded backend launch failed: could not stage backend jar.")
            return
        }
        stagedJarPath = runtimeJarPath

        let runtimeDir = defaultDesktopAppHome()
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("backend", isDirectory: true)
        try? FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        let stdoutPath = runtimeDir.appendingPathComponent("app-server.out.log").path
        let stderrPath = runtimeDir.appendingPathComponent("app-server.err.log").path
        FileManager.default.createFile(atPath: stdoutPath, contents: nil)
        FileManager.default.createFile(atPath: stderrPath, contents: nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: javaPath)
        process.arguments = [
            "-jar",
            runtimeJarPath,
            "app-server",
            "--port",
            "\(port)"
        ]
        process.environment = mergedEnvironment(javaPath: javaPath)
        process.standardOutput = FileHandle(forWritingAtPath: stdoutPath)
        process.standardError = FileHandle(forWritingAtPath: stderrPath)

        do {
            if shutdownRequested {
                AppLogger.info("Skipping embedded backend launch because shutdown is in progress.")
                return
            }
            AppLogger.info("Launching embedded backend on port \(port) with runtime jar \(runtimeJarPath).")
            try process.run()
            self.process = process
            let started = await waitForHealth(timeoutSeconds: 10)
            if !started {
                AppLogger.error("Embedded backend failed health check after launch.")
                _ = await terminateCurrentProcess(timeoutSeconds: 2)
            } else {
                AppLogger.info("Embedded backend became healthy on port \(port).")
            }
        } catch {
            self.process = nil
            AppLogger.error("Embedded backend launch threw error: \(error.localizedDescription)")
        }
    }

    func restart() async {
        if usesExternalServerConfiguration() {
            AppLogger.info("Skipping embedded backend restart because an external app-server URL is configured.")
            return
        }
        shutdownRequested = false
        AppLogger.info("Restarting embedded backend.")
        _ = await terminateCurrentProcess(timeoutSeconds: 2)
        terminateExternalBundledBackendProcesses()
        await ensureRunning()
    }

    func stop(timeoutSeconds: TimeInterval = 5) async -> Bool {
        if usesExternalServerConfiguration() {
            AppLogger.info("Skipping embedded backend stop because the backend is launcher-managed or externally configured.")
            return true
        }
        shutdownRequested = true
        AppLogger.info("Embedded backend stop started.")
        let gracefulShutdownRequested = await requestGracefulShutdown()
        if gracefulShutdownRequested {
            AppLogger.info("Requested graceful embedded backend shutdown over HTTP.")
        }
        var shutdownConfirmed = await waitForShutdown(timeoutSeconds: min(timeoutSeconds, 3))
        var trackedStopped = shutdownConfirmed
        if !shutdownConfirmed {
            trackedStopped = await terminateCurrentProcess(timeoutSeconds: min(timeoutSeconds, 2))
            terminateExternalBundledBackendProcesses()
            shutdownConfirmed = await waitForShutdown(timeoutSeconds: max(timeoutSeconds - 2, 1))
        }
        if shutdownConfirmed {
            AppLogger.info("Embedded backend stop completed.")
        } else if trackedStopped {
            AppLogger.error("Embedded backend stop timed out while waiting for shutdown confirmation.")
        } else {
            AppLogger.error("Embedded backend stop failed before shutdown confirmation completed.")
        }
        return shutdownConfirmed
    }

    private func terminateStaleBundledBackendProcesses() async {
        guard let jarPath = resolveBundledBackendJarPath() else {
            return
        }
        do {
            let stalePids = try staleBundledBackendPids(for: jarPath, excluding: process?.processIdentifier)
            if stalePids.isEmpty {
                return
            }
            stalePids.forEach { pid in
                _ = kill(pid, SIGTERM)
            }
            try? await Task.sleep(for: .milliseconds(800))
            let survivors = try staleBundledBackendPids(for: jarPath, excluding: process?.processIdentifier)
                .filter { stalePids.contains($0) }
            survivors.forEach { pid in
                _ = kill(pid, SIGKILL)
            }
            let pidList = stalePids.map(String.init).joined(separator: ", ")
            if survivors.isEmpty {
                AppLogger.info("Terminated stale bundled backends: \(pidList).")
            } else {
                let survivorList = survivors.map(String.init).joined(separator: ", ")
                AppLogger.info(
                    "Escalated stale bundled backend termination to SIGKILL. terminated=\(pidList) killed=\(survivorList)."
                )
            }
        } catch {
            AppLogger.error("Failed to inspect stale bundled backends: \(error.localizedDescription)")
        }
    }

    private func staleBundledBackendPids(for jarPath: String, excluding currentPid: Int32?) throws -> [Int32] {
        let runtimeDir = defaultDesktopAppHome()
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("backend", isDirectory: true)
            .path
        let inspector = Process()
        inspector.executableURL = URL(fileURLWithPath: "/bin/ps")
        inspector.arguments = ["-axo", "pid=,args="]
        let pipe = Pipe()
        inspector.standardOutput = pipe
        inspector.standardError = Pipe()
        do {
            let output = try runProcessAndDrainOutput(inspector, outputPipe: pipe)
            return output
                .split(separator: "\n")
                .compactMap { line -> Int32? in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    let matchesBundledJar = trimmed.contains(jarPath)
                    let matchesRuntimeJar = trimmed.contains("\(runtimeDir)/cotor-backend-runtime-")
                    guard !trimmed.isEmpty, (matchesBundledJar || matchesRuntimeJar), trimmed.contains("app-server") else {
                        return nil
                    }
                    let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
                    guard let first = parts.first, let pid = Int32(first) else {
                        return nil
                    }
                    if let currentPid, pid == currentPid {
                        return nil
                    }
                    return pid
                }
        } catch {
            throw error
        }
    }

    private func stageRuntimeBackendJar(sourcePath: String) -> String? {
        let runtimeDir = defaultDesktopAppHome()
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("backend", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
            let runtimeJar = runtimeDir.appendingPathComponent("cotor-backend-runtime-\(ProcessInfo.processInfo.processIdentifier).jar")
            if FileManager.default.fileExists(atPath: runtimeJar.path) {
                try FileManager.default.removeItem(at: runtimeJar)
            }
            try FileManager.default.copyItem(atPath: sourcePath, toPath: runtimeJar.path)
            return runtimeJar.path
        } catch {
            AppLogger.error("Failed to stage embedded backend jar: \(error.localizedDescription)")
            return nil
        }
    }

    private func waitForHealth(timeoutSeconds: Int) async -> Bool {
        for _ in 0 ..< timeoutSeconds * 5 {
            if await healthCheck() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(shutdownPollIntervalMs))
        }
        return false
    }

    private func waitForShutdown(timeoutSeconds: TimeInterval) async -> Bool {
        let checks = max(1, Int((timeoutSeconds * 1000) / Double(shutdownPollIntervalMs)))
        for _ in 0 ..< checks {
            if await healthCheck() == false {
                return true
            }
            try? await Task.sleep(for: .milliseconds(shutdownPollIntervalMs))
        }
        return await healthCheck() == false
    }

    private func healthCheck() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/app/health") else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        request.setValue("Bearer \(DesktopAPI.ensureAppToken())", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                guard (200 ..< 300).contains(http.statusCode) else {
                    return false
                }
                return isOwnedEmbeddedBackendHealthData(data)
            }
        } catch {
            return false
        }
        return false
    }

    private func requestGracefulShutdown() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/app/shutdown") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 1.5
        request.setValue("Bearer \(DesktopAPI.ensureAppToken())", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                return http.statusCode == 202 || (200 ..< 300).contains(http.statusCode)
            }
        } catch {
            return false
        }
        return false
    }

    private func mergedEnvironment(javaPath: String) -> [String: String] {
        sanitizedEmbeddedBackendEnvironment(
            processEnvironment: ProcessInfo.processInfo.environment,
            javaPath: javaPath,
            appHomePath: defaultDesktopAppHome().path,
            appToken: DesktopAPI.ensureAppToken()
        )
    }

    private func usesExternalServerConfiguration() -> Bool {
        guard let rawURL = ProcessInfo.processInfo.environment["COTOR_APP_SERVER_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty else {
            return false
        }
        return true
    }

    private func resolveJavaExecutablePath() -> String? {
        if let javaHome = ProcessInfo.processInfo.environment["JAVA_HOME"], !javaHome.isEmpty {
            let candidate = URL(fileURLWithPath: javaHome).appendingPathComponent("bin/java").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
        let pipe = Pipe()
        helper.standardOutput = pipe
        helper.standardError = Pipe()
        do {
            try helper.run()
            helper.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let output, !output.isEmpty {
                let candidate = URL(fileURLWithPath: output).appendingPathComponent("bin/java").path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        } catch {
            return nil
        }
        let shellCandidates = [
            "/opt/homebrew/bin/java",
            "/usr/local/bin/java",
            "/usr/bin/java"
        ]
        for candidate in shellCandidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    private func resolveBundledBackendJarPath() -> String? {
        let projectRootJar = ProcessInfo.processInfo.environment["COTOR_PROJECT_ROOT"].flatMap { rawPath -> URL? in
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return URL(fileURLWithPath: trimmed).appendingPathComponent("build/libs/cotor-backend.jar")
        }
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("backend/cotor-backend.jar"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/backend/cotor-backend.jar"),
            projectRootJar
        ]
        for candidate in candidates.compactMap({ $0 }) where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate.path
        }
        return nil
    }

    private func terminateExternalBundledBackendProcesses() {
        guard let jarPath = resolveBundledBackendJarPath() else {
            return
        }
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killer.arguments = ["-f", jarPath]
        killer.standardOutput = Pipe()
        killer.standardError = Pipe()
        do {
            try killer.run()
            killer.waitUntilExit()
        } catch {
            AppLogger.error("Embedded backend external cleanup failed: \(error.localizedDescription)")
        }
    }

    private func defaultDesktopAppHome() -> URL {
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        return userHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("CotorDesktop", isDirectory: true)
    }

    private func terminateCurrentProcess(timeoutSeconds: TimeInterval) async -> Bool {
        guard let process else { return true }
        if process.isRunning {
            process.terminate()
            let checks = max(1, Int((timeoutSeconds * 1000) / Double(shutdownPollIntervalMs)))
            for _ in 0 ..< checks {
                if !process.isRunning {
                    break
                }
                try? await Task.sleep(for: .milliseconds(shutdownPollIntervalMs))
            }
            if process.isRunning {
                process.interrupt()
                for _ in 0 ..< max(1, checks / 2) {
                    if !process.isRunning {
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(shutdownPollIntervalMs))
                }
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                for _ in 0 ..< 5 {
                    if !process.isRunning {
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(shutdownPollIntervalMs))
                }
            }
        }
        let terminated = !process.isRunning
        if !terminated {
            AppLogger.error("Embedded backend child process \(process.processIdentifier) did not exit after termination attempts.")
        }
        self.process = nil
        deleteStagedJar()
        return terminated
    }

    private func deleteStagedJar() {
        guard let path = stagedJarPath else { return }
        stagedJarPath = nil
        do {
            try FileManager.default.removeItem(atPath: path)
            AppLogger.info("Removed staged backend runtime jar.")
        } catch {
            AppLogger.error("Failed to remove staged backend runtime jar: \(error.localizedDescription)")
        }
    }

    private func cleanupStaleRuntimeJars() {
        let runtimeDir = defaultDesktopAppHome()
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("backend", isDirectory: true)
        let liveLines = liveJavaCommandLines()
        let toRemove = staleRuntimeJarsToClean(in: runtimeDir, liveCommandLines: liveLines)
        for jar in toRemove {
            do {
                try FileManager.default.removeItem(at: jar)
                AppLogger.info("Removed stale backend runtime jar: \(jar.lastPathComponent).")
            } catch {
                AppLogger.error("Failed to remove stale backend runtime jar \(jar.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    private func liveJavaCommandLines() -> Set<String> {
        let inspector = Process()
        inspector.executableURL = URL(fileURLWithPath: "/bin/ps")
        inspector.arguments = ["-axo", "args="]
        let pipe = Pipe()
        inspector.standardOutput = pipe
        inspector.standardError = Pipe()
        do {
            let output = try runProcessAndDrainOutput(inspector, outputPipe: pipe)
            return Set(output.split(separator: "\n").map(String.init))
        } catch {
            return []
        }
    }
}

private func runProcessAndDrainOutput(_ process: Process, outputPipe: Pipe) throws -> String {
    try process.run()
    let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: output, encoding: .utf8) ?? ""
}

private struct EmbeddedBackendHealthPayload: Decodable {
    let ok: Bool
    let service: String
    let owner: String
    let version: String
    let build: String
}

internal func isOwnedEmbeddedBackendHealthData(_ data: Data) -> Bool {
    guard let payload = try? JSONDecoder().decode(EmbeddedBackendHealthPayload.self, from: data) else {
        return false
    }
    return payload.ok &&
        payload.service == "cotor-app-server" &&
        payload.owner == "cotor-desktop" &&
        !payload.version.isEmpty &&
        !payload.build.isEmpty
}

internal func staleRuntimeJarsToClean(in runtimeDir: URL, liveCommandLines: Set<String>) -> [URL] {
    guard let files = try? FileManager.default.contentsOfDirectory(
        at: runtimeDir, includingPropertiesForKeys: nil
    ) else { return [] }
    return files.filter { file in
        let pathAliases = runtimeJarPathAliases(for: file)
        return isBackendRuntimeJar(file.lastPathComponent) &&
        file.pathExtension == "jar" &&
        !liveCommandLines.contains(where: { line in
            pathAliases.contains(where: { line.contains($0) })
        })
    }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func isBackendRuntimeJar(_ fileName: String) -> Bool {
    fileName.hasPrefix("cotor-backend-runtime-") || fileName.hasPrefix("cotor-app-server-")
}

private func runtimeJarPathAliases(for file: URL) -> Set<String> {
    let raw = file.path
    let standardized = file.standardizedFileURL.path
    let resolved = file.resolvingSymlinksInPath().path
    var aliases = Set([raw, standardized, resolved])
    for path in Array(aliases) {
        if path.hasPrefix("/private/var/") || path.hasPrefix("/private/tmp/") {
            aliases.insert(String(path.dropFirst("/private".count)))
        } else if path.hasPrefix("/var/") || path.hasPrefix("/tmp/") {
            aliases.insert("/private\(path)")
        }
    }
    return aliases
}

internal func sanitizedEmbeddedBackendEnvironment(
    processEnvironment: [String: String],
    javaPath: String,
    appHomePath: String,
    appToken: String
) -> [String: String] {
    let passthroughKeys: Set<String> = [
        "HOME",
        "USER",
        "LOGNAME",
        "SHELL",
        "TMPDIR",
        "LANG",
        "LC_ALL",
        "LC_CTYPE",
        "TERM",
        "NO_COLOR",
        "CODEX_HOME",
        "COTOR_CODEX_OAUTH_HOME"
    ]
    var env = processEnvironment.filter { key, value in
        !value.isEmpty && (passthroughKeys.contains(key) || key.hasPrefix("LC_"))
    }
    let javaHome = URL(fileURLWithPath: javaPath).deletingLastPathComponent().deletingLastPathComponent().path
    let defaultPath = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"

    env["JAVA_HOME"] = nonEmpty(processEnvironment["JAVA_HOME"]) ?? javaHome
    env["COTOR_DESKTOP_APP_HOME"] = appHomePath
    env["COTOR_APP_HOME"] = appHomePath
    env["COTOR_APP_TOKEN"] = appToken
    env["PATH"] = mergePath(nonEmpty(processEnvironment["PATH"]), defaultPath)
    return env
}

private func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private func mergePath(_ inheritedPath: String?, _ defaultPath: String) -> String {
    let entries = [inheritedPath, defaultPath]
        .compactMap(nonEmpty)
        .flatMap { $0.split(separator: ":").map(String.init) }
    var seen = Set<String>()
    let uniqueEntries = entries.filter { entry in
        seen.insert(entry).inserted
    }
    return uniqueEntries.joined(separator: ":")
}
