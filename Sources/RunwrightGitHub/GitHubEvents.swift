import Foundation
import RunwrightCore

/// What one runner looked like at a refresh, as far as events go.
public struct RunnerObservation: Equatable, Sendable {
    public var runner: String
    public var isOn: Bool
    /// The job it is on, when its log names one.
    public var current: DiagLog.Started?
    /// Jobs its log says finished, oldest first.
    public var finished: [DiagLog.Finished]

    public init(runner: String, isOn: Bool, current: DiagLog.Started?, finished: [DiagLog.Finished]) {
        self.runner = runner
        self.isOn = isOn
        self.current = current
        self.finished = finished
    }
}

/// Turns two looks at a runner into events. The first look only sets a
/// baseline, so starting Runwright doesn't replay old jobs.
public enum GitHubEvents {
    public static func events(from old: RunnerObservation?, to new: RunnerObservation, at date: Date) -> [RunnerEvent] {
        guard let old else { return [] }
        var events: [RunnerEvent] = []
        if old.isOn != new.isOn {
            events.append(new.isOn ? .runnerOnline(at: date) : .runnerOffline(at: date))
        }
        if let job = new.current, job != old.current {
            events.append(.jobStarted(runner: new.runner, stage: job.name, at: job.at))
        }
        // The log is read from its end, so older lines drop out of view;
        // only ones from after what was last seen are new.
        let latest = old.finished.last?.at ?? .distantPast
        for job in new.finished where job.at >= latest && !old.finished.contains(job) {
            if job.failed {
                events.append(.jobFailed(reason: "\(new.runner) · \(job.name)", at: job.at))
            } else {
                let canceled = job.result.lowercased().hasPrefix("cancel")
                events.append(.jobFinished(runner: new.runner, stage: canceled ? "\(job.name) (canceled)" : job.name, at: job.at))
            }
        }
        return events
    }
}
