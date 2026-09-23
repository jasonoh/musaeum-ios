import Foundation
import Security

/// The bearer token is a credential the user pastes once and the app then holds
/// for as long as it is installed, so it lives in the Keychain rather than in
/// `UserDefaults`; the base URL is not a secret and lives in `UserDefaults` where
/// it is easy to inspect and correct.
@MainActor
@Observable
final class SettingsStore {
    private let defaults: UserDefaults
    private static let baseURLKey = "musaeum.baseURL"
    private static let tokenAccount = "musaeum.token"

    private(set) var baseURLString: String
    private(set) var token: String

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = .init()) {
        self.defaults = defaults
        self.keychain = keychain
        baseURLString = defaults.string(forKey: Self.baseURLKey) ?? ""
        token = keychain.read(Self.tokenAccount) ?? ""
        // A probe run carries its own URL and token so it needs no human to paste
        // one. Nothing is persisted: the app's stored settings are untouched.
        if let probeBase = Probe.base { baseURLString = probeBase }
        if let probeToken = Probe.token { token = probeToken }
    }

    private let keychain: KeychainStore

    var baseURL: URL? {
        guard let text = Self.normalizeBase(baseURLString) else { return nil }
        return URL(string: text)
    }

    var isConfigured: Bool {
        baseURL != nil && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Both halves at once, because a client with a fresh URL and a stale token is
    /// the 401 the user cannot explain.
    func save(base: String, token newToken: String) {
        let normalized = Self.normalizeBase(base) ?? base.trimmingCharacters(in: .whitespacesAndNewlines)
        baseURLString = normalized
        token = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(normalized, forKey: Self.baseURLKey)
        keychain.write(token, account: Self.tokenAccount)
    }

    func clear() {
        baseURLString = ""
        token = ""
        defaults.removeObject(forKey: Self.baseURLKey)
        keychain.delete(Self.tokenAccount)
    }

    /// A pure rule, so a case can decide it: what a human types into a phone is
    /// `100.125.135.108:8788` as often as it is a URL, and a trailing slash must
    /// not turn `…8788//api/health` into a 404.
    static func normalizeBase(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://\(text)" }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty else { return nil }
        return text
    }
}

/// A thin wrapper over the four `SecItem` calls this app needs, so nothing else
/// touches the Security framework and the token has exactly one home.
struct KeychainStore: Sendable {
    let service: String

    init(service: String = "dev.jasonoh.Musaeum") {
        self.service = service
    }

    func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
