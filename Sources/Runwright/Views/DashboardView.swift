import RunwrightCore
import RunwrightGitHub
import SlateDesign
import SwiftUI

/// What the main area shows.
enum BoardSection: Hashable {
    case overview, jobs, failures, log
    /// How to set up a GitHub Actions runner.
    case githubSetup
    /// A runner, by its summary id.
    case runner(String)

    /// Stored form, so the window reopens where it was left.
    var key: String {
        switch self {
        case .overview: "overview"
        case .jobs: "jobs"
        case .failures: "failures"
        case .log: "log"
        case .githubSetup: "github-setup"
        case .runner(let id): "runner:\(id)"
        }
    }

    init(key: String) {
        switch key {
        case "jobs": self = .jobs
        case "failures": self = .failures
        case "log": self = .log
        case "github-setup": self = .githubSetup
        case let k where k.hasPrefix("runner:"): self = .runner(String(k.dropFirst(7)))
        // Runners outside Homebrew used to be stored as "other:<install id>|<name>",
        // which is their summary id now.
        case let k where k.hasPrefix("other:"): self = .runner(String(k.dropFirst(6)))
        default: self = .overview
        }
    }
}

/// The big window, laid out like the Command Slate board: title-bar tabs,
/// an icon rail, a sidebar of sections and runners, panes, and a status bar.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.slate) private var cs
    @AppStorage("boardSection") private var sectionKey = "overview"
    /// The Log tab's source filter; empty for everything.
    @State private var logSource = ""

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            HStack(spacing: 0) {
                rail
                sidebar
                ScrollView { content.padding(SlateSpacing.lg) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(cs.bg)
            }
            statusBar
        }
        .background(cs.bg)
        .ignoresSafeArea(edges: .top)
        .frame(minWidth: 960, minHeight: 640)
    }

    // MARK: Chrome

    private var titleBar: some View {
        let look = StatusLook(status: model.status, demo: model.settings.demoMode)
        return HStack(spacing: SlateSpacing.md) {
            HStack(spacing: SlateSpacing.sm + 2) {
                Circle().fill(cs.fill(look.tone)).frame(width: 6, height: 6)
                Text(Host.current().localizedName ?? "This Mac")
                    .font(.system(size: SlateType.small, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, SlateSpacing.md)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: SlateRadius.sm).fill(cs.hover))

            TitleTabs {
                TitleTab("Overview", icon: "square.grid.2x2", selected: section == .overview) { section = .overview }
                TitleTab("Jobs", icon: "list.bullet.rectangle", selected: section == .jobs) { section = .jobs }
                TitleTab("Log", icon: "terminal", selected: section == .log) { section = .log }
            }
            Spacer()
            Toggle(isOn: Binding(get: { model.settings.demoMode }, set: { model.setDemo($0) })) {
                Text("Demo").font(.system(size: SlateType.tiny)).foregroundStyle(cs.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            SettingsLink {
                Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(cs.textTertiary)
            }
            .buttonStyle(.plain)
        }
        // Clear the window's traffic lights.
        .padding(.leading, 84)
        .padding(.trailing, SlateSpacing.lg)
        .frame(height: 40)
        .background(cs.bgDeep)
        .overlay(alignment: .bottom) { Rectangle().fill(cs.border).frame(height: 1) }
    }

    private var rail: some View {
        let failing = !failureEvents.isEmpty
        return ActivityRail {
            RailButton("square.grid.2x2", help: "Overview", selected: section == .overview) { section = .overview }
            RailButton("server.rack", help: "Runners", selected: isRunnerSection) {
                if let first = model.summaries.first(where: { $0.location == nil }) ?? model.summaries.first {
                    section = .runner(first.id)
                }
            }
            RailButton("list.bullet.rectangle", help: "Jobs", selected: section == .jobs,
                       badge: model.status.busySlots > 0) { section = .jobs }
            RailButton("exclamationmark.triangle", help: "Failures", selected: section == .failures,
                       badge: failing) { section = .failures }
            RailButton("terminal", help: "Log", selected: section == .log) { section = .log }
        } bottom: {
            RailButton("arrow.up.right.square", help: "Open GitLab") { model.openGitLab() }
            RailButton("doc.text", help: "Show config.toml") { model.openConfig() }
            if model.github.isSetUp {
                RailButton("chevron.left.forwardslash.chevron.right", help: "Open GitHub") { model.openGitHub() }
            }
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    SidebarItem("Overview", selected: section == .overview) { section = .overview }
                    SidebarItem("Jobs", count: model.status.busySlots, selected: section == .jobs) { section = .jobs }
                    SidebarItem("Failures", count: failureEvents.count, selected: section == .failures) { section = .failures }
                    SidebarItem("Log", count: model.log.count, selected: section == .log) { section = .log }
                }
                .padding(.vertical, SlateSpacing.md)
                Hairline()
                GitLabSidebarRunners(section: Binding(get: { section }, set: { section = $0 }))
                GitHubSidebarRunners(section: Binding(get: { section }, set: { section = $0 }))
            }
        }
        .frame(width: 264)
        .background(cs.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(cs.border).frame(width: 1) }
    }

    private var statusBar: some View {
        let look = StatusLook(status: model.status, demo: model.settings.demoMode)
        let status = model.status
        return StatusBar {
            StatusItem("circle.fill", look.label, color: cs.fill(look.tone))
            GitLabStatusItems()
            GitHubStatusItems()
        } trailing: {
            StatusItem("gauge.with.dots.needle.33percent",
                       status.capacity.map { "\(status.busySlots)/\($0) slots" } ?? "\(status.busySlots) busy")
            GitLabLiveStatusItems()
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch section {
        case .overview: OverviewPage()
        case .jobs: JobsPage()
        case .failures: FailuresPage()
        case .log: log
        case .githubSetup: GitHubSetupPage()
        case .runner(let id):
            switch model.summaries.first(where: { $0.id == id })?.provider {
            case .github?: GitHubRunnerPage(summaryID: id)
            case .some: GitLabRunnerPage(summaryID: id)
            case nil: OverviewPage()
            }
        }
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: SlateSpacing.lg) {
            ContentHeader(title: "Log", subtitle: "Output from starting, stopping and running the runner")
            Pane("Runner output", icon: "terminal", padded: false) {
                HStack(spacing: SlateSpacing.sm) {
                    let sources = Array(Set(model.log.map(\.source))).sorted()
                    if sources.count > 1 || !logSource.isEmpty {
                        Picker("", selection: $logSource) {
                            Text("Everything").tag("")
                            ForEach(sources, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                        .help("Show one runner's or command's output")
                    }
                    Button("Clear") { model.clearLog() }.buttonStyle(.slate(.ghost, compact: true))
                }
            } content: {
                LogView(sources: logSource.isEmpty ? nil : [logSource]).frame(minHeight: 460)
            }
        }
    }

    // MARK: Helpers

    private var section: BoardSection {
        get { BoardSection(key: sectionKey) }
        nonmutating set { sectionKey = newValue.key }
    }

    private var isRunnerSection: Bool {
        if case .runner = section { true } else { false }
    }

    private var failureEvents: [RunnerEvent] {
        model.status.events.filter { if case .jobFailed = $0 { true } else { false } }
    }
}

/// The page title above the panes, like a thread's title and project line.
struct ContentHeader: View {
    @Environment(\.slate) private var cs
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: SlateType.large + 1, weight: .semibold))
            Text(subtitle).font(.system(size: SlateType.tiny)).foregroundStyle(cs.textTertiary).lineLimit(1)
        }
        .padding(.bottom, SlateSpacing.xs)
    }
}

/// Every event, newest first.
struct EventFeed: View {
    @Environment(\.slate) private var cs
    let events: [RunnerEvent]

    var body: some View {
        if events.isEmpty {
            Text("Nothing has happened yet.").foregroundStyle(cs.textTertiary).padding(SlateSpacing.lg)
        } else {
            VStack(spacing: 0) {
                ForEach(events.prefix(60)) { event in
                    SlateRow {
                        HStack(spacing: SlateSpacing.md) {
                            Image(systemName: icon(event)).foregroundStyle(color(event)).frame(width: 14)
                            Text(event.title).font(.system(size: SlateType.small, weight: .medium))
                            Text(event.detail).foregroundStyle(cs.textTertiary).lineLimit(1)
                            Spacer()
                            Text(event.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
                                .font(.system(size: SlateType.micro, design: .monospaced))
                                .foregroundStyle(cs.textTertiary)
                        }
                    }
                    Hairline()
                }
            }
        }
    }

    private func icon(_ e: RunnerEvent) -> String {
        switch e {
        case .jobStarted: "play.circle"
        case .jobFinished: "checkmark.circle"
        case .jobFailed: "xmark.octagon"
        case .runnerOffline: "bolt.slash"
        case .runnerOnline: "bolt"
        }
    }

    private func color(_ e: RunnerEvent) -> Color {
        switch e {
        case .jobStarted: cs.warning.text
        case .jobFinished, .runnerOnline: cs.success.text
        case .jobFailed: cs.danger.text
        case .runnerOffline: cs.textTertiary
        }
    }
}

