import SwiftUI

// The Command Slate control-deck language, ported from
// command-slate/packages/command_design_system: near-black ink surfaces, one
// violet accent, quiet hairlines, square panels and a mono "stamped" eyebrow.
// Everything in Runwright pulls colours, gaps, radii and type sizes from here.

extension Color {
    /// `0xAARRGGBB`, the same notation the Flutter palette uses.
    init(argb: UInt32) {
        self.init(
            .sRGB,
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }
}

/// Raw palette. Call sites read `SlateColors`, never these.
public enum SlatePalette {
    public static let violet400 = Color(argb: 0xFF9B82FF)
    public static let violet500 = Color(argb: 0xFF7C5CFF)
    public static let violet600 = Color(argb: 0xFF7452F2)
    public static let violet700 = Color(argb: 0xFF6142E6)

    public static let ink950 = Color(argb: 0xFF0E0E14)
    public static let ink900 = Color(argb: 0xFF14141B)
    public static let ink850 = Color(argb: 0xFF1C1C27)
    public static let ink800 = Color(argb: 0xFF242433)
    public static let ink500 = Color(argb: 0xFF5C5C6B)
    public static let ink400 = Color(argb: 0xFF84849A)
    public static let ink300 = Color(argb: 0xFFABABC2)
    public static let ink100 = Color(argb: 0xFFEDEDF4)

    public static let paper50 = Color(argb: 0xFFFFFFFF)
    public static let paper100 = Color(argb: 0xFFF4F4F8)
    public static let paper200 = Color(argb: 0xFFEDEDF3)
    public static let paper600 = Color(argb: 0xFF68687E)
    public static let paper700 = Color(argb: 0xFF50506A)
    public static let paper900 = Color(argb: 0xFF1B1B26)

    public static let gold400 = Color(argb: 0xFFF2B237)
    public static let coral400 = Color(argb: 0xFFFF8A4C)
    public static let teal400 = Color(argb: 0xFF3FB984)
    public static let teal300 = Color(argb: 0xFF4CC492)
    public static let red400 = Color(argb: 0xFFF2555A)
    public static let red300 = Color(argb: 0xFFFF6B70)
    public static let blue400 = Color(argb: 0xFF4C8DF5)
    public static let blue300 = Color(argb: 0xFF6FAEFF)
}

/// One status hue in its three roles: a solid fill (dots, bars), a text-safe
/// variant, and a subtle wash for chip backgrounds.
public struct SlateStatus: Sendable {
    public let fill: Color
    public let text: Color
    public let subtle: Color
}

/// Semantic colours for one deck (dark or light). Read with
/// `@Environment(\.slate)`.
public struct SlateColors: Sendable {
    public let bg: Color
    public let bgDeep: Color
    public let surface: Color
    public let surfaceRaised: Color
    public let surfaceOverlay: Color
    public let inputBg: Color
    public let border: Color
    public let borderStrong: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color
    public let textDisabled: Color
    public let accent: Color
    public let accentText: Color
    public let accentSolid: Color
    public let onAccent: Color
    public let accentSubtle: Color
    public let hover: Color
    public let hoverStrong: Color
    public let success: SlateStatus
    public let warning: SlateStatus
    public let danger: SlateStatus
    public let info: SlateStatus
    public let idle: Color

    /// Carbon, Command Slate's default dark deck: unlit graphite with no hue
    /// cast, a cold white-metal brand fill and steel-blue support. Values are
    /// the authored tokens after the roster's 35% deepening and the derived
    /// tiers from CsSemanticTokens.toCsColors.
    public static let carbon = SlateColors(
        bg: Color(argb: 0xFF080809),
        bgDeep: Color(argb: 0xFF060607),
        surface: Color(argb: 0xFF0E0F10),
        surfaceRaised: Color(argb: 0xFF141618),
        surfaceOverlay: Color(argb: 0xFF1D1F21),
        inputBg: Color(argb: 0xFF0C0D0E),
        border: Color(argb: 0x2B696C6F),
        borderStrong: Color(argb: 0x4D696C6F),
        textPrimary: Color(argb: 0xFFECEEF0),
        textSecondary: Color(argb: 0xFFB4BABF),
        textTertiary: Color(argb: 0xFF8A9096),
        textDisabled: Color(argb: 0xFF53575B),
        accent: Color(argb: 0xFFB9C2CB),
        accentText: Color(argb: 0xFFB9C2CB),
        accentSolid: Color(argb: 0xFFD6DBE0),
        onAccent: Color(argb: 0xFF0C0D0E),
        accentSubtle: Color(argb: 0x3DB9C2CB),
        hover: Color(argb: 0x12ECEEF0),
        hoverStrong: Color(argb: 0x1CECEEF0),
        success: .init(fill: Color(argb: 0xFF4FA574), text: Color(argb: 0xFF5DB582), subtle: Color(argb: 0x2E4FA574)),
        warning: .init(fill: Color(argb: 0xFFC9962F), text: Color(argb: 0xFFD4A443), subtle: Color(argb: 0x2EC9962F)),
        danger: .init(fill: Color(argb: 0xFFE05A4F), text: Color(argb: 0xFFE86C62), subtle: Color(argb: 0x2EE05A4F)),
        info: .init(fill: Color(argb: 0xFF5C7EA0), text: Color(argb: 0xFF7F9DBB), subtle: Color(argb: 0x2E5C7EA0)),
        idle: Color(argb: 0xFF5F6469)
    )

    /// The default dark deck.
    public static let dark = carbon

    /// The retired violet brand deck, kept for reference.
    public static let violet = SlateColors(
        bg: SlatePalette.ink950,
        bgDeep: Color(argb: 0xFF0C0C12),
        surface: SlatePalette.ink900,
        surfaceRaised: SlatePalette.ink850,
        surfaceOverlay: SlatePalette.ink800,
        inputBg: Color(argb: 0xFF101018),
        border: Color(argb: 0x14FFFFFF),
        borderStrong: Color(argb: 0x1AFFFFFF),
        textPrimary: SlatePalette.ink100,
        textSecondary: SlatePalette.ink300,
        textTertiary: SlatePalette.ink400,
        textDisabled: SlatePalette.ink500,
        accent: SlatePalette.violet500,
        accentText: SlatePalette.violet400,
        accentSolid: SlatePalette.violet600,
        onAccent: .white,
        accentSubtle: Color(argb: 0x2B7C5CFF),
        hover: Color(argb: 0x12EDEDF4),
        hoverStrong: Color(argb: 0x1CEDEDF4),
        success: .init(fill: SlatePalette.teal400, text: SlatePalette.teal300, subtle: Color(argb: 0x1F3FB984)),
        warning: .init(fill: SlatePalette.gold400, text: SlatePalette.gold400, subtle: Color(argb: 0x1FF2B237)),
        danger: .init(fill: SlatePalette.red400, text: SlatePalette.red300, subtle: Color(argb: 0x1FF2555A)),
        info: .init(fill: SlatePalette.blue400, text: SlatePalette.blue300, subtle: Color(argb: 0x1F4C8DF5)),
        idle: SlatePalette.ink500
    )

    public static let light = SlateColors(
        bg: SlatePalette.paper100,
        bgDeep: SlatePalette.paper200,
        surface: SlatePalette.paper50,
        surfaceRaised: SlatePalette.paper200,
        surfaceOverlay: SlatePalette.paper50,
        inputBg: SlatePalette.paper50,
        border: Color(argb: 0x140B0B10),
        borderStrong: Color(argb: 0x240B0B10),
        textPrimary: SlatePalette.paper900,
        textSecondary: SlatePalette.paper700,
        textTertiary: Color(argb: 0xFF5C5C70),
        textDisabled: Color(argb: 0xFF9C9CAE),
        accent: SlatePalette.violet500,
        accentText: Color(argb: 0xFF5D3DE5),
        accentSolid: SlatePalette.violet600,
        onAccent: .white,
        accentSubtle: Color(argb: 0x247C5CFF),
        hover: Color(argb: 0x0F1B1B26),
        hoverStrong: Color(argb: 0x171B1B26),
        success: .init(fill: Color(argb: 0xFF33976C), text: Color(argb: 0xFF156A47), subtle: Color(argb: 0x1A18774F)),
        warning: .init(fill: Color(argb: 0xFFB77D0C), text: Color(argb: 0xFF805300), subtle: Color(argb: 0x29F2B237)),
        danger: .init(fill: Color(argb: 0xFFF14C51), text: Color(argb: 0xFFB22B33), subtle: Color(argb: 0x1AC22F38)),
        info: .init(fill: Color(argb: 0xFF3E84F4), text: Color(argb: 0xFF2059C4), subtle: Color(argb: 0x1A2059C4)),
        idle: Color(argb: 0xFF87879A)
    )

    public static func forScheme(_ scheme: ColorScheme) -> SlateColors {
        scheme == .dark ? .dark : .light
    }
}

/// The spacing scale. Reach for the nearest step, not a bespoke value.
public enum SlateSpacing {
    public static let xs: CGFloat = 2
    public static let sm: CGFloat = 4
    public static let md: CGFloat = 8
    public static let lg: CGFloat = 12
    public static let xl: CGFloat = 16
    public static let xxl: CGFloat = 20
}

/// Corner radii. Panels and rows are square; only controls and badges round,
/// which is what tells a tappable thing apart from the surface it sits on.
public enum SlateRadius {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 6
    public static let panel: CGFloat = 0
    public static let pill: CGFloat = 20
}

/// The tight 10–14pt control-deck ramp plus the mono stamped eyebrow.
public enum SlateType {
    public static let micro: CGFloat = 10
    public static let tiny: CGFloat = 11
    public static let small: CGFloat = 12
    public static let base: CGFloat = 13
    public static let large: CGFloat = 14
    public static let display: CGFloat = 20
    public static let hero: CGFloat = 24
    public static let stamped: CGFloat = 10.5
}

private struct SlateColorsKey: EnvironmentKey {
    static let defaultValue = SlateColors.dark
}

extension EnvironmentValues {
    public var slate: SlateColors {
        get { self[SlateColorsKey.self] }
        set { self[SlateColorsKey.self] = newValue }
    }
}

/// Picks the dark or light deck from the system appearance and paints the deck
/// background. Put it at the root of every window.
struct SlateThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let colors = SlateColors.forScheme(scheme)
        content
            .environment(\.slate, colors)
            .tint(colors.accent)
            .font(.system(size: SlateType.small))
            .foregroundStyle(colors.textPrimary)
    }
}

extension View {
    public func slateTheme() -> some View { modifier(SlateThemeModifier()) }
}
