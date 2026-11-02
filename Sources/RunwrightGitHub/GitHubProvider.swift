import Foundation
import Observation
import RunwrightCore

extension ProviderID {
    public static let github = ProviderID(rawValue: "github")
}

/// GitHub Actions self-hosted runners on this Mac as a `RunnerProvider`.
/// Local only: what the runner folders, their logs and their processes say,
/// with no GitHub API and no tokens.
@MainActor
@Observable
public final class GitHubProvider: RunnerProvider {
    public let id = ProviderID.github
    public let control: GitHubControl
    /// Newest first.
    public private(set) var events: [RunnerEvent] = []
    @ObservationIgnored public var onEvent: (@MainActor (RunnerEvent) -> Void)?
    @ObservationIgnored private var observations: [GitHubRunner.ID: RunnerObservation] = [:]

    public init(control: GitHubControl = GitHubControl()) {
        self.control = control
    }

    // MARK: RunnerProvider

    public var isSetUp: Bool { !control.runners.isEmpty }

    public func refresh() async {
        await control.refresh()
        detectEvents()
    }

    /// Runs `work` against the control, then catches up with what it changed.
    public func perform(_ work: @MainActor (GitHubControl) async -> Void) async {
        await work(control)
        detectEvents()
    }

    public func perform(_ action: RunnerAction, on summaryID: RunnerSummary.ID) async {
        guard let runner = runner(for: summaryID) else { return }
        await perform { control in
            switch action {
            case .start: await control.start(runner)
            case .stop: await control.stop(runner)
            case .restart: await control.restart(runner)
            case .toggle: await control.toggle(runner)
            case .useTerminalTools: await control.useTerminalTools(for: runner)
            // The runner's own logs are its live status; nothing to turn on.
            case .enableLiveStatus: break
            }
        }
    }

    public static func summaryID(_ runner: GitHubRunner) -> RunnerSummary.ID { "github|\(runner.id)" }

    public func runner(for summaryID: RunnerSummary.ID) -> GitHubRunner? {
        control.runners.first { Self.summaryID($0) == summaryID }
    }

    public var summaries: [RunnerSummary] {
        control.runners.map { runner in
            let on = runner.isRunning
            let jobs = runner.currentJob.map { [$0] } ?? []
            let missing = control.missingTools(for: runner)
            var actions: Set<RunnerAction> = on ? [.stop, .restart, .toggle] : [.start, .toggle]
            if !missing.isEmpty { actions.insert(.useTerminalTools) }
            return RunnerSummary(
                id: Self.summaryID(runner),
                provider: id,
                name: runner.name,
                location: runner.label,
                detail: Self.detail(runner.registration),
                state: !on ? .offline : jobs.isEmpty ? .idle : .busy,
                runningJobs: jobs,
                mode: runner.mode,
                // Nothing can be started or stopped while the control is busy.
                actions: control.busy == nil ? actions : [],
                // Jobs on a self-hosted Mac runner always run in its shell.
                tools: RunnerSummary.Tools(missing: missing, hasJobPath: runner.folder.jobPath != nil)
            )
        }
    }

    public var status: ProviderStatus {
        var status = ProviderStatus()
        let on = control.runners.filter(\.isRunning)
        if !control.hasLooked {
            status.connection = .connecting
        } else if on.isEmpty {
            status.connection = .unreachable
            status.lastError = control.runners.isEmpty ? "No GitHub Actions runner on this Mac" : "No GitHub Actions runner is running"
        } else {
            status.connection = .online
        }
        status.runningJobs = control.runners.compactMap(\.currentJob)
        status.busySlots = status.runningJobs.count
        // A runner takes one job at a time.
        status.capacity = on.count
        status.events = events
        status.serviceName = "GitHub"
        return status
    }

    /// "owner/repo", with the host when it isn't github.com.
    nonisolated static func detail(_ registration: RunnerRegistration?) -> String {
        guard let registration else { return "" }
        let host = registration.host.flatMap { $0 == "github.com" ? nil : $0 }
        return [registration.scope, host].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Events

    private func detectEvents() {
        let now = Date.now
        var next: [GitHubRunner.ID: RunnerObservation] = [:]
        var fresh: [RunnerEvent] = []
        for runner in control.runners {
            let observation = RunnerObservation(runner: runner.name, isOn: runner.isRunning,
                                                current: runner.isBusy ? runner.folder.activity.current : nil,
                                                finished: runner.folder.activity.finished)
            fresh += GitHubEvents.events(from: observations[runner.id], to: observation, at: now)
            next[runner.id] = observation
        }
        observations = next
        record(fresh)
    }

    func record(_ fresh: [RunnerEvent]) {
        guard !fresh.isEmpty else { return }
        let sorted = fresh.sorted { $0.date < $1.date }
        events.insert(contentsOf: sorted.reversed(), at: 0)
        if events.count > 100 { events.removeLast(events.count - 100) }
        sorted.forEach { onEvent?($0) }
    }
}
