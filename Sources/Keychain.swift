import Foundation
import Security

/// Secrets for extensions (API keys and the like), stored in the login keychain.
/// They are keyed by name only, so every extension that asks for ANTHROPIC_API_KEY
/// shares the one you entered.
enum Keychain {
    private static let service = "app.popoli.Popoli.secrets"

    private static func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name]
    }

    static func get(_ name: String) -> String? {
        var q = query(name)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func has(_ name: String) -> Bool { get(name) != nil }

    @discardableResult
    static func set(_ value: String, for name: String) -> Bool {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(name) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(name)
            q[kSecValueData as String] = data
            q[kSecAttrLabel as String] = "Popoli: \(name)"
            return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func delete(_ name: String) {
        SecItemDelete(query(name) as CFDictionary)
    }
}
