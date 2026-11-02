import RunwrightCore
import SlateDesign
import SwiftUI

/// One of the logs a runner page can follow.
struct RunnerLogChoice: Identifiable {
    enum Source {
        /// A file the runner writes, re-read every second like `tail -f`.
        /// Resolved each time, so a newer log file is picked up.
        case file(@MainActor () -> URL?)
        /// Output Runwright captured, from these sources.
        case app(Set<String>)
    }

    let id: String
    let source: Source
    /// What to say while there's nothing to show.
    let empty: String

    init(_ title: String, _ source: Source, empty: String) {
        self.id = title
        self.source = source
        self.empty = empty
    }
}

/// A runner's own log, followed as it's written. With several logs (its
/// output, its diagnostics, the job it's on) a switch picks one.
struct RunnerLogPane: View {
    let choices: [RunnerLogChoice]
    @State private var selected: String?

    var body: some View {
        let current = choices.first { $0.id == selected } ?? choices.first
        Pane("Log", icon: "terminal", padded: false) {
            if choices.count > 1 {
                Picker("", selection: Binding(get: { current?.id ?? "" }, set: { selected = $0 })) {
                    ForEach(choices) { Text($0.id).tag($0.id) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
            }
        } content: {
            Group {
                if let current {
                    switch current.source {
                    case .file(let file): FileTailView(file: file, empty: current.empty).id(current.id)
                    case .app(let sources): LogView(sources: sources, emptyText: current.empty)
                    }
                }
            }
            .frame(height: 320)
        }
    }
}

/// The end of a log file, re-read every second and kept scrolled to the bottom.
struct FileTailView: View {
    @Environment(\.slate) private var cs
    let file: @MainActor () -> URL?
    let empty: String
    @State private var lines: [String] = []
    @State private var url: URL?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if lines.isEmpty {
                            Text(empty).foregroundStyle(cs.textTertiary)
                        }
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            Text(line).foregroundStyle(cs.textSecondary).textSelection(.enabled).id(i)
                        }
                    }
                    .font(.system(size: SlateType.tiny, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SlateSpacing.md)
                }
                .background(cs.bgDeep)
                .onChange(of: lines) { _, lines in
                    if !lines.isEmpty { proxy.scrollTo(lines.count - 1, anchor: .bottom) }
                }
            }
            if let url {
                HStack(spacing: SlateSpacing.md) {
                    Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: SlateType.micro, design: .monospaced))
                        .foregroundStyle(cs.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .buttonStyle(.slate(.ghost, compact: true))
                        .disabled(!FileManager.default.fileExists(atPath: url.path))
                }
                .padding(.horizontal, SlateSpacing.md)
                .padding(.vertical, SlateSpacing.xs)
            }
        }
        .task {
            while !Task.isCancelled {
                let next = file()
                url = next
                let read = await Task.detached { next.flatMap { LogTail.lastLines(of: $0) } ?? [] }.value
                if read != lines { lines = read }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
