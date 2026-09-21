import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let playbackMonitor = PlaybackMonitor()
    private let lyricsCache = LyricsCache()
    private let settings = Settings()
    private let spotifyCredentials = KeychainSpotifyCredentialStore()
    private lazy var spotifyTokens = SpotifyTokenProvider(
        credentials: spotifyCredentials, secretsURL: settings.spotifySecretsURL)
    // Spotify first: it is looked up by track ID, and it is skipped while no cookie is stored.
    private lazy var lyricsResolver = LyricsResolver(
        provider: LyricsProviderChain(providers: [
            SpotifyLyricsProvider(tokenProvider: spotifyTokens), LRCLibProvider(),
        ]),
        cache: lyricsCache)
    private lazy var launchAtLogin = LaunchAtLoginController(settings: settings)
    private lazy var spotifyAccount = SpotifyAccountController(
        credentials: spotifyCredentials, verifier: spotifyTokens)
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings, launchAtLogin: launchAtLogin, spotify: spotifyAccount, cache: lyricsCache)
    private var statusItemController: StatusItemController?
    private var playbackObservation: ObservationLoop?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Makes Cmd+W close the settings window; see makeMainMenu().
        NSApplication.shared.mainMenu = makeMainMenu()

        // The login item may have been removed in System Settings since the last run.
        launchAtLogin.syncFromSystem()

        // A saved or removed cookie changes where the lyrics of the current track come from, so the
        // cached result of the previous conditions must not win.
        spotifyAccount.onChange = { [weak self] in
            self?.lyricsResolver.refetch()
        }

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

    // Subscribed before playbackMonitor.start(), so the empty initial state needs no first call.
    private func observePlayback() {
        playbackObservation = ObservationLoop(
            read: { [playbackMonitor] in _ = playbackMonitor.state },
            onChange: { [weak self] in
                guard let self else { return }
                lyricsResolver.resolve(track: playbackMonitor.state.track)
            })
    }
}
