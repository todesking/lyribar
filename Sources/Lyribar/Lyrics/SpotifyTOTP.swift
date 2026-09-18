import CryptoKit
import Foundation

/// The TOTP the Spotify web player sends when it asks for an access token: RFC 6238 over a key the
/// player derives from a secret embedded in its JavaScript.
enum SpotifyTOTP {
    /// Each element is XORed with a rotating offset, and the decimal forms are joined into the key.
    static func key(fromSecret secret: [Int]) -> Data {
        let digits = secret.enumerated()
            .map { String($0.element ^ (($0.offset % 33) + 9)) }
            .joined()
        return Data(digits.utf8)
    }

    /// RFC 6238: HMAC-SHA1 over the 30-second counter, dynamic truncation, six digits.
    static func code(key: Data, time: Int) -> String {
        let counter = UInt64(truncatingIfNeeded: time / 30).bigEndian
        let message = withUnsafeBytes(of: counter) { Data($0) }
        let mac = HMAC<Insecure.SHA1>.authenticationCode(
            for: message, using: SymmetricKey(data: key))
        let digest = Array(mac)
        let offset = Int(digest[digest.count - 1] & 0x0f)
        let truncated =
            (UInt32(digest[offset] & 0x7f) << 24)
            | (UInt32(digest[offset + 1]) << 16)
            | (UInt32(digest[offset + 2]) << 8)
            | UInt32(digest[offset + 3])
        return String(format: "%06u", truncated % 1_000_000)
    }
}
