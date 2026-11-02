import RunwrightCore
import RunwrightGitLab
import SlateDesign
import SwiftUI

/// The overview: the Homebrew runner's status, metrics and controls.
struct GitLabOverview: View {
    @Environment(AppModel.self) private var model
    @Environment(GitLabProvider.self) private var gitlab
    @Environment(\.slate) private var cs

    var body: some View {
        let look = StatusLook(status: gitlab.status, demo: model.settings.demoMode)
        VStack(alignment: .leading, spacing: SlateSpacing.lg) {
            ContentHeader(title: "This Mac", subtitle: "GitLab Runner · \(look.detail)")
            Pane("Status", status: cs.fill(look.tone), pulsing: look.pulsing) {
                if model.settings.demoMode { SlateTag("Demo", tone: .info) }
            } content: {
                VStack(alignment: .leading, spacing: SlateSpacing.lg) {
                    CapacityBlock()
                    KPIRow()
                }
            }
            HStack(alignment: .top, spacing: SlateSpacing.lg) {
                VStack(spacing: SlateSpacing.lg) {
                    Pane("Activity", icon: "waveform.path.ecg") { Sparklines(height: 72) }
                    Pane("Job durations", icon: "timer") { DurationChart() }
                    Pane("Connection to GitLab", icon: "network") { APIHealth() }
                }
                VStack(spacing: SlateSpacing.lg) {
                    Pane("GitLab Runners", icon: "server.rack") { RunnersControl(compact: true) }
                    Pane("Running jobs", icon: "list.bullet.rectangle", padded: false) {
                        RunningJobsList().padding(SlateSpacing.sm)
                    }
                    Pane("Failures and errors", icon: "exclamationmark.triangle") { FailuresAndErrors() }
                }
            }
        }
    }
}

/// The failures page's GitLab panes: failure reasons and the API's health.
struct GitLabFailures: View {
    var body: some View {
        Pane("Failures and errors", icon: "exclamationmark.triangle") { FailuresAndErrors(limit: 50) }
        Pane("Connection to GitLab", icon: "network") { APIHealth() }
    }
}

/// A runner's page: the Homebrew runner's, or one from an install elsewhere.
struct GitLabRunnerPage: View {
    @Environment(GitLabProvider.self) private var gitlab
    let summaryID: RunnerSummary.ID

    var body: some View {
        if let (runner, install) = gitlab.runner(for: summaryID) {
            if let install {
                OtherRunnerDetail(install: install, runner: runner)
            } else {
                RunnerDetail(runner: runner)
            }
        }
    }
}

/// The sidebar's runners: the Homebrew install's, then one section per
/// install outside Homebrew.
struct GitLabSidebarRunners: View {
    @Environment(AppModel.self) private var model
    @Environment(GitLabProvider.self) private var gitlab
    @Environment(\.slate) private var cs
    @Binding var section: BoardSection
    @State private var showRegister = false

    var body: some View {
        let control = gitlab.control
        let summaries = gitlab.summaries
        SectionHeader("GitLab Runners", count: control.registeredRunners.count) {
            if control.isInstalled {
                Button { showRegister = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .help("Register a runner")
            }
        }
        .padding(.top, SlateSpacing.md)
        .sheet(isPresented: $showRegister) { RegisterSheet().environment(model).environment(gitlab).slateTheme() }

        if !control.isInstalled {
            SetupSteps(compact: true).padding(SlateSpacing.md)
        } else if control.registeredRunners.isEmpty {
            Text("No runners registered yet.")
                .font(.system(size: SlateType.tiny))
                .foregroundStyle(cs.textTertiary)
                .padding(SlateSpacing.md)
        } else {
            ForEach(summaries.filter { $0.location == nil }) { summary in
                row(summary)
            }
        }

        ForEach(control.others) { install in
            SectionHeader(install.label, count: install.runners.count)
                .padding(.top, SlateSpacing.md)
            ForEach(install.runners) { runner in
                if let summary = summaries.first(where: { $0.id == GitLabProvider.summaryID(runner, in: install) }) {
                    row(summary)
                }
            }
        }
    }

    private func row(_ summary: RunnerSummary) -> some View {
        RunnerSidebarRow(summary: summary, selected: section == .runner(summary.id)) {
            section = .runner(summary.id)
        }
    }
}

/// The status bar's gitlab-runner segments: how it is running and its version.
struct GitLabStatusItems: View {
    @Environment(GitLabProvider.self) private var gitlab

    var body: some View {
        let control = gitlab.control
        if control.isInstalled { StatusItem("server.rack", mode(control.mode)) }
        if let v = control.version { StatusItem("shippingbox", "gitlab-runner \(v)") }
    }

    private func mode(_ mode: GitLabControl.Mode) -> String {
        switch mode {
        case .off: "Stopped"
        case .service: "Background service"
        case .inApp: "Running in Runwright"
        case .individual: "Some runners on"
        }
    }
}

/// The status bar's live-status segments: where it is read from and when.
struct GitLabLiveStatusItems: View {
    @Environment(AppModel.self) private var model
    @Environment(GitLabProvider.self) private var gitlab

    var body: some View {
        StatusItem("antenna.radiowaves.left.and.right", model.settings.demoMode ? "demo" : model.settings.metricsAddress)
        if let updated = gitlab.store.lastUpdated {
            StatusItem("clock", "Updated \(updated.formatted(date: .omitted, time: .standard)) · every \(Int(model.settings.pollInterval))s")
        }
    }
}
