import Foundation
import RunwrightCore

/// One GitHub Actions runner folder on this Mac and how it is running:
/// as a launchd service (`svc.sh`), as `run.sh` inside Runwright, or as a
/// `run.sh` started somewhere else, like a Terminal tab.
@MainActor
@Observable
public final class GitHubRunner: Identifiable {
    public let root: URL
    public private(set) var folder: RunnerFolder
    /// The listener's process, however it was started.
    public private(set) var listenerPID: Int32?
    public private(set) var listenerAsService = false
    /// A worker is running, so the runner is on a job.
    public private(set) var workerRunning = false
    /// The launchd job, while it is loaded.
    public private(set) var service: LaunchdList.Job?
    /// `run.sh` as a child of Runwright.
    public private(set) var process: ManagedProcess!
    /// When the current worker was first seen, for a job the log hasn't named yet.
    @ObservationIgnored private var workerSeenAt: Date?

    public nonisolated var id: String { root.path }

    init(folder: RunnerFolder, log: @escaping @MainActor (LogLine) -> Void) {
        self.root = folder.root
        self.folder = folder
        self.process = ManagedProcess(name: folder.registration?.name ?? folder.root.lastPathComponent, onLine: log)
    }

    func update(folder: RunnerFolder, processes: [ActionsProcessScanner.Found], launchd: [String: LaunchdList.Job]) {
        self.folder = folder
        let mine = processes.filter { URL(fileURLWithPath: $0.root).standardizedFileURL.path == root.standardizedFileURL.path }
        let listener = mine.first { $0.kind == .listener }
        listenerPID = listener?.pid
        listenerAsService = listener?.asService ?? false
        let working = mine.contains { $0.kind == .worker }
        if working && workerSeenAt == nil { workerSeenAt = .now }
        if !working { workerSeenAt = nil }
        workerRunning = working
        service = folder.serviceLabel.flatMap { launchd[$0] }
    }

    // MARK: State

    public var name: String { folder.registration?.name ?? root.lastPathComponent }
    public var label: String { folder.label }
    public var registration: RunnerRegistration? { folder.registration }

    /// `svc.sh install` has been run.
    public var serviceInstalled: Bool { folder.servicePlist != nil }
    public var serviceRunning: Bool { service?.pid != nil || (listenerPID != nil && listenerAsService) }
    public var isRunning: Bool { serviceRunning || process.isRunning || listenerPID != nil }
    /// Running from a `run.sh` Runwright didn't start.
    public var runningElsewhere: Bool { listenerPID != nil && !serviceRunning && !process.isRunning }

    public var mode: RunnerSummary.Mode {
        if serviceRunning { return .service }
        if process.isRunning { return .inApp }
        if listenerPID != nil { return .individual }
        return .off
    }

    /// Where the background service writes its output (`stdout.log`,
    /// `stderr.log` under `~/Library/Logs/<service>`).
    public var serviceLogs: [URL] {
        if let plist = folder.servicePlist {
            let logs = LogTail.launchdLogs(plist: URL(fileURLWithPath: plist))
            if !logs.isEmpty { return logs }
        }
        guard let label = folder.serviceLabel else { return [] }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/\(label)")
        return [dir.appendingPathComponent("stdout.log"), dir.appendingPathComponent("stderr.log")]
    }

    /// The newest of the runner's own diagnostic logs: `Runner_` for the
    /// listener, `Worker_` for the job it's on.
    public func diagLog(_ prefix: String) -> URL? {
        let diag = root.appendingPathComponent("_diag")
        return prefix == "Runner_" ? DiagLog.newestListenerLog(in: diag) : DiagLog.newestLog(prefix, in: diag)
    }

    public var isBusy: Bool { isRunning && (workerRunning || folder.activity.current != nil) }

    /// The job it is on, named from its log.
    public var currentJob: RunnerSummary.Job? {
        guard isBusy else { return nil }
        let started = folder.activity.current
        let name = started?.name ?? "Job"
        let startedAt = started?.at ?? workerSeenAt ?? .now
        return RunnerSummary.Job(id: "\(id)|\(name)|\(Int(startedAt.timeIntervalSince1970))", name: name,
                                 runner: self.name, detail: workerRunning ? folder.currentStep ?? "" : "",
                                 startedAt: startedAt)
    }

    // MARK: Running here

    func startHere() {
        process.start("/bin/bash", [root.appendingPathComponent("run.sh").path], in: root)
    }

    /// Ctrl-C to the listener first, the way `run.sh` is meant to be stopped,
    /// so it can hand back a job; then the script itself.
    func stopHere() async {
        if let pid = listenerPID { kill(pid, SIGINT) }
        for _ in 0..<80 where listenerPID.map({ kill($0, 0) == 0 }) ?? false {
            try? await Task.sleep(for: .milliseconds(100))
        }
        process.stop()
        for _ in 0..<100 where process.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        listenerPID = nil
    }

    /// Stops a `run.sh` started outside Runwright.
    func stopElsewhere(log: (LogLine) -> Void) async {
        guard let pid = listenerPID else { return }
        kill(pid, SIGINT)
        log(LogLine(date: .now, source: name, text: "Asked process \(pid) to stop"))
        for _ in 0..<80 where kill(pid, 0) == 0 {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        listenerPID = nil
    }

    /// For quitting: no waiting.
    func stopHereNow() {
        guard process.isRunning else { return }
        if let pid = listenerPID { kill(pid, SIGINT) }
        process.stop()
    }
}
