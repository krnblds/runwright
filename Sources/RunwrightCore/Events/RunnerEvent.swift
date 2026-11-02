import Foundation

/// How well Runwright can see the runner right now.
public enum ConnectionState: Equatable, Sendable {
    /// No poll has finished yet.
    case connecting
    case online
    /// The runner answers but its requests to the CI server are failing.
    case degraded
    /// Nothing answering: the runner is stopped or its live status is off.
    case unreachable
}

/// Something that happened to a runner or one of its jobs.
public enum RunnerEvent: Equatable, Sendable, Identifiable {
    case jobStarted(runner: String, stage: String, at: Date)
    case jobFinished(runner: String, stage: String, at: Date)
    case jobFailed(reason: String, at: Date)
    case runnerOffline(at: Date)
    case runnerOnline(at: Date)

    public var id: String { "\(title)-\(date.timeIntervalSince1970)-\(detail)" }

    public var date: Date {
        switch self {
        case .jobStarted(_, _, let d), .jobFinished(_, _, let d), .jobFailed(_, let d),
             .runnerOffline(let d), .runnerOnline(let d): d
        }
    }

    public var title: String {
        switch self {
        case .jobStarted: "Job started"
        case .jobFinished: "Job finished"
        case .jobFailed: "Job failed"
        case .runnerOffline: "Runner went offline"
        case .runnerOnline: "Runner is online"
        }
    }

    public var detail: String {
        switch self {
        case .jobStarted(let r, let s, _), .jobFinished(let r, let s, _): s.isEmpty ? r : "\(r) · \(s)"
        case .jobFailed(let reason, _): reason
        case .runnerOffline, .runnerOnline: ""
        }
    }
}
