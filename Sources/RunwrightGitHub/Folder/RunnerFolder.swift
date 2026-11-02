import Foundation

/// A folder `config.sh` has set up as a GitHub Actions runner, as read from
/// disk: `.runner`, `.service`, the job search path in `.path` / `.env`,
/// and the logs in `_diag`. `.credentials` is never opened.
public struct RunnerFolder: Equatable, Sendable {
    public var root: URL
    public var registration: RunnerRegistration?
    /// The launchd plist `svc.sh install` made, from `.service`.
    public var servicePlist: String?
    public var hasServiceScript = false
    /// The search path `config.sh` saved in `.path` for jobs.
    public var pathFile: String?
    /// A `PATH=` line in `.env`, which the runner applies on top.
    public var envPath: String?
    public var activity = DiagLog.Activity()
    /// The step the newest worker log is on.
    public var currentStep: String?
    /// The runner version, from the listener's newest log.
    public var version: String?

    public init(root: URL, registration: RunnerRegistration? = nil) {
        self.root = root
        self.registration = registration
    }

    /// The launchd label, like `actions.runner.owner-repo.my-mac`.
    public var serviceLabel: String? {
        servicePlist.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
    }

    /// What jobs search for tools, when the folder says.
    public var jobPath: String? { envPath ?? pathFile }

    /// "~/actions-runner".
    public var label: String { root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }

    public static func isRunnerFolder(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".runner").path)
    }

    /// A folder with the runner unpacked but `config.sh` not run yet.
    public static func isUnconfigured(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent("config.sh").path)
            && fm.fileExists(atPath: url.appendingPathComponent("bin").path)
            && !isRunnerFolder(url)
    }

    /// Reads everything but the credentials. Off the main thread: the logs
    /// can run to megabytes.
    public static func read(_ root: URL) -> RunnerFolder {
        var folder = RunnerFolder(root: root)
        let file = { (name: String) in root.appendingPathComponent(name) }
        let text = { (name: String) in
            (try? String(contentsOf: file(name), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        folder.registration = (try? Data(contentsOf: file(".runner"))).flatMap(RunnerRegistration.parse)
        folder.servicePlist = text(".service").flatMap { $0.isEmpty ? nil : $0 }
        folder.hasServiceScript = FileManager.default.fileExists(atPath: file("svc.sh").path)
        folder.pathFile = text(".path").flatMap { $0.isEmpty ? nil : $0 }
        folder.envPath = text(".env").flatMap(envValue("PATH"))
        let diag = file("_diag")
        if let log = DiagLog.newestListenerLog(in: diag) {
            if let tail = DiagLog.tail(of: log) { folder.activity = DiagLog.activity(in: tail) }
            folder.version = DiagLog.head(of: log).flatMap(DiagLog.version(in:))
        }
        if let log = DiagLog.newestLog("Worker_", in: diag), let tail = DiagLog.tail(of: log, bytes: 256 * 1024) {
            folder.currentStep = DiagLog.currentStep(in: tail)
        }
        return folder
    }

    /// One `KEY=value` line's value from a `.env` file.
    static func envValue(_ key: String) -> (String) -> String? {
        { text in
            text.split(whereSeparator: \.isNewline).lazy
                .compactMap { line -> String? in
                    let parts = line.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key else { return nil }
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
                .first { !$0.isEmpty }
        }
    }

    /// `text` with the `PATH=` line set to `path`, or nil when it has none.
    static func settingEnvPath(in text: String, to path: String) -> String? {
        var found = false
        let lines = text.components(separatedBy: "\n").map { line -> String in
            let key = line.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces)
            guard key == "PATH" else { return line }
            found = true
            return "PATH=\(path)"
        }
        return found ? lines.joined(separator: "\n") : nil
    }

    /// Where runners usually are: `~/actions-runner` and its siblings
    /// (`~/actions-runner-2`, `~/actions-runners`), and the folders inside
    /// them, for several runners kept side by side.
    public static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: home.path)) ?? []
        var found: [URL] = []
        for name in names.sorted() where name.lowercased().hasPrefix("actions-runner") {
            let base = home.appendingPathComponent(name)
            found.append(base)
            let inner = (try? fm.contentsOfDirectory(atPath: base.path)) ?? []
            for child in inner.sorted() where !child.hasPrefix(".") && !child.hasPrefix("_") {
                let url = base.appendingPathComponent(child)
                var dir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &dir), dir.boolValue, child != "bin", child != "externals" {
                    found.append(url)
                }
            }
        }
        return found
    }
}
