import Foundation

/// Reads what a runner has been doing from the logs in its `_diag` folder.
/// There is no live-status endpoint, but the listener writes every line it
/// prints to `Runner_*.log`, and each job's worker writes its steps to
/// `Worker_*.log`:
///
///     [2026-11-02 09:14:03Z INFO Terminal] WRITE LINE: 2026-11-02 09:14:03Z: Running job: build
///     [2026-11-02 09:15:40Z INFO Terminal] WRITE LINE: 2026-11-02 09:15:40Z: Job build completed with result: Succeeded
///
/// The same lines come out of `run.sh`, so either can be read.
public enum DiagLog {
    public struct Started: Equatable, Sendable {
        public var name: String
        public var at: Date
    }

    public struct Finished: Equatable, Sendable {
        public var name: String
        /// `Succeeded`, `Failed`, `Canceled`…
        public var result: String
        public var at: Date

        public var failed: Bool { result.lowercased() == "failed" }
    }

    /// What the log says about jobs.
    public struct Activity: Equatable, Sendable {
        /// The job started last, if it hasn't finished.
        public var current: Started?
        /// Oldest first.
        public var finished: [Finished] = []
        /// The runner said it was listening for jobs (and hasn't stopped since).
        public var listening = false

        public init(current: Started? = nil, finished: [Finished] = [], listening: Bool = false) {
            self.current = current
            self.finished = finished
            self.listening = listening
        }
    }

    private static let stamp = #"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})Z: "#
    private static let started = try! NSRegularExpression(pattern: stamp + #"Running job: (.+?)\s*$"#)
    private static let completed = try! NSRegularExpression(pattern: stamp + #"Job (.+) completed with result: (\w+)"#)
    private static let step = try! NSRegularExpression(pattern: #"Processing step: DisplayName='(.+)'"#)
    private static let versionLine = try! NSRegularExpression(pattern: #"Current runner version: '([0-9.]+)'|INFO Listener\] Version: ([0-9.]+)"#)

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    public static func date(_ text: String) -> Date? { formatter.date(from: text) }

    /// Jobs started and finished in a `Runner_*.log` or `run.sh`'s output.
    public static func activity(in text: String) -> Activity {
        var activity = Activity()
        for line in text.split(whereSeparator: \.isNewline) {
            let line = String(line)
            if let m = match(started, line), let at = date(m[0]) {
                activity.current = Started(name: m[1], at: at)
            } else if let m = match(completed, line), let at = date(m[0]) {
                activity.finished.append(Finished(name: m[1], result: m[2], at: at))
                if activity.current?.name == m[1] { activity.current = nil }
            } else if line.contains("Listening for Jobs") {
                activity.listening = true
            } else if line.contains("Exiting...") || line.contains("Runner listener exit") {
                activity.listening = false
                activity.current = nil
            }
        }
        return activity
    }

    /// The step a job's worker is on, from its `Worker_*.log`.
    public static func currentStep(in text: String) -> String? {
        var last: String?
        for line in text.split(whereSeparator: \.isNewline) {
            if let m = match(step, String(line)) { last = m[0] }
        }
        return last
    }

    /// The runner version a listener log was written by. It's near the top.
    public static func version(in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            if let m = match(versionLine, String(line)), let v = m.first(where: { !$0.isEmpty }) { return v }
        }
        return nil
    }

    /// The newest log a listener wrote while taking jobs. Every run of the
    /// runner's binary starts a `Runner_` log, `--version` too, so the
    /// newest by name can be a short one from a command.
    public static func newestListenerLog(in diag: URL) -> URL? {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: diag.path)) ?? [])
            .filter { $0.hasPrefix("Runner_") && $0.hasSuffix(".log") }
            .sorted(by: >)
        for name in names.prefix(10) {
            let url = diag.appendingPathComponent(name)
            guard let text = tail(of: url, bytes: 64 * 1024) else { continue }
            if text.contains("Listening for Jobs") || text.contains("Running job:") || text.contains("Current runner version") {
                return url
            }
        }
        return names.first.map { diag.appendingPathComponent($0) }
    }

    /// The start of a file.
    public static func head(of url: URL, bytes: Int = 64 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: bytes) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The newest log in `_diag` whose name starts with `prefix`. The names
    /// carry their start time, so they sort by name.
    public static func newestLog(_ prefix: String, in diag: URL) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: diag.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".log") }.max().map { diag.appendingPathComponent($0) }
    }

    /// The end of a file: logs grow for as long as the runner runs.
    public static func tail(of url: URL, bytes: Int = 512 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func match(_ regex: NSRegularExpression, _ line: String) -> [String]? {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = regex.firstMatch(in: line, range: range) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: line).map { String(line[$0]) } ?? ""
        }
    }
}
