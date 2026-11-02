import Foundation

public struct CommandResult: Sendable {
    public var status: Int32
    public var output: String
    public var succeeded: Bool { status == 0 }
}

/// Runs short commands off the main thread and long-lived ones as managed
/// child processes. PATH always includes Homebrew so `brew` and the runner
/// tools it installs resolve when the app is launched from Finder.
public enum ProcessRunner {
    public static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    public static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existing = env["PATH"].map { $0.split(separator: ":").map(String.init) } ?? []
        env["PATH"] = (searchPaths + existing.filter { !searchPaths.contains($0) }).joined(separator: ":")
        return env
    }

    public static func which(_ tool: String) -> String? {
        let fm = FileManager.default
        let dirs = environment["PATH"]?.split(separator: ":").map(String.init) ?? searchPaths
        for dir in dirs {
            let path = (dir as NSString).appendingPathComponent(tool)
            if fm.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// Runs to completion and returns combined stdout/stderr. With a
    /// `timeout`, the command is killed if it hasn't finished by then. With a
    /// `directory`, it runs from there (scripts that use relative paths).
    public static func run(_ executable: String, _ arguments: [String], timeout: Double? = nil,
                           in directory: URL? = nil) async -> CommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment
            if let directory { process.currentDirectoryURL = directory }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            let collector = OutputCollector()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                collector.append(handle.availableData)
            }
            process.terminationHandler = { p in
                pipe.fileHandleForReading.readabilityHandler = nil
                collector.append(pipe.fileHandleForReading.readDataToEndOfFile())
                continuation.resume(returning: CommandResult(status: p.terminationStatus, output: collector.text))
            }
            do {
                try process.run()
                if let timeout {
                    let pid = process.processIdentifier
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
                    }
                }
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: CommandResult(status: -1, output: error.localizedDescription))
            }
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

public struct LogLine: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let date: Date
    public let source: String
    public let text: String

    public init(date: Date, source: String, text: String) {
        self.date = date
        self.source = source
        self.text = text
    }
}

/// A long-running child process (a runner's `run` command, say) whose
/// output streams into a log, and which can be stopped from the UI.
@MainActor
@Observable
public final class ManagedProcess {
    public let name: String
    public private(set) var isRunning = false
    public private(set) var exitStatus: Int32?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private let onLine: @MainActor (LogLine) -> Void
    @ObservationIgnored private var partial = ""

    public init(name: String, onLine: @escaping @MainActor (LogLine) -> Void) {
        self.name = name
        self.onLine = onLine
    }

    /// The child's process id while it runs.
    public var pid: Int32? { process?.isRunning == true ? process?.processIdentifier : nil }

    public func start(_ executable: String, _ arguments: [String], in directory: URL? = nil) {
        guard !isRunning else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessRunner.environment
        process.currentDirectoryURL = directory ?? FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = String(decoding: handle.availableData, as: UTF8.self)
            guard !chunk.isEmpty else { return }
            Task { @MainActor in self?.receive(chunk) }
        }
        process.terminationHandler = { [weak self] p in
            pipe.fileHandleForReading.readabilityHandler = nil
            let status = p.terminationStatus
            Task { @MainActor in self?.finished(status) }
        }
        do {
            try process.run()
            self.process = process
            isRunning = true
            exitStatus = nil
            emit("Started: \((executable as NSString).lastPathComponent) \(arguments.joined(separator: " "))")
        } catch {
            emit("Could not start: \(error.localizedDescription)")
        }
    }

    /// SIGTERM first so a runner can hand back its jobs, then SIGKILL.
    public func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        Task {
            try? await Task.sleep(for: .seconds(8))
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private func receive(_ chunk: String) {
        partial += chunk
        while let newline = partial.firstIndex(of: "\n") {
            let line = String(partial[..<newline])
            partial = String(partial[partial.index(after: newline)...])
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { emit(line) }
        }
    }

    private func finished(_ status: Int32) {
        if !partial.isEmpty { emit(partial); partial = "" }
        isRunning = false
        exitStatus = status
        process = nil
        emit("Stopped (exit \(status))")
    }

    private func emit(_ text: String) {
        onLine(LogLine(date: .now, source: name, text: Self.stripANSI(text)))
    }

    public nonisolated static func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    }
}
