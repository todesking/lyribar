import Foundation
import Synchronization
import Testing

@testable import Lyribar

private struct FakeError: LocalizedError {
    var errorDescription: String? { "boom" }
}

private final class StubVerifier: SpotifyTokenVerifying {
    private let failure: (any Error)?
    private let count = Mutex(0)

    init(failure: (any Error)? = nil) {
        self.failure = failure
    }

    var calls: Int { count.withLock { $0 } }

    func token() async throws -> String {
        count.withLock { $0 += 1 }
        if let failure { throw failure }
        return "token"
    }
}

/// Holds `token()` until the test lets it go, to put a save or remove in the middle of a check.
private final class GatedVerifier: SpotifyTokenVerifying {
    private let entered = AsyncStream<Void>.makeStream()
    private let gate = AsyncStream<Void>.makeStream()

    func token() async throws -> String {
        entered.continuation.yield()
        for await _ in gate.stream { break }
        return "token"
    }

    func waitUntilEntered() async {
        for await _ in entered.stream { break }
    }

    func open() {
        gate.continuation.yield()
    }
}

private final class FailingCredentialStore: SpotifyCredentialStore {
    func cookie() -> String? { nil }
    func setCookie(_ value: String?) throws { throw FakeError() }
}

@MainActor
struct SpotifyAccountControllerTests {
    typealias State = SpotifyAccountController.State

    @Test func startsNotConfiguredWithoutACookie() {
        let controller = SpotifyAccountController(
            credentials: InMemorySpotifyCredentialStore(), verifier: StubVerifier())

        #expect(controller.state == .notConfigured)
    }

    @Test func startsCheckingWithACookie() {
        let verifier = StubVerifier()
        let controller = SpotifyAccountController(
            credentials: InMemorySpotifyCredentialStore(cookie: "abc"), verifier: verifier)

        #expect(controller.state == .checking)
        #expect(verifier.calls == 0)
    }

    @Test func saveStoresTheNormalizedCookieAndConnects() async {
        let store = InMemorySpotifyCredentialStore()
        let verifier = StubVerifier()
        let controller = SpotifyAccountController(credentials: store, verifier: verifier)
        var changes = 0
        controller.onChange = { changes += 1 }

        await controller.save("  Cookie: sp_t=x; sp_dc=abc; sp_key=y \n")

        #expect(store.cookie() == "abc")
        #expect(controller.state == .connected)
        #expect(verifier.calls == 1)
        #expect(changes == 1)
    }

    @Test func savingBlankInputDoesNothing() async {
        let store = InMemorySpotifyCredentialStore()
        let verifier = StubVerifier()
        let controller = SpotifyAccountController(credentials: store, verifier: verifier)
        var changes = 0
        controller.onChange = { changes += 1 }

        await controller.save(" \n\t ")

        #expect(store.cookie() == nil)
        #expect(controller.state == .notConfigured)
        #expect(verifier.calls == 0)
        #expect(changes == 0)
    }

    @Test func aRejectedCookieStaysStored() async {
        let store = InMemorySpotifyCredentialStore()
        let controller = SpotifyAccountController(
            credentials: store, verifier: StubVerifier(failure: SpotifyAuthError.cookieRejected))
        var changes = 0
        controller.onChange = { changes += 1 }

        await controller.save("abc")

        #expect(controller.state == .rejected)
        #expect(store.cookie() == "abc")
        #expect(changes == 1)
    }

    @Test func anyOtherFailureIsUnverified() async {
        let store = InMemorySpotifyCredentialStore()
        let controller = SpotifyAccountController(
            credentials: store, verifier: StubVerifier(failure: FakeError()))

        await controller.save("abc")

        #expect(controller.state == .unverified("boom"))
        #expect(store.cookie() == "abc")
    }

    @Test func aFailedWriteIsUnverifiedAndSkipsTheCheck() async {
        let verifier = StubVerifier()
        let controller = SpotifyAccountController(
            credentials: FailingCredentialStore(), verifier: verifier)
        var changes = 0
        controller.onChange = { changes += 1 }

        await controller.save("abc")

        #expect(controller.state == .unverified("boom"))
        #expect(verifier.calls == 0)
        #expect(changes == 0)
    }

    @Test func removeDeletesTheCookie() async {
        let store = InMemorySpotifyCredentialStore(cookie: "abc")
        let controller = SpotifyAccountController(credentials: store, verifier: StubVerifier())
        await controller.refresh()
        #expect(controller.state == .connected)
        var changes = 0
        controller.onChange = { changes += 1 }

        controller.remove()

        #expect(store.cookie() == nil)
        #expect(controller.state == .notConfigured)
        #expect(changes == 1)
    }

    @Test func refreshChecksTheStoredCookie() async {
        let verifier = StubVerifier()
        let controller = SpotifyAccountController(
            credentials: InMemorySpotifyCredentialStore(cookie: "abc"), verifier: verifier)
        var changes = 0
        controller.onChange = { changes += 1 }

        await controller.refresh()

        #expect(controller.state == .connected)
        #expect(verifier.calls == 1)
        #expect(changes == 0)
    }

    @Test func refreshWithoutACookieSkipsTheCheck() async {
        let verifier = StubVerifier()
        let controller = SpotifyAccountController(
            credentials: InMemorySpotifyCredentialStore(), verifier: verifier)

        await controller.refresh()

        #expect(controller.state == .notConfigured)
        #expect(verifier.calls == 0)
    }

    @Test func removingDuringACheckWins() async {
        let store = InMemorySpotifyCredentialStore(cookie: "abc")
        let verifier = GatedVerifier()
        let controller = SpotifyAccountController(credentials: store, verifier: verifier)

        let check = Task { await controller.refresh() }
        await verifier.waitUntilEntered()
        #expect(controller.state == .checking)
        controller.remove()
        verifier.open()
        await check.value

        #expect(controller.state == .notConfigured)
    }

    @Test func statusTexts() {
        #expect(SpotifyAccountController.statusText(.notConfigured) == nil)
        #expect(SpotifyAccountController.statusText(.checking) == "Checking…")
        #expect(SpotifyAccountController.statusText(.connected) == "Connected")
        #expect(
            SpotifyAccountController.statusText(.rejected)
                == "Cookie rejected. Log in to open.spotify.com again and paste a new one.")
        #expect(SpotifyAccountController.statusText(.unverified("boom")) == "Could not verify: boom")
    }
}
