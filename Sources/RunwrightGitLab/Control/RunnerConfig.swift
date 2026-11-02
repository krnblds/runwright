import Foundation
import RunwrightCore

/// One `[[runners]]` entry in config.toml. The token is never read.
public struct RegisteredRunner: Equatable, Hashable, Sendable, Identifiable {
    public var name: String
    public var url: String
    public var executor: String
    public var limit: Int?
    /// `environment = [...]` entries, e.g. `PATH=/usr/bin:/bin`.
    public var environment: [String] = []
    public var id: String { name }

    /// The search path jobs get, if the runner sets one.
    public var jobPath: String? {
        environment.first { $0.hasPrefix("PATH=") }.map { String($0.dropFirst(5)) }
    }
}

/// The few parts of config.toml Runwright cares about. A small line reader is
/// enough: runner configs are flat `key = value` pairs under `[[runners]]`.
public struct RunnerConfig: Equatable, Sendable {
    public var concurrent: Int?
    public var listenAddress: String?
    public var runners: [RegisteredRunner] = []

    public static func parse(_ text: String) -> RunnerConfig {
        var config = RunnerConfig()
        var section = ""
        var current: RegisteredRunner?

        func flush() {
            if let r = current { config.runners.append(r) }
            current = nil
        }

        var pending = ""
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = stripComment(String(raw)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // Arrays can span lines: gather until the brackets balance.
            if !pending.isEmpty || (line.contains("= [") && !balanced(line)) {
                pending += (pending.isEmpty ? "" : " ") + line
                guard balanced(pending) else { continue }
                line = pending
                pending = ""
            }
            if line.hasPrefix("[") {
                let header = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                if line.hasPrefix("[[") && header == "runners" {
                    flush()
                    current = RegisteredRunner(name: "runner \(config.runners.count + 1)", url: "", executor: "")
                }
                section = header
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = unquote(line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces))

            if section.isEmpty {
                switch key {
                case "concurrent": config.concurrent = Int(value)
                case "listen_address": config.listenAddress = value
                default: break
                }
            } else if section == "runners", current != nil {
                switch key {
                case "name": current?.name = value
                case "url": current?.url = value
                case "executor": current?.executor = value
                case "limit": current?.limit = Int(value)
                case "environment": current?.environment = parseArray(value)
                default: break
                }
            }
        }
        flush()
        return config
    }

    /// Returns `text` with `listen_address` set at the top level, adding it
    /// before the first table if it is missing.
    public static func enablingMetrics(in text: String, address: String = "127.0.0.1:9252") -> String {
        let entry = "listen_address = \"\(address)\""
        var lines = text.components(separatedBy: "\n")
        let firstTable = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
        if let existing = lines[..<firstTable].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("listen_address")
        }) {
            lines[existing] = entry
        } else {
            lines.insert(entry, at: firstTable)
        }
        return lines.joined(separator: "\n")
    }

    /// Returns `text` with the named runner's jobs given `path` as PATH.
    /// Other environment entries are kept. Nil if the runner isn't there.
    public static func settingJobPath(in text: String, runner name: String, path: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            guard lines[i].trimmingCharacters(in: .whitespaces) == "[[runners]]" else { i += 1; continue }
            // The runner's own keys run until its first sub-table or the next runner.
            var end = i + 1
            while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("[") { end += 1 }
            let block = i + 1..<end
            let isTarget = block.contains { idx in
                let l = lines[idx].trimmingCharacters(in: .whitespaces)
                guard l.hasPrefix("name"), let eq = l.firstIndex(of: "=") else { return false }
                return unquote(stripComment(String(l[l.index(after: eq)...])).trimmingCharacters(in: .whitespaces)) == name
            }
            guard isTarget else { i = end; continue }

            var entries: [String] = []
            var range: Range<Int>?
            if let start = block.first(where: { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("environment") }) {
                var stop = start
                var joined = lines[start]
                while !balanced(joined), stop + 1 < end { stop += 1; joined += " " + lines[stop] }
                if let eq = joined.firstIndex(of: "=") {
                    entries = parseArray(stripComment(String(joined[joined.index(after: eq)...])).trimmingCharacters(in: .whitespaces))
                }
                range = start..<(stop + 1)
            }
            entries.removeAll { $0.hasPrefix("PATH=") }
            entries.insert("PATH=\(path)", at: 0)
            let quoted = entries.map { "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
            let line = "  environment = [\(quoted.joined(separator: ", "))]"
            if let range {
                lines.replaceSubrange(range, with: [line])
            } else {
                // After the runner's last plain key, before any sub-table.
                var at = end
                while at > i + 1, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
                lines.insert(line, at: at)
            }
            return lines.joined(separator: "\n")
        }
        return nil
    }

    static func parseArray(_ value: String) -> [String] {
        var items: [String] = []
        var current = ""
        var inString = false
        var escaped = false
        for c in value {
            if escaped { current.append(c); escaped = false; continue }
            if inString && c == "\\" { escaped = true; continue }
            if c == "\"" {
                if inString { items.append(current); current = "" }
                inString.toggle()
                continue
            }
            if inString { current.append(c) }
        }
        return items
    }

    private static func balanced(_ s: String) -> Bool {
        var depth = 0
        var inString = false
        var previous: Character = " "
        for c in s {
            if c == "\"" && previous != "\\" { inString.toggle() }
            if !inString { if c == "[" { depth += 1 } else if c == "]" { depth -= 1 } }
            previous = c
        }
        return depth <= 0
    }

    private static func stripComment(_ line: String) -> String {
        var inString = false
        for (i, c) in line.enumerated() {
            if c == "\"" { inString.toggle() }
            if c == "#" && !inString { return String(line.prefix(i)) }
        }
        return line
    }

    private static func unquote(_ s: String) -> String {
        if s.count >= 2, (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}
