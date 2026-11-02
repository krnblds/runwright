import Foundation
import RunwrightCore

/// One line of the Prometheus text exposition format.
public struct Sample: Equatable, Sendable {
    public var name: String
    public var labels: [String: String]
    public var value: Double

    public init(name: String, labels: [String: String] = [:], value: Double) {
        self.name = name
        self.labels = labels
        self.value = value
    }
}

/// Parses `/metrics` text into samples. Skips `#` comment/HELP/TYPE lines,
/// handles quoted label values with `\"`, `\\` and `\n` escapes, optional
/// timestamps, and the special values `NaN`, `+Inf` and `-Inf`. Lines it cannot
/// read are dropped rather than failing the whole scrape.
public enum PrometheusParser {
    public static func parse(_ text: String) -> [Sample] {
        var samples: [Sample] = []
        samples.reserveCapacity(256)
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if let sample = parseLine(Substring(line)) { samples.append(sample) }
        }
        return samples
    }

    static func parseLine(_ line: Substring) -> Sample? {
        var i = line.startIndex
        // Metric name.
        while i < line.endIndex, line[i] != "{", !line[i].isWhitespace { i = line.index(after: i) }
        let name = String(line[line.startIndex..<i])
        guard !name.isEmpty else { return nil }

        var labels: [String: String] = [:]
        if i < line.endIndex, line[i] == "{" {
            i = line.index(after: i)
            while true {
                skipSpaces(line, &i)
                guard i < line.endIndex else { return nil }
                if line[i] == "}" { i = line.index(after: i); break }
                if line[i] == "," { i = line.index(after: i); continue }
                let keyStart = i
                while i < line.endIndex, line[i] != "=", line[i] != "}" { i = line.index(after: i) }
                guard i < line.endIndex, line[i] == "=" else { return nil }
                let key = line[keyStart..<i].trimmingCharacters(in: .whitespaces)
                i = line.index(after: i)
                skipSpaces(line, &i)
                guard i < line.endIndex, line[i] == "\"" else { return nil }
                i = line.index(after: i)
                var value = ""
                var closed = false
                while i < line.endIndex {
                    let c = line[i]
                    if c == "\\" {
                        let next = line.index(after: i)
                        guard next < line.endIndex else { return nil }
                        switch line[next] {
                        case "n": value.append("\n")
                        case "\\": value.append("\\")
                        case "\"": value.append("\"")
                        default: value.append(line[next])
                        }
                        i = line.index(after: next)
                    } else if c == "\"" {
                        i = line.index(after: i)
                        closed = true
                        break
                    } else {
                        value.append(c)
                        i = line.index(after: i)
                    }
                }
                guard closed else { return nil }
                labels[key] = value
            }
        }

        let rest = line[i...].split(separator: " ", omittingEmptySubsequences: true)
        guard let valueToken = rest.first, let value = parseValue(valueToken) else { return nil }
        return Sample(name: name, labels: labels, value: value)
    }

    static func parseValue(_ token: Substring) -> Double? {
        switch token {
        case "NaN": return .nan
        case "+Inf", "Inf": return .infinity
        case "-Inf": return -.infinity
        default: return Double(token)
        }
    }

    private static func skipSpaces(_ line: Substring, _ i: inout Substring.Index) {
        while i < line.endIndex, line[i].isWhitespace { i = line.index(after: i) }
    }
}
