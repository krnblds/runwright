import Foundation
import RunwrightCore

/// One point on the sparklines.
public struct HistoryPoint: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var running: Int
    public var jobsTotal: Double
    public var failedTotal: Double
    public var online: Bool
}

/// A running job as the UI shows it: the group it belongs to, plus when this
/// app first saw it start.
public struct RunningJob: Identifiable, Equatable, Sendable {
    public var id: String
    public var runner: String
    public var stage: String
    public var executorStage: String
    public var startedAt: Date
}

/// Compares two snapshots and lists what happened in between.
public enum TransitionDetector {
    public static func events(from old: RunnerSnapshot?, to new: RunnerSnapshot, at date: Date) -> [RunnerEvent] {
        guard let old else { return [] }
        var events: [RunnerEvent] = []
        let oldByKey = counts(old)
        let newByKey = counts(new)
        let groups = Dictionary(new.jobs.map { (lifecycleKey($0), $0) }, uniquingKeysWith: { a, _ in a })
        let oldGroups = Dictionary(old.jobs.map { (lifecycleKey($0), $0) }, uniquingKeysWith: { a, _ in a })

        for (key, count) in newByKey where count > oldByKey[key, default: 0] {
            let g = groups[key]!
            for _ in 0..<(count - oldByKey[key, default: 0]) {
                events.append(.jobStarted(runner: g.runner, stage: g.stage, at: date))
            }
        }
        let finished = max(0, Int(new.jobsTotal - old.jobsTotal))
        let failed = max(0, Int(new.failedTotal - old.failedTotal))
        if finished > 0 {
            // Attribute finishes to groups that shrank, where possible.
            let shrunk = oldByKey.filter { $0.value > newByKey[$0.key, default: 0] }.keys.compactMap { oldGroups[$0] }
            for i in 0..<max(0, finished - failed) {
                let g = shrunk.isEmpty ? nil : shrunk[i % shrunk.count]
                events.append(.jobFinished(runner: g?.runner ?? "runner", stage: g?.stage ?? "", at: date))
            }
        }
        if failed > 0 {
            for (reason, value) in new.failuresByReason {
                let delta = Int(value - old.failuresByReason[reason, default: 0])
                for _ in 0..<max(0, delta) { events.append(.jobFailed(reason: readable(reason), at: date)) }
            }
        }
        return events
    }

    /// The runner reports which step a job is on (`stage`: get_sources,
    /// step_script…) and what the executor is doing (`executor_stage`), and
    /// both change as one job runs. Only the per-runner count says a job
    /// started or ended.
    static func lifecycleKey(_ g: JobGroup) -> String { g.runner }

    /// Plain words for the runner's job steps.
    public static func readableStage(_ stage: String) -> String {
        switch stage {
        case "": "Job"
        case "resolve_secrets": "Resolving secrets"
        case "prepare_executor", "prepare_script": "Preparing"
        case "get_sources", "clear_worktree": "Getting source"
        case "restore_cache": "Restoring cache"
        case "download_artifacts": "Downloading artifacts"
        case "step_script", "build_script": "Running script"
        case "after_script": "Running after-script"
        case "archive_cache", "archive_cache_on_failure": "Saving cache"
        case "upload_artifacts_on_success", "upload_artifacts_on_failure": "Uploading artifacts"
        case "cleanup_file_variables": "Cleaning up"
        default:
            // CI step names like "step_release" or custom stages.
            readable(stage.hasPrefix("step_") ? String(stage.dropFirst(5)) : stage)
        }
    }

    static func counts(_ s: RunnerSnapshot) -> [String: Int] {
        s.jobs.reduce(into: [:]) { $0[lifecycleKey($1), default: 0] += $1.count }
    }

    public static func readable(_ reason: String) -> String {
        reason.replacingOccurrences(of: "_", with: " ").capitalizedFirst
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Holds the live view of the runner: polls the metrics source, keeps 15
/// minutes of history, works out rates and spots transitions.
@MainActor
@Observable
public final class GitLabStore {
    public private(set) var state: ConnectionState = .connecting
    public private(set) var snapshot: RunnerSnapshot?
    public private(set) var history: [HistoryPoint] = []
    public private(set) var events: [RunnerEvent] = []
    public private(set) var runningJobs: [RunningJob] = []
    public private(set) var lastError: String?
    public private(set) var lastUpdated: Date?
    public private(set) var currentInterval: Double = 3

    public var pollInterval: Double = 3 { didSet { currentInterval = pollInterval } }
    public var historyWindow: TimeInterval = 15 * 60
    /// Called for every event, after the store has updated.
    @ObservationIgnored public var onEvent: (@MainActor (RunnerEvent) -> Void)?

    @ObservationIgnored private var source: any MetricsSource
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var jobStarts: [String: [Date]] = [:]
    @ObservationIgnored private var offlineSince: Date?
    @ObservationIgnored private var announcedOffline = false
    @ObservationIgnored private var previousAPIErrors: Double?
    @ObservationIgnored private var previousAPIRequests: Double?
    /// How long the endpoint must be down before "offline" is announced.
    public var offlineGrace: TimeInterval = 30

    public init(source: any MetricsSource) {
        self.source = source
    }

    public func setSource(_ source: any MetricsSource) {
        self.source = source
        reset()
        if loop != nil { restart() }
    }

    public var isPolling: Bool { loop != nil }

    /// The endpoint being polled, when it's a real runner.
    public var sourceURL: URL? { (source as? MetricsClient)?.url }

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                try? await Task.sleep(for: .seconds(self.currentInterval))
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    public func restart() {
        stop()
        currentInterval = pollInterval
        start()
    }

    public func reset() {
        snapshot = nil
        history = []
        events = []
        runningJobs = []
        jobStarts = [:]
        state = .connecting
        offlineSince = nil
        announcedOffline = false
        previousAPIErrors = nil
        previousAPIRequests = nil
        lastError = nil
    }

    // MARK: Derived

    public var capacity: Int? {
        if let c = snapshot?.concurrent, c > 0 { return c }
        let sum = snapshot?.limits.values.reduce(0, +) ?? 0
        return sum > 0 ? sum : nil
    }

    public var busySlots: Int { snapshot?.runningJobs ?? 0 }

    /// Jobs finished per minute over the history window.
    public var jobsPerMinute: Double { rate(\.jobsTotal) * 60 }
    /// Failures per hour over the history window.
    public var failuresPerHour: Double { rate(\.failedTotal) * 3600 }

    private func rate(_ path: KeyPath<HistoryPoint, Double>) -> Double {
        let online = history.filter(\.online)
        guard let first = online.first, let last = online.last, last.date > first.date else { return 0 }
        let delta = max(0, last[keyPath: path] - first[keyPath: path])
        return delta / last.date.timeIntervalSince(first.date)
    }

    /// Failures per minute bucket for the sparkline.
    public var failuresPerMinute: [(date: Date, count: Double)] {
        guard !history.isEmpty else { return [] }
        let now = history.last!.date
        var buckets: [(Date, Double)] = []
        for minute in stride(from: 14, through: 0, by: -1) {
            let end = now.addingTimeInterval(-Double(minute) * 60)
            let start = end.addingTimeInterval(-60)
            let points = history.filter { $0.date > start && $0.date <= end && $0.online }
            let d = (points.last?.failedTotal ?? 0) - (points.first?.failedTotal ?? 0)
            buckets.append((end, max(0, d)))
        }
        return buckets
    }

    // MARK: Polling

    public func poll() async {
        let now = Date.now
        do {
            let text = try await source.fetch()
            let next = SnapshotMapper.snapshot(from: PrometheusParser.parse(text), at: now)
            apply(next, at: now)
        } catch {
            markUnreachable(error, at: now)
        }
    }

    /// Feeds a snapshot in directly (tests, previews).
    public func apply(_ next: RunnerSnapshot, at now: Date) {
        let wasOffline = state == .unreachable
        var newEvents = TransitionDetector.events(from: snapshot, to: next, at: now)
        if wasOffline && announcedOffline { newEvents.insert(.runnerOnline(at: now), at: 0) }
        offlineSince = nil
        announcedOffline = false
        lastError = nil
        currentInterval = pollInterval

        state = degraded(next) ? .degraded : .online
        trackStarts(next, at: now)
        snapshot = next
        lastUpdated = now
        record(HistoryPoint(date: now, running: next.runningJobs, jobsTotal: next.jobsTotal,
                            failedTotal: next.failedTotal, online: true))
        push(newEvents)
    }

    private func markUnreachable(_ error: Error, at now: Date) {
        lastError = describe(error)
        if state != .unreachable { offlineSince = now }
        state = .unreachable
        runningJobs = []
        jobStarts = [:]
        record(HistoryPoint(date: now, running: 0, jobsTotal: history.last?.jobsTotal ?? 0,
                            failedTotal: history.last?.failedTotal ?? 0, online: false))
        if let since = offlineSince, !announcedOffline, now.timeIntervalSince(since) >= offlineGrace {
            announcedOffline = true
            push([.runnerOffline(at: now)])
        }
        // Back off: 3s → 6 → 12 → 24 → 30s.
        currentInterval = min(30, max(pollInterval, currentInterval * 2))
    }

    /// API errors rising since the last poll, and making up a real share of
    /// requests, means the runner cannot talk to GitLab properly.
    private func degraded(_ s: RunnerSnapshot) -> Bool {
        defer {
            previousAPIErrors = s.apiErrorCount
            previousAPIRequests = s.apiRequestCount
        }
        guard let pe = previousAPIErrors, let pr = previousAPIRequests else { return false }
        let errors = s.apiErrorCount - pe
        let requests = s.apiRequestCount - pr
        guard errors > 0, requests > 0 else { return state == .degraded && requests == 0 }
        return errors / requests >= 0.25
    }

    private func trackStarts(_ s: RunnerSnapshot, at now: Date) {
        // One entry per job, grouped by runner, oldest group first.
        var byRunner: [String: [JobGroup]] = [:]
        for g in s.jobs {
            byRunner[TransitionDetector.lifecycleKey(g), default: []] += Array(repeating: g, count: g.count)
        }
        var jobs: [RunningJob] = []
        var starts: [String: [Date]] = [:]
        for (key, groups) in byRunner {
            var dates = jobStarts[key] ?? []
            // First poll: unknown start, so count from now.
            while dates.count < groups.count { dates.append(now) }
            // A job ended: assume the oldest finished first.
            if dates.count > groups.count { dates.removeFirst(dates.count - groups.count) }
            starts[key] = dates
            for (i, (date, group)) in zip(dates, groups).enumerated() {
                jobs.append(RunningJob(id: "\(key)#\(i)", runner: group.runner, stage: group.stage,
                                       executorStage: group.executorStage, startedAt: date))
            }
        }
        jobStarts = starts
        runningJobs = jobs.sorted { $0.startedAt < $1.startedAt }
    }

    private func record(_ point: HistoryPoint) {
        history.append(point)
        let cutoff = point.date.addingTimeInterval(-historyWindow)
        history.removeAll { $0.date < cutoff }
    }

    private func push(_ newEvents: [RunnerEvent]) {
        guard !newEvents.isEmpty else { return }
        events.insert(contentsOf: newEvents.reversed(), at: 0)
        if events.count > 100 { events.removeLast(events.count - 100) }
        newEvents.forEach { onEvent?($0) }
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case MetricsError.badStatus(let code): "The metrics endpoint answered \(code)."
        case MetricsError.unreachable: "Nothing is answering on the metrics address."
        default: error.localizedDescription
        }
    }
}
