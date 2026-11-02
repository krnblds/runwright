import Foundation

/// The last lines of a log file that is still being written, for following
/// a runner's own log (`tail -f`, re-read on a timer).
public enum LogTail {
    /// Up to `maxLines` lines from the last `maxBytes` of the file, oldest
    /// first, without colour codes. Nil when the file can't be read.
    public static func lastLines(of url: URL, maxBytes: Int = 128 * 1024, maxLines: Int = 400) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return [] }
        return lines(in: String(decoding: data, as: UTF8.self), cutMidway: start > 0, maxLines: maxLines)
    }

    static func lines(in text: String, cutMidway: Bool, maxLines: Int) -> [String] {
        var lines = text.split(whereSeparator: \.isNewline).map(String.init)
        // Reading from the middle of a file starts partway through a line.
        if cutMidway, !lines.isEmpty { lines.removeFirst() }
        return lines.suffix(maxLines)
            .map(ManagedProcess.stripANSI)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The files a launchd agent's output goes to, from its plist.
    public static func launchdLogs(plist: URL) -> [URL] {
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [] }
        var seen = Set<String>()
        return ["StandardOutPath", "StandardErrorPath"].compactMap { dict[$0] as? String }
            .filter { seen.insert($0).inserted }
            .map { URL(fileURLWithPath: $0) }
    }
}
