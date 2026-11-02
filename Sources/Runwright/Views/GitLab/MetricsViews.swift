import Charts
import RunwrightCore
import RunwrightGitLab
import SlateDesign
import SwiftUI

/// The four headline numbers in the resource-viewer voice.
struct KPIRow: View {
    @Environment(GitLabProvider.self) private var gitlab

    var body: some View {
        let s = gitlab.store
        let errors = s.snapshot?.errorCount ?? 0
        let warnings = s.snapshot?.warningCount ?? 0
        HStack(spacing: SlateSpacing.lg) {
            Readout("JOBS / MIN", String(format: "%.1f", s.jobsPerMinute))
            Readout("FAILS / HR", String(format: "%.0f", s.failuresPerHour), tone: s.failuresPerHour > 0 ? .danger : nil)
            Readout("ERRORS", "\(Int(errors))", tone: errors > 0 ? .danger : nil)
            Readout("WARNINGS", "\(Int(warnings))", tone: warnings > 0 ? .warning : nil)
        }
    }
}

struct Sparklines: View {
    @Environment(GitLabProvider.self) private var gitlab
    @Environment(\.slate) private var cs
    var height: CGFloat = 44

    var body: some View {
        let history = gitlab.store.history
        let fails = gitlab.store.failuresPerMinute
        VStack(alignment: .leading, spacing: SlateSpacing.md) {
            HStack {
                Eyebrow("Concurrent jobs · 15 min")
                Spacer()
                Text("\(gitlab.store.busySlots)").font(.system(size: SlateType.tiny, design: .monospaced)).foregroundStyle(cs.textSecondary)
            }
            Chart(history) { point in
                AreaMark(x: .value("Time", point.date), y: .value("Jobs", point.running))
                    .foregroundStyle(LinearGradient(colors: [cs.accent.opacity(0.16), cs.accent.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.stepEnd)
                LineMark(x: .value("Time", point.date), y: .value("Jobs", point.running))
                    .foregroundStyle(cs.accentText)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.stepEnd)
            }
            .chartYScale(domain: 0...max(1, gitlab.store.capacity ?? 1, history.map(\.running).max() ?? 1))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 2)) { _ in
                    AxisGridLine().foregroundStyle(cs.border)
                }
            }
            .frame(height: height)

            HStack {
                Eyebrow("Failures per minute")
                Spacer()
                Text("\(Int(fails.map(\.count).reduce(0, +)))").font(.system(size: SlateType.tiny, design: .monospaced)).foregroundStyle(cs.textSecondary)
            }
            let peak = max(1, fails.map(\.count).max() ?? 1)
            Chart(Array(fails.enumerated()), id: \.offset) { item in
                // Quiet minutes still draw a sliver so the timeline reads.
                BarMark(x: .value("Minute", String(item.offset)), y: .value("Failures", max(item.element.count, peak * 0.06)), width: .ratio(0.7))
                    .foregroundStyle(item.element.count > 0 ? cs.danger.fill : cs.hoverStrong)
            }
            .chartYScale(domain: 0...peak)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: height * 0.6)
        }
    }
}

struct FailuresAndErrors: View {
    @Environment(GitLabProvider.self) private var gitlab
    @Environment(\.slate) private var cs
    var limit = 5

    var body: some View {
        let reasons = (gitlab.store.snapshot?.failuresByReason ?? [:]).sorted { $0.value > $1.value }
        let recent = gitlab.store.events.filter {
            switch $0 { case .jobFailed, .runnerOffline: true; default: false }
        }.prefix(limit)
        VStack(alignment: .leading, spacing: SlateSpacing.sm) {
            if reasons.isEmpty && recent.isEmpty {
                HStack(spacing: SlateSpacing.md) {
                    Image(systemName: "checkmark.seal").foregroundStyle(cs.success.text)
                    Text("No failures so far.").foregroundStyle(cs.textTertiary)
                }
            }
            if !reasons.isEmpty {
                FlowBadges(items: reasons.map { ("\(TransitionDetector.readable($0.key)) · \(Int($0.value))", SlateTone.danger) })
            }
            ForEach(Array(recent)) { event in
                HStack(spacing: SlateSpacing.md) {
                    Image(systemName: icon(for: event)).foregroundStyle(cs.danger.text).frame(width: 14)
                    Text(event.title).font(.system(size: SlateType.small, weight: .medium))
                    Text(event.detail).foregroundStyle(cs.textTertiary).lineLimit(1)
                    Spacer()
                    Text(event.date, style: .relative)
                        .font(.system(size: SlateType.micro, design: .monospaced))
                        .foregroundStyle(cs.textTertiary)
                }
            }
        }
    }

    private func icon(for event: RunnerEvent) -> String {
        if case .runnerOffline = event { return "bolt.slash" }
        return "xmark.octagon"
    }
}

struct DurationChart: View {
    @Environment(GitLabProvider.self) private var gitlab
    @Environment(\.slate) private var cs

    var body: some View {
        let histogram = gitlab.store.snapshot?.duration ?? DurationHistogram()
        let bars = histogram.distribution
        if histogram.count == 0 {
            Text("No finished jobs yet.").foregroundStyle(cs.textTertiary)
        } else {
            VStack(alignment: .leading, spacing: SlateSpacing.md) {
                Chart(Array(bars.enumerated()), id: \.offset) { item in
                    BarMark(x: .value("Duration", item.element.label), y: .value("Jobs", item.element.count))
                        .foregroundStyle(cs.accent)
                }
                .chartXAxis {
                    AxisMarks { _ in AxisValueLabel().font(.system(size: SlateType.micro)).foregroundStyle(cs.textTertiary) }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(cs.border)
                        AxisValueLabel().font(.system(size: SlateType.micro)).foregroundStyle(cs.textTertiary)
                    }
                }
                .frame(height: 110)
                HStack {
                    KeyValueRow("Finished", "\(Int(histogram.count))")
                    Spacer(minLength: SlateSpacing.xl)
                    KeyValueRow("Average", histogram.average.map(format) ?? "–")
                }
            }
        }
    }

    private func format(_ s: Double) -> String {
        s < 60 ? String(format: "%.0fs", s) : String(format: "%.1fm", s / 60)
    }
}

struct APIHealth: View {
    @Environment(GitLabProvider.self) private var gitlab
    @Environment(\.slate) private var cs

    var body: some View {
        let statuses = (gitlab.store.snapshot?.apiStatuses ?? [:]).filter { $0.value > 0 }.sorted { $0.key < $1.key }
        if statuses.isEmpty {
            Text("No requests to GitLab seen yet.").foregroundStyle(cs.textTertiary)
        } else {
            VStack(spacing: SlateSpacing.sm) {
                ForEach(statuses, id: \.key) { key, value in
                    let parts = key.split(separator: " ")
                    let code = Int(parts.last ?? "") ?? 0
                    HStack {
                        Text(parts.first.map { $0.replacingOccurrences(of: "_", with: " ") } ?? key)
                            .foregroundStyle(cs.textSecondary)
                        Spacer()
                        SlateTag("\(code)", tone: code >= 400 || code == 0 ? .danger : .success)
                        Text("\(Int(value))")
                            .font(.system(size: SlateType.small, design: .monospaced))
                            .foregroundStyle(cs.textTertiary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
    }
}
