import RunwrightGitHub
import SlateDesign
import SwiftUI

/// Puts a GitHub Actions runner on this Mac: downloads the newest release,
/// registers it with the token GitHub shows, and starts it. The token goes
/// straight to the runner's own `config.sh`; Runwright doesn't keep it.
struct GitHubSetupPage: View {
    @Environment(AppModel.self) private var model
    @Environment(GitHubProvider.self) private var github
    @Environment(\.slate) private var cs
    @State private var folder = ""
    @State private var url = ""
    @State private var token = ""
    @State private var name = Host.current().localizedName ?? "my-mac"
    @State private var labels = ""
    @State private var asService = true

    var body: some View {
        let control = github.control
        VStack(alignment: .leading, spacing: SlateSpacing.lg) {
            ContentHeader(title: "Add a GitHub Actions runner",
                          subtitle: control.latestVersion.map { "Installs actions-runner \($0) on this Mac" } ?? "Installs actions-runner on this Mac")
            Pane("1 · Get a token from GitHub", icon: "key") {
                VStack(alignment: .leading, spacing: SlateSpacing.md) {
                    Text("On GitHub open the repository (or organization), then Settings → Actions → Runners → New self-hosted runner. Copy the token from the Configure step: the part after --token.")
                        .foregroundStyle(cs.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { openRunnerSettings() } label: { Label("Open runner settings on GitHub", systemImage: "arrow.up.right.square") }
                        .buttonStyle(.slate(.secondary, compact: true))
                        .help(url.isEmpty ? "Fill in the repository address first to go straight there" : "")
                }
            }
            Pane("2 · Install and register", icon: "arrow.down.circle") {
                VStack(alignment: .leading, spacing: SlateSpacing.md) {
                    field("Repository or organization") { TextField("https://github.com/owner/repo", text: $url) }
                    field("Token") { SecureField("A…", text: $token) }
                    field("Name on GitHub") { TextField("my-mac", text: $name) }
                    field("Extra labels (optional)") { TextField("ios, flutter", text: $labels) }
                    field("Folder") { TextField(control.suggestedFolder().path, text: $folder) }
                    Toggle("Keep it running after Runwright quits (background service)", isOn: $asService)
                        .toggleStyle(.checkbox)
                    Text("Runwright downloads the runner from github.com/actions/runner, hands the token to its config.sh and doesn't keep it. Tokens expire after an hour.")
                        .font(.system(size: SlateType.tiny))
                        .foregroundStyle(cs.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let busy = control.busy {
                        HStack(spacing: SlateSpacing.md) {
                            ProgressView().controlSize(.small)
                            Text(busy + "…").foregroundStyle(cs.textSecondary)
                        }
                    }
                    if let error = control.lastError { ErrorBanner(text: error) { control.dismissError() } }
                    HStack {
                        Spacer()
                        Button { install() } label: { Label("Install runner", systemImage: "arrow.down.circle") }
                            .buttonStyle(.slate(.primary))
                            .disabled(!canInstall || control.busy != nil)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
            if !control.unconfigured.isEmpty {
                Pane("Downloaded but not registered", icon: "exclamationmark.circle") {
                    VStack(alignment: .leading, spacing: SlateSpacing.sm) {
                        Text("These folders have the runner but it isn't registered yet. Pick one as the folder above to register it without downloading again.")
                            .foregroundStyle(cs.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(control.unconfigured, id: \.self) { url in
                            Button { folder = url.path } label: {
                                Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.system(size: SlateType.tiny, design: .monospaced))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Pane("Already have one?", icon: "magnifyingglass") {
                VStack(alignment: .leading, spacing: SlateSpacing.md) {
                    Text("Runwright finds runners in ~/actions-runner, folders next to it whose name starts with actions-runner (and the folders inside them), and any folder a running runner was started from.")
                        .foregroundStyle(cs.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { Task { await github.refresh() } } label: { Label("Look again", systemImage: "arrow.clockwise") }
                        .buttonStyle(.slate(.secondary, compact: true))
                }
            }
        }
        .task { await control.checkLatestVersion() }
    }

    private var canInstall: Bool {
        URL(string: url.trimmingCharacters(in: .whitespaces))?.host() != nil
            && !token.trimmingCharacters(in: .whitespaces).isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func install() {
        let path = folder.trimmingCharacters(in: .whitespaces)
        let target = path.isEmpty ? github.control.suggestedFolder()
            : URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let (u, t, n, l, s) = (url.trimmingCharacters(in: .whitespaces), token.trimmingCharacters(in: .whitespaces),
                               name.trimmingCharacters(in: .whitespaces), labels, asService)
        token = ""
        model.performGitHub { await $0.install(into: target, url: u, token: t, name: n, labels: l, asService: s) }
    }

    /// The repository's runner settings when it's filled in, otherwise GitHub.
    private func openRunnerSettings() {
        let base = url.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "/")))
        let target = URL(string: base)?.host() != nil ? URL(string: "\(base)/settings/actions/runners/new?arch=\(RunnerRelease.arch)&os=osx")
            : URL(string: "https://github.com")
        if let target { NSWorkspace.shared.open(target) }
    }

    private func field<F: View>(_ label: String, @ViewBuilder _ content: () -> F) -> some View {
        VStack(alignment: .leading, spacing: SlateSpacing.sm) {
            Text(label).font(.system(size: SlateType.tiny, weight: .medium)).foregroundStyle(cs.textSecondary)
            content()
        }
    }
}
