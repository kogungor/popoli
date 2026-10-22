import AppKit

/// The page open in the browser in front, for extensions that use `$POPOLI_BROWSER_URL`,
/// `$POPOLI_BROWSER_TITLE` or `{url}`.
enum BrowserTab {
    struct Page {
        let url: String
        let title: String
    }

    private static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    private static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "org.chromium.Chromium",
        "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]
    private static let firefox: Set<String> = [
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "app.zen-browser.zen", "net.waterfox.waterfox", "io.gitlab.librewolf-community",
    ]

    static func isBrowser(_ bundleID: String) -> Bool {
        safari.contains(bundleID) || chromium.contains(bundleID) || firefox.contains(bundleID)
    }

    /// Calls back on the main thread, with nil when the app is not a browser Popoli knows.
    static func current(in app: NSRunningApplication, completion: @escaping (Page?) -> Void) {
        guard let id = app.bundleIdentifier else { return completion(nil) }
        if safari.contains(id) || chromium.contains(id) {
            // Safari calls it "current tab" and its title "name"; Chromium browsers say "active tab" and "title".
            let tab = safari.contains(id) ? "current tab" : "active tab"
            let title = safari.contains(id) ? "name" : "title"
            let script = "tell application id \"\(id)\" to return (URL of \(tab) of front window) & linefeed & (\(title) of \(tab) of front window)"
            Runner.run(executable: URL(fileURLWithPath: "/usr/bin/osascript"), arguments: ["-e", script], input: nil,
                       environment: [:], directory: FileManager.default.temporaryDirectory, timeout: 5) { result in
                guard case .success(let output) = result else { return completion(nil) }
                let lines = output.components(separatedBy: "\n")
                completion(Page(url: lines.first ?? "", title: lines.dropFirst().joined(separator: " ")))
            }
        } else if firefox.contains(id) {
            DispatchQueue.global(qos: .userInitiated).async {
                let page = addressBar(of: app)
                DispatchQueue.main.async { completion(page) }
            }
        } else {
            completion(nil)
        }
    }

    /// Firefox-based browsers have no AppleScript, so their address bar is read through
    /// Accessibility: it is the first combo box near the top of the window (fields on the page
    /// are much deeper).
    private static func addressBar(of app: NSRunningApplication) -> Page? {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        guard let window = AX.element(application, kAXFocusedWindowAttribute) else { return nil }
        var level = [window]
        for _ in 0..<10 where !level.isEmpty {
            for element in level where AX.string(element, kAXRoleAttribute) == "AXComboBox" {
                guard var url = AX.string(element, kAXValueAttribute), !url.isEmpty else { continue }
                // The bar leaves out "https://".
                if !url.contains("://") { url = "https://" + url }
                var title = AX.string(window, kAXTitleAttribute) ?? ""
                for suffix in [" — Mozilla Firefox", " — Firefox", " — Zen Browser"] where title.hasSuffix(suffix) {
                    title.removeLast(suffix.count)
                }
                return Page(url: url, title: title)
            }
            level = level.flatMap(AX.children)
        }
        return nil
    }
}
