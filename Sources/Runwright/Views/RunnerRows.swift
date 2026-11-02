import RunwrightCore
import SlateDesign
import SwiftUI

/// One runner with its own on/off button.
struct RunnerLine: View {
    @Environment(AppModel.self) private var model
    @Environment(\.slate) private var cs
    let summary: RunnerSummary

    var body: some View {
        let on = summary.isOn
        let jobs = summary.runningJobs.count
        SlateRow {
            HStack(spacing: SlateSpacing.md) {
                StatusPulse(color: on ? (jobs > 0 ? cs.warning.fill : cs.success.fill) : cs.idle, active: on, size: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.name).font(.system(size: SlateType.base, weight: .medium)).lineLimit(1)
                    Text([summary.detail, jobs > 0 ? "\(jobs) running" : nil]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: SlateType.tiny))
                        .foregroundStyle(cs.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    model.perform(.toggle, on: summary)
                } label: {
                    Label(on ? "Stop" : "Start", systemImage: on ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.slate(on ? .danger : .secondary, compact: true))
                .disabled(!summary.actions.contains(.toggle))
            }
        }
        if let tools = summary.tools { ToolsLine(summary: summary, tools: tools) }
    }
}

/// Shell jobs only see the runner's search path, not the Terminal's, so
/// tools installed in the home folder (Flutter, nvm, cargo) go missing.
struct ToolsLine: View {
    @Environment(AppModel.self) private var model
    @Environment(\.slate) private var cs
    let summary: RunnerSummary
    let tools: RunnerSummary.Tools

    var body: some View {
        let missing = tools.missing
        HStack(spacing: SlateSpacing.md) {
            if !missing.isEmpty {
                Image(systemName: "wrench.and.screwdriver").foregroundStyle(cs.warning.text)
                Text("Jobs can't find \(missing.joined(separator: ", ")), which your Terminal has.")
                    .foregroundStyle(cs.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: SlateSpacing.md)
                Button("Use my Terminal's tools") { model.perform(.useTerminalTools, on: summary) }
                    .buttonStyle(.slate(.secondary, compact: true))
                    .disabled(!summary.actions.contains(.useTerminalTools))
            } else if tools.hasJobPath {
                Image(systemName: "checkmark.circle").foregroundStyle(cs.success.text)
                Text("Jobs use your Terminal's tools").foregroundStyle(cs.textTertiary)
                Spacer()
            }
        }
        .font(.system(size: SlateType.tiny))
        .padding(.horizontal, SlateSpacing.md)
        .padding(.bottom, SlateSpacing.md)
    }
}

/// One runner in the dashboard's sidebar.
struct RunnerSidebarRow: View {
    @Environment(\.slate) private var cs
    let summary: RunnerSummary
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let on = summary.isOn
        let jobs = summary.runningJobs.count
        let missing = summary.tools?.missing ?? []
        SidebarRow(
            summary.name,
            subtitle: summary.detail,
            status: on ? (jobs > 0 ? cs.warning.fill : cs.success.fill) : cs.idle,
            pulsing: summary.state == .busy,
            selected: selected
        ) {
            SlateTag(on ? "On" : "Stopped", tone: on ? .success : .neutral)
            if jobs > 0 { SlateTag("\(jobs) running", tone: .warning) }
            if !missing.isEmpty { SlateTag("Missing \(missing.count) tool\(missing.count == 1 ? "" : "s")", tone: .warning) }
        } action: {
            action()
        }
    }
}

struct ErrorBanner: View {
    @Environment(\.slate) private var cs
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: SlateSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(cs.danger.text)
            Text(text).foregroundStyle(cs.textPrimary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(cs.textTertiary)
        }
        .padding(SlateSpacing.md)
        .background(cs.danger.subtle)
        .overlay(Rectangle().strokeBorder(cs.danger.fill.opacity(0.35)))
    }
}

struct NoticeLine: View {
    @Environment(\.slate) private var cs
    let icon: String
    let text: String
    let action: String?
    let perform: () -> Void

    var body: some View {
        HStack(spacing: SlateSpacing.md) {
            Image(systemName: icon).foregroundStyle(cs.info.text)
            Text(text).foregroundStyle(cs.textSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let action {
                Button(action, action: perform).buttonStyle(.slate(.secondary, compact: true))
            }
        }
        .padding(SlateSpacing.md)
        .background(cs.info.subtle)
    }
}

/// Streams output from the runner processes and commands.
struct LogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.slate) private var cs
    /// Only lines from these sources, when set.
    var sources: Set<String>?
    var emptyText = "Output from starting, stopping and running the runner shows up here."

    var body: some View {
        let log = sources.map { s in model.log.filter { s.contains($0.source) } } ?? model.log
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if log.isEmpty {
                        Text(emptyText)
                            .foregroundStyle(cs.textTertiary)
                    }
                    ForEach(log) { line in
                        HStack(alignment: .firstTextBaseline, spacing: SlateSpacing.md) {
                            Text(line.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
                                .foregroundStyle(cs.textDisabled)
                            Text(line.source).foregroundStyle(cs.accentText).frame(width: 90, alignment: .leading).lineLimit(1)
                            Text(line.text).foregroundStyle(cs.textSecondary).textSelection(.enabled)
                        }
                        .id(line.id)
                    }
                }
                .font(.system(size: SlateType.tiny, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SlateSpacing.md)
            }
            .background(cs.bgDeep)
            .onChange(of: log.last?.id) { _, id in
                if let id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }
}
