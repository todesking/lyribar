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
        // An LSUIElement app is never active, and an inactive app's window opens behind the others.
        NSApplication.shared.activate()
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
