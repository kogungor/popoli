import Foundation

/// User preferences, stored in UserDefaults (app.popoli.Popoli).
enum Settings {
    private static let defaults = UserDefaults.standard

    static func registerDefaults() {
        defaults.register(defaults: [
            "enabled": true,
            "finderFiles": true,
            "barStyle": "dark",
            "pasteOnEmptyField": true,
            // ⌃⌥P
            "hotkeyCode": 35,
            "hotkeyModifiers": 6144,
            "translateSource": "auto",
            "translateTarget": defaultTranslateTarget,
            "translateSecondary": defaultTranslateSecondary,
            "searchURL": "https://www.google.com/search?q=***",
            "keepCollections": true,
        ])
    }

    static var enabled: Bool {
        get { defaults.bool(forKey: "enabled") }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    /// Show the bar when files are selected in Finder (for the Path action).
    static var finderFiles: Bool {
        get { defaults.bool(forKey: "finderFiles") }
        set { defaults.set(newValue, forKey: "finderFiles") }
    }

    /// Apps (bundle IDs) where the bar never appears on its own. The shortcut still works there.
    static var excludedApps: [String] {
        get { defaults.stringArray(forKey: "excludedApps") ?? [] }
        set { defaults.set(newValue, forKey: "excludedApps") }
    }

    /// Password managers: a password shown in one is ordinary text, and the bar would hand it to
    /// extensions. They start out excluded; Settings can take them off the list.
    static let passwordManagers = ["com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
                                   "com.apple.Passwords", "com.apple.keychainaccess", "org.keepassxc.keepassxc",
                                   "com.lastpass.LastPass", "in.sinew.Enpass-Desktop"]

    /// Once per Mac, also for people updating from a version without it.
    static func excludePasswordManagers() {
        guard !defaults.bool(forKey: "passwordManagersExcluded") else { return }
        excludedApps += passwordManagers.filter { !excludedApps.contains($0) }
        defaults.set(true, forKey: "passwordManagersExcluded")
    }

    /// Show a Paste-only bar when clicking into an empty text field.
    static var pasteOnEmptyField: Bool {
        get { defaults.bool(forKey: "pasteOnEmptyField") }
        set { defaults.set(newValue, forKey: "pasteOnEmptyField") }
    }

    /// The global shortcut that shows the bar; nil when cleared.
    static var hotkey: Shortcut? {
        get {
            let code = defaults.integer(forKey: "hotkeyCode")
            return code < 0 ? nil : Shortcut(keyCode: UInt32(code), modifiers: UInt32(defaults.integer(forKey: "hotkeyModifiers")))
        }
        set {
            defaults.set(newValue.map { Int($0.keyCode) } ?? -1, forKey: "hotkeyCode")
            defaults.set(newValue.map { Int($0.modifiers) } ?? 0, forKey: "hotkeyModifiers")
        }
    }

    /// A value the user entered for an extension's `setting:` (nil: use the default).
    static func extensionSetting(_ extensionID: String, _ name: String) -> String? {
        defaults.string(forKey: "\(extensionID).setting.\(name)")
    }

    static func setExtensionSetting(_ extensionID: String, _ name: String, _ value: String?) {
        defaults.set(value, forKey: "\(extensionID).setting.\(name)")
    }

    enum BarStyle: String, CaseIterable { case dark, light, system }

    /// Look of the glass surfaces: dark smoky glass (default), light, or following the system.
    static var barStyle: BarStyle {
        get { BarStyle(rawValue: defaults.string(forKey: "barStyle") ?? "") ?? .dark }
        set { defaults.set(newValue.rawValue, forKey: "barStyle") }
    }

    /// Default source language for Translate: "auto" (detect) or a language code.
    static var translateSource: String {
        get { defaults.string(forKey: "translateSource") ?? "auto" }
        set { defaults.set(newValue, forKey: "translateSource") }
    }

    /// The Mac's preferred languages as language codes ("en", "de", …), most preferred first.
    private static var preferredLanguageCodes: [String] {
        Locale.preferredLanguages.compactMap { Locale.Language(identifier: $0).languageCode?.identifier }
    }

    /// By default Translate goes into the Mac's own language…
    static var defaultTranslateTarget: String { preferredLanguageCodes.first ?? "en" }

    /// …or, for text already in that language, into the next preferred language (else English).
    static var defaultTranslateSecondary: String {
        preferredLanguageCodes.first { $0 != defaultTranslateTarget } ?? "en"
    }

    /// Language the Translate action translates into.
    static var translateTarget: String {
        get { defaults.string(forKey: "translateTarget") ?? defaultTranslateTarget }
        set { defaults.set(newValue, forKey: "translateTarget") }
    }

    /// Used instead of `translateTarget` when the selection is already in that language.
    static var translateSecondary: String {
        get { defaults.string(forKey: "translateSecondary") ?? defaultTranslateSecondary }
        set { defaults.set(newValue, forKey: "translateSecondary") }
    }

    /// Collections are saved and kept for a week; off, they live only until Popoli quits.
    static var keepCollections: Bool {
        get { defaults.bool(forKey: "keepCollections") }
        set { defaults.set(newValue, forKey: "keepCollections") }
    }

    /// Bundle identifier of the terminal app "Open in Terminal" uses.
    static var terminalApp: String {
        get { defaults.string(forKey: "terminalApp") ?? "com.apple.Terminal" }
        set { defaults.set(newValue, forKey: "terminalApp") }
    }

    /// Search engine URL; `***` is replaced by the selected text.
    static var searchURL: String {
        defaults.string(forKey: "searchURL") ?? "https://www.google.com/search?q=***"
    }

    /// IDs of built-in actions and extensions the user switched off.
    static var disabledIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "disabledIDs") ?? []) }
        set { defaults.set(newValue.sorted(), forKey: "disabledIDs") }
    }

    /// Button order chosen in Settings (action IDs). Buttons not listed keep their default order after these.
    /// Open in ›: the apps and commands shown (ids such as "app:dev.zed.Zed", "command:claude").
    static var openInEnabled: [String] {
        get { defaults.stringArray(forKey: "openInEnabled") ?? [] }
        set { defaults.set(newValue, forKey: "openInEnabled") }
    }

    /// Apps and commands added by hand in Settings.
    static var openInAdded: [String] {
        get { defaults.stringArray(forKey: "openInAdded") ?? [] }
        set { defaults.set(newValue, forKey: "openInAdded") }
    }

    /// Set once the first choice of apps was made, so later changes are the user's.
    static var openInConfigured: Bool {
        get { defaults.bool(forKey: "openInConfigured") }
        set { defaults.set(newValue, forKey: "openInConfigured") }
    }

    static var buttonOrder: [String] {
        get { defaults.stringArray(forKey: "buttonOrder") ?? [] }
        set { defaults.set(newValue, forKey: "buttonOrder") }
    }

    static func isEnabled(_ id: String) -> Bool { !disabledIDs.contains(id) }

    static func setEnabled(_ id: String, _ on: Bool) {
        var ids = disabledIDs
        if on { ids.remove(id) } else { ids.insert(id) }
        disabledIDs = ids
    }
}
