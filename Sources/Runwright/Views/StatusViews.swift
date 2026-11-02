import Charts
import RunwrightCore
import SlateDesign
import SwiftUI

/// How the current state reads at a glance: one label, one tone, one icon.
struct StatusLook {
    var label: String
    var detail: String
    var tone: SlateTone
    var symbol: String
    var pulsing: Bool

    init(status: ProviderStatus, demo: Bool) {
        let running = status.busySlots
        let recentFailure = status.events.contains {
            if case .jobFailed = $0 { return Date.now.timeIntervalSince($0.date) < 300 }
            return false
        }
        switch status.connection {
        case .connecting:
            self.init(label: "Connecting", detail: "Looking for the runner…", tone: .neutral, symbol: "gearshape", pulsing: true)
        case .unreachable:
            self.init(label: "Offline", detail: status.lastError ?? "Runner not answering", tone: .neutral, symbol: "bolt.slash", pulsing: false)
        case .degraded:
            self.init(label: "Trouble", detail: "Requests to \(status.serviceName ?? "the CI server") are failing", tone: .danger, symbol: running > 0 ? "gearshape.2" : "gearshape", pulsing: true)
        case .online where recentFailure:
            self.init(label: running > 0 ? "Running" : "Failing", detail: "A job failed in the last 5 minutes",
                      tone: .danger, symbol: running > 0 ? "gearshape.2" : "gearshape", pulsing: running > 0)
        case .online where running > 0:
            self.init(label: "Running", detail: "\(running) job\(running == 1 ? "" : "s") in progress", tone: .warning, symbol: "gearshape.2", pulsing: true)
        case .online:
            self.init(label: "Idle", detail: "Waiting for jobs", tone: .success, symbol: "gearshape", pulsing: false)
        }
        if demo { detail += " · demo" }
    }

    init(label: String, detail: String, tone: SlateTone, symbol: String, pulsing: Bool) {
        self.label = label
        self.detail = detail
        self.tone = tone
        self.symbol = symbol
        self.pulsing = pulsing
    }
}

/// The top block shared by the panel and the dashboard: light, state, version.
struct StatusHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.slate) private var cs

    var body: some View {
        let look = StatusLook(status: model.status, demo: model.settings.demoMode)
        HStack(spacing: SlateSpacing.md) {
            StatusPulse(color: cs.fill(look.tone), active: look.pulsing, size: 8)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: SlateSpacing.md) {
                    Text(look.label).font(.system(size: SlateType.large, weight: .semibold))
                    if let v = model.status.version {
                        Text("v\(v)")
                            .font(.system(size: SlateType.tiny, design: .monospaced))
                            .foregroundStyle(cs.textTertiary)
                    }
                }
                Text(look.detail)
                    .font(.system(size: SlateType.tiny))
                    .foregroundStyle(cs.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if model.settings.demoMode { SlateBadge("Demo", tone: .accent, icon: "sparkles") }
        }
    }
}

struct CapacityBlock: View {
    @Environment(AppModel.self) private var model
    @Environment(\.slate) private var cs

    var body: some View {
        let used = model.status.busySlots
        let total = model.status.capacity
        VStack(alignment: .leading, spacing: SlateSpacing.sm + 2) {
            HStack {
                Eyebrow("Capacity")
                Spacer()
                Text(total.map { "\(used)/\($0) slots busy" } ?? "\(used) busy")
                    .font(.system(size: SlateType.tiny, design: .monospaced))
                    .foregroundStyle(cs.textSecondary)
                    .contentTransition(.numericText())
            }
            CapacityMeter(used: used, total: total ?? max(used, 1),
                          tone: used == 0 ? .success : .warning)
        }
        .animation(.snappy, value: used)
    }
}

struct RunningJobsList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.slate) private var cs
    var limit: Int = .max
    /// Only this runner's jobs, when set.
    var filter: String?

    var body: some View {
        let jobs = model.status.runningJobs.filter { filter == nil || $0.runner == filter }
        if jobs.isEmpty {
            HStack(spacing: SlateSpacing.md) {
                Image(systemName: "moon.zzz").foregroundStyle(cs.textTertiary)
                Text(model.status.connection == .unreachable ? "No live status while the runner is off." : "No jobs running right now.")
                    .foregroundStyle(cs.textTertiary)
            }
            .padding(.vertical, SlateSpacing.sm)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 0) {
                    ForEach(jobs.prefix(limit)) { job in
                        SlateRow {
                            HStack(spacing: SlateSpacing.md) {
                                StatusPulse(color: cs.warning.fill, active: true, size: 6)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(job.name)
                                        .font(.system(size: SlateType.base, weight: .medium))
                                    Text([job.runner, job.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: SlateType.tiny))
                                        .foregroundStyle(cs.textTertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(elapsed(context.date.timeIntervalSince(job.startedAt)))
                                    .font(.system(size: SlateType.small, design: .monospaced))
                                    .foregroundStyle(cs.textSecondary)
                            }
                        }
                        if job.id != jobs.prefix(limit).last?.id { Hairline() }
                    }
                    if jobs.count > limit {
                        Text("+\(jobs.count - limit) more")
                            .font(.system(size: SlateType.tiny))
                            .foregroundStyle(cs.textTertiary)
                            .padding(.top, SlateSpacing.sm)
                    }
                }
            }
        }
    }

    private func elapsed(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Badges that wrap onto new lines.
struct FlowBadges: View {
    var items: [(String, SlateTone)]
    var body: some View {
        FlowLayout(spacing: SlateSpacing.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in SlateBadge(item.0, tone: item.1) }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (i, p) in result.points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        var points: [CGPoint] = []
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += row + spacing; row = 0 }
            points.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            row = max(row, s.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + row), points)
    }
}
