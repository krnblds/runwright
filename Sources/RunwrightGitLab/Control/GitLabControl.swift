import Foundation
import RunwrightCore

/// Starts, stops and runs gitlab-runner on this Mac.
///
/// Three ways a runner can be on:
/// - **Background service** (`brew services`): keeps going after Runwright quits.
/// - **In Runwright** (`gitlab-runner run`): every registered runner, as a child
///   of the app, with its output in the log.
/// - **One runner** (`gitlab-runner run-single --runner`): a single
///   registration, so runners can be switched on and off one at a time.
///
/// Stopping one runner while the service or the in-app run has them all keeps
/// the others going: those are stopped and the rest restarted one by one.
@MainActor
@Observable
public final class GitLabControl {
    public private(set) var binaryPath: String?
    public private(set) var brewPath: String?
    public private(set) var version: String?
    public private(set) var config: RunnerConfig?
    public private(set) var serviceRunning = false
    public private(set) var busy: String?
    public private(set) var lastError: String?
    public private(set) var log: [LogLine] = []
    public private(set) var singles: [String: ManagedProcess] = [:]
    public private(set) var appRun: ManagedProcess!

    public let configURL: URL
    public var metricsAddress = "127.0.0.1:9252"

    public init(configURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".gitlab-runner/config.toml")) {
        self.configURL = configURL
        self.appRun = ManagedProcess(name: "all runners") { [weak self] in self?.append($0) }
    }

    // MARK: State

    public var isInstalled: Bool { binaryPath != nil }
    public var registeredRunners: [RegisteredRunner] { config?.runners ?? [] }
    public var metricsEnabled: Bool { !(config?.listenAddress ?? "").isEmpty }
    /// True when the service or the in-app run is serving every runner.
    public var allRunning: Bool { serviceRunning || appRun.isRunning }
    public var anyRunning: Bool { allRunning || singles.values.contains { $0.isRunning } }

    public func isRunning(_ runner: RegisteredRunner) -> Bool {
        allRunning || singles[runner.name]?.isRunning == true
    }

    public typealias Mode = RunnerSummary.Mode

    public var mode: Mode {
        if serviceRunning { return .service }
        if appRun.isRunning { return .inApp }
        if singles.values.contains(where: \.isRunning) { return .individual }
        return .off
    }

    /// Re-reads the binary, config file and service state.
    public func refresh() async {
        binaryPath = ProcessRunner.which("gitlab-runner")
        brewPath = ProcessRunner.which("brew")
        if let text = try? String(contentsOf: configURL, encoding: .utf8) {
            config = RunnerConfig.parse(text)
        } else {
            config = nil
        }
        if let binaryPath, version == nil {
            let r = await ProcessRunner.run(binaryPath, ["--version"], timeout: 10)
            version = r.output.split(separator: "\n").first { $0.hasPrefix("Version:") }
                .map { $0.replacingOccurrences(of: "Version:", with: "").trimmingCharacters(in: .whitespaces) }
        }
        serviceRunning = await checkService()
        if terminalPath == nil && !triedTerminalPath { await loadTerminalPath() }
        await refreshOthers()
    }

    // MARK: Other installs

    /// Runners set up outside Homebrew, each with its own binary and config.
    public private(set) var others: [OtherInstall] = []
    private static let othersKey = "otherInstalls"

    private func refreshOthers() async {
        let found = await RunnerProcessScanner.scan()
        let primary = configURL.standardizedFileURL.path
        var known = (UserDefaults.standard.array(forKey: Self.othersKey) as? [[String]] ?? []).filter { $0.count == 2 }
        for f in found {
            guard let config = f.config.map({ URL(fileURLWithPath: $0).standardizedFileURL.path }), config != primary else { continue }
            if !known.contains(where: { $0[1] == config }) { known.append([f.binary, config]) }
        }
        var next: [OtherInstall] = []
        for entry in known {
            let config = URL(fileURLWithPath: entry[1])
            // Forget installs whose folder has gone.
            guard FileManager.default.fileExists(atPath: config.path) else { continue }
            let install = others.first { $0.configURL.path == config.path }
                ?? OtherInstall(binaryURL: URL(fileURLWithPath: entry[0]), configURL: config) { [weak self] in self?.append($0) }
            let pid = found.first { $0.config.map { URL(fileURLWithPath: $0).standardizedFileURL.path } == config.path }?.pid
            install.update(config: (try? String(contentsOf: config, encoding: .utf8)).map(RunnerConfig.parse), externalPID: pid)
            next.append(install)
        }
        others = next
        UserDefaults.standard.set(next.map { [$0.binaryURL.path, $0.configURL.path] }, forKey: Self.othersKey)
    }

    public func start(_ install: OtherInstall) async {
        install.start()
        try? await Task.sleep(for: .milliseconds(300))
        await refreshOthers()
    }

    public func stop(_ install: OtherInstall) async {
        busy = "Stopping \(install.label)"
        await install.stop()
        busy = nil
        await refreshOthers()
    }

    public func restart(_ install: OtherInstall) async {
        busy = "Restarting \(install.label)"
        await install.restart()
        busy = nil
        await refreshOthers()
    }

    public func useTerminalTools(for runner: RegisteredRunner, in install: OtherInstall) async {
        if terminalPath == nil { await loadTerminalPath() }
        guard let path = terminalPath else { return fail("Couldn't read your Terminal's search path.") }
        if install.rewrite({ RunnerConfig.settingJobPath(in: $0, runner: runner.name, path: path) }) {
            append(LogLine(date: .now, source: "config", text: "\(runner.name): jobs now use your Terminal's tools"))
        } else {
            fail("Couldn't update \(install.label)/config.toml.")
        }
    }

    /// Gives the install its own metrics port (9253 up, clear of the
    /// Homebrew runner's), then restarts it so the setting takes effect.
    public func enableMetrics(in install: OtherInstall) async {
        let taken = Set([metricsAddress] + others.compactMap(\.metricsAddress))
        let port = (9253...9299).first { !taken.contains("127.0.0.1:\($0)") } ?? 9253
        let address = "127.0.0.1:\(port)"
        guard install.rewrite({ RunnerConfig.enablingMetrics(in: $0, address: address) }) else {
            return fail("Couldn't update \(install.label)/config.toml.")
        }
        append(LogLine(date: .now, source: "config", text: "\(install.label): live status on at \(address)"))
        if install.isRunning {
            busy = "Restarting \(install.label)"
            await install.restart()
            busy = nil
        }
        await refreshOthers()
    }

    private func checkService() async -> Bool {
        guard let brewPath else { return false }
        let r = await ProcessRunner.run(brewPath, ["services", "info", "gitlab-runner", "--json"], timeout: 20)
        guard r.succeeded,
              let data = r.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = json.first else { return false }
        return first["running"] as? Bool ?? false
    }

    // MARK: Whole runner

    public func startService() async {
        await stopInAppRuns()
        await brewServices("start", label: "Starting the background service")
    }

    public func stopService() async {
        await brewServices("stop", label: "Stopping the background service")
    }

    public func restartService() async {
        await brewServices("restart", label: "Restarting the background service")
    }

    /// Runs every registered runner inside Runwright, with metrics on.
    public func runInApp() async {
        guard let binaryPath else { return fail("gitlab-runner is not installed.") }
        if serviceRunning { await stopService() }
        stopSingles()
        appRun.start(binaryPath, ["run", "--config", configURL.path, "--working-directory", workingDirectory,
                                  "--listen-address", metricsAddress])
    }

    /// Stops the runner however it is running.
    public func stopAll() async {
        if serviceRunning { await stopService() }
        await stopInAppRuns()
    }

    // MARK: One runner

    public func start(_ runner: RegisteredRunner) async {
        guard let binaryPath else { return fail("gitlab-runner is not installed.") }
        guard !isRunning(runner) else { return }
        let process = singles[runner.name] ?? ManagedProcess(name: runner.name) { [weak self] in self?.append($0) }
        singles[runner.name] = process
        // run-single has no --working-directory; the child starts in $HOME.
        process.start(binaryPath, ["run-single", "--config", configURL.path, "--runner", runner.name])
    }

    public func stop(_ runner: RegisteredRunner) async {
        if allRunning {
            // Keep the other runners going on their own.
            let others = registeredRunners.filter { $0.name != runner.name }
            busy = "Stopping \(runner.name)"
            if serviceRunning { await brewServices("stop", label: "Stopping the background service") }
            appRun.stop()
            await waitUntil { !self.appRun.isRunning }
            for other in others { await start(other) }
            busy = nil
        } else {
            singles[runner.name]?.stop()
        }
    }

    public func toggle(_ runner: RegisteredRunner) async {
        if isRunning(runner) { await stop(runner) } else { await start(runner) }
    }

    // MARK: Setup

    public func install() async {
        guard let brewPath else { return fail("Homebrew is not installed, so the runner cannot be installed from here.") }
        busy = "Installing gitlab-runner"
        append(LogLine(date: .now, source: "brew", text: "brew install gitlab-runner"))
        let r = await ProcessRunner.run(brewPath, ["install", "gitlab-runner"])
        appendOutput(r.output, source: "brew")
        if !r.succeeded { fail("Install did not finish (exit \(r.status)).") }
        busy = nil
        await refresh()
    }

    /// Registers a runner with a runner authentication token (`glrt-…`). The
    /// token is handed to gitlab-runner and not kept by Runwright.
    public func register(url: String, token: String, name: String, executor: String = "shell") async {
        guard let binaryPath else { return fail("gitlab-runner is not installed.") }
        busy = "Registering \(name)"
        try? FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let r = await ProcessRunner.run(binaryPath, [
            "register", "--non-interactive", "--config", configURL.path,
            "--url", url, "--token", token, "--name", name, "--executor", executor,
        ])
        appendOutput(r.output, source: "register")
        if !r.succeeded { fail("Registration failed (exit \(r.status)). See the log.") }
        busy = nil
        await refresh()
        if r.succeeded && !metricsEnabled { await enableMetrics() }
    }

    /// Adds `listen_address` to config.toml (keeping a backup) so the live
    /// status can be read, and restarts the service if it is running.
    public func enableMetrics() async {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
            return fail("No config.toml yet. Register a runner first.")
        }
        let backup = configURL.appendingPathExtension("runwright-backup")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: configURL, to: backup)
        do {
            try RunnerConfig.enablingMetrics(in: text, address: metricsAddress)
                .write(to: configURL, atomically: true, encoding: .utf8)
            append(LogLine(date: .now, source: "config", text: "Turned on live status at \(metricsAddress)"))
        } catch {
            return fail("Could not update config.toml: \(error.localizedDescription)")
        }
        await refresh()
        if serviceRunning { await restartService() }
    }

    public func verify() async {
        guard let binaryPath else { return }
        busy = "Checking runners with GitLab"
        let r = await ProcessRunner.run(binaryPath, ["verify", "--config", configURL.path])
        appendOutput(r.output, source: "verify")
        busy = nil
    }

    public func clearLog() { log.removeAll() }

    // MARK: Tools jobs can use

    /// The search path the user's Terminal has; see `TerminalTools`.
    public private(set) var terminalPath: String?

    /// What a shell-executor job gets when the runner sets no PATH: the
    /// background service starts with launchd's short list plus Homebrew.
    public static let servicePath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

    public func jobPath(for runner: RegisteredRunner) -> String {
        runner.jobPath ?? Self.servicePath
    }

    /// Tools the Terminal can run that this runner's jobs can't find.
    public func missingTools(for runner: RegisteredRunner) -> [String] {
        TerminalTools.missingTools(jobPath: jobPath(for: runner), terminalPath: terminalPath)
    }

    @ObservationIgnored private var triedTerminalPath = false

    public func loadTerminalPath() async {
        triedTerminalPath = true
        if let path = await TerminalTools.loadTerminalPath() { terminalPath = path }
    }

    /// Gives the runner's jobs the Terminal's search path. gitlab-runner
    /// notices config.toml changes by itself, so running jobs aren't cut off
    /// by a restart.
    public func useTerminalTools(for runner: RegisteredRunner) async {
        if terminalPath == nil { await loadTerminalPath() }
        guard let path = terminalPath else { return fail("Couldn't read your Terminal's search path.") }
        guard let text = try? String(contentsOf: configURL, encoding: .utf8),
              let updated = RunnerConfig.settingJobPath(in: text, runner: runner.name, path: path) else {
            return fail("Couldn't find \(runner.name) in config.toml.")
        }
        let backup = configURL.appendingPathExtension("runwright-backup")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: configURL, to: backup)
        do {
            try updated.write(to: configURL, atomically: true, encoding: .utf8)
            append(LogLine(date: .now, source: "config", text: "\(runner.name): jobs now use your Terminal's tools"))
        } catch {
            fail("Could not update config.toml: \(error.localizedDescription)")
        }
        await refresh()
    }

    // MARK: Logs

    /// Where the Homebrew service writes its output, when its plist says.
    /// Homebrew's own gitlab-runner service often keeps none.
    public var serviceLogs: [URL] {
        let agents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        return ["homebrew.mxcl.gitlab-runner.plist", "sh.brew.gitlab-runner.plist"]
            .flatMap { LogTail.launchdLogs(plist: agents.appendingPathComponent($0)) }
    }

    // MARK: Helpers

    private var workingDirectory: String { FileManager.default.homeDirectoryForCurrentUser.path }

    private func brewServices(_ verb: String, label: String) async {
        guard let brewPath else { return fail("Homebrew is not installed, so the background service is not available.") }
        busy = label
        let r = await ProcessRunner.run(brewPath, ["services", verb, "gitlab-runner"])
        appendOutput(r.output, source: "service")
        if !r.succeeded { fail("\(label) failed (exit \(r.status)).") }
        serviceRunning = await checkService()
        busy = nil
    }

    private func stopInAppRuns() async {
        appRun.stop()
        stopSingles()
        await waitUntil { !self.appRun.isRunning && !self.singles.values.contains(where: \.isRunning) }
    }

    private func stopSingles() {
        singles.values.forEach { $0.stop() }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func fail(_ message: String) {
        lastError = message
        busy = nil
        append(LogLine(date: .now, source: "Runwright", text: message))
    }

    public func dismissError() { lastError = nil }

    private func appendOutput(_ output: String, source: String) {
        for line in output.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            append(LogLine(date: .now, source: source, text: ManagedProcess.stripANSI(String(line))))
        }
    }

    private func append(_ line: LogLine) {
        log.append(line)
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }

    /// Stop child processes when the app quits; the background service stays.
    public func shutdown() {
        appRun.stop()
        stopSingles()
        // Installs started here stop with the app; ones started elsewhere stay.
        others.forEach { $0.process.stop() }
    }
}
