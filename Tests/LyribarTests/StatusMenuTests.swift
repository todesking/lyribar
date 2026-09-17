import AppKit
import Testing
@testable import Lyribar

@MainActor
struct StatusMenuTests {
    private struct StubError: Error {}

    private let track = TrackInfo(id: "spotify:track:abc", title: "Song", artist: "Artist", duration: 200)
    private let lyrics = SyncedLyrics(lines: [LyricLine(time: 0, text: "la")])
    private let syncedAt = Date(timeIntervalSince1970: 1_000)

    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.filter { !$0.isHidden }.map { $0.isSeparatorItem ? "-" : $0.title }
    }

    @Test func withoutTrack() {
        let menu = StatusMenu()
        #expect(titles(menu.menu) == ["Not playing", "-", "Settings…", "-", "Quit Lyribar"])
    }

    @Test func showsTrackAndLyricsStatus() {
        let menu = StatusMenu()
        menu.update(track: track, status: .found(lyrics, source: LRCLibProvider.source))
        #expect(titles(menu.menu) == ["Song – Artist", "Lyrics from LRCLIB", "-", "Settings…", "-", "Quit Lyribar"])
        #expect(!menu.menu.items[0].isEnabled)
        #expect(!menu.menu.items[1].isEnabled)

        menu.update(track: nil, status: .idle)
        #expect(titles(menu.menu).first == "Not playing")
        #expect(menu.menu.items[1].isHidden)
    }

    @Test func lyricsTitles() {
        #expect(StatusMenu.lyricsTitle(.idle) == nil)
        #expect(StatusMenu.lyricsTitle(.loading) == "Loading lyrics…")
        #expect(StatusMenu.lyricsTitle(.notFound) == "No lyrics found")
        #expect(StatusMenu.lyricsTitle(.failed(StubError())) == "Failed to load lyrics")
        #expect(StatusMenu.lyricsTitle(.found(lyrics, source: "other")) == "Lyrics from other")
    }

    @Test func settingsItemInvokesHandler() {
        let menu = StatusMenu()
        var opened = 0
        menu.onOpenSettings = { opened += 1 }
        let item = menu.menu.item(withTitle: "Settings…")
        #expect(item?.isEnabled == true)
        if let item, let action = item.action {
            _ = (item.target as? NSObject)?.perform(action, with: item)
        }
        #expect(opened == 1)
    }

    @Test func statusOfAnotherTrackIsNotShown() {
        let state = PlaybackState(track: track, isPlaying: true, syncedPosition: 0, syncedAt: syncedAt)
        let found = LyricsResolver.Status.found(lyrics, source: "lrclib")
        let other = TrackInfo(id: "spotify:track:xyz", title: "Other", artist: "Artist", duration: 100)
        var revised = track
        revised.duration = 200.027

        #expect(StatusMenu.lyricsTitle(effectiveStatus(state: state, resolvedTrack: other, status: found)) == "Loading lyrics…")
        #expect(StatusMenu.lyricsTitle(effectiveStatus(state: state, resolvedTrack: nil, status: .idle)) == "Loading lyrics…")
        #expect(StatusMenu.lyricsTitle(effectiveStatus(state: state, resolvedTrack: revised, status: found)) == "Lyrics from LRCLIB")
        #expect(StatusMenu.lyricsTitle(effectiveStatus(state: .empty(at: syncedAt), resolvedTrack: track, status: found)) == nil)
    }
}
