import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let playbackMonitor = PlaybackMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "Lyribar")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.menu = makeMenu()
        self.statusItem = statusItem

        logPlaybackState()
        playbackMonitor.start()
    }

    private func logPlaybackState() {
        let state = withObservationTracking {
            playbackMonitor.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.logPlaybackState()
            }
        }
        let track = state.track.map { "\($0.artist) - \($0.title) [\($0.id)] \($0.duration)s" } ?? "(no track)"
        print("playback: \(state.isPlaying ? "playing" : "paused") \(state.syncedPosition)s \(track)")
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
