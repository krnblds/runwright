import Foundation
import Testing
@testable import RunwrightCore

@Suite struct ProviderStatusTests {
    private func status(_ connection: ConnectionState, busy: Int = 0, capacity: Int? = nil,
                        events: [RunnerEvent] = [], service: String? = nil, error: String? = nil) -> ProviderStatus {
        var s = ProviderStatus()
        s.connection = connection
        s.busySlots = busy
        s.capacity = capacity
        s.events = events
        s.serviceName = service
        s.lastError = error
        s.version = "17.0.0"
        return s
    }

    @Test func oneStatusComesBackUnchanged() {
        let only = status(.degraded, busy: 2, capacity: 4, service: "GitLab", error: "timeout")
        #expect(ProviderStatus.combined([only]) == only)
        #expect(ProviderStatus.combined([]) == ProviderStatus())
    }

    @Test func troubleAnywhereShowsWithItsService() {
        let combined = ProviderStatus.combined([status(.online), status(.degraded, service: "GitLab")])
        #expect(combined.connection == .degraded)
        #expect(combined.serviceName == "GitLab")
    }

    @Test func oneRunnerUpIsOnline() {
        let combined = ProviderStatus.combined([status(.unreachable, error: "off"), status(.online)])
        #expect(combined.connection == .online)
        #expect(combined.lastError == nil)
        #expect(combined.version == nil)
    }

    @Test func allOffKeepsTheFirstError() {
        let combined = ProviderStatus.combined([status(.unreachable, error: "off"), status(.unreachable)])
        #expect(combined.connection == .unreachable)
        #expect(combined.lastError == "off")
    }

    @Test func slotsAddUpAndCapacityOnlyWhenAllKnow() {
        #expect(ProviderStatus.combined([status(.online, busy: 1, capacity: 2), status(.online, busy: 1, capacity: 1)]).capacity == 3)
        let unknown = ProviderStatus.combined([status(.online, busy: 1, capacity: 2), status(.online, busy: 2)])
        #expect(unknown.capacity == nil)
        #expect(unknown.busySlots == 3)
    }

    @Test func eventsMergeNewestFirst() {
        let old = RunnerEvent.runnerOnline(at: Date(timeIntervalSince1970: 100))
        let new = RunnerEvent.runnerOffline(at: Date(timeIntervalSince1970: 200))
        let middle = RunnerEvent.jobFailed(reason: "x", at: Date(timeIntervalSince1970: 150))
        let combined = ProviderStatus.combined([status(.online, events: [new, old]), status(.online, events: [middle])])
        #expect(combined.events == [new, middle, old])
    }
}

@Suite struct LogTailTests {
    @Test func keepsTheLastWholeLines() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("runwright-tail-\(UUID().uuidString).log")
        try (1...50).map { "line \($0)" }.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        #expect(LogTail.lastLines(of: url, maxLines: 3) == ["line 48", "line 49", "line 50"])
        // Starting mid-file drops the partial first line.
        let tail = try #require(LogTail.lastLines(of: url, maxBytes: 12))
        #expect(tail == ["line 50"])
        #expect(LogTail.lastLines(of: url.appendingPathExtension("missing")) == nil)
    }

    @Test func stripsColourAndBlankLines() {
        #expect(LogTail.lines(in: "\u{1B}[32mok\u{1B}[0m\n\n  \nnext", cutMidway: false, maxLines: 10) == ["ok", "next"])
    }

    @Test func readsLaunchdLogPaths() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("runwright-\(UUID().uuidString).plist")
        let plist: [String: Any] = ["Label": "x", "StandardOutPath": "/tmp/out.log", "StandardErrorPath": "/tmp/err.log"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
        #expect(LogTail.launchdLogs(plist: url).map(\.path) == ["/tmp/out.log", "/tmp/err.log"])
        #expect(LogTail.launchdLogs(plist: url.appendingPathExtension("missing")).isEmpty)
    }
}
