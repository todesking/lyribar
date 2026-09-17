import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let playbackMonitor = PlaybackMonitor()
    private let lyricsCache = LyricsCache()
    private let settings = Settings()
    private lazy var lyricsResolver = LyricsResolver(provider: LRCLibProvider(), cache: lyricsCache)
    private lazy var launchAtLogin = LaunchAtLoginController(settings: settings)
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings, launchAtLogin: launchAtLogin, cache: lyricsCache)
    private var statusItemController: StatusItemController?
    private var resolvedTrack: TrackInfo?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The login item may have been removed in System Settings since the last run.
        launchAtLogin.syncFromSystem()

        let controller = StatusItemController(
            monitor: playbackMonitor, resolver: lyricsResolver, settings: settings)
        controller.onOpenSettings = { [weak self] in
            self?.settingsWindow.show()
        }
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
