import AppKit
import Foundation
import Testing

@testable import Lyribar

/// The status item itself is only created by `start()`, which needs a real status bar; these tests
/// cover the wiring that does not.
@MainActor
struct StatusItemControllerTests {
    private func makeController() -> (StatusItemController, Settings, () -> Void) {
        let suite = "LyribarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = Settings(defaults: defaults)
        let cache = LyricsCache(
            directory: URL.temporaryDirectory.appending(path: "lyribar-statusitem-\(UUID().uuidString)"))
        let controller = StatusItemController(
            monitor: PlaybackMonitor(),
            resolver: LyricsResolver(provider: LRCLibProvider(), cache: cache),
            settings: settings)
        return (controller, settings, { defaults.removePersistentDomain(forName: suite) })
    }

    @Test func settingsMenuItemReachesTheHandler() {
        let (controller, _, cleanup) = makeController()
        defer { cleanup() }
        var opened = 0
        controller.onOpenSettings = { opened += 1 }

        let item = controller.menu.menu.item(withTitle: "Settings…")
        #expect(item?.isEnabled == true)
        if let item, let action = item.action {
            _ = (item.target as? NSObject)?.perform(action, with: item)
        }

        #expect(opened == 1)
    }
}
