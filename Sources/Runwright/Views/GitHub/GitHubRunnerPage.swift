import RunwrightCore
import RunwrightGitHub
import SlateDesign
import SwiftUI

/// One GitHub Actions runner: how it runs, the tools its jobs can see, its
/// settings and the job it's on.
struct GitHubRunnerPage: View {
    @Environment(AppModel.self) private var model
    @Environment(GitHubProvider.self) private var github
    @Environment(\.slate) private var cs
    let summaryID: RunnerSummary.ID

    var body: some View {
        if let runner = github.runner(for: summaryID), let summary = github.summaries.first(where: { $0.id == summaryID }) {
            page(runner, summary)
        }
    }

    private func page(_ runner: GitHubRunner, _ summary: RunnerSummary) -> some View {
        let control = github.control
        let on = runner.isRunning
        let idle = control.busy == nil
        return VStack(alignment: .leading, spacing: SlateSpacing.lg) {
            ContentHeader(title: runner.name, subtitle: [runner.label, runner.registration?.url].compactMap { $0 }.joined(separator: " · "))
            Pane(on ? "Running" : "Stopped", status: on ? cs.success.fill : cs.idle, pulsing: summary.state == .busy) {
                HStack(spacing: SlateSpacing.sm) {
                    if !runner.process.isRunning {
                        Button { model.performGitHub { await $0.runHere(runner) } } label: { Label("Run here", systemImage: "terminal") }
                            .buttonStyle(.slate(.secondary, compact: true))
                            .help("Run run.sh inside Runwright and show its output in the log")
                    }
                    Button { model.perform(.toggle, on: summary) } label: {
                        Label(on ? "Stop" : "Start", systemImage: on ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.slate(on ? .danger : .primary, compact: true))
                }
                .disabled(!idle)
            } content: {
                VStack(alignment: .leading, spacing: SlateSpacing.md) {
                    Text(description(runner)).foregroundStyle(cs.textSecondary).fixedSize(horizontal: false, vertical: true)
                    if let busy = control.busy {
                        HStack(spacing: SlateSpacing.md) { ProgressView().controlSize(.small); Text(busy + "…").foregroundStyle(cs.textSecondary) }
                    }
                    if let error = control.lastError { ErrorBanner(text: error) { control.dismissError() } }
                    if control.updateAvailable(for: runner), let latest = control.latestVersion {
                        NoticeLine(icon: "arrow.down.circle",
                                   text: "actions-runner \(latest) is out (this one is \(control.version(of: runner) ?? "older")).\(on ? " Updating restarts it." : "")",
                                   action: "Update") { model.performGitHub { await $0.update(runner) } }
                    }
                    if runner.serviceInstalled {
                        NoticeLine(icon: "gearshape.2", text: "Installed as a background service, so it starts at login.",
                                   action: "Remove service") { model.performGitHub { await $0.uninstallService(runner) } }
                    } else if runner.folder.hasServiceScript {
                        NoticeLine(icon: "gearshape.2", text: "Install it as a background service to keep it going after Runwright quits.",
                                   action: "Install service") { model.performGitHub { await $0.installService(runner) } }
                    }
                }
            }
            Pane("Tools jobs can use", icon: "wrench.and.screwdriver") { GitHubToolsDetail(runner: runner, summary: summary) }
            HStack(alignment: .top, spacing: SlateSpacing.lg) {
                Pane("Running job", icon: "list.bullet.rectangle", padded: false) {
                    if summary.runningJobs.isEmpty {
                        Text(on ? "No job on this runner right now." : "Start the runner to take jobs.")
                            .foregroundStyle(cs.textTertiary).padding(SlateSpacing.lg)
                    } else {
                        RunningJobsList(filter: runner.name).padding(SlateSpacing.sm)
                    }
                }
                Pane("Settings", icon: "slider.horizontal.3") {
                    VStack(spacing: SlateSpacing.sm) {
                        KeyValueRow("GitHub", runner.registration?.url ?? "unknown")
                        KeyValueRow("Runner group", runner.registration?.poolName ?? "Default")
                        KeyValueRow("Folder", runner.label)
                        KeyValueRow("Work folder", tilde(runner.registration?.workURL(in: runner.root).path ?? "_work"))
                        KeyValueRow("Service", runner.folder.serviceLabel ?? "not installed")
                        KeyValueRow("Version", version(runner))
                        if runner.registration?.ephemeral == true { KeyValueRow("Ephemeral", "takes one job") }
                    }
                }
            }
            RunnerLogPane(choices: logChoices(runner))
            HStack(spacing: SlateSpacing.sm) {
                Button { model.openGitHub(runner) } label: { Label("Open on GitHub", systemImage: "arrow.up.right.square") }
                Button { NSWorkspace.shared.activateFileViewerSelecting([runner.root]) } label: { Label("Show folder", systemImage: "folder") }
                Button { NSWorkspace.shared.open(runner.root.appendingPathComponent("_diag")) } label: { Label("Diagnostic logs", systemImage: "doc.text") }
            }
            .buttonStyle(.slate(.ghost, compact: true))
        }
    }

    private func description(_ runner: GitHubRunner) -> String {
        switch runner.mode {
        case .service: "Running as a background service. It keeps going after Runwright quits."
        case .inApp: "Running inside Runwright. It stops when Runwright quits."
        case .individual: "Running, started outside Runwright (run.sh). Stopping it here stops that process."
        case .off:
            runner.serviceInstalled ? "Not running. Start starts its background service."
                : "Not running. Start runs run.sh inside Runwright."
        }
    }

    /// What it prints (the service's log, or run.sh's output here), its
    /// diagnostic log, and the log of the job it's on.
    private func logChoices(_ runner: GitHubRunner) -> [RunnerLogChoice] {
        var choices: [RunnerLogChoice] = []
        if runner.serviceInstalled && runner.mode != .inApp {
            choices.append(RunnerLogChoice("Output", .file { runner.serviceLogs.first },
                                           empty: "Nothing from the background service yet."))
        } else {
            choices.append(RunnerLogChoice("Output", .app([runner.process.name]), empty: runner.runningElsewhere
                ? "It was started outside Runwright, so its output goes there. The Runner log has the same lines."
                : "run.sh's output shows here while it runs inside Runwright."))
        }
        choices.append(RunnerLogChoice("Runner", .file { runner.diagLog("Runner_") },
                                       empty: "No diagnostic log yet. The runner starts one each time it starts."))
        choices.append(RunnerLogChoice("Job", .file { runner.diagLog("Worker_") }, empty: "No job has run on it yet."))
        if runner.serviceInstalled && runner.mode != .inApp {
            choices.append(RunnerLogChoice("Errors", .file { runner.serviceLogs.dropFirst().first },
                                           empty: "No errors from the background service."))
        }
        return choices
    }

    private func version(_ runner: GitHubRunner) -> String {
        let control = github.control
        guard let version = control.version(of: runner) else { return "unknown" }
        guard let latest = control.latestVersion else { return version }
        return control.updateAvailable(for: runner) ? "\(version) (\(latest) is out)" : "\(version) (newest)"
    }

    private func tilde(_ path: String) -> String { path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
}

/// Which common tools this runner's jobs can and can't find, from its
/// `.path` / `.env`, next to the Terminal's own view.
struct GitHubToolsDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(GitHubProvider.self) private var github
    @Environment(\.slate) private var cs
    let runner: GitHubRunner
    let summary: RunnerSummary

    var body: some View {
        let control = github.control
        let missing = control.missingTools(for: runner)
        let jobPath = control.jobPath(for: runner)
        VStack(alignment: .leading, spacing: SlateSpacing.md) {
            if missing.isEmpty {
                HStack(spacing: SlateSpacing.md) {
                    Image(systemName: "checkmark.circle").foregroundStyle(cs.success.text)
                    Text("Jobs can find every tool your Terminal has.").foregroundStyle(cs.textSecondary)
                }
            } else {
                HStack(spacing: SlateSpacing.md) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(cs.warning.text)
                    Text(runner.isBusy ? "Jobs can't find some tools your Terminal has. Takes effect when it next restarts."
                                       : "Jobs can't find some tools your Terminal has.")
                        .foregroundStyle(cs.textSecondary)
                    Spacer()
                    Button("Use my Terminal's tools") { model.perform(.useTerminalTools, on: summary) }
                        .buttonStyle(.slate(.primary, compact: true))
                        .disabled(!summary.actions.contains(.useTerminalTools))
                }
            }
            FlowLayout(spacing: SlateSpacing.sm) {
                ForEach(TerminalTools.watchedTools, id: \.self) { tool in
                    if missing.contains(tool) {
                        SlateTag("\(tool) missing", tone: .warning)
                    } else if TerminalTools.find(tool, in: jobPath) != nil {
                        SlateTag(tool, tone: .neutral)
                    }
                }
            }
            Hairline()
            Eyebrow(runner.folder.envPath != nil ? "Where jobs look (.env)" : "Where jobs look (.path)")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(jobPath.split(separator: ":").map(String.init), id: \.self) { dir in
                    Text(dir.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: SlateType.tiny, design: .monospaced))
                        .foregroundStyle(cs.textSecondary)
                }
            }
        }
    }
}
