import Foundation

/// actions-runner releases on github.com. The latest version comes from
/// where `releases/latest` redirects to, not the API, so no token is needed.
public enum RunnerRelease {
    public static let latestPage = URL(string: "https://github.com/actions/runner/releases/latest")!

    /// "arm64" on Apple silicon, "x64" on Intel.
    public static var arch: String {
        #if arch(arm64)
        "arm64"
        #else
        "x64"
        #endif
    }

    /// The version in a release tag page's address, like `…/releases/tag/v2.321.0`.
    public static func version(fromTagURL url: URL) -> String? {
        let parts = url.pathComponents
        guard let i = parts.lastIndex(of: "tag"), i + 1 < parts.count else { return nil }
        let tag = parts[i + 1]
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return parse(version) == nil ? nil : version
    }

    public static func downloadURL(version: String, arch: String = arch) -> URL {
        URL(string: "https://github.com/actions/runner/releases/download/v\(version)/actions-runner-osx-\(arch)-\(version).tar.gz")!
    }

    /// The version `Runner.Listener --version` prints.
    public static func version(fromOutput output: String) -> String? {
        output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { parse($0) != nil }
    }

    /// True when `version` is older than `latest`.
    public static func isOutdated(_ version: String, latest: String) -> Bool {
        guard let a = parse(version), let b = parse(latest) else { return false }
        return a.lexicographicallyPrecedes(b)
    }

    static func parse(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".").map { Int($0) }
        guard parts.count >= 2, !parts.contains(nil) else { return nil }
        return parts.compactMap { $0 }
    }

    /// Asks github.com where `releases/latest` points.
    public static func latestVersion() async -> String? {
        var request = URLRequest(url: latestPage)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let url = response.url else { return nil }
        return version(fromTagURL: url)
    }

    /// Downloads a release into a temporary file.
    public static func download(version: String) async throws -> URL {
        let (temp, response) = try await URLSession.shared.download(from: downloadURL(version: version))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            try? FileManager.default.removeItem(at: temp)
            throw URLError(.badServerResponse)
        }
        // The download's own file goes away when this returns; keep a copy.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("actions-runner-\(version)-\(UUID().uuidString).tar.gz")
        try FileManager.default.moveItem(at: temp, to: kept)
        return kept
    }
}
