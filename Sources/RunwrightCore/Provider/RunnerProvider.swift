import Foundation
import Observation

/// Which CI provider a runner belongs to. Each provider declares its own
/// value next to its code, so the core never names one.
public struct ProviderID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Something the shared views can ask a provider to do to one runner.
public enum RunnerAction: Hashable, Sendable {
    case start
    case stop
    case restart
    case toggle
    /// Give the runner's jobs the Terminal's search path.
    case useTerminalTools
    /// Turn on the live status the runner reports, so its jobs can be seen.
    case enableLiveStatus
}

/// One runner as the shared views show it, whichever provider it comes from.
public struct RunnerSummary: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// Not running, so not taking jobs.
        case offline
        case idle
        /// Running at least one job.
        case busy
    }

    /// How the runner is being kept going.
    public enum Mode: Equatable, Sendable {
        case off
        /// A background service that keeps going after Runwright quits.
        case service
        /// A child of Runwright, with its output in the log.
        case inApp
        /// Started on its own, apart from the provider's other runners.
        case individual
    }

    /// A job the runner is on.
    public struct Job: Identifiable, Equatable, Sendable {
        public var id: String
        /// The job's name, or the step it is on when the name isn't known.
        public var name: String
        /// The runner taking it.
        public var runner: String
        /// What the runner is doing for it right now, if it says.
        public var detail: String
        public var startedAt: Date

        public init(id: String, name: String, runner: String, detail: String, startedAt: Date) {
            self.id = id
            self.name = name
            self.runner = runner
            self.detail = detail
            self.startedAt = startedAt
        }
    }

    /// Whether the runner's jobs can find the tools the Terminal has.
    public struct Tools: Equatable, Sendable {
        /// Tools the Terminal has that jobs can't find.
        public var missing: [String]
        /// Jobs have been given a search path of their own.
        public var hasJobPath: Bool

        public init(missing: [String], hasJobPath: Bool) {
            self.missing = missing
            self.hasJobPath = hasJobPath
        }
    }

    /// Unique across every provider's summaries.
    public var id: String
    public var provider: ProviderID
    public var name: String
    /// Where the runner is set up when it isn't the provider's main install:
    /// the install's folder, like `~/CI`. Nil for the main install.
    public var location: String?
    /// How it runs jobs and where it takes them from, e.g. "shell · ci.example.com".
    public var detail: String
    public var state: State
    public var runningJobs: [Job]
    public var mode: Mode
    /// What can be done to it right now. Empty while the provider is busy.
    public var actions: Set<RunnerAction>
    /// Nil when its jobs don't run in this Mac's shell, so the Terminal's
    /// tools don't matter.
    public var tools: Tools?

    public init(id: String, provider: ProviderID, name: String, location: String?, detail: String,
                state: State, runningJobs: [Job], mode: Mode, actions: Set<RunnerAction>, tools: Tools?) {
        self.id = id
        self.provider = provider
        self.name = name
        self.location = location
        self.detail = detail
        self.state = state
        self.runningJobs = runningJobs
        self.mode = mode
        self.actions = actions
        self.tools = tools
    }

    public var isOn: Bool { state != .offline }
}

/// How a provider is doing as a whole: what the status header, the menu bar
/// icon and the running-jobs list show. Its jobs can include ones on runners
/// it doesn't list (the demo's, say).
public struct ProviderStatus: Equatable, Sendable {
    public var connection: ConnectionState = .connecting
    /// Why the runner can't be seen, when it can't.
    public var lastError: String?
    /// The version the runner reports.
    public var version: String?
    public var runningJobs: [RunnerSummary.Job] = []
    /// Job slots in use.
    public var busySlots = 0
    /// Job slots in all, when known.
    public var capacity: Int?
    /// Newest first.
    public var events: [RunnerEvent] = []
    /// What the runner talks to, for "Requests to … are failing".
    public var serviceName: String?

    public init() {}

    /// Several providers' statuses as one, for the menu bar icon and the
    /// status header. A single status comes back unchanged.
    public static func combined(_ statuses: [ProviderStatus]) -> ProviderStatus {
        guard statuses.count > 1 else { return statuses.first ?? ProviderStatus() }
        let states = statuses.map(\.connection)
        var status = ProviderStatus()
        // Trouble anywhere shows; otherwise one runner up is enough to be online.
        status.connection = states.contains(.degraded) ? .degraded
            : states.contains(.online) ? .online
            : states.contains(.connecting) ? .connecting
            : .unreachable
        status.serviceName = statuses.first { $0.connection == .degraded }?.serviceName
        status.lastError = status.connection == .unreachable ? statuses.compactMap(\.lastError).first : nil
        // One version can't stand for several providers.
        status.version = nil
        status.runningJobs = statuses.flatMap(\.runningJobs)
        status.busySlots = statuses.map(\.busySlots).reduce(0, +)
        let capacities = statuses.map(\.capacity)
        status.capacity = capacities.contains(nil) ? nil : capacities.compactMap { $0 }.reduce(0, +)
        status.events = statuses.flatMap(\.events).sorted { $0.date > $1.date }
        return status
    }
}

/// A CI provider's runners on this Mac: what they are doing and how to
/// control them, in terms the shared views understand.
@MainActor
public protocol RunnerProvider: AnyObject, Observable {
    var id: ProviderID { get }
    var summaries: [RunnerSummary] { get }
    var status: ProviderStatus { get }
    /// Called for every event, after the provider has updated.
    var onEvent: (@MainActor (RunnerEvent) -> Void)? { get set }
    /// Whether the provider has anything to show: its status counts towards
    /// the app's, and its sections appear. True once it has runners.
    var isSetUp: Bool { get }
    /// Re-reads what is installed and running.
    func refresh() async
    func perform(_ action: RunnerAction, on summaryID: RunnerSummary.ID) async
}

extension RunnerProvider {
    public var isSetUp: Bool { !summaries.isEmpty }
}
