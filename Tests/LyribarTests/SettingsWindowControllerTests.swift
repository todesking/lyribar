import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Lyribar

/// Never touches SMAppService: these tests must not change the user's login items.
@MainActor
private struct NoopLaunchAtLoginService: LaunchAtLoginService {
    var isEnabled: Bool { false }
    func register() throws {}
    func unregister() throws {}
}

@MainActor
struct SettingsWindowControllerTests {
    private func makeController() -> (SettingsWindowController, () -> Void) {
        let suite = "LyribarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = Settings(defaults: defaults)
        let cache = LyricsCache(
            directory: URL.temporaryDirectory.appending(path: "lyribar-settings-\(UUID().uuidString)"))
        let controller = SettingsWindowController(
            settings: settings,
            launchAtLogin: LaunchAtLoginController(settings: settings, service: NoopLaunchAtLoginService()),
            cache: cache)
        return (controller, { defaults.removePersistentDomain(forName: suite) })
    }

    @Test func windowIsTitledClosableAndFixedSize() {
        let (controller, cleanup) = makeController()
        defer { cleanup() }

        let window = controller.prepareWindow()

        #expect(window.title == "Lyribar Settings")
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(!window.styleMask.contains(.resizable))
        #expect(!window.styleMask.contains(.miniaturizable))
        #expect(!window.isReleasedWhenClosed)
        #expect(window.contentViewController is NSHostingController<SettingsView>)
    }

    @Test func theSameWindowIsReused() {
        let (controller, cleanup) = makeController()
        defer { cleanup() }

        let first = controller.prepareWindow()
        let second = controller.prepareWindow()

        #expect(first === second)
        #expect(controller.window === first)
    }
}
