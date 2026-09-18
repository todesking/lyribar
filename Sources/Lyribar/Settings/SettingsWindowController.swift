import AppKit
import SwiftUI

/// Owns the single settings window and keeps it alive across open/close cycles.
@MainActor
final class SettingsWindowController {
    static let title = "Lyribar Settings"

    private let settings: Settings
    private let launchAtLogin: LaunchAtLoginController
    private let cache: LyricsCache
    private(set) var window: NSWindow?

    init(settings: Settings, launchAtLogin: LaunchAtLoginController, cache: LyricsCache) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.cache = cache
    }

    func show() {
        let window = prepareWindow()
        // An accessory app is never active, and an inactive app's window opens behind the others.
        // orderFrontRegardless() puts the window on screen even while the app is still inactive;
        // activate(ignoringOtherApps:) then pulls the app in front of whatever was frontmost.
        // The plain activate() is cooperative -- the frontmost app has to yield, which it does not
        // always do right after a status-bar menu closes -- and the NSRunningApplication option
        // that used to force activation has had no effect since macOS 14, so the (only soft-)
        // deprecated NSApplication call is the one that still works. makeKeyAndOrderFront(nil)
        // comes last, when the app is active and the window can actually take key focus.
        window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Building the window is separate from showing it so tests can inspect it.
    @discardableResult
    func prepareWindow() -> NSWindow {
        if let window { return window }
        let hosting = NSHostingController(
            rootView: SettingsView(settings: settings, launchAtLogin: launchAtLogin, cache: cache))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = Self.title
        // Titled and closable only: no zoom, no minimize, fixed size.
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        return window
    }
}
