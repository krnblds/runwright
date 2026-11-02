import AppKit
import Foundation
import Observation
import RunwrightCore
import RunwrightGitHub
import RunwrightGitLab
import ServiceManagement
import UserNotifications

/// Wires the providers, settings and notifications together.
@MainActor
@Observable
final class AppModel {
    let settings = AppSettings()
    let gitlab = GitLabProvider()
    let github = GitHubProvider()
    /// Every CI provider Runwright watches.
    let providers: [any RunnerProvider]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var controlRefresh: Task<Void, Never>?

    init() {
        providers = [gitlab, github]
        gitlab.apply(metricsAddress: settings.metricsAddress, pollInterval: settings.pollInterval, demo: settings.demoMode)
        for provider in providers {
            let id = provider.id
            provider.onEvent = { [weak self] event in self?.notify(event, from: id) }
        }
        gitlab.store.start()
        watchSleep()
        controlRefresh = Task { [weak self] in
            while !Task.isCancelled {
                for provider in self?.providers ?? [] { await provider.refresh() }
                try? await Task.sleep(for: .seconds(10))
            }
        }
        Notifier.requestPermission()
    }

    /// Every provider's runners.
    var summaries: [RunnerSummary] { providers.flatMap(\.summaries) }

    /// How the providers that are set up are doing, as one. With only
    /// GitLab set up, that is GitLab's status.
    var status: ProviderStatus { ProviderStatus.combined(providers.filter(\.isSetUp).map(\.status)) }

    /// Output from starting, stopping and running the runners, oldest first.
    var log: [LogLine] {
        let github = github.control.log
        guard !github.isEmpty else { return gitlab.control.log }
        return (gitlab.control.log + github).sorted { $0.date < $1.date }
    }

    func clearLog() {
        gitlab.control.clearLog()
        github.control.clearLog()
    }

    // MARK: Settings changes

    func applySource() {
        gitlab.apply(metricsAddress: settings.metricsAddress, pollInterval: settings.pollInterval, demo: settings.demoMode)
        gitlab.store.restart()
    }

    func setDemo(_ on: Bool) {
        settings.demoMode = on
        applySource()
    }

    // MARK: Actions

    func perform(_ action: RunnerAction, on summary: RunnerSummary) {
        guard let provider = providers.first(where: { $0.id == summary.provider }) else { return }
        Task { await provider.perform(action, on: summary.id) }
    }

    /// Runs GitLab-only work (setup, the whole runner) against its control.
    func perform(_ work: @escaping @MainActor (GitLabControl) async -> Void) {
        Task { await gitlab.perform(work) }
    }

    /// Runs GitHub-only work (the service, running here) against its control.
    func performGitHub(_ work: @escaping @MainActor (GitHubControl) async -> Void) {
        Task { await github.perform(work) }
    }

    /// The repository or organization a GitHub runner takes jobs from, or
    /// GitHub itself.
    func openGitHub(_ runner: GitHubRunner? = nil) {
        let url = (runner ?? github.control.runners.first)?.registration?.url
        if let url = URL(string: url?.isEmpty == false ? url! : "https://github.com") { NSWorkspace.shared.open(url) }
    }

    /// Project runners live under each project's CI/CD settings, and without
    /// an API token there is no way to know which project. The projects list
    /// is one click from there.
    func openGitLab() {
        let base = gitlab.control.registeredRunners.first?.url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let host = base?.isEmpty == false ? base! : "https://gitlab.com"
        if let url = URL(string: "\(host)/dashboard/projects") { NSWorkspace.shared.open(url) }
    }

    func openConfig() {
        let url = gitlab.control.configURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent().deletingLastPathComponent())
        }
    }

    // MARK: Launch at login

    var canLaunchAtLogin: Bool { Bundle.main.bundleIdentifier != nil }

    var launchAtLogin: Bool {
        get { canLaunchAtLogin && SMAppService.mainApp.status == .enabled }
        set {
            guard canLaunchAtLogin else { return }
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    // MARK: Notifications

    private func notify(_ event: RunnerEvent, from provider: ProviderID) {
        // GitHub runners are seen from their processes, not a live status.
        let gitlab = provider == .gitlab
        switch event {
        case .jobFailed(let reason, _) where settings.notifyFailures:
            Notifier.post(title: "Job failed", body: reason)
        case .runnerOffline where settings.notifyOffline:
            Notifier.post(title: "Runner offline",
                          body: gitlab ? "The runner has not answered for 30 seconds." : "A GitHub Actions runner stopped.")
        case .runnerOnline where settings.notifyOnline:
            Notifier.post(title: "Runner back online",
                          body: gitlab ? "Live status is coming in again." : "A GitHub Actions runner is listening for jobs.")
        default:
            break
        }
    }

    // MARK: Sleep

    private func watchSleep() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.gitlab.store.stop() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.gitlab.store.restart() }
        })
    }

    func shutdown() {
        gitlab.control.shutdown()
        github.control.shutdown()
    }
}

/// Posts user notifications. A bundled app uses UserNotifications; when run
/// straight from `swift run` there is no bundle, so it falls back to
/// AppleScript's `display notification`.
enum Notifier {
    static var bundled: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    static func requestPermission() {
        guard bundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        if bundled {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        } else {
            let escape = { (s: String) in s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
            let script = "display notification \"\(escape(body))\" with title \"Runwright\" subtitle \"\(escape(title))\""
            Task.detached { _ = await ProcessRunner.run("/usr/bin/osascript", ["-e", script]) }
        }
    }
}
