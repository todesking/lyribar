import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let playbackMonitor = PlaybackMonitor()
    private let lyricsResolver = LyricsResolver(provider: LRCLibProvider(), cache: LyricsCache())
    private let settings = Settings()
    private var statusItemController: StatusItemController?
    private var resolvedTrack: TrackInfo?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController(
            monitor: playbackMonitor, resolver: lyricsResolver, settings: settings)
        controller.start()
        statusItemController = controller

        observePlayback()
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

        // Compared by id: the duration Spotify reports for the track being played can be revised.
        if state.track?.id != resolvedTrack?.id {
            resolvedTrack = state.track
            lyricsResolver.resolve(track: state.track)
        }
    }
}
