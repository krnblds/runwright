import AppKit
import RunwrightCore
import RunwrightGitHub
import RunwrightGitLab
import SlateDesign
import SwiftUI

@main
struct RunwrightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Runwright", id: "dashboard") {
            DashboardView()
                .environment(model)
                .environment(model.gitlab)
                .environment(model.github)
                .slateTheme()
                .onAppear { delegate.model = model }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 760)

        MenuBarExtra {
            PanelView()
                .environment(model)
                .environment(model.gitlab)
                .environment(model.github)
                .slateTheme()
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .environment(model.gitlab)
                .environment(model.github)
                .slateTheme()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let showInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { model?.shutdown() }
    }
}

/// The menu bar icon: a rounded box with a double chevron, a runner moving
/// jobs along. Outlined when idle, filled while jobs run (with a count), red
/// when a job just failed, and dimmed while the runner is off or still
/// being looked for.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let look = StatusLook(status: model.status, demo: model.settings.demoMode)
        let count = model.status.busySlots
        HStack(spacing: 3) {
            Image(nsImage: Self.icon(look: look, running: count > 0))
            if count > 0 { Text("\(count)").monospacedDigit() }
        }
    }

    enum Glyph: Equatable {
        case idle, running, failing, off
    }

    static func glyph(look: StatusLook, running: Bool) -> Glyph {
        if look.symbol == "bolt.slash" || look.label == "Connecting" { return .off }
        if look.tone == .danger { return .failing }
        return running ? .running : .idle
    }

    static func icon(look: StatusLook, running: Bool) -> NSImage {
        icon(glyph(look: look, running: running))
    }

    static func icon(_ glyph: Glyph) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let ink: NSColor = glyph == .failing ? .systemRed : .black.withAlphaComponent(glyph == .off ? 0.45 : 1)
            ink.set()
            let box = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 15, height: 15), xRadius: 4, yRadius: 4)
            let filled = glyph == .running || glyph == .failing
            if filled {
                box.fill()
            } else {
                box.lineWidth = 1.6
                box.stroke()
            }
            let chevrons = NSBezierPath()
            for dx in [0.0, 4.5] {
                chevrons.move(to: NSPoint(x: 5 + dx, y: 5.5))
                chevrons.line(to: NSPoint(x: 8.5 + dx, y: 9))
                chevrons.line(to: NSPoint(x: 5 + dx, y: 12.5))
            }
            chevrons.lineWidth = 1.9
            chevrons.lineCapStyle = .round
            chevrons.lineJoinStyle = .round
            // On a filled box the chevrons are cut out of it.
            if filled { NSGraphicsContext.current?.compositingOperation = .clear }
            chevrons.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = glyph != .failing
        image.accessibilityDescription = "Runwright"
        return image
    }
}
