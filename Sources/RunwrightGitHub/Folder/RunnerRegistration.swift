import Foundation

/// What `config.sh` wrote to a runner folder's `.runner` file: the runner's
/// name, where it takes jobs from and where it does them. The credentials
/// sit next to it in `.credentials`, which Runwright never reads.
public struct RunnerRegistration: Equatable, Sendable {
    public var name: String
    /// The repository or organization, like `https://github.com/owner/repo`.
    public var url: String
    /// Where jobs check out and build, relative to the runner folder unless absolute.
    public var workFolder: String
    /// The runner group.
    public var poolName: String?
    /// Takes one job, then unregisters itself.
    public var ephemeral: Bool

    public init(name: String, url: String, workFolder: String = "_work", poolName: String? = nil, ephemeral: Bool = false) {
        self.name = name
        self.url = url
        self.workFolder = workFolder
        self.poolName = poolName
        self.ephemeral = ephemeral
    }

    /// Nil when it isn't a `.runner` file, or names no runner.
    public static func parse(_ data: Data) -> RunnerRegistration? {
        // .NET writes the file with a byte order mark.
        var data = data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["agentName"] as? String, !name.isEmpty else { return nil }
        return RunnerRegistration(
            name: name,
            url: json["gitHubUrl"] as? String ?? "",
            workFolder: (json["workFolder"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "_work",
            poolName: json["poolName"] as? String,
            ephemeral: json["ephemeral"] as? Bool ?? false
        )
    }

    /// `owner/repo` for a repository runner, `org` for an organization's.
    public var scope: String {
        guard let url = URL(string: url) else { return url }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public var host: String? { URL(string: url)?.host() }

    /// The work folder as a full path, given the runner's folder.
    public func workURL(in root: URL) -> URL {
        workFolder.hasPrefix("/") ? URL(fileURLWithPath: workFolder) : root.appendingPathComponent(workFolder)
    }
}
