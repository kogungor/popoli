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

    /// The Finder extension's Application Support folder, inside its sandbox container: its
    /// token is there, and the list for its Open in › menu.
    static let finderContainer = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/app.popoli.Popoli.FinderMenu/Data/Library/Application Support")

    /// Whether `token` is the one the Finder extension keeps in its container (see FinderMenu).
    static func isFinderToken(_ token: String) -> Bool {
        let file = finderContainer.appendingPathComponent("terminal-token")
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

    /// The terminal chosen in Settings, or Terminal when that one is gone.
    private static var chosenApp: String {
        installed.contains { $0.id == Settings.terminalApp } ? Settings.terminalApp : "com.apple.Terminal"
    }

    /// The login shell from the user's account (apps started from the Dock get no $SHELL).
    static var userShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    private static func shellQuoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Opens a new terminal window in `folder` and runs `command` there (Open in › Claude Code…),
    /// leaving the shell open when it ends.
    /// - Terminal and iTerm take it through AppleScript; macOS asks once whether Popoli may
    ///   control them.
    /// - Ghostty, WezTerm and kitty take it on their command line, in a new window.
    /// - Warp can't be told to run a command: it opens the folder, and the command is copied.
    static func run(_ command: String, in folder: URL, near anchor: NSRect = .zero) {
        let shell = userShell
        let inShell = [shell, "-l", "-i", "-c", "\(command); exec \(shellQuoted(shell)) -l"]
        let line = "cd \(shellQuoted(folder.path)) && \(command)"
        switch chosenApp {
        case "com.googlecode.iterm2":
            appleScript("""
                tell application id "com.googlecode.iterm2"
                    activate
                    set newWindow to (create window with default profile)
                    tell current session of newWindow to write text \(appleScriptString(line))
                end tell
                """, app: "iTerm", near: anchor)
        case "com.mitchellh.ghostty":
            launch("com.mitchellh.ghostty", ["--working-directory=\(folder.path)", "-e"] + inShell)
        case "com.github.wez.wezterm":
            launch("com.github.wez.wezterm", ["start", "--cwd", folder.path, "--"] + inShell)
        case "net.kovidgoyal.kitty":
            launch("net.kovidgoyal.kitty", ["--directory", folder.path] + inShell)
        case "dev.warp.Warp-Stable":
            open(path: folder.path)
            Clipboard.copy(command)
            HUD.shared.show(symbol: "doc.on.clipboard", text: "Warp can’t start it: paste “\(command)”", near: anchor)
        default:
            appleScript("""
                tell application id "com.apple.Terminal"
                    activate
                    do script \(appleScriptString(line))
                end tell
                """, app: "Terminal", near: anchor)
        }
    }

    /// A new instance with these arguments, as `open -na App --args …` does.
    private static func launch(_ bundleID: String, _ arguments: [String]) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }

    private static func appleScript(_ source: String, app: String, near anchor: NSRect) {
        Runner.run(executable: URL(fileURLWithPath: "/usr/bin/osascript"), arguments: ["-e", source], input: nil,
                   environment: [:], directory: FileManager.default.temporaryDirectory, timeout: 30) { result in
            guard case .failure(let error) = result else { return }
            let denied = error.message.contains("-1743") || error.message.localizedCaseInsensitiveContains("not authorized")
            HUD.shared.show(symbol: "hand.raised",
                            text: denied ? "Allow Popoli to control \(app) in Privacy & Security ▸ Automation" : "\(app) didn’t start it",
                            near: anchor)
        }
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
