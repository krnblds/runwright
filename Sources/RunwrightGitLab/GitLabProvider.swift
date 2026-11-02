import Foundation
import Observation
import RunwrightCore

extension ProviderID {
    public static let gitlab = ProviderID(rawValue: "gitlab")
}

/// gitlab-runner as a `RunnerProvider`: the Homebrew runner's control and
/// live status, plus installs outside Homebrew (like `~/CI`) and their live
/// status, mapped into `RunnerSummary` values.
@MainActor
@Observable
public final class GitLabProvider: RunnerProvider {
    public let id = ProviderID.gitlab
    public let control: GitLabControl
    /// Live status for the Homebrew runner (or the demo).
    public let store: GitLabStore
    /// Live status for runners outside Homebrew that have metrics on, keyed
    /// by install id.
    public private(set) var otherStores: [String: GitLabStore] = [:]
    @ObservationIgnored public var onEvent: (@MainActor (RunnerEvent) -> Void)?

    public init(control: GitLabControl = GitLabControl()) {
        self.control = control
        self.store = GitLabStore(source: DemoMetricsSource())
        store.onEvent = { [weak self] event in self?.onEvent?(event) }
    }

    public func store(for install: OtherInstall) -> GitLabStore? { otherStores[install.id] }

    // MARK: Settings

    /// Points the live status at the metrics address, or at the demo.
    public func apply(metricsAddress: String, pollInterval: Double, demo: Bool) {
        store.pollInterval = pollInterval
        control.metricsAddress = metricsAddress
        store.setSource(Self.source(metricsAddress: metricsAddress, demo: demo))
    }

    private static func source(metricsAddress: String, demo: Bool) -> any MetricsSource {
        if demo { return DemoMetricsSource() }
        let url = MetricsClient.url(from: metricsAddress) ?? URL(string: "http://127.0.0.1:9252/metrics")!
        return MetricsClient(url: url)
    }

    // MARK: RunnerProvider

    /// GitLab always shows: its setup steps and the demo stand in for runners.
    public var isSetUp: Bool { true }

    public func refresh() async {
        await control.refresh()
        syncOtherStores()
    }

    /// Runs `work` against the control, then catches up with what it changed.
    public func perform(_ work: @MainActor (GitLabControl) async -> Void) async {
        await work(control)
        await control.refresh()
        syncOtherStores()
        await store.poll()
    }

    public func perform(_ action: RunnerAction, on summaryID: RunnerSummary.ID) async {
        guard let (runner, install) = runner(for: summaryID) else { return }
        await perform { control in
            if let install {
                switch action {
                case .start: await control.start(install)
                case .stop: await control.stop(install)
                case .restart: await control.restart(install)
                case .toggle: install.isRunning ? await control.stop(install) : await control.start(install)
                case .useTerminalTools: await control.useTerminalTools(for: runner, in: install)
                case .enableLiveStatus: await control.enableMetrics(in: install)
                }
            } else {
                switch action {
                case .start: await control.start(runner)
                case .stop: await control.stop(runner)
                case .restart: await control.restartService()
                case .toggle: await control.toggle(runner)
                case .useTerminalTools: await control.useTerminalTools(for: runner)
                case .enableLiveStatus: await control.enableMetrics()
                }
            }
        }
    }

    /// The registered runner behind a summary, and its install when it is
    /// outside Homebrew.
    public func runner(for summaryID: RunnerSummary.ID) -> (runner: RegisteredRunner, install: OtherInstall?)? {
        if let runner = control.registeredRunners.first(where: { Self.summaryID($0) == summaryID }) {
            return (runner, nil)
        }
        for install in control.others {
            if let runner = install.runners.first(where: { Self.summaryID($0, in: install) == summaryID }) {
                return (runner, install)
            }
        }
        return nil
    }

    /// The Homebrew runner's id is its name, as it always was in stored
    /// window state; runners elsewhere add their install's id.
    public static func summaryID(_ runner: RegisteredRunner, in install: OtherInstall? = nil) -> RunnerSummary.ID {
        install.map { "\($0.id)|\(runner.name)" } ?? runner.name
    }

    public var summaries: [RunnerSummary] {
        let main = control.registeredRunners.map { runner in
            let on = control.isRunning(runner)
            var actions: Set<RunnerAction> = on ? [.stop, .toggle] : [.start, .toggle]
            if control.serviceRunning { actions.insert(.restart) }
            if !control.metricsEnabled { actions.insert(.enableLiveStatus) }
            return summary(runner, location: nil, on: on, mode: control.mode,
                           jobs: store.runningJobs, actions: actions)
        }
        let others = control.others.flatMap { install in
            install.runners.map { runner in
                let on = install.isRunning
                var actions: Set<RunnerAction> = on ? [.stop, .restart, .toggle] : [.start, .toggle]
                if install.metricsAddress == nil { actions.insert(.enableLiveStatus) }
                let mode: RunnerSummary.Mode = install.process.isRunning ? .inApp : on ? .service : .off
                return summary(runner, in: install, location: install.label, on: on, mode: mode,
                               jobs: store(for: install)?.runningJobs ?? [], actions: actions)
            }
        }
        return main + others
    }

    public var status: ProviderStatus {
        var status = ProviderStatus()
        status.connection = store.state
        status.lastError = store.lastError
        status.version = store.snapshot?.version
        status.runningJobs = store.runningJobs.map(Self.job)
        status.busySlots = store.busySlots
        status.capacity = store.capacity
        status.events = store.events
        status.serviceName = "GitLab"
        return status
    }

    // MARK: Mapping

    private func summary(_ runner: RegisteredRunner, in install: OtherInstall? = nil, location: String?, on: Bool,
                         mode: RunnerSummary.Mode, jobs: [RunningJob], actions: Set<RunnerAction>) -> RunnerSummary {
        let jobs = jobs.filter { $0.runner == runner.name }.map(Self.job)
        let shell = runner.executor == "shell"
        let missing = shell ? control.missingTools(for: runner) : []
        var actions = actions
        if !missing.isEmpty { actions.insert(.useTerminalTools) }
        return RunnerSummary(
            id: Self.summaryID(runner, in: install),
            provider: id,
            name: runner.name,
            location: location,
            detail: [runner.executor, URL(string: runner.url)?.host()].compactMap { $0 }.filter { !$0.isEmpty }
                .joined(separator: " · "),
            state: !on ? .offline : jobs.isEmpty ? .idle : .busy,
            runningJobs: jobs,
            mode: mode,
            // Nothing can be started or stopped while the control is busy.
            actions: control.busy == nil ? actions : [],
            tools: shell ? RunnerSummary.Tools(missing: missing, hasJobPath: runner.jobPath != nil) : nil
        )
    }

    private static func job(_ job: RunningJob) -> RunnerSummary.Job {
        RunnerSummary.Job(id: job.id, name: TransitionDetector.readableStage(job.stage), runner: job.runner,
                          detail: job.executorStage.replacingOccurrences(of: "_", with: " "), startedAt: job.startedAt)
    }

    // MARK: Other installs

    private func syncOtherStores() {
        var next: [String: GitLabStore] = [:]
        for install in control.others {
            guard let address = install.metricsAddress, let url = MetricsClient.url(from: address) else { continue }
            if let existing = otherStores[install.id], existing.sourceURL == url {
                next[install.id] = existing
            } else {
                otherStores[install.id]?.stop()
                let store = GitLabStore(source: MetricsClient(url: url))
                store.pollInterval = self.store.pollInterval
                store.onEvent = { [weak self] event in self?.onEvent?(event) }
                store.start()
                next[install.id] = store
            }
        }
        for (id, store) in otherStores where next[id] == nil { store.stop() }
        otherStores = next
    }
}
