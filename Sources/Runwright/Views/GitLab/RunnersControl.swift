import RunwrightCore
import RunwrightGitLab
import SlateDesign
import SwiftUI

/// Whole-runner controls plus one row per registered runner with its own
/// start/stop switch.
struct RunnersControl: View {
    @Environment(AppModel.self) private var model
    @Environment(GitLabProvider.self) private var gitlab
    @Environment(\.slate) private var cs
    var compact = false
    @State private var showRegister = false

    var body: some View {
        let control = gitlab.control
        VStack(alignment: .leading, spacing: SlateSpacing.md) {
            if !control.isInstalled {
                SetupSteps(compact: compact)
            } else {
                modeLine(control)
                wholeRunnerButtons(control)
                if let busy = control.busy {
                    HStack(spacing: SlateSpacing.md) {
                        ProgressView().controlSize(.small)
                        Text(busy + "…").foregroundStyle(cs.textSecondary)
                    }
                }
                if let error = control.lastError {
                    ErrorBanner(text: error) { control.dismissError() }
                }
                if !control.metricsEnabled && !control.registeredRunners.isEmpty {
                    NoticeLine(icon: "antenna.radiowaves.left.and.right.slash",
                               text: "Live status is off in config.toml.",
                               action: "Turn on") { model.perform { await $0.enableMetrics() } }
                }
                if control.mode == .individual {
                    NoticeLine(icon: "info.circle",
                               text: "Runners started one by one don't report live jobs. Use Run all for live status.",
                               action: nil) {}
                }
                Hairline()
                if control.registeredRunners.isEmpty {
                    EmptyState(icon: "person.badge.plus", title: "No runners registered",
                               message: "Register this Mac with a GitLab project to start taking jobs.") {
                        Button { showRegister = true } label: { Label("Register a runner", systemImage: "plus") }
                            .buttonStyle(.slate(.primary))
                    }
                } else {
                    let rows = gitlab.summaries.filter { $0.location == nil }
                    VStack(spacing: 0) {
                        ForEach(rows) { summary in
                            RunnerLine(summary: summary)
                            if summary.id != rows.last?.id { Hairline() }
                        }
                    }
                    if !compact {
                        HStack {
                            Button { showRegister = true } label: { Label("Register another", systemImage: "plus") }
                                .buttonStyle(.slate(.ghost, compact: true))
                            Button { model.perform { await $0.verify() } } label: { Label("Check with GitLab", systemImage: "checkmark.shield") }
                                .buttonStyle(.slate(.ghost, compact: true))
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showRegister) { RegisterSheet().slateTheme() }
    }

    private func modeLine(_ control: GitLabControl) -> some View {
        let (text, tone): (String, SlateTone) = switch control.mode {
        case .off: ("Stopped", .neutral)
        case .service: (compact ? "Service" : "Background service", .success)
        case .inApp: (compact ? "In app" : "Running in Runwright", .success)
        case .individual: ("Some runners on", .warning)
        }
        return HStack(spacing: SlateSpacing.md) {
            SlateBadge(text, tone: tone, icon: control.anyRunning ? "play.fill" : "stop.fill")
            if let v = control.version {
                Text("gitlab-runner \(v)").font(.system(size: SlateType.tiny, design: .monospaced)).foregroundStyle(cs.textTertiary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func wholeRunnerButtons(_ control: GitLabControl) -> some View {
        let disabled = control.busy != nil || control.registeredRunners.isEmpty
        HStack(spacing: SlateSpacing.sm) {
            if control.anyRunning {
                Button { model.perform { await $0.stopAll() } } label: { Label("Stop all", systemImage: "stop.fill") }
                    .buttonStyle(.slate(.danger, compact: compact))
                if control.serviceRunning {
                    Button { model.perform { await $0.restartService() } } label: { Label("Restart", systemImage: "arrow.clockwise") }
                        .buttonStyle(.slate(.secondary, compact: compact))
                }
            }
            if !control.serviceRunning {
                Button { model.perform { await $0.startService() } } label: { Label("Start", systemImage: "play.fill") }
                    .buttonStyle(.slate(control.anyRunning ? .secondary : .primary, compact: compact))
                    .help("Start every runner as a background service that keeps going after Runwright quits")
            }
            if !control.appRun.isRunning {
                Button { model.perform { await $0.runInApp() } } label: { Label("Run all here", systemImage: "terminal") }
                    .buttonStyle(.slate(.secondary, compact: compact))
                    .help("Run every runner inside Runwright and show its output in the log")
            }
        }
        .disabled(disabled)
    }
}

/// Shown until gitlab-runner is installed: install, then register, or just
/// try the demo.
struct SetupSteps: View {
    @Environment(AppModel.self) private var model
    @Environment(GitLabProvider.self) private var gitlab
    @Environment(\.slate) private var cs
    var compact = false

    var body: some View {
        let control = gitlab.control
        VStack(alignment: .leading, spacing: SlateSpacing.md) {
            Text("gitlab-runner isn't on this Mac yet")
                .font(.system(size: SlateType.base, weight: .semibold))
            Text("Install it, register it with a GitLab project, and Runwright will show its jobs live. Or try the demo to see how it looks.")
                .foregroundStyle(cs.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let busy = control.busy {
                HStack(spacing: SlateSpacing.md) {
                    ProgressView().controlSize(.small)
                    Text(busy + "… this can take a minute").foregroundStyle(cs.textSecondary)
                }
            }
            if let error = control.lastError { ErrorBanner(text: error) { control.dismissError() } }
            HStack(spacing: SlateSpacing.sm) {
                Button { model.perform { await $0.install() } } label: { Label("Install runner", systemImage: "arrow.down.circle") }
                    .buttonStyle(.slate(.primary, compact: compact))
                    .disabled(control.busy != nil || control.brewPath == nil)
                Button { model.setDemo(!model.settings.demoMode) } label: {
                    Label(model.settings.demoMode ? "Stop demo" : "Try the demo", systemImage: "sparkles")
                }
                .buttonStyle(.slate(.secondary, compact: compact))
            }
        }
    }
}

/// Registers this Mac as a runner with a runner authentication token.
struct RegisterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(GitLabProvider.self) private var gitlab
    @Environment(\.slate) private var cs
    @Environment(\.dismiss) private var dismiss
    @State private var url = "https://gitlab.com"
    @State private var token = ""
    @State private var name = Host.current().localizedName ?? "my-mac"
    @State private var executor = "shell"

    var body: some View {
        VStack(alignment: .leading, spacing: SlateSpacing.lg) {
            Eyebrow("Register a runner")
            Text("In GitLab open your project, then Settings → CI/CD → Runners → New project runner. Copy the token it shows (it starts with glrt-) and paste it here.")
                .foregroundStyle(cs.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            field("GitLab address") { TextField("https://gitlab.com", text: $url) }
            field("Runner token") { SecureField("glrt-…", text: $token) }
            field("Name on this Mac") { TextField("my-mac", text: $name) }
            field("Runs jobs with") {
                Picker("", selection: $executor) {
                    Text("This Mac's shell").tag("shell")
                    Text("Docker").tag("docker")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            Text("The token goes straight to gitlab-runner. Runwright doesn't keep it.")
                .font(.system(size: SlateType.tiny))
                .foregroundStyle(cs.textTertiary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.slate(.ghost))
                Button("Register") {
                    let (u, t, n, e) = (url, token, name, executor)
                    model.perform { await $0.register(url: u, token: t, name: n, executor: e) }
                    dismiss()
                }
                .buttonStyle(.slate(.primary))
                .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || name.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(SlateSpacing.xxl)
        .frame(width: 440)
        .background(cs.surfaceRaised)
    }

    private func field<F: View>(_ label: String, @ViewBuilder _ content: () -> F) -> some View {
        VStack(alignment: .leading, spacing: SlateSpacing.sm) {
            Text(label).font(.system(size: SlateType.tiny, weight: .medium)).foregroundStyle(cs.textSecondary)
            content()
        }
    }
}
