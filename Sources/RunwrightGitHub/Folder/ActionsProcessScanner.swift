import Foundation
import RunwrightCore

/// Finds actions-runner processes: a `Runner.Listener` for each runner that
/// is on, and a `Runner.Worker` next to it while it runs a job. The folder
/// a process belongs to is the one above its `bin`.
public enum ActionsProcessScanner {
    public struct Found: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case listener, worker }
        public var pid: Int32
        public var kind: Kind
        /// The runner's folder.
        public var root: String
        /// Started by the launchd service rather than `run.sh`.
        public var asService: Bool
    }

    public static func scan() async -> [Found] {
        let r = await ProcessRunner.run("/bin/ps", ["-axww", "-o", "pid=,command="], timeout: 10)
        return parse(r.output)
    }

    static func parse(_ output: String) -> [Found] {
        output.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(of: " "), let pid = Int32(line[..<space]) else { return nil }
            let command = line[line.index(after: space)...].trimmingCharacters(in: .whitespaces)
            // Folder names can have spaces, so look for the binary by name.
            for (binary, kind) in [("/bin/Runner.Listener", Found.Kind.listener), ("/bin/Runner.Worker", .worker)] {
                guard let range = command.range(of: binary) else { continue }
                let rest = command[range.upperBound...]
                guard rest.isEmpty || rest.first == " " else { continue }
                return Found(pid: pid, kind: kind, root: String(command[..<range.lowerBound]),
                             asService: rest.contains("--startuptype service"))
            }
            return nil
        }
    }
}

/// `launchctl list`: which launchd jobs are loaded, and their process ids.
public enum LaunchdList {
    public struct Job: Equatable, Sendable {
        public var label: String
        /// Nil when loaded but not running.
        public var pid: Int32?
    }

    public static func load() async -> [String: Job] {
        let r = await ProcessRunner.run("/bin/launchctl", ["list"], timeout: 10)
        return parse(r.output)
    }

    static func parse(_ output: String) -> [String: Job] {
        var jobs: [String: Job] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3, parts[0] != "PID" else { continue }
            let label = parts[2].trimmingCharacters(in: .whitespaces)
            jobs[label] = Job(label: label, pid: Int32(parts[0].trimmingCharacters(in: .whitespaces)))
        }
        return jobs
    }
}
