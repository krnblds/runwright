// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Runwright",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Runwright", targets: ["Runwright"])
    ],
    targets: [
        // The Command Slate design system in SwiftUI: tokens and components.
        .target(
            name: "SlateDesign",
            path: "Sources/SlateDesign"
        ),
        // Provider-neutral pieces every CI provider shares: processes, the
        // Terminal's tools, events and the provider protocol. No UI, and no
        // provider: providers depend on it, never the other way round.
        .target(
            name: "RunwrightCore",
            path: "Sources/RunwrightCore"
        ),
        // gitlab-runner: metrics parsing, models, polling and runner control.
        // No UI, so it can be unit tested.
        .target(
            name: "RunwrightGitLab",
            dependencies: ["RunwrightCore"],
            path: "Sources/RunwrightGitLab"
        ),
        // GitHub Actions self-hosted runners: finding runner folders, reading
        // their logs, and starting and stopping them. Local only, no UI.
        .target(
            name: "RunwrightGitHub",
            dependencies: ["RunwrightCore"],
            path: "Sources/RunwrightGitHub"
        ),
        // The SwiftUI app: menu bar extra, dashboard window and settings.
        .executableTarget(
            name: "Runwright",
            dependencies: ["RunwrightCore", "RunwrightGitLab", "RunwrightGitHub", "SlateDesign"],
            path: "Sources/Runwright"
        ),
        .testTarget(
            name: "RunwrightCoreTests",
            dependencies: ["RunwrightCore"],
            path: "Tests/RunwrightCoreTests"
        ),
        .testTarget(
            name: "RunwrightGitLabTests",
            dependencies: ["RunwrightGitLab", "RunwrightCore"],
            path: "Tests/RunwrightGitLabTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "RunwrightGitHubTests",
            dependencies: ["RunwrightGitHub", "RunwrightCore"],
            path: "Tests/RunwrightGitHubTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
