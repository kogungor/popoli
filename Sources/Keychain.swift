import AppKit
import CryptoKit
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

/// Which extensions may read which saved secret. The keychain keys secrets by name only, so
/// without this any extension naming ANTHROPIC_API_KEY would get the key saved for another one.
/// A permission belongs to one extension file with its exact contents: a changed or replaced
/// file is asked about again.
enum SecretAccess {
    private static let key = "secretGrants"

    private static var grants: [String: [String]] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// The extension's ID and a hash of its file, e.g. "ext.improve-writing.sh:3f2a…".
    private static func fingerprint(_ ext: UserExtension) -> String? {
        guard let data = try? Data(contentsOf: ext.file) else { return nil }
        return ext.id + ":" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isAllowed(_ ext: UserExtension, _ secret: String) -> Bool {
        guard let fingerprint = fingerprint(ext) else { return false }
        return grants[secret]?.contains(fingerprint) == true
    }

    static func allow(_ ext: UserExtension, _ secret: String) {
        guard let fingerprint = fingerprint(ext) else { return }
        var all = grants
        all[secret] = (all[secret] ?? []).filter { !$0.hasPrefix(ext.id + ":") } + [fingerprint]
        grants = all
    }

    /// Removes every permission for `secret` (used when a secret is deleted).
    static func forget(_ secret: String) {
        var all = grants
        all[secret] = nil
        grants = all
    }

    /// Once, when updating from a version without these permissions: extensions that were
    /// already installed keep the keys they had.
    static func migrate(_ extensions: [UserExtension]) {
        guard !UserDefaults.standard.bool(forKey: "secretGrantsMigrated") else { return }
        for ext in extensions {
            for secret in ext.secrets where Keychain.has(secret) { allow(ext, secret) }
        }
        UserDefaults.standard.set(true, forKey: "secretGrantsMigrated")
    }

    /// Asks before an extension reads a secret it hasn't been given. True when it may run.
    static func confirm(_ ext: UserExtension) -> Bool {
        for secret in ext.secrets where Keychain.has(secret) && !isAllowed(ext, secret) {
            let changed = grants[secret]?.contains { $0.hasPrefix(ext.id + ":") } == true
            let others = (grants[secret] ?? []).compactMap { $0.split(separator: ":").first.map { String($0.dropFirst(4)) } }
                .filter { $0 != ext.file.lastPathComponent }
            let alert = NSAlert()
            alert.messageText = "Give “\(ext.name)” your \(secret)?"
            alert.informativeText = (changed
                ? "\(ext.file.lastPathComponent) changed since you allowed it. "
                : "\(secret) is saved in your keychain\(others.isEmpty ? "" : " for \(others.joined(separator: ", "))"). ")
                + "An extension that has it can use it or send it anywhere, so allow only extensions you trust."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Don’t Allow")
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            allow(ext, secret)
        }
        return true
    }
}
