import Foundation
import Testing
import RunwrightCore
@testable import RunwrightGitHub

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func fixtureText(_ name: String) throws -> String {
    String(decoding: try fixture(name), as: UTF8.self)
}

private func utc(_ text: String) -> Date { DiagLog.date(text)! }

/// A runner folder as config.sh leaves it, with the fixture logs in `_diag`.
private func runnerFolder(in home: URL, named name: String = "actions-runner") throws -> URL {
    let fm = FileManager.default
    let root = home.appendingPathComponent(name)
    try fm.createDirectory(at: root.appendingPathComponent("_diag"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
    try fixture("runner.json").write(to: root.appendingPathComponent(".runner"))
    for log in ["Runner_20261102-091100-utc.log", "Worker_20261102-092012-utc.log"] {
        try fixture(log).write(to: root.appendingPathComponent("_diag/\(log)"))
    }
    // An older log that must not win over the newer one.
    try "[2026-11-01 08:00:00Z INFO Terminal] WRITE LINE: 2026-11-01 08:00:00Z: Running job: old\n"
        .write(to: root.appendingPathComponent("_diag/Runner_20261101-080000-utc.log"), atomically: true, encoding: .utf8)
    try "/usr/bin:/bin\n".write(to: root.appendingPathComponent(".path"), atomically: true, encoding: .utf8)
    try "LANG=en_GB.UTF-8\n".write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
    try "#!/bin/bash\n".write(to: root.appendingPathComponent("svc.sh"), atomically: true, encoding: .utf8)
    try "/Users/kieran/Library/LaunchAgents/actions.runner.krnblds-runwright.kierans-mac.plist\n"
        .write(to: root.appendingPathComponent(".service"), atomically: true, encoding: .utf8)
    try "{\"scheme\":\"OAuth\",\"data\":{\"clientId\":\"SECRET-CLIENT\"}}"
        .write(to: root.appendingPathComponent(".credentials"), atomically: true, encoding: .utf8)
    return root
}

/// One shared, emptied defaults suite: a new suite per test would leave a
/// preferences file behind each run. No test reads back what another wrote.
private func scratchDefaults() -> UserDefaults {
    let name = "runwright-tests"
    UserDefaults.standard.removePersistentDomain(forName: name)
    return UserDefaults(suiteName: name)!
}

private func tempHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("runwright-gh-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite struct RegistrationTests {
    @Test func readsTheRunnerFileWithItsByteOrderMark() throws {
        let r = try #require(RunnerRegistration.parse(try fixture("runner.json")))
        #expect(r.name == "kierans-mac")
        #expect(r.url == "https://github.com/krnblds/runwright")
        #expect(r.workFolder == "_work")
        #expect(r.poolName == "Default")
        #expect(r.ephemeral == false)
        #expect(r.scope == "krnblds/runwright")
        #expect(r.host == "github.com")
        #expect(r.workURL(in: URL(fileURLWithPath: "/r")).path == "/r/_work")
    }

    @Test func organizationRunnersAndAbsoluteWorkFolders() throws {
        let json = #"{"agentName":"build-box","gitHubUrl":"https://github.example.com/acme","workFolder":"/Volumes/ci/work"}"#
        let r = try #require(RunnerRegistration.parse(Data(json.utf8)))
        #expect(r.scope == "acme")
        #expect(GitHubProvider.detail(r) == "acme · github.example.com")
        #expect(r.workURL(in: URL(fileURLWithPath: "/r")).path == "/Volumes/ci/work")
    }

    @Test func rejectsFilesThatNameNoRunner() {
        #expect(RunnerRegistration.parse(Data("{}".utf8)) == nil)
        #expect(RunnerRegistration.parse(Data("not json".utf8)) == nil)
    }
}

@Suite struct DiagLogTests {
    @Test func followsJobsThroughTheRunnerLog() throws {
        let activity = DiagLog.activity(in: try fixtureText("Runner_20261102-091100-utc.log"))
        #expect(activity.listening)
        #expect(activity.current == DiagLog.Started(name: "build", at: utc("2026-11-02 09:20:12")))
        #expect(activity.finished.map(\.name) == ["lint", "unit tests (macos)"])
        #expect(activity.finished.map(\.result) == ["Succeeded", "Failed"])
        #expect(activity.finished.map(\.failed) == [false, true])
        #expect(activity.finished[1].at == utc("2026-11-02 09:16:41"))
    }

    @Test func readsRunShOutputToo() {
        let text = """
        √ Connected to GitHub
        2026-11-02 10:00:00Z: Listening for Jobs
        2026-11-02 10:01:00Z: Running job: deploy
        2026-11-02 10:02:00Z: Job deploy completed with result: Canceled
        """
        let activity = DiagLog.activity(in: text)
        #expect(activity.current == nil)
        #expect(activity.finished == [DiagLog.Finished(name: "deploy", result: "Canceled", at: utc("2026-11-02 10:02:00"))])
    }

    @Test func aRunnerThatExitedIsOnNoJob() {
        let text = """
        2026-11-02 10:01:00Z: Running job: deploy
        [2026-11-02 10:01:30Z INFO Listener] Runner listener exit with 0 return code, stop the service, no retry needed.
        """
        #expect(DiagLog.activity(in: text).current == nil)
    }

    @Test func theWorkerLogNamesTheStep() throws {
        #expect(DiagLog.currentStep(in: try fixtureText("Worker_20261102-092012-utc.log")) == "Run swift build")
        #expect(DiagLog.currentStep(in: "nothing here") == nil)
    }
}

@Suite struct ScannerTests {
    @Test func findsListenersAndWorkersByTheirFolder() throws {
        let found = ActionsProcessScanner.parse(try fixtureText("ps.txt"))
        #expect(found == [
            .init(pid: 8824, kind: .listener, root: "/Users/kieran/actions-runner", asService: false),
            .init(pid: 8901, kind: .worker, root: "/Users/kieran/actions-runner", asService: false),
            .init(pid: 9100, kind: .listener, root: "/Users/kieran/Runners/App Runner", asService: true),
        ])
    }

    @Test func readsLaunchctlList() throws {
        let jobs = LaunchdList.parse(try fixtureText("launchctl.txt"))
        #expect(jobs["actions.runner.krnblds-runwright.kierans-mac"]?.pid == 9050)
        #expect(jobs["actions.runner.krnblds-other.spare"] != nil)
        #expect(jobs["actions.runner.krnblds-other.spare"]?.pid == nil)
        #expect(jobs["PID"] == nil)
    }
}

@Suite struct FolderTests {
    @Test func readsAFolderWithoutItsCredentials() throws {
        let home = try tempHome()
        let root = try runnerFolder(in: home)
        let folder = RunnerFolder.read(root)
        #expect(folder.registration?.name == "kierans-mac")
        #expect(folder.serviceLabel == "actions.runner.krnblds-runwright.kierans-mac")
        #expect(folder.hasServiceScript)
        #expect(folder.jobPath == "/usr/bin:/bin")
        #expect(folder.activity.current?.name == "build")
        #expect(folder.currentStep == "Run swift build")
        #expect(!String(describing: folder).contains("SECRET-CLIENT"))
    }

    @Test func skipsLogsFromShortCommandsLikeVersion() throws {
        let root = try runnerFolder(in: try tempHome())
        // What `Runner.Listener --version` leaves behind, newer than the listener's log.
        try """
        [2026-11-02 10:00:00Z INFO CommandSettings] Flag 'version': 'True'
        [2026-11-02 10:00:00Z INFO Terminal] WRITE LINE: 2.338.2
        [2026-11-02 10:00:00Z INFO Listener] Runner execution has finished with return code 0
        """.write(to: root.appendingPathComponent("_diag/Runner_20261102-100000-utc.log"), atomically: true, encoding: .utf8)
        let folder = RunnerFolder.read(root)
        #expect(folder.activity.current?.name == "build")
        #expect(folder.activity.listening)
        #expect(folder.version == "2.338.2")
    }

    @Test func readsTheVersionFromEitherLine() {
        #expect(DiagLog.version(in: "[x INFO Terminal] WRITE LINE: Current runner version: '2.338.2'") == "2.338.2")
        #expect(DiagLog.version(in: "[2026-11-02 03:08:46Z INFO Listener] Version: 2.330.0") == "2.330.0")
        #expect(DiagLog.version(in: "[x INFO Listener] RuntimeInformation: Darwin Kernel Version 27.2.0") == nil)
    }

    @Test func envPathWinsOverThePathFile() {
        #expect(RunnerFolder.envValue("PATH")("LANG=C\nPATH=/a:/b\n") == "/a:/b")
        #expect(RunnerFolder.envValue("PATH")("LANG=C\n") == nil)
        #expect(RunnerFolder.settingEnvPath(in: "LANG=C\nPATH=/old\n", to: "/new") == "LANG=C\nPATH=/new\n")
        #expect(RunnerFolder.settingEnvPath(in: "LANG=C\n", to: "/new") == nil)
    }

    @Test func looksBesideAndInsideActionsRunnerFolders() throws {
        let home = try tempHome()
        _ = try runnerFolder(in: home)
        _ = try runnerFolder(in: home.appendingPathComponent("actions-runners"), named: "app")
        let unpacked = home.appendingPathComponent("actions-runner-2")
        try FileManager.default.createDirectory(at: unpacked.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try "".write(to: unpacked.appendingPathComponent("config.sh"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Projects"), withIntermediateDirectories: true)

        let (folders, unconfigured) = GitHubControl.look(home: home, remembered: [], processRoots: [])
        #expect(Set(folders.map(\.root.lastPathComponent)) == ["actions-runner", "app"])
        #expect(unconfigured.map(\.lastPathComponent) == ["actions-runner-2"])
    }

    @Test func remembersFoldersElsewhereAndDropsDuplicates() throws {
        let home = try tempHome()
        let elsewhere = try runnerFolder(in: try tempHome(), named: "ci")
        let (folders, _) = GitHubControl.look(home: home, remembered: [elsewhere.path],
                                              processRoots: [elsewhere.path + "/", "/nowhere"])
        #expect(folders.map(\.root.lastPathComponent) == ["ci"])
    }
}

@Suite struct EventTests {
    private let build = DiagLog.Started(name: "build", at: utc("2026-11-02 09:20:12"))
    private let lint = DiagLog.Finished(name: "lint", result: "Succeeded", at: utc("2026-11-02 09:13:05"))
    private let tests = DiagLog.Finished(name: "tests", result: "Failed", at: utc("2026-11-02 09:16:41"))

    private func look(on: Bool = true, current: DiagLog.Started? = nil, finished: [DiagLog.Finished] = []) -> RunnerObservation {
        RunnerObservation(runner: "kierans-mac", isOn: on, current: current, finished: finished)
    }

    @Test func theFirstLookIsOnlyABaseline() {
        #expect(GitHubEvents.events(from: nil, to: look(current: build, finished: [lint, tests]), at: .now).isEmpty)
    }

    @Test func goingOnAndOff() {
        #expect(GitHubEvents.events(from: look(on: false), to: look(on: true), at: .now).map(\.title) == ["Runner is online"])
        #expect(GitHubEvents.events(from: look(on: true), to: look(on: false), at: .now).map(\.title) == ["Runner went offline"])
    }

    @Test func jobsStartingAndFinishing() {
        let started = GitHubEvents.events(from: look(finished: [lint]), to: look(current: build, finished: [lint]), at: .now)
        #expect(started == [.jobStarted(runner: "kierans-mac", stage: "build", at: build.at)])

        let failed = GitHubEvents.events(from: look(finished: [lint]), to: look(finished: [lint, tests]), at: .now)
        #expect(failed == [.jobFailed(reason: "kierans-mac · tests", at: tests.at)])

        let canceled = DiagLog.Finished(name: "deploy", result: "Canceled", at: utc("2026-11-02 09:30:00"))
        #expect(GitHubEvents.events(from: look(finished: [tests]), to: look(finished: [tests, canceled]), at: .now)
            == [.jobFinished(runner: "kierans-mac", stage: "deploy (canceled)", at: canceled.at)])
    }

    @Test func linesDroppingOutOfTheTailAreNotNew() {
        // The tail moved on: lint fell out of view, nothing new happened.
        #expect(GitHubEvents.events(from: look(finished: [lint, tests]), to: look(finished: [tests]), at: .now).isEmpty)
    }
}

@MainActor
@Suite struct ProviderTests {
    private func provider(home: URL) -> GitHubProvider {
        GitHubProvider(control: GitHubControl(home: home, defaults: scratchDefaults()))
    }

    @Test func aBusyRunnerShowsItsJob() throws {
        let home = try tempHome()
        let root = try runnerFolder(in: home)
        let gh = provider(home: home)
        #expect(gh.status.connection == .connecting)
        #expect(!gh.isSetUp)

        let (folders, _) = GitHubControl.look(home: home, remembered: [], processRoots: [])
        gh.control.apply(folders: folders, processes: [
            .init(pid: 1, kind: .listener, root: root.path, asService: false),
            .init(pid: 2, kind: .worker, root: root.path, asService: false),
        ], launchd: [:])

        #expect(gh.isSetUp)
        let summary = try #require(gh.summaries.first)
        #expect(summary.id == "github|\(root.standardizedFileURL.path)")
        #expect(summary.provider == .github)
        #expect(summary.name == "kierans-mac")
        #expect(summary.detail == "krnblds/runwright")
        #expect(summary.state == .busy)
        #expect(summary.mode == .individual)
        #expect(summary.runningJobs.map(\.name) == ["build"])
        #expect(summary.runningJobs.first?.detail == "Run swift build")
        #expect(summary.actions.isSuperset(of: [.stop, .restart, .toggle]))
        #expect(gh.runner(for: summary.id)?.id == root.standardizedFileURL.path)

        let status = gh.status
        #expect(status.busySlots == 1)
        #expect(status.capacity == 1)
        #expect(status.serviceName == "GitHub")
    }

    @Test func theLaunchdServiceCountsAsRunning() throws {
        let home = try tempHome()
        _ = try runnerFolder(in: home)
        let gh = provider(home: home)
        let (folders, _) = GitHubControl.look(home: home, remembered: [], processRoots: [])
        let label = "actions.runner.krnblds-runwright.kierans-mac"
        gh.control.apply(folders: folders, processes: [], launchd: [label: .init(label: label, pid: 77)])
        let summary = try #require(gh.summaries.first)
        #expect(summary.mode == .service)
        // No worker seen yet, but the log has a job it hasn't finished.
        #expect(summary.state == .busy)

        gh.control.apply(folders: folders, processes: [], launchd: [label: .init(label: label, pid: nil)])
        #expect(gh.summaries.first?.state == .offline)
        #expect(gh.summaries.first?.mode == .off)
        #expect(gh.summaries.first?.runningJobs.isEmpty == true)
    }

    @Test func eventsReachTheCallback() {
        let gh = provider(home: FileManager.default.temporaryDirectory)
        var seen: [RunnerEvent] = []
        gh.onEvent = { seen.append($0) }
        let a = RunnerEvent.runnerOnline(at: Date(timeIntervalSince1970: 1))
        let b = RunnerEvent.jobFailed(reason: "x", at: Date(timeIntervalSince1970: 2))
        gh.record([b, a])
        #expect(seen == [a, b])
        #expect(gh.events == [b, a])
        #expect(gh.status.events == [b, a])
    }
}

@Suite struct ReleaseTests {
    @Test func readsTheVersionFromTheLatestRedirect() {
        #expect(RunnerRelease.version(fromTagURL: URL(string: "https://github.com/actions/runner/releases/tag/v2.321.0")!) == "2.321.0")
        #expect(RunnerRelease.version(fromTagURL: URL(string: "https://github.com/actions/runner/releases")!) == nil)
        #expect(RunnerRelease.version(fromTagURL: URL(string: "https://github.com/actions/runner/releases/tag/latest")!) == nil)
    }

    @Test func downloadsTheMacBuildForThisChip() {
        #expect(RunnerRelease.downloadURL(version: "2.321.0", arch: "arm64").absoluteString
            == "https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-osx-arm64-2.321.0.tar.gz")
    }

    @Test func readsTheListenersVersionOutput() {
        #expect(RunnerRelease.version(fromOutput: "2.319.1\n") == "2.319.1")
        #expect(RunnerRelease.version(fromOutput: "Starting\n2.320.0") == "2.320.0")
        #expect(RunnerRelease.version(fromOutput: "error") == nil)
    }

    @Test func comparesVersionsByNumber() {
        #expect(RunnerRelease.isOutdated("2.319.1", latest: "2.321.0"))
        #expect(RunnerRelease.isOutdated("2.99.0", latest: "2.100.0"))
        #expect(!RunnerRelease.isOutdated("2.321.0", latest: "2.321.0"))
        #expect(!RunnerRelease.isOutdated("2.322.0", latest: "2.321.0"))
        #expect(!RunnerRelease.isOutdated("junk", latest: "2.321.0"))
    }
}

@MainActor
@Suite struct InstallFolderTests {
    @Test func suggestsTheFirstFreeFolder() throws {
        let home = try tempHome()
        let control = GitHubControl(home: home, defaults: scratchDefaults())
        #expect(control.suggestedFolder().lastPathComponent == "actions-runner")
        _ = try runnerFolder(in: home)
        #expect(control.suggestedFolder().lastPathComponent == "actions-runner-2")
    }
}
