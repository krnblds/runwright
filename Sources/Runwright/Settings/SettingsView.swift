import SlateDesign
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.slate) private var cs

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: SlateSpacing.lg) {
            LiveStatusSettings()
            SlatePanel("Notifications") {
                VStack(alignment: .leading, spacing: SlateSpacing.md) {
                    Toggle("A job fails", isOn: $settings.notifyFailures)
                    Toggle("The runner is offline for 30 seconds", isOn: $settings.notifyOffline)
                    Toggle("The runner comes back online", isOn: $settings.notifyOnline)
                }
            }
            SlatePanel("App") {
                VStack(alignment: .leading, spacing: SlateSpacing.md) {
                    Toggle("Show in the Dock", isOn: $settings.showInDock)
                        .onChange(of: settings.showInDock) { _, show in
                            NSApp.setActivationPolicy(show ? .regular : .accessory)
                        }
                    Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                        .disabled(!model.canLaunchAtLogin)
                    if !model.canLaunchAtLogin {
                        Text("Available once Runwright is installed as an app.")
                            .font(.system(size: SlateType.tiny))
                            .foregroundStyle(cs.textTertiary)
                    }
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(SlateSpacing.xl)
        .frame(width: 440)
        .background(cs.bg)
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack {
            Text(label).foregroundStyle(cs.textSecondary)
            Spacer()
            content()
        }
    }
}
