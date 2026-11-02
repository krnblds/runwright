import Foundation
import Testing
import RunwrightCore
@testable import RunwrightGitLab

private func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

private func snapshot(_ name: String, at date: Date = .now) throws -> RunnerSnapshot {
    SnapshotMapper.snapshot(from: PrometheusParser.parse(try fixture(name)), at: date)
}

/// Serves canned responses, then fails like a stopped runner.
private final class ScriptedSource: MetricsSource, @unchecked Sendable {
    var responses: [String?]
    init(_ responses: [String?]) { self.responses = responses }
    func fetch() async throws -> String {
        guard !responses.isEmpty, let next = responses.removeFirst() else {
            throw MetricsError.unreachable("connection refused")
        }
        return next
    }
}

@Suite struct ParserTests {
    @Test func skipsCommentsAndReadsLabels() {
        let samples = PrometheusParser.parse("""
        # HELP x help
        # TYPE x counter
        x{a="1",b="two"} 3
        y 4.5 1712345678000
        """)
        #expect(samples == [
            Sample(name: "x", labels: ["a": "1", "b": "two"], value: 3),
            Sample(name: "y", value: 4.5),
        ])
    }

    @Test func handlesEscapesAndSpecialValues() {
        let samples = PrometheusParser.parse(#"""
        m{path="C:\\dir",msg="say \"hi\"\nbye"} NaN
        b{le="+Inf"} +Inf
        c -Inf
        """#)
        #expect(samples.count == 3)
        #expect(samples[0].labels["path"] == #"C:\dir"#)
        #expect(samples[0].labels["msg"] == "say \"hi\"\nbye")
        #expect(samples[0].value.isNaN)
        #expect(samples[1].value == .infinity)
        #expect(samples[2].value == -.infinity)
    }

    @Test func dropsBrokenLinesOnly() {
        let samples = PrometheusParser.parse("""
        good 1
        broken{a="1 2
        nolabelvalue{a=} 3
        alsogood{x="y"} 2
        """)
        #expect(samples.map(\.name) == ["good", "alsogood"])
    }
}

@Suite struct MapperTests {
    @Test func idle() throws {
        let s = try snapshot("idle")
        #expect(s.version == "19.5.2")
        #expect(s.architecture == "arm64")
        #expect(s.concurrent == 4)
        #expect(s.runningJobs == 0)
        #expect(s.jobsTotal == 12)
        #expect(s.failedTotal == 0)
        #expect(s.failuresByReason.isEmpty)
        #expect(s.warningCount == 2)
        #expect(s.errorCount == 0)
        #expect(s.apiErrorCount == 0)
        #expect(s.duration.count == 12)
        #expect(s.duration.average == 840.5 / 12)
        #expect(s.duration.distribution.map(\.count) == [2, 5, 5, 0])
    }

    @Test func runningJobs() throws {
        let s = try snapshot("running")
        #expect(s.runningJobs == 2)
        #expect(Set(s.jobs.map(\.stage)) == ["build", "test"])
        #expect(s.jobs.allSatisfy { $0.runner == "kierans-mac" && $0.state == "running" })
    }

    @Test func failures() throws {
        let s = try snapshot("failures")
        #expect(s.failedTotal == 2)
        #expect(s.failuresByReason == ["script_failure": 2])
        #expect(s.errorCount == 1)
        #expect(s.apiErrorCount == 9)
    }
}

@Suite struct TransitionTests {
    @Test func startAndFinish() throws {
        let t0 = Date(timeIntervalSince1970: 0)
        let idle = try snapshot("idle", at: t0)
        let running = try snapshot("running", at: t0.addingTimeInterval(3))
        let started = TransitionDetector.events(from: idle, to: running, at: running.takenAt)
        #expect(started.count == 2)
        #expect(started.allSatisfy { if case .jobStarted = $0 { true } else { false } })

        let failed = try snapshot("failures", at: t0.addingTimeInterval(6))
        let after = TransitionDetector.events(from: running, to: failed, at: failed.takenAt)
        // 2 finished, both failed by script failure.
        #expect(after.filter { if case .jobFailed = $0 { true } else { false } }.count == 2)
        #expect(after.filter { if case .jobFinished = $0 { true } else { false } }.isEmpty)
    }

    @Test func movingThroughStepsIsNotANewJob() {
        var a = RunnerSnapshot()
        a.jobs = [JobGroup(runner: "r", state: "running", stage: "get_sources", executorStage: "prepare", count: 1)]
        var b = a
        b.jobs[0].stage = "step_script"
        b.jobs[0].executorStage = "build"
        #expect(TransitionDetector.events(from: a, to: b, at: .now).isEmpty)

        var c = b
        c.jobs.append(JobGroup(runner: "r", state: "running", stage: "prepare_script", executorStage: "prepare", count: 1))
        #expect(TransitionDetector.events(from: b, to: c, at: .now).count == 1)
    }

    @Test func readableStages() {
        #expect(TransitionDetector.readableStage("step_script") == "Running script")
        #expect(TransitionDetector.readableStage("get_sources") == "Getting source")
        #expect(TransitionDetector.readableStage("step_release") == "Release")
    }
}

@Suite @MainActor struct StoreTests {
    @Test func goesOnlineThenOfflineAndBacksOff() async throws {
        let source = ScriptedSource([try fixture("idle"), try fixture("running"), nil, nil, nil])
        let store = GitLabStore(source: source)
        store.offlineGrace = 0
        var seen: [RunnerEvent] = []
        store.onEvent = { seen.append($0) }

        await store.poll()
        #expect(store.state == .online)
        #expect(store.capacity == 4)

        await store.poll()
        #expect(store.busySlots == 2)
        #expect(store.runningJobs.count == 2)

        await store.poll()
        #expect(store.state == .unreachable)
        #expect(store.runningJobs.isEmpty)
        #expect(seen.contains { if case .runnerOffline = $0 { true } else { false } })
        #expect(store.currentInterval == 6)
        await store.poll()
        await store.poll()
        #expect(store.currentInterval == 24)
    }

    @Test func comesBackOnline() async throws {
        let source = ScriptedSource([nil, try fixture("idle")])
        let store = GitLabStore(source: source)
        store.offlineGrace = 0
        var seen: [RunnerEvent] = []
        store.onEvent = { seen.append($0) }
        await store.poll()
        await store.poll()
        #expect(store.state == .online)
        #expect(store.currentInterval == 3)
        #expect(seen.last.map { if case .runnerOnline = $0 { true } else { false } } == true)
    }

    @Test func degradedWhenAPIErrorsRise() async throws {
        let store = GitLabStore(source: ScriptedSource([]))
        let idle = try snapshot("idle")
        store.apply(idle, at: .now)
        var worse = idle
        worse.apiStatuses["update_job 500"] = 20
        worse.apiStatuses["request_job 204"]! += 5
        store.apply(worse, at: .now)
        #expect(store.state == .degraded)
    }

    @Test func demoSourceParses() async throws {
        let store = GitLabStore(source: DemoMetricsSource())
        await store.poll()
        #expect(store.state == .online)
        #expect(store.snapshot?.version == "19.5.2")
        #expect(store.capacity == 4)
    }
}

@Suite struct ConfigTests {
    let sample = """
    concurrent = 4
    check_interval = 0

    [session_server]
      session_timeout = 1800

    [[runners]]
      name = "kierans-mac"
      url = "https://gitlab.com"
      id = 123
      token = "glrt-secret" # never read
      executor = "shell"
      [runners.cache]
        MaxUploadedArchiveSize = 0

    [[runners]]
      name = "docker # one"
      url = "https://gitlab.example.com/"
      executor = "docker"
      limit = 2
      [runners.docker]
        image = "alpine:latest"
    """

    @Test func readsRunners() {
        let c = RunnerConfig.parse(sample)
        #expect(c.concurrent == 4)
        #expect(c.listenAddress == nil)
        #expect(c.runners.map(\.name) == ["kierans-mac", "docker # one"])
        #expect(c.runners[1].executor == "docker")
        #expect(c.runners[1].limit == 2)
    }

    @Test func enablesMetricsAtTopLevel() {
        let updated = RunnerConfig.enablingMetrics(in: sample)
        let c = RunnerConfig.parse(updated)
        #expect(c.listenAddress == "127.0.0.1:9252")
        #expect(c.runners.count == 2)
        // Idempotent: replaces rather than duplicates.
        let twice = RunnerConfig.enablingMetrics(in: updated, address: "127.0.0.1:9999")
        #expect(twice.components(separatedBy: "listen_address").count == 2)
        #expect(RunnerConfig.parse(twice).listenAddress == "127.0.0.1:9999")
    }

    @Test func metricsURLParsing() {
        #expect(MetricsClient.url(from: "127.0.0.1:9252")?.absoluteString == "http://127.0.0.1:9252/metrics")
        #expect(MetricsClient.url(from: "http://localhost:9252/metrics")?.absoluteString == "http://localhost:9252/metrics")
        #expect(MetricsClient.url(from: "  ") == nil)
    }
}

@Suite struct JobPathTests {
    let config = """
    concurrent = 1

    [[runners]]
      name = "Kieran’s MacBook Pro"
      url = "https://gitlab.com"
      executor = "shell"
      [runners.cache]
        MaxUploadedArchiveSize = 0

    [[runners]]
      name = "other"
      executor = "shell"
      environment = [
        "LANG=en_US.UTF-8",
        "PATH=/usr/bin",
      ]
    """

    @Test func addsPathToTheRightRunner() throws {
        let out = try #require(RunnerConfig.settingJobPath(in: config, runner: "Kieran’s MacBook Pro", path: "/a:/b"))
        let c = RunnerConfig.parse(out)
        #expect(c.runners[0].jobPath == "/a:/b")
        #expect(c.runners[1].jobPath == "/usr/bin")
        // Inserted before the runner's sub-table, not inside it.
        let lines = out.components(separatedBy: "\n")
        let env = try #require(lines.firstIndex { $0.contains("PATH=/a:/b") })
        let cache = try #require(lines.firstIndex { $0.contains("[runners.cache]") })
        #expect(env < cache)
    }

    @Test func replacesPathAndKeepsOtherEntries() throws {
        let out = try #require(RunnerConfig.settingJobPath(in: config, runner: "other", path: "/x"))
        let c = RunnerConfig.parse(out)
        #expect(c.runners[1].environment == ["PATH=/x", "LANG=en_US.UTF-8"])
        #expect(c.runners[0].environment.isEmpty)
        #expect(RunnerConfig.settingJobPath(in: config, runner: "missing", path: "/x") == nil)
    }

    @Test func dedupesPath() {
        #expect(TerminalTools.dedupe("/a:/b::/a:/c") == "/a:/b:/c")
    }
}

@Suite struct ScannerTests {
    @Test func findsRunProcessesAndTheirConfigs() {
        let ps = """
          45371 /Users/k/CI/gitlab-runner run --config /Users/k/CI/config.toml
          60994 /opt/homebrew/opt/gitlab-runner/bin/gitlab-runner run --syslog
          61000 /opt/homebrew/bin/gitlab-runner run-single --config /x --runner a
          61001 /usr/bin/grep gitlab-runner run
          61002 /opt/homebrew/bin/gitlab-runner run -c /tmp/other.toml --working-directory /tmp
        """
        let found = RunnerProcessScanner.parse(ps)
        #expect(found.map(\.pid) == [45371, 60994, 61002])
        #expect(found[0].config == "/Users/k/CI/config.toml")
        #expect(found[1].config == nil)
        #expect(found[2].config == "/tmp/other.toml")
    }
}
