import RunwrightCore
import SlateDesign
import SwiftUI

/// The popover under the menu bar icon.
struct PanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.slate) private var cs
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: SlateSpacing.lg) {
                StatusHeader()
                CapacityBlock()
            }
            .padding(SlateSpacing.lg)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: SlateSpacing.lg) {
                    section("Running jobs") { RunningJobsList(limit: 5) }
                    section("Activity") { Sparklines(height: 36) }
                    section("Failures and errors") { FailuresAndErrors(limit: 3) }
                    section("GitLab runners") { RunnersControl(compact: true) }
                    if model.github.isSetUp {
                        section("GitHub Action runners") { GitHubRunnersList() }
                    }
                }
                .padding(SlateSpacing.lg)
            }
            .frame(maxHeight: 520)
            Hairline()
            footer
        }
        .frame(width: 380)
        .background(cs.bg)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: SlateSpacing.md) {
            Eyebrow(title)
            content()
        }
    }

    private var footer: some View {
        HStack(spacing: SlateSpacing.xs) {
            Button { openDashboard() } label: { Label("Dashboard", systemImage: "rectangle.grid.2x2") }
            Button { model.openGitLab() } label: { Label("GitLab", systemImage: "arrow.up.right.square") }
            Button { model.openConfig() } label: { Label("config.toml", systemImage: "doc.text") }
            Spacer()
            Button { NSApp.activate(); openSettings() } label: { Image(systemName: "gearshape") }.help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quit Runwright")
        }
        .buttonStyle(.slate(.ghost, compact: true))
        .padding(.horizontal, SlateSpacing.md)
        .padding(.vertical, SlateSpacing.md)
        .background(cs.surface)
    }

    private func openDashboard() {
        NSApp.activate()
        openWindow(id: "dashboard")
    }
}
