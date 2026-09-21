import AppKit
import Foundation
import Synchronization
import SwiftUI
import Testing

@testable import Lyribar

/// Never touches SMAppService: these tests must not change the user's login items. Reads are
/// counted, since asking the system is what syncing the login item state amounts to.
@MainActor
private final class CountingLaunchAtLoginService: LaunchAtLoginService {
    private(set) var enabledReads = 0

    var isEnabled: Bool {
        enabledReads += 1
        return false
    }

    func register() throws {}
    func unregister() throws {}
}

/// Never reaches Spotify: the window controller checks the stored cookie when the window opens.
private final class CountingTokenVerifier: SpotifyTokenVerifying {
    private let count = Mutex(0)

    var calls: Int { count.withLock { $0 } }

    func token() async throws -> String {
        count.withLock { $0 += 1 }
        return "token"
    }
}

/// Polls rather than counting yields: a busy machine only makes the wait longer.
@MainActor
private func waitUntil(_ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return false
}

private func makeCache() -> LyricsCache {
    LyricsCache(directory: URL.temporaryDirectory.appending(path: "lyribar-settings-\(UUID().uuidString)"))
}

@MainActor
private final class FakeApp: ActivatableApp {
    var isCurrentApp = false
    var isTerminated = false
    var activateResult = true
    private(set) var activateCount = 0

    func activate() -> Bool {
        activateCount += 1
        return activateResult
    }
}

@MainActor
private final class FakeActivationService: ActivationService {
    var frontmost: FakeApp?
    private(set) var frontmostQueries = 0
    private(set) var hideCount = 0
    /// Never reaches NSApplication: switching the real policy would put the test process in the
    /// Dock. The order matters, so the calls are kept as a list.
    private(set) var policies: [NSApplication.ActivationPolicy] = []

    func frontmostApplication() -> (any ActivatableApp)? {
        frontmostQueries += 1
        return frontmost
    }

    func hideSelf() {
        hideCount += 1
    }

    func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        policies.append(policy)
    }
}

@MainActor
struct SettingsWindowControllerTests {
    private func makeController(
        activation: any ActivationService = FakeActivationService(),
        cache: LyricsCache? = nil,
        launchAtLogin: any LaunchAtLoginService = CountingLaunchAtLoginService(),
        spotify: SpotifyAccountController? = nil
    ) -> (SettingsWindowController, () -> Void) {
        let suite = "LyribarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = Settings(defaults: defaults)
        let cache = cache ?? makeCache()
        let controller = SettingsWindowController(
            settings: settings,
            launchAtLogin: LaunchAtLoginController(settings: settings, service: launchAtLogin),
            spotify: spotify
                ?? SpotifyAccountController(
                    credentials: InMemorySpotifyCredentialStore(), verifier: CountingTokenVerifier()),
            cache: cache,
            activation: activation)
        return (
            controller,
            {
                defaults.removePersistentDomain(forName: suite)
                try? FileManager.default.removeItem(at: cache.directory)
            }
        )
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

    /// A reused window stays on the Space it was closed on, so it has to follow the active one.
    @Test func windowMovesToTheActiveSpace() {
        let (controller, cleanup) = makeController()
        defer { cleanup() }

        let window = controller.prepareWindow()

        #expect(window.collectionBehavior.contains(.moveToActiveSpace))
    }

    @Test func theSameWindowIsReused() {
        let (controller, cleanup) = makeController()
        defer { cleanup() }

        let first = controller.prepareWindow()
        let second = controller.prepareWindow()

        #expect(first === second)
        #expect(controller.window === first)
    }

    /// Opening and closing the window, without putting it on screen: `show()` would activate the
    /// test process, so only the focus bookkeeping of it is driven here.
    private func openAndClose(_ controller: SettingsWindowController) {
        let window = controller.prepareWindow()
        controller.rememberFocusOwner()
        window.close()
    }

    @Test func focusGoesBackToTheAppThatHadIt() {
        let activation = FakeActivationService()
        let previous = FakeApp()
        activation.frontmost = previous
        let (controller, cleanup) = makeController(activation: activation)
        defer { cleanup() }

        openAndClose(controller)

        #expect(previous.activateCount == 1)
        #expect(activation.hideCount == 0)
    }

    @Test func closingHidesWhenThereIsNoAppToGoBackTo() {
        let activation = FakeActivationService()
        activation.frontmost = nil
        let (controller, cleanup) = makeController(activation: activation)
        defer { cleanup() }

        openAndClose(controller)

        #expect(activation.hideCount == 1)
    }

    @Test func lyribarItselfIsNotRememberedAsTheFocusOwner() {
        let activation = FakeActivationService()
        let itself = FakeApp()
        itself.isCurrentApp = true
        activation.frontmost = itself
        let (controller, cleanup) = makeController(activation: activation)
        defer { cleanup() }

        openAndClose(controller)

        #expect(itself.activateCount == 0)
        #expect(activation.hideCount == 1)
    }

    @Test func hidingIsTheFallbackWhenActivationIsRefused() {
        let activation = FakeActivationService()
        let previous = FakeApp()
        previous.activateResult = false
        activation.frontmost = previous
        let (controller, cleanup) = makeController(activation: activation)
        defer { cleanup() }

        openAndClose(controller)

        #expect(previous.activateCount == 1)
        #expect(activation.hideCount == 1)
    }

    @Test func aQuitAppIsNotActivated() {
        let activation = FakeActivationService()
        let previous = FakeApp()
        previous.isTerminated = true
        activation.frontmost = previous
        let (controller, cleanup) = makeController(activation: activation)
        defer { cleanup() }

        openAndClose(controller)

        #expect(previous.activateCount == 0)
        #expect(activation.hideCount == 1)
    }

    @Test func reopeningDoesNotForgetTheOriginalFocusOwner() {
        let activation = FakeActivationService()
        let previous = FakeApp()
        let later = FakeApp()
        activation.frontmost = previous
        let (controller, cleanup) = makeController(activation: activation)
        defer { cleanup() }

        let window = controller.prepareWindow()
        controller.rememberFocusOwner()
        activation.frontmost = later
        controller.rememberFocusOwner()
        window.close()

        #expect(activation.frontmostQueries == 1)
        #expect(previous.activateCount == 1)
        #expect(later.activateCount == 0)
    }

    @Test func aSecondOpenAfterCloseRemembersAgain() {
        let activation = FakeActivationService()
        let previous = FakeApp()
        let later = FakeApp()
        activation.frontmost = previous
        let (controller, cleanup) = makeController(activation: activation)
        defer { cleanup() }

        let window = controller.prepareWindow()
        openAndClose(controller)
        activation.frontmost = later
        controller.rememberFocusOwner()
        // A window that was never on screen is closed once and stays closed, so the second close is
        // driven through the delegate method the other tests reach through close().
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))

        #expect(activation.frontmostQueries == 2)
        #expect(previous.activateCount == 1)
        #expect(later.activateCount == 1)
        #expect(activation.hideCount == 0)
    }

    private let track = TrackInfo(
        id: "spotify:track:abc", title: "Song Name", artist: "The Artist", duration: 222.0)
    private let otherTrack = TrackInfo(
        id: "spotify:track:xyz", title: "Other Song", artist: "Nobody", duration: 100.0)
    private let lyrics = SyncedLyrics(lines: [LyricLine(time: 1, text: "First")])

    /// The window keeps the view it was built with, so what it shows is synced by the controller.
    /// `show()` would activate the test process, so the two halves of it are driven separately.
    @Test func refreshingPicksUpCacheGrowth() {
        let cache = makeCache()
        let (controller, cleanup) = makeController(cache: cache)
        defer { cleanup() }

        controller.prepareWindow()
        controller.refreshContents()
        #expect(controller.cacheUsage.bytes == 0)

        cache.set(track, lyrics: lyrics, source: LRCLibProvider.source)
        controller.refreshContents()

        #expect(controller.cacheUsage.bytes > 0)
        #expect(controller.cacheUsage.bytes == cache.totalSize())
    }

    /// Reopening the window after more tracks played must not show the size from the first open.
    @Test func everyRefreshShowsTheLatestCacheSize() {
        let cache = makeCache()
        let (controller, cleanup) = makeController(cache: cache)
        defer { cleanup() }

        controller.prepareWindow()
        cache.set(track, lyrics: lyrics, source: LRCLibProvider.source)
        controller.refreshContents()
        let afterFirstOpen = controller.cacheUsage.bytes
        #expect(afterFirstOpen > 0)

        cache.set(otherTrack, lyrics: lyrics, source: LRCLibProvider.source)
        controller.refreshContents()

        #expect(controller.cacheUsage.bytes > afterFirstOpen)
        #expect(controller.cacheUsage.bytes == cache.totalSize())
    }

    /// The login item can be removed in System Settings while the window is closed.
    @Test func refreshingAsksTheSystemAboutTheLoginItem() {
        let service = CountingLaunchAtLoginService()
        let (controller, cleanup) = makeController(launchAtLogin: service)
        defer { cleanup() }

        controller.prepareWindow()
        controller.refreshContents()
        #expect(service.enabledReads == 1)

        controller.refreshContents()

        #expect(service.enabledReads == 2)
    }

    /// The stored cookie can expire while the window is closed, so it is checked again on open.
    @Test func refreshingRechecksTheSpotifyCookie() async {
        let verifier = CountingTokenVerifier()
        let spotify = SpotifyAccountController(
            credentials: InMemorySpotifyCredentialStore(cookie: "abc"), verifier: verifier)
        let (controller, cleanup) = makeController(spotify: spotify)
        defer { cleanup() }

        controller.prepareWindow()
        controller.refreshContents()

        #expect(await waitUntil { spotify.state == .connected })
        #expect(verifier.calls == 1)
    }
}
