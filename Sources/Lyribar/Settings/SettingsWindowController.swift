import AppKit
import SwiftUI

/// Owns the single settings window and keeps it alive across open/close cycles.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let title = "Lyribar Settings"

    private let settings: Settings
    private let launchAtLogin: LaunchAtLoginController
    private let cache: LyricsCache
    private let activation: any ActivationService
    private var isOpen = false
    /// Who had focus when the window opened; it gets focus back when the window closes.
    private var appToRestore: (any ActivatableApp)?
    private(set) var window: NSWindow?

    init(
        settings: Settings, launchAtLogin: LaunchAtLoginController, cache: LyricsCache,
        activation: any ActivationService = SystemActivationService()
    ) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.cache = cache
        self.activation = activation
    }

    func show() {
        let window = prepareWindow()
        rememberFocusOwner()
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

    /// Remembers the app whose focus `show()` is about to take. Split out of `show()` for the same
    /// reason as `prepareWindow()`: tests can then drive the hand-off without a window on screen.
    func rememberFocusOwner() {
        // Opening the menu again while the window is already up must not overwrite the app we owe
        // focus to -- by then the frontmost app may well be this one.
        guard !isOpen else { return }
        isOpen = true
        let frontmost = activation.frontmostApplication()
        // Focus coming from Lyribar itself is nothing to give back; hiding on close is better.
        appToRestore = frontmost?.isCurrentApp == true ? nil : frontmost
    }

    /// Lyribar is an accessory app, so staying active once its only window is gone would leave the
    /// keyboard focus nowhere: it goes back to the app that had it when the window opened.
    /// The hand-off follows the cooperative activation rules of macOS 14 and later -- yield to the
    /// other app first, then let that app activate itself (both inside `ActivationService`) --
    /// since an app can no longer push another one to the front on its own.
    func windowWillClose(_ notification: Notification) {
        isOpen = false
        let app = appToRestore
        appToRestore = nil
        // The app may be gone by now, and the system may refuse the hand-off anyway. Hiding is the
        // fallback that always works, because the system then picks the next app itself.
        if let app, !app.isTerminated, app.activate() { return }
        activation.hideSelf()
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
        window.delegate = self
        window.center()
        self.window = window
        return window
    }
}
