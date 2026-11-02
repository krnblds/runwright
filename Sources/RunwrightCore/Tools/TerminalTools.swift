import Foundation

/// The tools a runner's jobs can find, next to the ones the user's Terminal
/// can. Jobs started by a background service only get a short search path, so
/// tools installed in the home folder (Flutter, nvm, cargo…) go missing.
public enum TerminalTools {
    /// Tools worth checking for, in the order they're shown.
    public static let watchedTools = ["flutter", "dart", "node", "npm", "pnpm", "yarn", "cargo", "go", "python3",
                                      "ruby", "java", "docker", "xcodebuild", "pod", "fastlane"]

    /// The search path the user's Terminal has, read from a login shell so
    /// `.zshrc`/`.zprofile` additions (Flutter, nvm, cargo…) are included.
    /// Nil when the shell couldn't be read.
    public static func loadTerminalPath() async -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let marker = "__RUNWRIGHT_PATH__"
        // An interactive shell reads .zshrc, but with job control on it tries
        // to take over any terminal Runwright inherited and gets stopped. +m
        // turns job control off; the timeout covers a slow or odd rc file.
        // rc files can print banners; only trust what follows the marker.
        let r = await ProcessRunner.run(shell, ["-i", "+m", "-l", "-c", "printf '\(marker)%s' \"$PATH\""], timeout: 10)
        guard let range = r.output.range(of: marker) else { return nil }
        let path = r.output[range.upperBound...].split(separator: "\n").first.map(String.init) ?? ""
        return path.isEmpty ? nil : dedupe(path)
    }

    /// Tools the Terminal can run that jobs with `jobPath` can't find.
    public static func missingTools(jobPath: String, terminalPath: String?) -> [String] {
        guard let terminalPath else { return [] }
        return watchedTools.filter { find($0, in: terminalPath) != nil && find($0, in: jobPath) == nil }
    }

    /// The first executable called `tool` in a colon-separated search path.
    public static func find(_ tool: String, in path: String) -> String? {
        for dir in path.split(separator: ":") {
            let candidate = (String(dir) as NSString).appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Drops empty and repeated entries from a search path, keeping order.
    public static func dedupe(_ path: String) -> String {
        var seen = Set<Substring>()
        return path.split(separator: ":").filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }
}
