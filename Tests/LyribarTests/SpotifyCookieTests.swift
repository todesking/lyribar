import Foundation
import Testing

@testable import Lyribar

struct SpotifyCookieTests {
    @Test func bareValuePassesThrough() {
        #expect(SpotifyCookie.normalize("abc") == "abc")
    }

    @Test func surroundingWhitespaceIsDropped() {
        #expect(SpotifyCookie.normalize("  abc\n") == "abc")
    }

    @Test func cookieListKeepsOnlySpDc() {
        #expect(SpotifyCookie.normalize("sp_dc=abc; sp_key=def") == "abc")
    }

    @Test func headerFormIsAccepted() {
        #expect(SpotifyCookie.normalize("Cookie: foo=1; sp_dc=abc") == "abc")
    }

    @Test func spDcAtTheEndHasNoTerminator() {
        #expect(SpotifyCookie.normalize("foo=1; sp_dc=abc") == "abc")
    }

    @Test func emptyInputIsNil() {
        #expect(SpotifyCookie.normalize("") == nil)
        #expect(SpotifyCookie.normalize("   \n ") == nil)
        #expect(SpotifyCookie.normalize("sp_dc= ; sp_key=def") == nil)
    }
}

struct InMemorySpotifyCredentialStoreTests {
    @Test func storesAndRemovesTheCookie() throws {
        let store: any SpotifyCredentialStore = InMemorySpotifyCredentialStore()
        #expect(store.cookie() == nil)

        try store.setCookie("abc")
        #expect(store.cookie() == "abc")

        try store.setCookie(nil)
        #expect(store.cookie() == nil)
    }
}
