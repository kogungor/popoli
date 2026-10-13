import AppKit

/// Opens a terminal window in a folder (Finder menu, bar button, popoli://terminal URLs).
struct TerminalApp: Identifiable {
    let id: String
    let name: String
}

enum TerminalLauncher {
    static let known = [
        TerminalApp(id: "com.apple.Terminal", name: "Terminal"),
        TerminalApp(id: "com.googlecode.iterm2", name: "iTerm"),
        TerminalApp(id: "com.mitchellh.ghostty", name: "Ghostty"),
        TerminalApp(id: "dev.warp.Warp-Stable", name: "Warp"),
        TerminalApp(id: "com.github.wez.wezterm", name: "WezTerm"),
        TerminalApp(id: "net.kovidgoyal.kitty", name: "kitty"),
    ]

    static var installed: [TerminalApp] {
        known.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
    }

    /// Where Open in Terminal goes for selected files: the file or folder itself when there is
    /// one, the folder they are all in when there are several. nil when they are in different
    /// folders, where there is no single right place.
    static func target(for paths: [String]) -> String? {
        guard let first = paths.first else { return nil }
        if paths.count == 1 { return first }
        let folders = Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.deletingLastPathComponent().path })
        return folders.count == 1 ? folders.first : nil
    }

    /// Whether `token` is the one the Finder extension keeps in its container (see FinderMenu).
    static func isFinderToken(_ token: String) -> Bool {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/app.popoli.Popoli.FinderMenu/Data/Library/Application Support/terminal-token")
        guard let saved = try? String(contentsOf: file, encoding: .utf8), saved.count == 64, token.count == 64 else { return false }
        // Compared in full every time, so the time taken says nothing about how much matched.
        return zip(saved.utf8, token.utf8).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    /// The folder to open for `path`: the path itself if it is a plain folder, otherwise its
    /// parent. Never a file: handing a script to Terminal would run it, and popoli:// URLs
    /// can come from anywhere.
    static func folder(for path: String) -> URL? {
        var url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue || NSWorkspace.shared.isFilePackage(atPath: url.path) {
            url = url.deletingLastPathComponent()
        }
        return url
    }

    static func open(path: String) {
        guard let folder = folder(for: path) else { return }
        let workspace = NSWorkspace.shared
        guard let app = workspace.urlForApplication(withBundleIdentifier: Settings.terminalApp)
                ?? workspace.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open([folder], withApplicationAt: app, configuration: configuration)
    }
}
