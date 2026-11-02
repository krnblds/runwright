import SwiftUI

// Window chrome in the Command Slate board layout: title-bar tabs, the icon
// activity rail, sidebar rows with counts and tags, pane headers and the
// bottom status bar.

// MARK: - Title bar

/// One tab in the title bar ("Board", "Graph", "Terminals"): icon + label,
/// a raised wash when selected.
public struct TitleTab: View {
    @Environment(\.slate) private var cs
    @State private var hovering = false
    private let title: String
    private let icon: String
    private let selected: Bool
    private let action: () -> Void

    public init(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: SlateSpacing.sm + 1) {
                Image(systemName: icon).font(.system(size: SlateType.tiny, weight: .medium))
                Text(title).font(.system(size: SlateType.small, weight: selected ? .semibold : .medium))
            }
            .padding(.horizontal, SlateSpacing.md)
            .frame(height: 24)
            .foregroundStyle(selected ? cs.textPrimary : cs.textSecondary)
            .background(RoundedRectangle(cornerRadius: SlateRadius.sm).fill(selected ? cs.hoverStrong : (hovering ? cs.hover : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A group of title tabs on a faint tray.
public struct TitleTabs<Content: View>: View {
    @Environment(\.slate) private var cs
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        HStack(spacing: SlateSpacing.xs) { content }
            .padding(SlateSpacing.xs)
            .background(RoundedRectangle(cornerRadius: SlateRadius.sm + 2).fill(cs.hover))
    }
}

// MARK: - Activity rail

/// A square icon button in the far-left rail.
public struct RailButton: View {
    @Environment(\.slate) private var cs
    @State private var hovering = false
    private let icon: String
    private let help: String
    private let selected: Bool
    private let badge: Bool
    private let action: () -> Void

    public init(_ icon: String, help: String, selected: Bool = false, badge: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.help = help
        self.selected = selected
        self.badge = badge
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .frame(width: 32, height: 32)
                .foregroundStyle(selected ? cs.textPrimary : cs.textTertiary)
                .background(RoundedRectangle(cornerRadius: SlateRadius.sm).fill(selected ? cs.hoverStrong : (hovering ? cs.hover : .clear)))
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(cs.warning.fill).frame(width: 6, height: 6).offset(x: -5, y: 5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// The vertical icon rail down the window's left edge.
public struct ActivityRail<Top: View, Bottom: View>: View {
    @Environment(\.slate) private var cs
    private let top: Top
    private let bottom: Bottom

    public init(@ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom = { EmptyView() }) {
        self.top = top()
        self.bottom = bottom()
    }

    public var body: some View {
        VStack(spacing: SlateSpacing.sm + 2) {
            top
            Spacer()
            bottom
        }
        .padding(.vertical, SlateSpacing.md)
        .frame(width: 48)
        .frame(maxHeight: .infinity)
        .background(cs.bgDeep)
        .overlay(alignment: .trailing) { Rectangle().fill(cs.border).frame(width: 1) }
    }
}

// MARK: - Sidebar

/// A top-level sidebar entry ("Projects 5"): label left, count right.
public struct SidebarItem: View {
    @Environment(\.slate) private var cs
    @State private var hovering = false
    private let title: String
    private let count: Int?
    private let selected: Bool
    private let action: () -> Void

    public init(_ title: String, count: Int? = nil, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: SlateType.base, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? cs.textPrimary : cs.textSecondary)
                Spacer()
                if let count { CountBadge(count) }
            }
            .padding(.horizontal, SlateSpacing.md)
            .frame(height: 30)
            .background(selected ? cs.hoverStrong : (hovering ? cs.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A small square count chip.
public struct CountBadge: View {
    @Environment(\.slate) private var cs
    private let count: Int
    public init(_ count: Int) { self.count = count }
    public var body: some View {
        Text("\(count)")
            .font(.system(size: SlateType.micro, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(cs.textTertiary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 16)
            .background(RoundedRectangle(cornerRadius: SlateRadius.xs - 1).fill(cs.hover))
    }
}

/// The sidebar's section voice: "THREADS 11" with optional trailing actions.
public struct SectionHeader<Trailing: View>: View {
    @Environment(\.slate) private var cs
    private let title: String
    private let count: Int?
    private let trailing: Trailing

    public init(_ title: String, count: Int? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.count = count
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: SlateSpacing.sm + 2) {
            Text(title.uppercased())
                .font(.system(size: SlateType.tiny - 0.5, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(cs.textTertiary)
            if let count {
                Text("\(count)").font(.system(size: SlateType.tiny - 0.5, weight: .semibold)).foregroundStyle(cs.textDisabled)
            }
            Spacer()
            trailing.foregroundStyle(cs.textTertiary)
        }
        .padding(.horizontal, SlateSpacing.md)
        .frame(height: 26)
    }
}

/// A two-line list row: bold title, muted subtitle, tags underneath, a status
/// light on the right. Selected rows sit on a raised wash with an accent bar.
public struct SidebarRow<Tags: View>: View {
    @Environment(\.slate) private var cs
    @State private var hovering = false
    private let title: String
    private let subtitle: String
    private let status: Color?
    private let pulsing: Bool
    private let selected: Bool
    private let tags: Tags
    private let action: () -> Void

    public init(_ title: String, subtitle: String, status: Color? = nil, pulsing: Bool = false, selected: Bool,
                @ViewBuilder tags: () -> Tags = { EmptyView() }, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.pulsing = pulsing
        self.selected = selected
        self.tags = tags()
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: SlateSpacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: SlateType.base, weight: .semibold))
                        .foregroundStyle(cs.textPrimary)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.system(size: SlateType.tiny))
                        .foregroundStyle(cs.textTertiary)
                        .lineLimit(1)
                    HStack(spacing: SlateSpacing.sm) { tags }
                }
                Spacer(minLength: 0)
                if let status { StatusPulse(color: status, active: pulsing, size: 7).padding(.top, -2) }
            }
            .padding(.horizontal, SlateSpacing.md + 2)
            .padding(.vertical, SlateSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? cs.surfaceOverlay : (hovering ? cs.hover : .clear))
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(cs.accentSolid).frame(width: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A tiny rectangular tag ("3 uncommitted", "Committed").
public struct SlateTag: View {
    @Environment(\.slate) private var cs
    private let text: String
    private let tone: SlateTone

    public init(_ text: String, tone: SlateTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(.system(size: SlateType.micro, weight: .medium))
            .foregroundStyle(cs.text(tone))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(cs.subtle(tone)))
            .lineLimit(1)
    }
}

// MARK: - Panes

/// A pane's header row: grip, status light, title, then trailing actions.
public struct PaneHeader<Trailing: View>: View {
    @Environment(\.slate) private var cs
    private let title: String
    private let icon: String?
    private let status: Color?
    private let pulsing: Bool
    private let trailing: Trailing

    public init(_ title: String, icon: String? = nil, status: Color? = nil, pulsing: Bool = false,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.icon = icon
        self.status = status
        self.pulsing = pulsing
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: SlateSpacing.md) {
            Image(systemName: "circle.grid.2x3.fill")
                .font(.system(size: 8))
                .foregroundStyle(cs.textDisabled)
            if let status { StatusPulse(color: status, active: pulsing, size: 7) }
            if let icon { Image(systemName: icon).font(.system(size: SlateType.tiny)).foregroundStyle(cs.textTertiary) }
            Text(title).font(.system(size: SlateType.base, weight: .semibold)).lineLimit(1)
            Spacer(minLength: SlateSpacing.md)
            trailing
        }
        .padding(.horizontal, SlateSpacing.md + 2)
        .frame(height: 34)
        .background(cs.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(cs.border).frame(height: 1) }
    }
}

/// A pane: header plus content on the deck, with a hairline frame.
public struct Pane<Content: View, Trailing: View>: View {
    @Environment(\.slate) private var cs
    private let title: String
    private let icon: String?
    private let status: Color?
    private let pulsing: Bool
    private let padded: Bool
    private let trailing: Trailing
    private let content: Content

    public init(_ title: String, icon: String? = nil, status: Color? = nil, pulsing: Bool = false, padded: Bool = true,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.status = status
        self.pulsing = pulsing
        self.padded = padded
        self.trailing = trailing()
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title, icon: icon, status: status, pulsing: pulsing) { trailing }
            content
                .padding(padded ? SlateSpacing.lg : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(cs.bg)
        .overlay(Rectangle().strokeBorder(cs.border, lineWidth: 1))
    }
}

/// A labelled reading in the resource-viewer voice: small label, big value.
public struct Readout: View {
    @Environment(\.slate) private var cs
    private let label: String
    private let value: String
    private let tone: SlateTone?

    public init(_ label: String, _ value: String, tone: SlateTone? = nil) {
        self.label = label
        self.value = value
        self.tone = tone
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: SlateType.tiny, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(cs.textTertiary)
            Text(value)
                .font(.system(size: SlateType.large + 2, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tone.map { cs.text($0) } ?? cs.textPrimary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status bar

/// The thin bar along the window's bottom edge.
public struct StatusBar<Leading: View, Trailing: View>: View {
    @Environment(\.slate) private var cs
    private let leading: Leading
    private let trailing: Trailing

    public init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: SlateSpacing.lg) {
            leading
            Spacer()
            trailing
        }
        .font(.system(size: SlateType.tiny))
        .foregroundStyle(cs.textTertiary)
        .padding(.horizontal, SlateSpacing.md + 2)
        .frame(height: 24)
        .background(cs.bgDeep)
        .overlay(alignment: .top) { Rectangle().fill(cs.border).frame(height: 1) }
    }
}

/// One segment of the status bar: icon + text.
public struct StatusItem: View {
    private let icon: String
    private let text: String
    private let color: Color?

    public init(_ icon: String, _ text: String, color: Color? = nil) {
        self.icon = icon
        self.text = text
        self.color = color
    }

    public var body: some View {
        HStack(spacing: SlateSpacing.sm) {
            Image(systemName: icon).font(.system(size: SlateType.micro)).foregroundStyle(color ?? .secondary)
            Text(text).lineLimit(1)
        }
    }
}
