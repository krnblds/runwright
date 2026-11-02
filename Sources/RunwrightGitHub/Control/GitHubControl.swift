import Foundation
import RunwrightCore

/// Finds the GitHub Actions runners on this Mac and starts and stops them.
///
/// Runners are folders `config.sh` has set up. Runwright looks for them in
/// `~/actions-runner` and its siblings, in running `Runner.Listener`
/// processes, and in folders it has seen before, so a stopped runner still
/// shows.
///
/// Two ways a runner can be on:
/// - **Background service** (`svc.sh`): a launchd agent that keeps going
///   after Runwright quits. Used whenever it has been installed.
/// - **In Runwright** (`run.sh`): a child of the app, with its output in the log.
@MainActor
@Observable
public final class GitHubControl {
    public private(set) var runners: [GitHubRunner] = []
    /// Folders with the runner unpacked but not configured yet.
    public private(set) var unconfigured: [URL] = []
    public private(set) var busy: String?
    public private(set) var lastError: String?
    public private(set) var log: [LogLine] = []
    /// A refresh has finished, so an empty list means there are none.
    public private(set) var hasLooked = false

    @ObservationIgnored private let home: URL
    @ObservationIgnored private let defaults: UserDefaults
    private static let foldersKey = "githubRunnerFolders"

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, defaults: UserDefaults = .standard) {
        self.home = home
        self.defaults = defaults
    }

    public func runner(id: GitHubRunner.ID) -> GitHubRunner? { runners.first { $0.id == id } }

    // MARK: Finding runners

    public func refresh() async {
        let processes = await ActionsProcessScanner.scan()
        let launchd = await LaunchdList.load()
        let remembered = defaults.stringArray(forKey: Self.foldersKey) ?? []
        let home = self.home
        let (folders, unconfigured) = await Task.detached {
            Self.look(home: home, remembered: remembered, processRoots: processes.map(\.root))
        }.value
        apply(folders: folders, unconfigured: unconfigured, processes: processes, launchd: launchd)
        hasLooked = true
        if !runners.isEmpty && terminalPath == nil && !triedTerminalPath { await loadTerminalPath() }
        if !runners.isEmpty { await checkLatestVersion() }
    }

    /// Reads every folder that could be a runner, without the credentials.
    nonisolated static func look(home: URL, remembered: [String], processRoots: [String]) -> ([RunnerFolder], [URL]) {
        var seen = Set<String>()
        let roots = (RunnerFolder.candidates(home: home) + (remembered + processRoots).map { URL(fileURLWithPath: $0) })
            .map(\.standardizedFileURL)
            .filter { seen.insert($0.path).inserted }
        let folders = roots.filter(RunnerFolder.isRunnerFolder).map(RunnerFolder.read)
        return (folders, roots.filter(RunnerFolder.isUnconfigured))
    }

    func apply(folders: [RunnerFolder], unconfigured: [URL] = [], processes: [ActionsProcessScanner.Found],
               launchd: [String: LaunchdList.Job]) {
        runners = folders.map { folder in
            let runner = runners.first { $0.id == folder.root.path }
                ?? GitHubRunner(folder: folder) { [weak self] in self?.append($0) }
            runner.update(folder: folder, processes: processes, launchd: launchd)
            return runner
        }
        self.unconfigured = unconfigured
        defaults.set(runners.map(\.id) + unconfigured.map(\.path), forKey: Self.foldersKey)
    }

    /// Keeps looking at a folder Runwright put a runner in, wherever it is.
    private func remember(_ folder: URL) {
        var known = defaults.stringArray(forKey: Self.foldersKey) ?? []
        if !known.contains(folder.path) { known.append(folder.path) }
        defaults.set(known, forKey: Self.foldersKey)
    }

    // MARK: Versions

    /// The newest actions-runner release, when it could be found out.
    public private(set) var latestVersion: String?
    @ObservationIgnored private var checkedLatestAt: Date?
    /// The version the runner last started as, from its log. Running
    /// `Runner.Listener --version` would start a log of its own.
    public func version(of runner: GitHubRunner) -> String? { runner.folder.version }

    /// A newer release is out than the one in the runner's folder.
    public func updateAvailable(for runner: GitHubRunner) -> Bool {
        guard let version = version(of: runner), let latest = latestVersion else { return false }
        return RunnerRelease.isOutdated(version, latest: latest)
    }

    /// Looks up the newest release, at most every six hours unless `force`d.
    public func checkLatestVersion(force: Bool = false) async {
        if !force, let checked = checkedLatestAt, Date.now.timeIntervalSince(checked) < 6 * 3600 { return }
        checkedLatestAt = .now
        if let latest = await RunnerRelease.latestVersion() { latestVersion = latest }
    }

    // MARK: Installing

    /// Where a new runner goes: `~/actions-runner`, or the first free
    /// `~/actions-runner-N` once that is taken.
    public func suggestedFolder() -> URL {
        let fm = FileManager.default
        let free = { (url: URL) in
            !fm.fileExists(atPath: url.path) || RunnerFolder.isUnconfigured(url)
                || ((try? fm.contentsOfDirectory(atPath: url.path))?.isEmpty ?? false)
        }
        let first = home.appendingPathComponent("actions-runner")
        if free(first) { return first }
        for n in 2...99 {
            let url = home.appendingPathComponent("actions-runner-\(n)")
            if free(url) { return url }
        }
        return first
    }

    /// Downloads the newest runner into `folder` (unless it is already
    /// unpacked there), registers it with `config.sh`, then starts it. The
    /// registration token goes straight to config.sh and isn't kept.
    public func install(into folder: URL, url: String, token: String, name: String, labels: String,
                        asService: Bool) async {
        let folder = folder.standardizedFileURL
        guard !RunnerFolder.isRunnerFolder(folder) else {
            return fail("\(RunnerFolder(root: folder).label) already has a runner. Pick another folder.")
        }
        if !RunnerFolder.isUnconfigured(folder) {
            guard await unpack(into: folder) else { return }
        }
        remember(folder)

        busy = "Registering \(name)"
        var args = ["config.sh", "--unattended", "--url", url, "--token", token, "--name", name, "--work", "_work"]
        let labels = labels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !labels.isEmpty { args += ["--labels", labels.joined(separator: ",")] }
        append(LogLine(date: .now, source: "config.sh", text: "Registering \(name) with \(url)"))
        let r = await ProcessRunner.run("/bin/bash", args, timeout: 120, in: folder)
        appendOutput(r.output, source: "config.sh")
        busy = nil
        guard r.succeeded else {
            return fail("Registration failed (exit \(r.status)). See the log; a token is good for an hour.")
        }
        await refresh()
        guard let runner = runners.first(where: { $0.root.standardizedFileURL.path == folder.path }) else { return }
        if asService { await installService(runner) } else { await start(runner) }
    }

    /// Puts the newest release into `folder`. Files the runner keeps
    /// (`.runner`, `.credentials`, `_work`, `_diag`) aren't in the download,
    /// so updating over a registered runner keeps its registration.
    private func unpack(into folder: URL) async -> Bool {
        busy = "Looking up the newest runner"
        await checkLatestVersion(force: latestVersion == nil)
        guard let version = latestVersion else {
            fail("Couldn't find the newest actions-runner on github.com.")
            return false
        }
        busy = "Downloading actions-runner \(version)"
        append(LogLine(date: .now, source: "download", text: RunnerRelease.downloadURL(version: version).absoluteString))
        let archive: URL
        do {
            archive = try await RunnerRelease.download(version: version)
        } catch {
            fail("Download failed: \(error.localizedDescription)")
            return false
        }
        defer { try? FileManager.default.removeItem(at: archive) }
        busy = "Unpacking actions-runner \(version)"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            fail("Couldn't make \(folder.path): \(error.localizedDescription)")
            return false
        }
        let r = await ProcessRunner.run("/usr/bin/tar", ["-xzf", archive.path, "-C", folder.path], timeout: 300)
        busy = nil
        guard r.succeeded else {
            appendOutput(r.output, source: "tar")
            fail("Unpacking failed (exit \(r.status)).")
            return false
        }
        append(LogLine(date: .now, source: "download", text: "actions-runner \(version) is in \(RunnerFolder(root: folder).label)"))
        return true
    }

    /// Puts the newest release into the runner's folder. It is stopped
    /// first, and started again the way it was running.
    public func update(_ runner: GitHubRunner) async {
        let wasRunning = runner.isRunning
        let wasHere = runner.process.isRunning
        if wasRunning { await stop(runner) }
        let updated = await unpack(into: runner.root)
        await refresh()
        if wasRunning {
            if wasHere { runner.startHere(); await settle() } else { await start(runner) }
        }
        if updated, let latest = latestVersion {
            append(LogLine(date: .now, source: "download", text: "\(runner.name) updated to \(latest)"))
        }
    }

    // MARK: Control

    /// Starts the background service when it is installed, otherwise runs
    /// `run.sh` inside Runwright.
    public func start(_ runner: GitHubRunner) async {
        guard !runner.isRunning else { return }
        if runner.serviceInstalled {
            await svc(runner, "start", label: "Starting \(runner.name)")
        } else {
            runner.startHere()
        }
        await settle()
    }

    /// Runs `run.sh` inside Runwright, stopping the service first.
    public func runHere(_ runner: GitHubRunner) async {
        if runner.serviceRunning { await svc(runner, "stop", label: "Stopping the background service") }
        if runner.runningElsewhere { await runner.stopElsewhere(log: append) }
        runner.startHere()
        await settle()
    }

    /// Stops it however it is running. A job it is on is handed back.
    public func stop(_ runner: GitHubRunner) async {
        busy = "Stopping \(runner.name)"
        if runner.serviceRunning && runner.serviceInstalled {
            await svc(runner, "stop", label: "Stopping \(runner.name)")
        } else if runner.process.isRunning {
            await runner.stopHere()
        } else if runner.listenerPID != nil {
            await runner.stopElsewhere(log: append)
        }
        busy = nil
        await refresh()
    }

    public func restart(_ runner: GitHubRunner) async {
        let here = runner.process.isRunning
        await stop(runner)
        busy = "Restarting \(runner.name)"
        if here { runner.startHere() } else { await start(runner) }
        busy = nil
        await settle()
    }

    public func toggle(_ runner: GitHubRunner) async {
        runner.isRunning ? await stop(runner) : await start(runner)
    }

    /// `svc.sh install` and start: a launchd agent that keeps the runner
    /// going after Runwright quits and after a restart.
    public func installService(_ runner: GitHubRunner) async {
        guard runner.folder.hasServiceScript else {
            return fail("\(runner.label) has no svc.sh. Run config.sh there first.")
        }
        if runner.process.isRunning { await runner.stopHere() }
        if runner.runningElsewhere { await runner.stopElsewhere(log: append) }
        await svc(runner, "install", label: "Installing the background service")
        await refresh()
        if runner.serviceInstalled { await svc(runner, "start", label: "Starting \(runner.name)") }
        await settle()
    }

    /// `svc.sh stop` and `uninstall`. The runner stays registered.
    public func uninstallService(_ runner: GitHubRunner) async {
        if runner.serviceRunning { await svc(runner, "stop", label: "Stopping \(runner.name)") }
        await svc(runner, "uninstall", label: "Removing the background service")
        await refresh()
    }

    // MARK: Tools jobs can use

    /// The search path the user's Terminal has; see `TerminalTools`.
    public private(set) var terminalPath: String?
    @ObservationIgnored private var triedTerminalPath = false

    /// What jobs get when the folder saved no search path.
    public static let defaultJobPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    public func jobPath(for runner: GitHubRunner) -> String { runner.folder.jobPath ?? Self.defaultJobPath }

    public func missingTools(for runner: GitHubRunner) -> [String] {
        TerminalTools.missingTools(jobPath: jobPath(for: runner), terminalPath: terminalPath)
    }

    public func loadTerminalPath() async {
        triedTerminalPath = true
        if let path = await TerminalTools.loadTerminalPath() { terminalPath = path }
    }

    /// Saves the Terminal's search path as the runner's `.path` (and `.env`'s
    /// `PATH`, when it sets one). The runner reads them when it starts, so
    /// an idle runner is restarted; a busy one picks it up next time.
    public func useTerminalTools(for runner: GitHubRunner) async {
        if terminalPath == nil { await loadTerminalPath() }
        guard let path = terminalPath else { return fail("Couldn't read your Terminal's search path.") }
        guard write(path, to: ".path", in: runner) else { return fail("Couldn't update \(runner.label)/.path.") }
        let env = runner.root.appendingPathComponent(".env")
        if let text = try? String(contentsOf: env, encoding: .utf8),
           let updated = RunnerFolder.settingEnvPath(in: text, to: path),
           !write(updated, to: ".env", in: runner) {
            return fail("Couldn't update \(runner.label)/.env.")
        }
        append(LogLine(date: .now, source: "config", text: "\(runner.name): jobs now use your Terminal's tools"))
        await refresh()
        if runner.isRunning && !runner.isBusy {
            await restart(runner)
        } else if runner.isRunning {
            append(LogLine(date: .now, source: "config", text: "\(runner.name): takes effect when it next restarts"))
        }
    }

    /// Writes a file in the runner's folder, keeping a backup next to it.
    private func write(_ text: String, to name: String, in runner: GitHubRunner) -> Bool {
        let url = runner.root.appendingPathComponent(name)
        let backup = url.appendingPathExtension("runwright-backup")
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
        }
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
    }

    // MARK: Helpers

    private func svc(_ runner: GitHubRunner, _ verb: String, label: String) async {
        busy = label
        let r = await ProcessRunner.run("/bin/bash", ["svc.sh", verb], timeout: 60, in: runner.root)
        appendOutput(r.output, source: "svc.sh")
        if !r.succeeded { fail("\(label) failed (exit \(r.status)). See the log.") }
        busy = nil
    }

    /// Gives a start a moment to show up in `ps` and launchd.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(800))
        await refresh()
    }

    private func fail(_ message: String) {
        lastError = message
        busy = nil
        append(LogLine(date: .now, source: "Runwright", text: message))
    }

    public func dismissError() { lastError = nil }

    public func clearLog() { log.removeAll() }

    private func appendOutput(_ output: String, source: String) {
        for line in output.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            append(LogLine(date: .now, source: source, text: ManagedProcess.stripANSI(String(line))))
        }
    }

    private func append(_ line: LogLine) {
        log.append(line)
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }

    /// Runners started here stop with the app; services keep going.
    public func shutdown() {
        runners.forEach { $0.stopHereNow() }
    }
}
