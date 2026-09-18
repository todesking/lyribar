import Foundation
import Security
import Synchronization

/// Holds the `sp_dc` cookie of a logged-in Spotify web session. Setting nil removes it.
protocol SpotifyCredentialStore: Sendable {
    func cookie() -> String?
    func setCookie(_ value: String?) throws
}

struct KeychainError: Error, Equatable, LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}

/// The login keychain. `kSecUseDataProtectionKeychain` is deliberately not set: it needs a
/// keychain-access-groups entitlement, which ad-hoc signed builds cannot carry.
struct KeychainSpotifyCredentialStore: SpotifyCredentialStore {
    static let defaultService = "com.todesking.lyribar"
    static let defaultAccount = "spotify-sp_dc"

    private let service: String
    private let account: String

    init(service: String = defaultService, account: String = defaultAccount) {
        self.service = service
        self.account = account
    }

    // A missing item and a failed read are the same thing here: no cookie to use.
    func cookie() -> String? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setCookie(_ value: String?) throws {
        guard let value else { return try delete() }
        let data = Data(value.utf8)
        let status = SecItemUpdate(
            itemQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = itemQuery
            attributes[kSecValueData as String] = data
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        default:
            throw KeychainError(status: status)
        }
    }

    private func delete() throws {
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// For tests and `swift run`, which must not touch the real keychain.
final class InMemorySpotifyCredentialStore: SpotifyCredentialStore {
    private let stored: Mutex<String?>

    init(cookie: String? = nil) {
        stored = Mutex(cookie)
    }

    func cookie() -> String? { stored.withLock { $0 } }

    func setCookie(_ value: String?) { stored.withLock { $0 = value } }
}

enum SpotifyCookie {
    /// Accepts the bare value, or anything pasted around it: a `Cookie:` header, a cookie list, or
    /// stray whitespace from the browser's developer tools.
    static func normalize(_ input: String) -> String? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let marker = value.range(of: "sp_dc=") {
            let rest = value[marker.upperBound...]
            let end = rest.firstIndex(of: ";") ?? rest.endIndex
            value = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.isEmpty ? nil : value
    }
}
