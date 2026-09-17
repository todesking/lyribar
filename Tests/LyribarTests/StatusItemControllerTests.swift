import AppKit
import Foundation
import Testing

@testable import Lyribar

/// The status item itself is only created by `start()`, which needs a real status bar; these tests
/// cover the wiring that does not.
/// Runs the observation callbacks on demand instead of on a task hop.
@MainActor
private final class ManualScheduler {
    private var pending: [@MainActor () -> Void] = []

    func enqueue(_ work: @escaping @MainActor () -> Void) {
        pending.append(work)
    }

    func run() {
        let work = pending
        pending = []
        for item in work { item() }
    }
}

@MainActor
struct StatusItemControllerTests {
    private func makeController() -> (StatusItemController, Settings, ManualScheduler, () -> Void) {
        let suite = "LyribarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = Settings(defaults: defaults)
        let cache = LyricsCache(
            directory: URL.temporaryDirectory.appending(path: "lyribar-statusitem-\(UUID().uuidString)"))
        let scheduler = ManualScheduler()
        let controller = StatusItemController(
            monitor: PlaybackMonitor(),
            resolver: LyricsResolver(provider: LRCLibProvider(), cache: cache),
            settings: settings,
            schedule: { work in scheduler.enqueue(work) })
        return (controller, settings, scheduler, { defaults.removePersistentDomain(forName: suite) })
    }

    @Test func settingsMenuItemReachesTheHandler() {
        let (controller, _, _, cleanup) = makeController()
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

    @Test func maxWidthChangeReachesTheBarView() {
        let (controller, settings, scheduler, cleanup) = makeController()
        defer { cleanup() }
        let barView = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        controller.barView = barView

        settings.maxWidth = 200
        scheduler.run()

        #expect(barView.maxWidth == 200)
    }

    // Without a track the content is empty either way, so the bar view starts out with stale
    // content: the refresh is what clears it.
    @Test func showTrackInfoChangeRefreshesTheBarView() {
        let (controller, settings, scheduler, cleanup) = makeController()
        defer { cleanup() }
        let barView = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        barView.update(content: BarContent(lyric: "stale", trackInfo: "Song – Artist"), maxWidth: 999)
        controller.barView = barView

        settings.showTrackInfo = false
        scheduler.run()

        #expect(barView.content == BarContent())
        #expect(barView.maxWidth == 300)
    }
}
