import Foundation
import Observation
import RunwrightCore

/// User preferences, persisted in UserDefaults. No secrets live here.
@MainActor
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var pollInterval: Double { didSet { defaults.set(pollInterval, forKey: "pollInterval") } }
    var metricsAddress: String { didSet { defaults.set(metricsAddress, forKey: "metricsAddress") } }
    var demoMode: Bool { didSet { defaults.set(demoMode, forKey: "demoMode") } }
    var notifyFailures: Bool { didSet { defaults.set(notifyFailures, forKey: "notifyFailures") } }
    var notifyOffline: Bool { didSet { defaults.set(notifyOffline, forKey: "notifyOffline") } }
    var notifyOnline: Bool { didSet { defaults.set(notifyOnline, forKey: "notifyOnline") } }
    var showInDock: Bool { didSet { defaults.set(showInDock, forKey: "showInDock") } }

    init() {
        defaults.register(defaults: [
            "pollInterval": 3.0,
            "metricsAddress": "127.0.0.1:9252",
            // Start in the demo when there is no runner to watch yet.
            "demoMode": ProcessRunner.which("gitlab-runner") == nil,
            "notifyFailures": true,
            "notifyOffline": true,
            "notifyOnline": true,
            "showInDock": true,
        ])
        pollInterval = defaults.double(forKey: "pollInterval")
        metricsAddress = defaults.string(forKey: "metricsAddress") ?? "127.0.0.1:9252"
        demoMode = defaults.bool(forKey: "demoMode")
        notifyFailures = defaults.bool(forKey: "notifyFailures")
        notifyOffline = defaults.bool(forKey: "notifyOffline")
        notifyOnline = defaults.bool(forKey: "notifyOnline")
        showInDock = defaults.bool(forKey: "showInDock")
    }
}
