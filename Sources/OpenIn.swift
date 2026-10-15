import AppKit

/// One place Open in › can open the Finder selection: an app (an editor or an IDE), or a
/// command such as `claude` that starts in a new terminal window in the folder.
struct OpenInTarget: Identifiable, Hashable {
    enum Kind: Hashable {
        /// By bundle ID.
        case app(String)
        case command(String)
    }

    let kind: Kind
    let name: String

    var id: String {
        switch kind {
        case .app(let bundleID): "app:" + bundleID
        case .command(let command): "command:" + command
        }
    }

    init(kind: Kind, name: String) {
        self.kind = kind
        self.name = name
    }

    /// From an id saved in Settings; added apps and commands get their name from the app or
    /// the command itself.
    init?(id: String) {
        if id.hasPrefix("app:") {
            let bundleID = String(id.dropFirst(4))
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            let known = OpenIn.knownApps.first { $0.id == bundleID }?.name
            self.init(kind: .app(bundleID), name: known ?? url.map(OpenIn.displayName) ?? bundleID)
        } else if id.hasPrefix("command:") {
            let command = String(id.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty else { return nil }
            let known = OpenIn.knownCommands.first { $0.command == command }?.name
            self.init(kind: .command(command), name: known ?? command)
        } else {
            return nil
        }
    }

    var appURL: URL? {
        guard case .app(let bundleID) = kind else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    var isCommand: Bool {
        if case .command = kind { return true }
        return false
    }
}

/// Open in › for files and folders selected in Finder, on the bar and in the right-click menu:
/// an editor, or an AI coding tool such as Claude Code or Codex started in a terminal there.
/// Popoli knows the common ones and finds which are installed; Settings ▸ General ▸ Finder
/// chooses which ones show and can add any app or command.
enum OpenIn {
    static let knownApps: [(id: String, name: String)] = [
        ("com.microsoft.VSCode", "VS Code"),
        ("com.microsoft.VSCodeInsiders", "VS Code Insiders"),
        ("com.vscodium", "VSCodium"),
        ("com.todesktop.230313mzl4w4u92", "Cursor"),
        ("com.exafunction.windsurf", "Windsurf"),
        ("dev.zed.Zed", "Zed"),
        ("dev.zed.Zed-Preview", "Zed Preview"),
        ("com.sublimetext.4", "Sublime Text"),
        ("com.panic.Nova", "Nova"),
        ("com.barebones.bbedit", "BBEdit"),
        ("com.macromates.TextMate", "TextMate"),
        ("com.apple.dt.Xcode", "Xcode"),
        ("dev.kiro.desktop", "Kiro"),
        ("com.google.antigravity-ide", "Antigravity"),
        ("com.google.android.studio", "Android Studio"),
        ("com.jetbrains.intellij", "IntelliJ IDEA"),
        ("com.jetbrains.intellij.ce", "IntelliJ IDEA CE"),
        ("com.jetbrains.pycharm", "PyCharm"),
        ("com.jetbrains.pycharm.ce", "PyCharm CE"),
        ("com.jetbrains.WebStorm", "WebStorm"),
        ("com.jetbrains.goland", "GoLand"),
        ("com.jetbrains.CLion", "CLion"),
        ("com.jetbrains.PhpStorm", "PhpStorm"),
        ("com.jetbrains.rider", "Rider"),
        ("com.jetbrains.rubymine", "RubyMine"),
        ("com.jetbrains.rustrover", "RustRover"),
    ]

    static let knownCommands: [(command: String, name: String)] = [
        ("claude", "Claude Code"),
        ("codex", "Codex"),
        ("gemini", "Gemini CLI"),
        ("opencode", "OpenCode"),
        ("cursor-agent", "Cursor CLI"),
        ("copilot", "Copilot CLI"),
        ("aider", "Aider"),
    ]

    static let didChange = Notification.Name("OpenInDidChange")
    static let rowID = "builtin.openin"

    /// Installed known apps and commands, then the ones added in Settings.
    private(set) static var available: [OpenInTarget] = []
    /// The bar's buttons for `enabled`, rebuilt when it changes.
    private(set) static var actions: [PopAction] = []

    /// What Open in › shows, in the order of `available`. Read straight from Settings, so it
    /// is right before the first search for installed apps has finished.
    static var enabled: [OpenInTarget] {
        let on = Settings.openInEnabled
        return available.isEmpty ? on.compactMap(OpenInTarget.init(id:)) : available.filter { on.contains($0.id) }
    }

    static func displayName(_ url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: Finding what is installed

    /// Looks for installed apps and commands in the background (finding commands asks the
    /// login shell for its PATH), picks the defaults the first time, and updates the bar and
    /// the Finder menu.
    static func refresh(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .utility).async {
            let (apps, commands) = installed()
            DispatchQueue.main.async {
                let found = apps + commands
                let added = Settings.openInAdded.compactMap(OpenInTarget.init(id:))
                available = found + added.filter { new in !found.contains { $0.id == new.id } }
                if !Settings.openInConfigured {
                    Settings.openInEnabled = defaults(apps: apps, commands: commands).map(\.id)
                    Settings.openInConfigured = true
                }
                update()
                completion?()
            }
        }
    }

    /// The known apps and commands on this Mac. Not on the main thread: it waits for a shell.
    static func installed() -> (apps: [OpenInTarget], commands: [OpenInTarget]) {
        let apps = knownApps.compactMap { app in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) == nil
                ? nil : OpenInTarget(kind: .app(app.id), name: app.name)
        }
        let folders = commandFolders()
        let commands = knownCommands.compactMap { known in
            folders.contains { FileManager.default.isExecutableFile(atPath: $0 + "/" + known.command) }
                ? OpenInTarget(kind: .command(known.command), name: known.name) : nil
        }
        return (apps, commands)
    }

    /// The first time: the three editors used most recently, and every AI tool found.
    private static func defaults(apps: [OpenInTarget], commands: [OpenInTarget]) -> [OpenInTarget] {
        let recent = apps.map { ($0, $0.appURL.map(lastUsed) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map(\.0)
        return recent + commands
    }

    /// When the app was last opened, from Spotlight.
    private static func lastUsed(_ url: URL) -> Date {
        guard let item = MDItemCreateWithURL(nil, url as CFURL),
              let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date else { return .distantPast }
        return date
    }

    /// Where commands can be: the PATH of the user's shell started as in a terminal (Claude Code
    /// and others add ~/.local/bin in .zshrc), and the usual install places.
    private static func commandFolders() -> [String] {
        let home = NSHomeDirectory()
        var folders: [String] = []
        let shell = TerminalLauncher.userShell
        let script = (shell as NSString).lastPathComponent == "fish"
            ? "printf '__PATH__%s\\n' (string join : $PATH)"
            : "printf '__PATH__%s\\n' \"$PATH\""
        let done = DispatchSemaphore(value: 0)
        Runner.run(executable: URL(fileURLWithPath: shell), arguments: ["-l", "-i", "-c", script], input: nil,
                   environment: [:], directory: URL(fileURLWithPath: home), timeout: 5) { result in
            if case .success(let output) = result,
               let line = output.components(separatedBy: "\n").last(where: { $0.hasPrefix("__PATH__") }) {
                folders = line.dropFirst(8).split(separator: ":").map(String.init)
            }
            done.signal()
        }
        done.wait()
        folders += ["\(home)/.local/bin", "\(home)/.claude/local", "\(home)/.bun/bin", "\(home)/.npm-global/bin",
                    "\(home)/.volta/bin", "\(home)/.cargo/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        var seen = Set<String>()
        return folders.filter { seen.insert($0).inserted }
    }

    // MARK: Changing the list

    static func setEnabled(_ target: OpenInTarget, _ on: Bool) {
        var ids = Settings.openInEnabled.filter { $0 != target.id }
        if on { ids.append(target.id) }
        Settings.openInEnabled = ids
        update()
    }

    /// An app or command added in Settings; it is turned on right away.
    static func add(_ target: OpenInTarget) {
        if !available.contains(where: { $0.id == target.id }) {
            Settings.openInAdded.append(target.id)
            available.append(target)
        }
        setEnabled(target, true)
    }

    /// Takes an added app or command off the list.
    static func remove(_ target: OpenInTarget) {
        Settings.openInAdded.removeAll { $0 == target.id }
        let known = knownApps.contains { "app:" + $0.id == target.id }
            || knownCommands.contains { "command:" + $0.command == target.id }
        if !known { available.removeAll { $0.id == target.id } }
        setEnabled(target, false)
    }

    static func isAdded(_ target: OpenInTarget) -> Bool { Settings.openInAdded.contains(target.id) }

    /// Rebuilds the bar's buttons and the Finder menu's list.
    private static func update() {
        actions = enabled.map(action)
        writeFinderList()
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: The bar

    private static func action(for target: OpenInTarget) -> PopAction {
        PopAction(
            id: rowID + "." + target.id, rowID: rowID,
            title: target.isCommand ? target.name : "Open in \(target.name)",
            icon: target.appURL.map(icon),
            hint: target.isCommand ? "Starts \(commandWord(target)) in a terminal in the folder" : "⌥-click: open the folder it is in",
            group: "Open in",
            prepare: { ctx in
                guard !ctx.files.isEmpty else { return nil }
                if target.isCommand && TerminalLauncher.target(for: ctx.files) == nil { return nil }
                return ctx
            },
            perform: { ctx in open(target, paths: ctx.files, containingFolder: ctx.modifiers.contains(.option), near: ctx.anchor) })
    }

    private static func commandWord(_ target: OpenInTarget) -> String {
        guard case .command(let command) = target.kind else { return target.name }
        return command.split(separator: " ").first.map(String.init) ?? command
    }

    /// The app's own icon, in color, at the bar's size.
    private static func icon(_ url: URL) -> NSImage {
        let source = NSWorkspace.shared.icon(forFile: url.path)
        let side = Icons.size + 2
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: Opening

    /// Apps get the selected items (with ⌥, the folders they are in); a command starts in a
    /// terminal in the one folder they are in.
    static func open(_ target: OpenInTarget, paths: [String], containingFolder: Bool = false, near anchor: NSRect = .zero) {
        switch target.kind {
        case .app:
            guard let app = target.appURL else {
                HUD.shared.show(symbol: "exclamationmark.triangle", text: "\(target.name) isn’t installed", near: anchor)
                return
            }
            var urls = paths.map { URL(fileURLWithPath: $0) }
            if containingFolder {
                var seen = Set<String>()
                urls = urls.map { $0.deletingLastPathComponent() }.filter { seen.insert($0.path).inserted }
            }
            guard !urls.isEmpty else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration)
        case .command(let command):
            guard let path = TerminalLauncher.target(for: paths), let folder = TerminalLauncher.folder(for: path) else { return }
            TerminalLauncher.run(command, in: folder, near: anchor)
        }
    }

    // MARK: The Finder menu

    /// The Finder extension is sandboxed and can't read Popoli's settings, so the list for its
    /// right-click menu goes into its own container, next to its token. Only ids, names and
    /// where the apps are (for their icons): nothing it could run by itself.
    private static func writeFinderList() {
        let container = TerminalLauncher.finderContainer
        guard FileManager.default.fileExists(atPath: container.deletingLastPathComponent().deletingLastPathComponent().path) else { return }
        let list = enabled.map { target -> [String: String] in
            var entry = ["id": target.id, "name": target.name, "kind": target.isCommand ? "command" : "app"]
            if let app = target.appURL { entry["app"] = app.path }
            return entry
        }
        guard let data = try? JSONSerialization.data(withJSONObject: list, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try? data.write(to: container.appendingPathComponent("open-in.json"), options: .atomic)
    }

    /// popoli://open-in?target=…&path=…&token=… from the Finder menu. Only targets turned on in
    /// Settings, and only with the Finder extension's token: a web page can't use it to run
    /// anything.
    static func handle(_ items: [URLQueryItem]) {
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let token = value("token"), TerminalLauncher.isFinderToken(token), let id = value("target"),
              Settings.openInEnabled.contains(id), let target = OpenInTarget(id: id) else {
            NSLog("Popoli: ignored an Open in link that didn't come from the Finder menu")
            return
        }
        let paths = items.filter { $0.name == "path" }.compactMap(\.value).filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }
        open(target, paths: paths)
    }
}
