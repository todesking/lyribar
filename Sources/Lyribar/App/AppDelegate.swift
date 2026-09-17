import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let playbackMonitor = PlaybackMonitor()
    private let lyricsResolver = LyricsResolver()
    private var resolvedTrack: TrackInfo?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "Lyribar")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.menu = makeMenu()
        self.statusItem = statusItem

        observePlayback()
        observeLyrics()
        playbackMonitor.start()
    }

    private func observePlayback() {
        let state = withObservationTracking {
            playbackMonitor.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observePlayback()
            }
        }
        let track = state.track.map { "\($0.artist) - \($0.title) [\($0.id)] \($0.duration)s" } ?? "(no track)"
        print("playback: \(state.isPlaying ? "playing" : "paused") \(state.syncedPosition)s \(track)")

        // Compared by id: the duration Spotify reports for the track being played can be revised.
        if state.track?.id != resolvedTrack?.id {
            resolvedTrack = state.track
            lyricsResolver.resolve(track: state.track)
        }
    }

    private func observeLyrics() {
        let status = withObservationTracking {
            lyricsResolver.status
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeLyrics()
            }
        }
        switch status {
        case .idle:
            print("lyrics: idle")
        case .loading:
            print("lyrics: loading")
        case .found(let lyrics, let source):
            print("lyrics: \(lyrics.lines.count) lines from \(source)")
        case .notFound:
            print("lyrics: not found")
        case .failed(let error):
            print("lyrics: failed (\(error))")
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Lyribar を終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }
}
