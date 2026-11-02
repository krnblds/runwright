import Foundation
import RunwrightCore

/// Jobs that share a runner, state, stage and executor stage. The metrics
/// endpoint reports a count per combination, not one line per job.
public struct JobGroup: Equatable, Hashable, Sendable, Identifiable {
    public var runner: String
    public var state: String
    public var stage: String
    public var executorStage: String
    public var count: Int

    public var id: String { key }
    /// Identity of the group without its count, used to track starts and stops.
    public var key: String { "\(runner)|\(state)|\(stage)|\(executorStage)" }

    public init(runner: String, state: String, stage: String, executorStage: String, count: Int) {
        self.runner = runner
        self.state = state
        self.stage = stage
        self.executorStage = executorStage
        self.count = count
    }
}

public struct HistogramBucket: Equatable, Sendable {
    public var upperBound: Double
    public var cumulativeCount: Double
}

public struct DurationHistogram: Equatable, Sendable {
    public var buckets: [HistogramBucket] = []
    public var sum: Double = 0
    public var count: Double = 0

    public init() {}

    public var average: Double? { count > 0 ? sum / count : nil }

    /// Count per bucket (not cumulative), paired with a readable label.
    public var distribution: [(label: String, count: Double)] {
        var previous = 0.0
        return buckets.map { bucket in
            defer { previous = bucket.cumulativeCount }
            return (Self.label(bucket.upperBound), max(0, bucket.cumulativeCount - previous))
        }
    }

    static func label(_ seconds: Double) -> String {
        if seconds.isInfinite { return "more" }
        if seconds < 60 { return "≤\(Int(seconds))s" }
        if seconds < 3600 { return "≤\(Int(seconds / 60))m" }
        return "≤\(Int(seconds / 3600))h"
    }
}

/// Everything one scrape of `/metrics` says about the runner.
public struct RunnerSnapshot: Equatable, Sendable {
    public var takenAt: Date
    public var version: String?
    public var revision: String?
    public var architecture: String?
    public var os: String?
    public var concurrent: Int?
    public var limits: [String: Int] = [:]
    public var jobs: [JobGroup] = []
    public var jobsTotal: Double = 0
    public var failedTotal: Double = 0
    public var failuresByReason: [String: Double] = [:]
    public var errorsByLevel: [String: Double] = [:]
    /// Request counts keyed by "endpoint status".
    public var apiStatuses: [String: Double] = [:]
    public var duration = DurationHistogram()

    public init(takenAt: Date = .now) {
        self.takenAt = takenAt
    }

    /// Jobs actually holding a slot.
    public var runningJobs: Int { jobs.reduce(0) { $0 + $1.count } }

    /// Requests to GitLab that came back 4xx/5xx (or 0 for a network failure).
    public var apiErrorCount: Double {
        apiStatuses.reduce(0) { total, entry in
            let status = Int(entry.key.split(separator: " ").last ?? "") ?? 0
            return status >= 400 || status == 0 ? total + entry.value : total
        }
    }

    public var apiRequestCount: Double { apiStatuses.values.reduce(0, +) }

    public var errorCount: Double { errorsByLevel["error", default: 0] + errorsByLevel["fatal", default: 0] }
    public var warningCount: Double { errorsByLevel["warning", default: 0] }
}
