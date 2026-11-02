import Foundation
import RunwrightCore

public enum MetricsError: Error, Equatable {
    case unreachable(String)
    case badStatus(Int)
}

/// Something that can produce one scrape of metrics text.
public protocol MetricsSource: Sendable {
    func fetch() async throws -> String
}

/// Reads the runner's Prometheus endpoint (`listen_address`).
public struct MetricsClient: MetricsSource {
    public let url: URL
    private let session: URLSession

    public init(url: URL) {
        self.url = url
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    public func fetch() async throws -> String {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw MetricsError.unreachable(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MetricsError.badStatus(http.statusCode)
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Accepts "127.0.0.1:9252", "localhost:9252/metrics" or a full URL.
    public static func url(from text: String) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if !t.contains("://") { t = "http://" + t }
        guard var components = URLComponents(string: t) else { return nil }
        if components.path.isEmpty || components.path == "/" { components.path = "/metrics" }
        return components.url
    }
}
