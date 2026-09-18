import Foundation
import Testing

@testable import Lyribar

struct SpotifyTOTPTests {
    // The key of the RFC 6238 test vectors (ASCII "12345678901234567890").
    private let rfcKey = Data("12345678901234567890".utf8)

    @Test(arguments: [(59, "287082"), (1_111_111_109, "081804"), (1_234_567_890, "005924")])
    func matchesRFC6238Vectors(time: Int, expected: String) {
        #expect(SpotifyTOTP.code(key: rfcKey, time: time) == expected)
    }

    @Test func keyIsTheJoinedDecimalsOfTheXoredSecret() {
        let key = SpotifyTOTP.key(fromSecret: Array(1...40))

        #expect(
            String(decoding: key, as: UTF8.self)
                == "888888824242424242424248888888856565656565656568843414741434139")
    }

    @Test func codeFromASecretDerivedKey() {
        let key = SpotifyTOTP.key(fromSecret: Array(1...40))

        #expect(SpotifyTOTP.code(key: key, time: 1_700_000_000) == "727239")
    }

    // The counter only advances every 30 seconds.
    @Test func codeIsStableWithinAStep() {
        #expect(SpotifyTOTP.code(key: rfcKey, time: 30) == SpotifyTOTP.code(key: rfcKey, time: 59))
        #expect(SpotifyTOTP.code(key: rfcKey, time: 60) != SpotifyTOTP.code(key: rfcKey, time: 59))
    }
}
