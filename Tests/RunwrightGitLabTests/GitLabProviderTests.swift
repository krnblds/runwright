import Foundation
import Testing
import RunwrightCore
@testable import RunwrightGitLab

@MainActor
@Suite struct GitLabProviderTests {
    private func fixture(_ name: String) throws -> RunnerSnapshot {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures"))
        return SnapshotMapper.snapshot(from: PrometheusParser.parse(try String(contentsOf: url, encoding: .utf8)))
    }

    @Test func statusCarriesTheMainStoresJobsInPlainWords() throws {
        let provider = GitLabProvider()
        provider.store.apply(try fixture("running"), at: .now)
        let status = provider.status
        #expect(status.connection == .online)
        #expect(status.busySlots == 2)
        #expect(status.runningJobs.count == 2)
        #expect(status.runningJobs.allSatisfy { $0.runner == "kierans-mac" })
        #expect(Set(status.runningJobs.map(\.name)) == ["Build", "Test"])
        #expect(Set(status.runningJobs.map(\.detail)) == ["step script", "prepare executor"])
    }

    @Test func eventsReachTheCallback() throws {
        let provider = GitLabProvider()
        var events: [RunnerEvent] = []
        provider.onEvent = { events.append($0) }
        provider.store.apply(try fixture("idle"), at: .now)
        provider.store.apply(try fixture("running"), at: .now)
        #expect(events.filter { if case .jobStarted = $0 { true } else { false } }.count == 2)
    }

    @Test func homebrewRunnersKeepTheirNameAsTheirID() {
        let runner = RegisteredRunner(name: "kierans-mac", url: "https://gitlab.com", executor: "shell")
        #expect(GitLabProvider.summaryID(runner) == "kierans-mac")
    }
}
