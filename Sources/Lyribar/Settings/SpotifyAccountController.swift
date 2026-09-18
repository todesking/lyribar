import Foundation
import Observation

/// The part of `SpotifyTokenProvider` the settings need: proof that the stored cookie still works.
protocol SpotifyTokenVerifying: Sendable {
    func token() async throws -> String
}

extension SpotifyTokenProvider: SpotifyTokenVerifying {}

/// Stores and removes the Spotify cookie for the settings window, and reports whether Spotify
/// accepts it. Having a cookie is what turns Spotify lyrics on; there is no separate switch.
@MainActor
@Observable
final class SpotifyAccountController {
    enum State: Equatable {
        case notConfigured
        case checking
        case connected
        case rejected
        case unverified(String)
    }

    private(set) var state: State
    /// Called after the cookie was saved or removed, so lyrics can be looked up again.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let credentials: any SpotifyCredentialStore
    @ObservationIgnored private let verifier: any SpotifyTokenVerifying
    @ObservationIgnored private var generation = 0

    init(credentials: any SpotifyCredentialStore, verifier: any SpotifyTokenVerifying) {
        self.credentials = credentials
        self.verifier = verifier
        state = credentials.cookie() == nil ? .notConfigured : .checking
    }

    func save(_ input: String) async {
        guard let cookie = SpotifyCookie.normalize(input) else { return }
        do {
            try credentials.setCookie(cookie)
        } catch {
            generation += 1
            state = .unverified(error.localizedDescription)
            return
        }
        await refresh()
        onChange?()
    }

    func remove() {
        generation += 1
        do {
            try credentials.setCookie(nil)
        } catch {
            state = .unverified(error.localizedDescription)
            return
        }
        state = .notConfigured
        onChange?()
    }

    func refresh() async {
        generation += 1
        let current = generation
        guard credentials.cookie() != nil else {
            state = .notConfigured
            return
        }
        state = .checking
        let result: State
        do {
            _ = try await verifier.token()
            result = .connected
        } catch SpotifyAuthError.cookieRejected {
            result = .rejected
        } catch {
            result = .unverified(error.localizedDescription)
        }
        // A save or remove that happened while waiting owns the state now.
        guard current == generation else { return }
        state = result
    }

    static func statusText(_ state: State) -> String? {
        switch state {
        case .notConfigured: nil
        case .checking: "Checking…"
        case .connected: "Connected"
        case .rejected: "Cookie rejected. Log in to open.spotify.com again and paste a new one."
        case .unverified(let message): "Could not verify: \(message)"
        }
    }
}
