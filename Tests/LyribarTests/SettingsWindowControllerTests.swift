import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Lyribar

/// Never touches SMAppService: these tests must not change the user's login items.
@MainActor
private struct NoopLaunchAtLoginService: LaunchAtLoginService {
    var isEnabled: Bool { false }
    func register() throws {}
    func unregister() throws {}
}

/// Never reaches Spotify: the settings view checks the stored cookie when it appears.
private struct NoopTokenVerifier: SpotifyTokenVerifying {
    func token() async throws -> String { "token" }
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

    func frontmostApplication() -> (any ActivatableApp)? {
        frontmostQueries += 1
        return frontmost
    }

    func hideSelf() {
        hideCount += 1
    }
}

@MainActor
struct SettingsWindowControllerTests {
    private func makeController(
        activation: any ActivationService = FakeActivationService()
    ) -> (SettingsWindowController, () -> Void) {
        let suite = "LyribarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = Settings(defaults: defaults)
        let cache = LyricsCache(
            directory: URL.temporaryDirectory.appending(path: "lyribar-settings-\(UUID().uuidString)"))
        let controller = SettingsWindowController(
            settings: settings,
            launchAtLogin: LaunchAtLoginController(settings: settings, service: NoopLaunchAtLoginService()),
            spotify: SpotifyAccountController(
                credentials: InMemorySpotifyCredentialStore(), verifier: NoopTokenVerifier()),
            cache: cache,
            activation: activation)
        return (controller, { defaults.removePersistentDomain(forName: suite) })
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
}
