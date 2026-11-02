import RunwrightCore
import SlateDesign
import SwiftUI

/// Where the runner's live status is read from, how often, or the demo.
struct LiveStatusSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.slate) private var cs
    @State private var address = ""
    @State private var interval = 3.0

    var body: some View {
        @Bindable var settings = model.settings
        SlatePanel("Live status") {
            VStack(alignment: .leading, spacing: SlateSpacing.md) {
                row("Metrics address") {
                    TextField("127.0.0.1:9252", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: SlateType.small, design: .monospaced))
                        .frame(width: 200)
                        .onSubmit(apply)
                }
                row("Check every") {
                    HStack {
                        Slider(value: $interval, in: 1...30, step: 1) { Text("") } onEditingChanged: { editing in
                            if !editing { apply() }
                        }
                        .frame(width: 140)
                        Text("\(Int(interval))s").font(.system(size: SlateType.small, design: .monospaced)).frame(width: 30)
                    }
                }
                row("Demo runner") {
                    Toggle("", isOn: Binding(get: { settings.demoMode }, set: { model.setDemo($0) })).toggleStyle(.switch).labelsHidden()
                }
            }
        }
        .onAppear {
            address = settings.metricsAddress
            interval = settings.pollInterval
        }
    }

    private func apply() {
        model.settings.metricsAddress = address
        model.settings.pollInterval = interval
        model.applySource()
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack {
            Text(label).foregroundStyle(cs.textSecondary)
            Spacer()
            content()
        }
    }
}
