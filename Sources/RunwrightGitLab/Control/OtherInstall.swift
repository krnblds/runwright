import Foundation
import RunwrightCore

/// A gitlab-runner set up outside Homebrew: its own binary and config.toml,
/// run as a plain `gitlab-runner run --config …` process (CommandSlate's CI
/// runner in `~/CI` is one). Runwright finds these by looking at running
/// processes and remembers them so they still show while stopped.
@MainActor
@Observable
public final class OtherInstall: Identifiable {
    public let binaryURL: URL
    public let configURL: URL
    public private(set) var config: RunnerConfig?
    /// A process Runwright didn't start (launched by another app or a shell).
    public private(set) var externalPID: Int32?
    public private(set) var process: ManagedProcess!
    @ObservationIgnored private let log: @MainActor (LogLine) -> Void

    public nonisolated var id: String { configURL.path }

    /// "~/CI", the folder the install lives in.
    public var label: String {
        configURL.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    public var isRunning: Bool { externalPID != nil || process.isRunning }
    public var runners: [RegisteredRunner] { config?.runners ?? [] }
    public var metricsAddress: String? { config?.listenAddress.flatMap { $0.isEmpty ? nil : $0 } }

    public init(binaryURL: URL, configURL: URL, log: @escaping @MainActor (LogLine) -> Void) {
        self.binaryURL = binaryURL
        self.configURL = configURL
        self.log = log
        self.process = ManagedProcess(name: configURL.deletingLastPathComponent().lastPathComponent, onLine: log)
    }

    func update(config: RunnerConfig?, externalPID: Int32?) {
        self.config = config
        // Our own child shows up in `ps` too; it isn't external.
        self.externalPID = externalPID == process.pid ? nil : externalPID
    }

    /// Starts it the way it was run before: from its own folder, so relative
    /// `builds/` and `cache/` land where they always have.
    public func start() {
        guard !isRunning else { return }
        let folder = configURL.deletingLastPathComponent()
        process.start(binaryURL.path, ["run", "--config", configURL.path, "--working-directory", folder.path],
                      in: folder)
    }

    public func stop() async {
        process.stop()
        if let pid = externalPID {
            kill(pid, SIGTERM)
            log(LogLine(date: .now, source: process.name, text: "Asked process \(pid) to stop"))
            // gitlab-runner finishes handing back jobs before it exits.
            for _ in 0..<80 where kill(pid, 0) == 0 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            externalPID = nil
        }
    }

    public func restart() async {
        await stop()
        start()
    }

    /// Writes config.toml with a backup next to it.
    func rewrite(_ transform: (String) -> String?) -> Bool {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8), let updated = transform(text) else { return false }
        let backup = configURL.appendingPathExtension("runwright-backup")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: configURL, to: backup)
        do {
            try updated.write(to: configURL, atomically: true, encoding: .utf8)
            config = RunnerConfig.parse(updated)
            return true
        } catch {
            return false
        }
    }
}

/// Finds `gitlab-runner run` processes and their config files.
public enum RunnerProcessScanner {
    public struct Found: Equatable, Sendable {
        public var pid: Int32
        public var binary: String
        public var config: String?
    }

    public static func scan() async -> [Found] {
        let r = await ProcessRunner.run("/bin/ps", ["-axww", "-o", "pid=,command="], timeout: 10)
        return parse(r.output)
    }

    static func parse(_ output: String) -> [Found] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 3, let pid = Int32(parts[0]),
                  (parts[1] as NSString).lastPathComponent == "gitlab-runner", parts[2] == "run" else { return nil }
            var config: String?
            for (i, arg) in parts.enumerated() where (arg == "--config" || arg == "-c") && i + 1 < parts.count {
                config = parts[i + 1]
            }
            if let c = parts.first(where: { $0.hasPrefix("--config=") }) { config = String(c.dropFirst(9)) }
            return Found(pid: pid, binary: parts[1], config: config)
        }
    }
}
