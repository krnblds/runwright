import RunwrightCore
import RunwrightGitHub
import SlateDesign
import SwiftUI

/// The GitHub runners with their on/off buttons, for the panel and the overview.
struct GitHubRunnersList: View {
    @Environment(GitHubProvider.self) private var github
    @Environment(\.slate) private var cs

    var body: some View {
        let control = github.control
        let rows = github.summaries
        VStack(alignment: .leading, spacing: SlateSpacing.md) {
            if let busy = control.busy {
                HStack(spacing: SlateSpacing.md) {
                    ProgressView().controlSize(.small)
                    Text(busy + "…").foregroundStyle(cs.textSecondary)
                }
            }
            if let error = control.lastError {
                ErrorBanner(text: error) { control.dismissError() }
            }
            VStack(spacing: 0) {
                ForEach(rows) { summary in
                    RunnerLine(summary: summary)
                    if summary.id != rows.last?.id { Hairline() }
                }
            }
        }
    }
}

/// The overview's GitHub Actions pane, under GitLab's.
struct GitHubOverview: View {
    @Environment(GitHubProvider.self) private var github
    @Environment(\.slate) private var cs

    var body: some View {
        let look = StatusLook(status: github.status, demo: false)
        Pane("GitHub Action Runners", icon: "server.rack", status: cs.fill(look.tone), pulsing: look.pulsing) {
            Text(look.detail).font(.system(size: SlateType.tiny)).foregroundStyle(cs.textTertiary)
        } content: {
            GitHubRunnersList()
        }
    }
}

/// The sidebar's GitHub runners, one row per runner folder.
struct GitHubSidebarRunners: View {
    @Environment(GitHubProvider.self) private var github
    @Environment(\.slate) private var cs
    @Binding var section: BoardSection

    var body: some View {
        let summaries = github.summaries
        SectionHeader("GitHub Action Runners", count: summaries.count) {
            Button { section = .githubSetup } label: { Image(systemName: "plus") }
                .buttonStyle(.plain)
                .help("Add a GitHub Actions runner")
        }
        .padding(.top, SlateSpacing.md)

        if summaries.isEmpty {
            Button { section = .githubSetup } label: {
                Text(github.control.hasLooked ? "No runners on this Mac. Add one…" : "Looking for runners…")
                    .font(.system(size: SlateType.tiny))
                    .foregroundStyle(cs.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(SlateSpacing.md)
        } else {
            ForEach(summaries) { summary in
                RunnerSidebarRow(summary: summary, selected: section == .runner(summary.id)) {
                    section = .runner(summary.id)
                }
            }
        }
    }
}

/// The status bar's GitHub segment: how many runners are on.
struct GitHubStatusItems: View {
    @Environment(GitHubProvider.self) private var github

    var body: some View {
        if github.isSetUp {
            let runners = github.control.runners
            let on = runners.filter(\.isRunning).count
            StatusItem("server.rack", "GitHub \(on)/\(runners.count) on")
        }
    }
}

/// GitHub Actions failures, for the failures page.
struct GitHubFailures: View {
    @Environment(GitHubProvider.self) private var github
    @Environment(\.slate) private var cs
    var limit = 50

    var body: some View {
        let failed = github.events.filter { if case .jobFailed = $0 { true } else { false } }.prefix(limit)
        VStack(alignment: .leading, spacing: SlateSpacing.sm) {
            if failed.isEmpty {
                HStack(spacing: SlateSpacing.md) {
                    Image(systemName: "checkmark.seal").foregroundStyle(cs.success.text)
                    Text("No failures since Runwright started.").foregroundStyle(cs.textTertiary)
                }
            }
            ForEach(Array(failed)) { event in
                HStack(spacing: SlateSpacing.md) {
                    Image(systemName: "xmark.octagon").foregroundStyle(cs.danger.text).frame(width: 14)
                    Text(event.title).font(.system(size: SlateType.small, weight: .medium))
                    Text(event.detail).foregroundStyle(cs.textTertiary).lineLimit(1)
                    Spacer()
                    Text(event.date, style: .relative)
                        .font(.system(size: SlateType.micro, design: .monospaced))
                        .foregroundStyle(cs.textTertiary)
                }
            }
        }
    }
}
