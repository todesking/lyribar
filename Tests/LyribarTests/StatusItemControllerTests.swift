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
private final class Recorder {
    var opened = 0
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

    // The menu defers the handler to the main queue, so this waits for that hop.
    @Test func settingsMenuItemReachesTheHandler() async {
        let (controller, _, _, cleanup) = makeController()
        defer { cleanup() }
        let recorder = Recorder()
        controller.onOpenSettings = { recorder.opened += 1 }

        let item = controller.menu.menu.item(withTitle: "Settings…")
        #expect(item?.isEnabled == true)
        if let item, let action = item.action {
            _ = (item.target as? NSObject)?.perform(action, with: item)
        }
        // Time-based: the scheduled work is a main queue hop, and other suites can keep it busy.
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline, recorder.opened == 0 {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(recorder.opened == 1)
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

    // The whole point of the reserved lyric width: the menu bar must not move between lines.
    @Test func widthStaysWhileTheLineChanges() {
        let (controller, settings, _, cleanup) = makeController()
        defer { cleanup() }
        settings.lyricsDisplayMode = .currentLine
        let barView = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        controller.barView = barView

        let track = TrackInfo(id: "spotify:track:abc", title: "Song", artist: "Artist", duration: 200)
        let syncedAt = Date(timeIntervalSince1970: 1_000)
        let lyrics = SyncedLyrics(lines: [
            LyricLine(time: 5, text: "short"),
            LyricLine(time: 10, text: ""),
            LyricLine(time: 20, text: String(repeating: "a much longer line of lyrics ", count: 10)),
        ])
        let state = PlaybackState(track: track, isPlaying: true, syncedPosition: 0, syncedAt: syncedAt)
        let status = LyricsResolver.Status.found(lyrics, source: "lrclib")

        var widths: [CGFloat] = []
        var shown: [String?] = []
        // Before the first line, then each line.
        for offset in [0, 5, 10, 20] as [TimeInterval] {
            controller.render(state: state, status: status, now: syncedAt.addingTimeInterval(offset))
            widths.append(barView.preferredWidth)
            shown.append(barView.content.lyric?.text)
        }

        #expect(shown[0] == nil)
        #expect(shown[1] == "short")
        #expect(shown[2] == nil)
        #expect(shown[3]?.isEmpty == false)
        #expect(widths == [300, 300, 300, 300])
    }

    @Test func scrollingModeShowsTheRibbonAtTheSameWidth() {
        let (controller, _, _, cleanup) = makeController()
        defer { cleanup() }
        let barView = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        controller.barView = barView

        let track = TrackInfo(id: "spotify:track:abc", title: "Song", artist: "Artist", duration: 200)
        let syncedAt = Date(timeIntervalSince1970: 1_000)
        let lyrics = SyncedLyrics(lines: [
            LyricLine(time: 5, text: "short"),
            LyricLine(time: 10, text: ""),
            LyricLine(time: 20, text: String(repeating: "a much longer line of lyrics ", count: 10)),
        ])
        let state = PlaybackState(track: track, isPlaying: true, syncedPosition: 0, syncedAt: syncedAt)
        let status = LyricsResolver.Status.found(lyrics, source: "lrclib")

        var widths: [CGFloat] = []
        var indices: [Int?] = []
        for offset in [0, 5, 10, 20] as [TimeInterval] {
            controller.render(state: state, status: status, now: syncedAt.addingTimeInterval(offset))
            widths.append(barView.preferredWidth)
            indices.append(barView.ribbonView.currentIndex)
            #expect(barView.content.lyric == nil)
            #expect(barView.ribbonView.lyrics == lyrics)
        }

        #expect(indices == [nil, 0, 1, 2])
        #expect(widths == [300, 300, 300, 300])
    }

    // Seeking inside a line leaves the content as it was, but the ribbon still has to follow.
    @Test func playbackReachesTheBarViewEvenWhenTheContentStays() {
        let (controller, _, _, cleanup) = makeController()
        defer { cleanup() }
        let barView = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        controller.barView = barView

        let track = TrackInfo(id: "spotify:track:abc", title: "Song", artist: "Artist", duration: 200)
        let syncedAt = Date(timeIntervalSince1970: 1_000)
        let lyrics = SyncedLyrics(lines: [LyricLine(time: 5, text: "short"), LyricLine(time: 50, text: "next")])
        let status = LyricsResolver.Status.found(lyrics, source: "lrclib")

        let before = PlaybackState(track: track, isPlaying: true, syncedPosition: 10, syncedAt: syncedAt)
        controller.render(state: before, status: status, now: syncedAt)
        let after = PlaybackState(track: track, isPlaying: false, syncedPosition: 30, syncedAt: syncedAt)
        controller.render(state: after, status: status, now: syncedAt)

        #expect(barView.playback == after)
        #expect(barView.marquee.playback == after)
    }

    @Test func switchingTheDisplayModeRefreshesTheBarView() {
        let (controller, settings, scheduler, cleanup) = makeController()
        defer { cleanup() }
        let barView = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        barView.update(content: BarContent(lyric: CurrentLineContent(text: "stale", start: 0, end: 1), trackInfo: "Song – Artist"), maxWidth: 999)
        controller.barView = barView

        settings.lyricsDisplayMode = .currentLine
        scheduler.run()

        #expect(barView.content == BarContent())
        #expect(barView.maxWidth == 300)
    }

    // A track without lyrics shrinks back to the icon and the track info.
    @Test func widthShrinksWithoutLyrics() {
        let (controller, _, _, cleanup) = makeController()
        defer { cleanup() }
        let barView = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        controller.barView = barView

        let track = TrackInfo(id: "spotify:track:abc", title: "Song", artist: "Artist", duration: 200)
        let syncedAt = Date(timeIntervalSince1970: 1_000)
        let state = PlaybackState(track: track, isPlaying: true, syncedPosition: 0, syncedAt: syncedAt)

        controller.render(state: state, status: .notFound, now: syncedAt)
        #expect(barView.preferredWidth < 300)
    }

    // Without a track the content is empty either way, so the bar view starts out with stale
    // content: the refresh is what clears it.
    @Test func showTrackInfoChangeRefreshesTheBarView() {
        let (controller, settings, scheduler, cleanup) = makeController()
        defer { cleanup() }
        let barView = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        barView.update(content: BarContent(lyric: CurrentLineContent(text: "stale", start: 0, end: 1), trackInfo: "Song – Artist"), maxWidth: 999)
        controller.barView = barView

        settings.showTrackInfo = false
        scheduler.run()

        #expect(barView.content == BarContent())
        #expect(barView.maxWidth == 300)
    }
}
