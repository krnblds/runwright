import SwiftUI

// Building blocks in the Command Slate voice. Views compose these instead of
// styling raw Text/Button so every surface reads as one deck.

// MARK: - Text

/// Uppercase, letter-spaced mono "stamped label": the section-heading voice
/// ("RUNNING JOBS", "CAPACITY"). Looks stamped onto gear.
public struct Eyebrow: View {
    @Environment(\.slate) private var cs
    private let text: String
    private let color: Color?

    public init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text.uppercased())
            .font(.system(size: SlateType.stamped, weight: .semibold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(color ?? cs.textTertiary)
            .lineLimit(1)
    }
}

// MARK: - Status light

/// The deck's status light: a dot with a soft glow that breathes while
/// `active` (1.6s period, like the board's StatusPulse).
///
/// The ring is computed from the clock rather than a `repeatForever`
/// animation: a looping transaction started in `onAppear` also captures any
/// layout change in flight (a panel opening, a list redrawing), which made the
/// dot drift and bounce. Every pulse on screen also stays in phase this way.
public struct StatusPulse: View {
    private let color: Color
    private let active: Bool
    private let size: CGFloat
    private static let period: TimeInterval = 1.6

    public init(color: Color, active: Bool = true, size: CGFloat = 8) {
        self.color = color
        self.active = active
        self.size = size
    }

    public var body: some View {
        ZStack {
            if active {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let phase = t.truncatingRemainder(dividingBy: Self.period) / Self.period
                    let eased = 1 - pow(1 - phase, 2)
                    Circle()
                        .fill(color.opacity(0.45 * (1 - eased)))
                        .scaleEffect(0.45 + 0.55 * eased)
                }
            }
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: active ? color.opacity(0.8) : .clear, radius: size * 0.6)
        }
        .frame(width: size * 2.4, height: size * 2.4)
        .transaction { $0.animation = nil }
    }
}

// MARK: - Surfaces

/// A square panel: surface fill with a quiet hairline. Optional eyebrow title
/// and a trailing accessory in the header row.
public struct SlatePanel<Content: View, Accessory: View>: View {
    @Environment(\.slate) private var cs
    private let title: String?
    private let accessory: Accessory
    private let content: Content

    public init(
        _ title: String? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SlateSpacing.md) {
            if let title {
                HStack(spacing: SlateSpacing.md) {
                    Eyebrow(title)
                    Spacer(minLength: 0)
                    accessory
                }
            }
            content
        }
        .padding(SlateSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cs.surface)
        .overlay(Rectangle().strokeBorder(cs.border, lineWidth: 1))
    }
}

/// A one-pixel hairline in the quiet border tier.
public struct Hairline: View {
    @Environment(\.slate) private var cs
    public init() {}
    public var body: some View {
        Rectangle().fill(cs.border).frame(height: 1)
    }
}

/// A square list row that washes on hover.
public struct SlateRow<Content: View>: View {
    @Environment(\.slate) private var cs
    @State private var hovering = false
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, SlateSpacing.md)
            .padding(.vertical, SlateSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? cs.hover : .clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

// MARK: - Badges

public enum SlateTone: Sendable {
    case neutral, accent, success, warning, danger, info
}

extension SlateColors {
    public func fill(_ tone: SlateTone) -> Color {
        switch tone {
        case .neutral: idle
        case .accent: accent
        case .success: success.fill
        case .warning: warning.fill
        case .danger: danger.fill
        case .info: info.fill
        }
    }

    public func text(_ tone: SlateTone) -> Color {
        switch tone {
        case .neutral: textSecondary
        case .accent: accentText
        case .success: success.text
        case .warning: warning.text
        case .danger: danger.text
        case .info: info.text
        }
    }

    public func subtle(_ tone: SlateTone) -> Color {
        switch tone {
        case .neutral: hoverStrong
        case .accent: accentSubtle
        case .success: success.subtle
        case .warning: warning.subtle
        case .danger: danger.subtle
        case .info: info.subtle
        }
    }
}

/// A fully rounded status badge: subtle wash, text-safe label.
public struct SlateBadge: View {
    @Environment(\.slate) private var cs
    private let text: String
    private let tone: SlateTone
    private let icon: String?

    public init(_ text: String, tone: SlateTone = .neutral, icon: String? = nil) {
        self.text = text
        self.tone = tone
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: SlateSpacing.sm) {
            if let icon { Image(systemName: icon).font(.system(size: SlateType.micro, weight: .semibold)) }
            Text(text).font(.system(size: SlateType.tiny, weight: .medium))
        }
        .padding(.horizontal, SlateSpacing.md)
        .padding(.vertical, SlateSpacing.xs)
        .foregroundStyle(cs.text(tone))
        .background(Capsule().fill(cs.subtle(tone)))
        .lineLimit(1)
    }
}

// MARK: - Buttons

public enum SlateButtonKind: Sendable {
    /// Solid violet. One per surface.
    case primary
    /// Hairline outline on the surface.
    case secondary
    /// Text only; washes on hover.
    case ghost
    /// Red outline for stop/remove.
    case danger
}

public struct SlateButtonStyle: ButtonStyle {
    let kind: SlateButtonKind
    let compact: Bool

    public init(_ kind: SlateButtonKind = .secondary, compact: Bool = false) {
        self.kind = kind
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind, compact: compact)
    }

    private struct StyledButton: View {
        @Environment(\.slate) private var cs
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        let configuration: Configuration
        let kind: SlateButtonKind
        let compact: Bool

        var body: some View {
            configuration.label
                .font(.system(size: compact ? SlateType.tiny : SlateType.small, weight: .medium))
                .labelStyle(SlateLabelStyle())
                .padding(.horizontal, compact ? SlateSpacing.md : SlateSpacing.lg)
                .frame(height: compact ? 22 : 26)
                .foregroundStyle(foreground)
                .background(RoundedRectangle(cornerRadius: SlateRadius.sm).fill(background))
                .overlay(RoundedRectangle(cornerRadius: SlateRadius.sm).strokeBorder(stroke, lineWidth: 1))
                .opacity(enabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: SlateRadius.sm))
                .onHover { hovering = $0 }
        }

        private var pressed: Bool { configuration.isPressed }

        private var foreground: Color {
            switch kind {
            case .primary: cs.onAccent
            case .secondary, .ghost: cs.textPrimary
            case .danger: cs.danger.text
            }
        }

        private var background: Color {
            switch kind {
            case .primary: pressed ? cs.accent : (hovering ? cs.accentSolid.opacity(0.88) : cs.accentSolid)
            case .secondary, .ghost: pressed ? cs.hoverStrong : (hovering ? cs.hover : .clear)
            case .danger: pressed || hovering ? cs.danger.subtle : .clear
            }
        }

        private var stroke: Color {
            switch kind {
            case .primary, .ghost: .clear
            case .secondary: cs.borderStrong
            case .danger: cs.danger.fill.opacity(0.45)
            }
        }
    }
}

struct SlateLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: SlateSpacing.sm + 1) {
            configuration.icon.font(.system(size: SlateType.tiny, weight: .semibold))
            configuration.title
        }
    }
}

extension ButtonStyle where Self == SlateButtonStyle {
    public static func slate(_ kind: SlateButtonKind = .secondary, compact: Bool = false) -> SlateButtonStyle {
        SlateButtonStyle(kind, compact: compact)
    }
}

// MARK: - Instruments

/// A segmented capacity meter: one square cell per slot, filled cells lit in
/// the tone. Falls back to a continuous bar past 24 slots.
public struct CapacityMeter: View {
    @Environment(\.slate) private var cs
    private let used: Int
    private let total: Int
    private let tone: SlateTone

    public init(used: Int, total: Int, tone: SlateTone = .warning) {
        self.used = used
        self.total = total
        self.tone = tone
    }

    public var body: some View {
        if total > 0 && total <= 24 {
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { i in
                    Rectangle()
                        .fill(i < used ? cs.fill(tone) : cs.hoverStrong)
                        .frame(height: 6)
                        .shadow(color: i < used ? cs.fill(tone).opacity(0.5) : .clear, radius: 3)
                }
            }
        } else {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(cs.hoverStrong)
                    Rectangle()
                        .fill(cs.fill(tone))
                        .frame(width: total > 0 ? geo.size.width * min(1, Double(used) / Double(total)) : 0)
                }
            }
            .frame(height: 6)
        }
    }
}

/// A number with a stamped label under it, for KPI rows.
public struct StatTile: View {
    @Environment(\.slate) private var cs
    private let label: String
    private let value: String
    private let tone: SlateTone?

    public init(_ label: String, value: String, tone: SlateTone? = nil) {
        self.label = label
        self.value = value
        self.tone = tone
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SlateSpacing.sm) {
            Text(value)
                .font(.system(size: SlateType.display, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tone.map { cs.text($0) } ?? cs.textPrimary)
                .contentTransition(.numericText())
            Eyebrow(label)
        }
        .padding(SlateSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cs.surface)
        .overlay(Rectangle().strokeBorder(cs.border, lineWidth: 1))
    }
}

/// A key/value line in the secondary voice, value in mono.
public struct KeyValueRow: View {
    @Environment(\.slate) private var cs
    private let key: String
    private let value: String

    public init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(cs.textTertiary)
            Spacer(minLength: SlateSpacing.lg)
            Text(value)
                .font(.system(size: SlateType.small, design: .monospaced))
                .foregroundStyle(cs.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.system(size: SlateType.small))
    }
}

/// A centred empty/hero block for a surface with nothing to show yet.
public struct EmptyState<Actions: View>: View {
    @Environment(\.slate) private var cs
    private let icon: String
    private let title: String
    private let message: String
    private let actions: Actions

    public init(icon: String, title: String, message: String, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: SlateSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(cs.textTertiary)
            Text(title).font(.system(size: SlateType.large, weight: .semibold))
            Text(message)
                .font(.system(size: SlateType.small))
                .foregroundStyle(cs.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions.padding(.top, SlateSpacing.sm)
        }
        .padding(SlateSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}
