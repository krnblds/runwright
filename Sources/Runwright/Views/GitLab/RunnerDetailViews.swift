import RunwrightCore
import RunwrightGitLab
import SlateDesign
import SwiftUI

/// One registered runner: controls, the tools its jobs can see, its settings
/// and the jobs it's running.
struct RunnerDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(GitLabProvider.self) private var gitlab
    @Environment(\.slate) private var cs
    let runner: RegisteredRunner

    var body: some View {
        let control = gitlab.control
        let on = control.isRunning(runner)
        let jobs = gitlab.store.runningJobs.filter { $0.runner == runner.name }
        VStack(alignment: .leading, spacing: SlateSpacing.lg) {
            ContentHeader(title: runner.name, subtitle: [runner.executor, runner.url].filter { !$0.isEmpty }.joined(separator: " · "))
            Pane(on ? "Running" : "Stopped", status: on ? cs.success.fill : cs.idle, pulsing: on && !jobs.isEmpty) {
                Button { model.perform { await $0.toggle(runner) } } label: {
                    Label(on ? "Stop" : "Start", systemImage: on ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.slate(on ? .danger : .primary, compact: true))
                .disabled(control.busy != nil)
            } content: {
                VStack(alignment: .leading, spacing: SlateSpacing.md) {
                    Text(on ? "This runner is picking up jobs from GitLab." : "This runner isn't picking up jobs. Start it to take jobs from GitLab.")
                        .foregroundStyle(cs.textSecondary)
                    if let busy = control.busy {
                        HStack(spacing: SlateSpacing.md) { ProgressView().controlSize(.small); Text(busy + "…").foregroundStyle(cs.textSecondary) }
                    }
                    if let error = control.lastError { ErrorBanner(text: error) { control.dismissError() } }
                }
            }
            if runner.executor == "shell" {
                Pane("Tools jobs can use", icon: "wrench.and.screwdriver") { ToolsDetail(runner: runner) }
            }
            HStack(alignment: .top, spacing: SlateSpacing.lg) {
                Pane("Running jobs", icon: "list.bullet.rectangle", padded: false) {
                    if jobs.isEmpty {
                        Text("No jobs on this runner right now.").foregroundStyle(cs.textTertiary).padding(SlateSpacing.lg)
                    } else {
                        RunningJobsList(filter: runner.name).padding(SlateSpacing.sm)
                    }
                }
                Pane("Settings", icon: "slider.horizontal.3") {
                    VStack(spacing: SlateSpacing.sm) {
                        KeyValueRow("GitLab", runner.url)
                        KeyValueRow("Runs jobs with", runner.executor)
                        KeyValueRow("Job limit", runner.limit.map(String.init) ?? "none")
                        KeyValueRow("Config file", control.configURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    }
                }
            }
            RunnerLogPane(choices: logChoices(control))
        }
    }
}

extension RunnerDetail {
    /// Its output while it runs in Runwright, and the service's log file
    /// when the service keeps one.
    private func logChoices(_ control: GitLabControl) -> [RunnerLogChoice] {
        let logs = control.serviceLogs
        let empty = control.serviceRunning && logs.isEmpty
            ? "The background service doesn't keep a log. Run all here to follow this runner's output."
            : "Output shows here while this runner runs inside Runwright."
        var choices = [RunnerLogChoice("In Runwright", .app([runner.name, "all runners"]), empty: empty)]
        if !logs.isEmpty {
            choices.append(RunnerLogChoice("Service", .file { logs.first }, empty: "Nothing from the background service yet."))
        }
        return choices
    }
}

/// A runner from an install outside Homebrew (its own binary and config).
/// The whole install starts and stops together.
struct OtherRunnerDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(GitLabProvider.self) private var gitlab
    @Environment(\.slate) private var cs
    let install: OtherInstall
    let runner: RegisteredRunner

    var body: some View {
        let control = gitlab.control
        let on = install.isRunning
        let store = gitlab.store(for: install)
        let jobs = store?.runningJobs.filter { $0.runner == runner.name } ?? []
        VStack(alignment: .leading, spacing: SlateSpacing.lg) {
            ContentHeader(title: runner.name, subtitle: "\(install.label) · \(runner.executor) · \(runner.url)")
            Pane(on ? "Running" : "Stopped", status: on ? cs.success.fill : cs.idle, pulsing: on && !jobs.isEmpty) {
                Button {
                    let i = install
                    model.perform { on ? await $0.stop(i) : await $0.start(i) }
                } label: {
                    Label(on ? "Stop" : "Start", systemImage: on ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.slate(on ? .danger : .primary, compact: true))
                .disabled(control.busy != nil)
            } content: {
                VStack(alignment: .leading, spacing: SlateSpacing.md) {
                    Text(description(on)).foregroundStyle(cs.textSecondary).fixedSize(horizontal: false, vertical: true)
                    if let busy = control.busy {
                        HStack(spacing: SlateSpacing.md) { ProgressView().controlSize(.small); Text(busy + "…").foregroundStyle(cs.textSecondary) }
                    }
                    if install.metricsAddress == nil {
                        NoticeLine(icon: "antenna.radiowaves.left.and.right.slash",
                                   text: on ? "Live status is off, so running jobs can't be shown. Turning it on restarts this runner."
                                            : "Live status is off, so running jobs can't be shown.",
                                   action: "Turn on") {
                            let i = install
                            model.perform { await $0.enableMetrics(in: i) }
                        }
                    }
                }
            }
            if runner.executor == "shell" {
                Pane("Tools jobs can use", icon: "wrench.and.screwdriver") { ToolsDetail(runner: runner, install: install) }
            }
            HStack(alignment: .top, spacing: SlateSpacing.lg) {
                Pane("Running jobs", icon: "list.bullet.rectangle", padded: false) {
                    if store == nil {
                        Text("Turn on live status to see jobs here.").foregroundStyle(cs.textTertiary).padding(SlateSpacing.lg)
                    } else if jobs.isEmpty {
                        Text("No jobs on this runner right now.").foregroundStyle(cs.textTertiary).padding(SlateSpacing.lg)
                    } else {
                        OtherJobsList(jobs: jobs).padding(SlateSpacing.sm)
                    }
                }
                Pane("Settings", icon: "slider.horizontal.3") {
                    VStack(spacing: SlateSpacing.sm) {
                        KeyValueRow("GitLab", runner.url)
                        KeyValueRow("Runs jobs with", runner.executor)
                        KeyValueRow("Live status", install.metricsAddress ?? "off")
                        KeyValueRow("Program", install.binaryURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        KeyValueRow("Config file", install.configURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    }
                }
            }
            RunnerLogPane(choices: [RunnerLogChoice(
                "Output", .app([install.process.name]),
                empty: install.externalPID != nil
                    ? "It was started outside Runwright, so its output goes there. Stop and start it here to follow it."
                    : "Output shows here while it runs inside Runwright.")])
        }
    }

    private func description(_ on: Bool) -> String {
        switch (on, install.externalPID != nil) {
        case (true, true): "Running, started outside Runwright. Stopping it here stops that process."
        case (true, false): "Running inside Runwright. It stops when Runwright quits."
        default: "Not running. Start runs it inside Runwright from its own folder, the way it ran before."
        }
    }
}

/// Running jobs for a store other than the main one.
struct OtherJobsList: View {
    @Environment(\.slate) private var cs
    let jobs: [RunningJob]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                ForEach(jobs) { job in
                    SlateRow {
                        HStack(spacing: SlateSpacing.md) {
                            StatusPulse(color: cs.warning.fill, active: true, size: 6)
                            Text(TransitionDetector.readableStage(job.stage)).font(.system(size: SlateType.base, weight: .medium))
                            Spacer()
                            Text(Duration.seconds(context.date.timeIntervalSince(job.startedAt)).formatted(.time(pattern: .minuteSecond)))
                                .font(.system(size: SlateType.small, design: .monospaced))
                                .foregroundStyle(cs.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

/// Which common tools this runner's jobs can and can't find, next to the
/// Terminal's own view.
struct ToolsDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(GitLabProvider.self) private var gitlab
    @Environment(\.slate) private var cs
    let runner: RegisteredRunner
    /// Runners outside Homebrew write to their own config.toml.
    var install: OtherInstall?

    var body: some View {
        let control = gitlab.control
        let missing = control.missingTools(for: runner)
        let jobPath = control.jobPath(for: runner)
        VStack(alignment: .leading, spacing: SlateSpacing.md) {
            if missing.isEmpty {
                HStack(spacing: SlateSpacing.md) {
                    Image(systemName: "checkmark.circle").foregroundStyle(cs.success.text)
                    Text(runner.jobPath == nil ? "Jobs can find every tool your Terminal has." : "Jobs use your Terminal's tools.")
                        .foregroundStyle(cs.textSecondary)
                }
            } else {
                HStack(spacing: SlateSpacing.md) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(cs.warning.text)
                    Text("Jobs can't find some tools your Terminal has.").foregroundStyle(cs.textSecondary)
                    Spacer()
                    Button("Use my Terminal's tools") {
                        let (r, i) = (runner, install)
                        model.perform { control in
                            if let i { await control.useTerminalTools(for: r, in: i) } else { await control.useTerminalTools(for: r) }
                        }
                    }
                        .buttonStyle(.slate(.primary, compact: true))
                        .disabled(control.busy != nil)
                }
            }
            FlowLayout(spacing: SlateSpacing.sm) {
                ForEach(TerminalTools.watchedTools, id: \.self) { tool in
                    if let found = toolState(tool, missing: missing) {
                        SlateTag(found ? tool : "\(tool) missing", tone: found ? .neutral : .warning)
                    }
                }
            }
            Hairline()
            Eyebrow("Where jobs look")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(jobPath.split(separator: ":").map(String.init), id: \.self) { dir in
                    Text(dir.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: SlateType.tiny, design: .monospaced))
                        .foregroundStyle(cs.textSecondary)
                }
            }
        }
    }

    /// true = jobs find it, false = Terminal has it but jobs don't, nil = neither.
    private func toolState(_ tool: String, missing: [String]) -> Bool? {
        if missing.contains(tool) { return false }
        return TerminalTools.find(tool, in: gitlab.control.jobPath(for: runner)) != nil ? true : nil
    }
}
