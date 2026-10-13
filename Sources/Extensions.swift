import AppKit

// Popoli extensions are single files in ~/.config/popoli/extensions, all with the same
// comment header. A script extension puts code in any language below the header:
//
//     #!/bin/zsh
//     # name: Uppercase
//     # icon: AB
//     # after: paste
//     print -rn -- ${(U)POPOLI_TEXT}
//
// The selected text is in $POPOLI_TEXT and on stdin; what the script prints is the result.
// Links and keyboard shortcuts need no code, just the header (e.g. wikipedia.popoli):
//
//     # name: Wikipedia
//     # icon: W
//     # url: https://en.wikipedia.org/w/index.php?search={text}

/// One extension file, parsed.
struct UserExtension {
    enum Kind {
        case script(interpreter: [String])
        case appleScript
        case url(String)
        case keys([KeyCombo])
    }

    /// What happens with a script's output.
    enum After: String { case show, paste, copy, none }

    /// Whether the extension works on selected text or on files selected in Finder.
    enum Target: String { case text, files }

    /// `input:` — how the selection is handed over; `output:` — how the output is read.
    enum Format: String { case text, html, markdown }

    /// `# setting: NAME = default`: a value the user can change in Settings.
    struct Setting {
        let name: String
        let defaultValue: String
    }

    let file: URL
    let name: String
    let icon: NSImage?
    let kind: Kind
    /// nil: show the output in a card if there is any.
    let after: After?
    let target: Target
    let match: NSRegularExpression?
    let apps: Set<String>
    let input: Format
    let output: Format
    let settings: [Setting]
    /// `# secret: NAME`: kept in the keychain, shared by every extension using the same name.
    let secrets: [String]
    /// `# group: Encode`: shares one button on the bar with the other extensions of that group.
    let group: String?
    /// Uses `$POPOLI_BROWSER_URL` / `$POPOLI_BROWSER_TITLE` or `{url}`: the page open in the
    /// browser in front is looked up only for these (it can need the Automation permission).
    let usesBrowserTab: Bool

    var id: String { "ext." + file.lastPathComponent }
    var hasSettings: Bool { !settings.isEmpty || !secrets.isEmpty }
    var missingSecrets: [String] { secrets.filter { !Keychain.has($0) } }

    /// When this extension shows up on the bar, in words.
    var condition: String {
        var parts = [target == .files ? "Files selected in Finder" : after == .paste ? "In editable text" : "Any text"]
        // Long patterns would take over the Settings list; the tooltip there shows everything.
        if let match { parts.append(match.pattern.count <= 24 ? "matching \(match.pattern)" : "for matching text") }
        if !apps.isEmpty { parts.append(apps.count == 1 ? "only in \(apps.first!)" : "only in \(apps.count) apps") }
        if !secrets.isEmpty { parts.append("needs \(secrets.joined(separator: ", "))") }
        if let group { parts.append("in \(group) ›") }
        return parts.joined(separator: ", ")
    }

    func makeAction() -> PopAction {
        PopAction(id: id, title: name, icon: icon, group: group,
                  prepare: { ctx in self.prepare(ctx) },
                  perform: { ctx in self.perform(ctx) })
    }

    func prepare(_ ctx: SelectionContext) -> SelectionContext? {
        if !apps.isEmpty && !apps.contains(ctx.bundleID) { return nil }
        switch target {
        case .files:
            return ctx.files.isEmpty ? nil : ctx
        case .text:
            guard !ctx.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            if after == .paste && !ctx.canPaste { return nil }
            if let match, match.firstMatch(in: ctx.text, range: NSRange(ctx.text.startIndex..., in: ctx.text)) == nil {
                return nil
            }
            return ctx
        }
    }

    private func perform(_ ctx: SelectionContext) {
        switch kind {
        case .url:
            withBrowserTab(ctx) { tab in
                if let url = resolvedURL(ctx, tab: tab) { NSWorkspace.shared.open(url) }
            }
        case .keys(let combos):
            Keyboard.press(sequence: combos)
        case .script, .appleScript:
            if let missing = missingSecrets.first {
                HUD.shared.show(symbol: "key", text: "\(name) needs \(missing)", near: ctx.anchor)
                SettingsWindowController.shared.showSettings(forExtension: id)
                return
            }
            run(ctx) { result in
                switch result {
                case .failure(let error):
                    NSLog("Popoli: %@ failed: %@", name, error.message)
                    HUD.shared.show(symbol: "xmark", text: "\(name): \(error.message)", near: ctx.anchor)
                case .success(let output):
                    handle(output, ctx)
                }
            }
        }
    }

    private func handle(_ output: String, _ ctx: SelectionContext) {
        // With `output: markdown` or `html`, pasting and copying keep the formatting.
        let rich: String? = switch self.output {
        case .text: nil
        case .html: output
        case .markdown: MarkdownToHTML.convert(output)
        }
        switch after ?? (output.isEmpty ? .none : .show) {
        case .show:
            guard !output.isEmpty else { break }
            if let rich {
                // HTML output: its text for plain pastes; Markdown output: the Markdown itself.
                let plain = self.output == .html ? Self.plainText(fromHTML: rich) : output
                Popoli.result.showHTML(title: name, html: rich, plain: plain, base: file.deletingLastPathComponent(), ctx)
            } else {
                Popoli.result.showText(title: name, text: output, ctx)
            }
        case .paste:
            if let rich { RichClipboard.paste(html: rich, plain: output) } else { Clipboard.paste(output) }
        case .copy:
            if let rich { RichClipboard.write(html: rich, plain: output) } else { Clipboard.copy(output) }
            HUD.shared.show(symbol: "checkmark", text: "Copied", near: ctx.anchor)
        case .none:
            break
        }
    }

    /// The URL a link extension opens, with `{text}` (and `{url}`, the browser's page) filled in.
    func resolvedURL(_ ctx: SelectionContext, tab: BrowserTab.Page? = nil) -> URL? {
        guard case .url(let template) = kind else { return nil }
        let text = ctx.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: template.replacingOccurrences(of: "{text}", with: URLEncoding.encode(text))
            .replacingOccurrences(of: "{url}", with: URLEncoding.encode(tab?.url ?? "")))
    }

    /// Looks up the browser's page first when the extension uses it.
    private func withBrowserTab(_ ctx: SelectionContext, _ body: @escaping (BrowserTab.Page?) -> Void) {
        guard usesBrowserTab, let app = ctx.app else { return body(nil) }
        BrowserTab.current(in: app, completion: body)
    }

    /// Runs a script or AppleScript extension; calls back on the main thread with its output.
    /// With `input: html` or `markdown`, the formatted selection is copied first (a ⌘C round
    /// trip that leaves the clipboard as it was), off the main thread.
    func run(_ ctx: SelectionContext, completion: @escaping (Result<String, ExtensionError>) -> Void) {
        withBrowserTab(ctx) { tab in
            guard input != .text, target == .text else {
                return launch(ctx, html: nil, tab: tab, completion: completion)
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let formats = Clipboard.copySelectionFormats()
                DispatchQueue.main.async {
                    launch(ctx, html: Self.html(from: formats, fallback: ctx.text), tab: tab, completion: completion)
                }
            }
        }
    }

    static func plainText(fromHTML html: String) -> String {
        guard let data = html.data(using: .utf8),
              let attributed = NSAttributedString(html: data, documentAttributes: nil) else { return html }
        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The selection as HTML: what the app copied, its RTF converted, or the plain text.
    static func html(from formats: Clipboard.Formats?, fallback: String) -> String {
        if let html = formats?.html, !html.isEmpty { return html }
        if let rtf = formats?.rtf, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil),
           let data = try? attributed.data(from: NSRange(location: 0, length: attributed.length),
                                           documentAttributes: [.documentType: NSAttributedString.DocumentType.html]),
           let html = String(data: data, encoding: .utf8) {
            return html
        }
        return "<p>" + MarkdownToHTML.escape(formats?.text ?? fallback).replacingOccurrences(of: "\n", with: "<br>") + "</p>"
    }

    private func launch(_ ctx: SelectionContext, html: String?, tab: BrowserTab.Page?,
                        completion: @escaping (Result<String, ExtensionError>) -> Void) {
        var environment = [
            "POPOLI_TEXT": Self.envSafe(ctx.text),
            "POPOLI_FILES": ctx.files.joined(separator: "\n"),
            "POPOLI_APP": ctx.bundleID,
            "POPOLI_APP_NAME": ctx.appName,
        ]
        if usesBrowserTab {
            environment["POPOLI_BROWSER_URL"] = tab?.url ?? ""
            environment["POPOLI_BROWSER_TITLE"] = tab?.title ?? ""
        }
        // Keys held while clicking the button, for alternate behaviour.
        let keys: [(String, NSEvent.ModifierFlags)] = [("shift", .shift), ("option", .option),
                                                        ("command", .command), ("control", .control)]
        environment["POPOLI_MODIFIERS"] = keys.filter { ctx.modifiers.contains($0.1) }.map(\.0).joined(separator: " ")
        for (name, flag) in keys { environment["POPOLI_\(name.uppercased())"] = ctx.modifiers.contains(flag) ? "1" : "0" }
        for setting in settings {
            environment[setting.name] = Settings.extensionSetting(id, setting.name) ?? setting.defaultValue
        }
        for secret in secrets { environment[secret] = Keychain.get(secret) ?? "" }

        var input = target == .files ? ctx.files.joined(separator: "\n") : ctx.text
        if let html {
            let markdown = HTMLToMarkdown.convert(html) ?? ctx.text
            environment["POPOLI_HTML"] = Self.envSafe(html)
            environment["POPOLI_MARKDOWN"] = Self.envSafe(markdown)
            input = self.input == .html ? html : markdown
        }
        // Finder files are also passed as arguments, so `for f in "$@"` works.
        let extraArguments = target == .files ? ctx.files : []
        let directory = file.deletingLastPathComponent()

        switch kind {
        case .script(let interpreter):
            Runner.run(executable: URL(fileURLWithPath: interpreter[0]),
                       arguments: Array(interpreter.dropFirst()) + [file.path] + extraArguments,
                       input: input, environment: environment, directory: directory, timeout: 60,
                       completion: completion)
        case .appleScript:
            // `on run argv` receives the text (or the file paths) as item 1, 2, ….
            let arguments = target == .files ? ctx.files : [input]
            Runner.run(executable: URL(fileURLWithPath: "/usr/bin/osascript"), arguments: [file.path] + arguments,
                       input: nil, environment: environment, directory: directory, timeout: 60,
                       completion: completion)
        case .url, .keys:
            completion(.failure(ExtensionError("Not a script extension")))
        }
    }

    /// Environment variables share a size limit with the arguments; very long selections are
    /// left out of them (they are always complete on stdin).
    private static func envSafe(_ value: String) -> String {
        value.utf8.count < 100_000 ? value : ""
    }
}

/// An entry for the menu: a loaded extension, or a file that could not be loaded and why.
struct ExtensionInfo {
    let id: String
    let name: String
    let file: URL
    let ext: UserExtension?
    let problem: String?
    let action: PopAction?
}

struct ExtensionError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum URLEncoding {
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }
}

// MARK: - Loading

enum ExtensionStore {
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/popoli/extensions", isDirectory: true)
    }

    private static let headerKeys: Set<String> = ["name", "icon", "after", "match", "apps", "for", "url", "keys",
                                                  "input", "output", "setting", "secret", "group"]
    private static let variableName = try! NSRegularExpression(pattern: "^[A-Za-z_][A-Za-z0-9_]*$")
    private static let ignoredExtensions: Set<String> = ["md", "txt", "png", "jpg", "jpeg", "svg", "pdf", "log"]

    /// On first launch, creates the folder and copies the bundled examples into it,
    /// so there is something to look at and edit.
    static func seedExamplesIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: folder.path) else { return }
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("Extensions"),
              let files = try? fm.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? fm.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
        }
    }

    static func loadAll(from folder: URL = folder) -> [ExtensionInfo] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                 options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .filter { !ignoredExtensions.contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.hasPrefix("README") }
            .map(load)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// File names and modification dates; changes when extensions are added, removed or edited.
    static func signature(of folder: URL = folder) -> String {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        return files.map { file in
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            return "\(file.lastPathComponent)@\(date?.timeIntervalSince1970 ?? 0)"
        }.sorted().joined(separator: "|")
    }

    static func load(_ file: URL) -> ExtensionInfo {
        let fallbackName = file.deletingPathExtension().lastPathComponent
        do {
            let ext = try parse(file)
            return ExtensionInfo(id: ext.id, name: ext.name, file: file, ext: ext, problem: nil, action: ext.makeAction())
        } catch {
            return ExtensionInfo(id: "ext." + file.lastPathComponent, name: fallbackName, file: file, ext: nil,
                                 problem: (error as? ExtensionError)?.message ?? error.localizedDescription, action: nil)
        }
    }

    static func parse(_ file: URL) throws -> UserExtension {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            throw ExtensionError("Can’t read the file (is it UTF-8 text?)")
        }
        return try parse(text: text, file: file)
    }

    /// Parses extension text as if it were saved at `file` (the file name decides the type,
    /// e.g. .popoli or .applescript). Used to preview an extension before installing it.
    static func parse(text: String, file: URL) throws -> UserExtension {
        var meta: [String: String] = [:]
        var settings: [UserExtension.Setting] = []
        var secrets: [String] = []
        func isVariable(_ name: String) -> Bool {
            variableName.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
        }
        for (key, value) in header(of: text) {
            switch key {
            case "setting":
                let parts = value.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard let settingName = parts.first, isVariable(settingName) else {
                    throw ExtensionError("setting: needs a name like MODEL or MODEL = default")
                }
                settings.append(.init(name: settingName, defaultValue: parts.count > 1 ? parts[1] : ""))
            case "secret":
                let secretName = value.split(separator: " ").first.map(String.init) ?? ""
                guard isVariable(secretName) else { throw ExtensionError("secret: needs a name like ANTHROPIC_API_KEY") }
                secrets.append(secretName)
            default:
                meta[key] = value
            }
        }
        let kind: UserExtension.Kind
        if let url = meta["url"] {
            guard url.contains("{text}") || url.contains("{url}"),
                  URL(string: url.replacingOccurrences(of: "{text}", with: "x").replacingOccurrences(of: "{url}", with: "x")) != nil else {
                throw ExtensionError("url: must be a link containing {text} or {url}")
            }
            kind = .url(url)
        } else if let keys = meta["keys"] {
            guard let combo = Keyboard.parse(string: keys) else { throw ExtensionError("Unknown keys: \(keys)") }
            kind = .keys([combo])
        } else if ["applescript", "scpt"].contains(file.pathExtension.lowercased()) {
            kind = .appleScript
        } else if file.pathExtension.lowercased() == "popoli" {
            throw ExtensionError("A .popoli file needs url: or keys:")
        } else {
            kind = .script(interpreter: interpreter(for: file, firstLine: text.prefix { $0 != "\n" }))
        }

        guard let name = meta["name"], !name.isEmpty else {
            throw ExtensionError("Missing “name:” in the header")
        }
        let after: UserExtension.After?
        if let value = meta["after"] {
            guard let parsed = UserExtension.After(rawValue: value.lowercased()) else {
                throw ExtensionError("after: must be show, paste, copy or none")
            }
            after = parsed
        } else {
            after = nil
        }
        let target = UserExtension.Target(rawValue: (meta["for"] ?? "text").lowercased()) ?? .text
        var match: NSRegularExpression?
        if let pattern = meta["match"] {
            do { match = try NSRegularExpression(pattern: pattern) } catch { throw ExtensionError("Invalid match: regex") }
        }
        let apps = Set((meta["apps"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        func format(_ key: String) throws -> UserExtension.Format {
            guard let value = meta[key] else { return .text }
            guard let format = UserExtension.Format(rawValue: value.lowercased()) else {
                throw ExtensionError("\(key): must be text, html or markdown")
            }
            return format
        }

        let group = meta["group"].flatMap { $0.isEmpty ? nil : $0 }
        let usesBrowserTab = text.contains("POPOLI_BROWSER_URL") || text.contains("POPOLI_BROWSER_TITLE")
            || (meta["url"]?.contains("{url}") ?? false)

        return UserExtension(file: file, name: name, icon: Icons.load(meta["icon"], folder: file.deletingLastPathComponent()),
                             kind: kind, after: after, target: target, match: match, apps: apps,
                             input: try format("input"), output: try format("output"),
                             settings: settings, secrets: secrets, group: group, usesBrowserTab: usesBrowserTab)
    }

    /// Reads `key: value` comment lines at the top of a script (after an optional #! line).
    /// `#`, `//` and `--` comments all work. The header ends at the first line that is not
    /// such a comment, including an empty `#` line.
    static func header(of text: String) -> [(String, String)] {
        var meta: [(String, String)] = []
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if index == 0 && line.hasPrefix("#!") { continue }
            guard let prefix = ["//", "--", "#"].first(where: line.hasPrefix) else { break }
            let body = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            guard let colon = body.firstIndex(of: ":") else { break }
            let key = body[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard headerKeys.contains(key) else { break }
            meta.append((key, body[body.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
        }
        return meta
    }

    /// The command that runs a script: its #! line, or a guess from the file extension.
    /// Scripts do not need to be executable.
    static func interpreter(for file: URL, firstLine: Substring) -> [String] {
        if firstLine.hasPrefix("#!") {
            let parts = firstLine.dropFirst(2).split(separator: " ").map(String.init)
            if let first = parts.first, first.hasPrefix("/") { return parts }
        }
        switch file.pathExtension.lowercased() {
        case "py": return ["/usr/bin/env", "python3"]
        case "js", "mjs": return ["/usr/bin/env", "node"]
        case "rb": return ["/usr/bin/env", "ruby"]
        case "pl": return ["/usr/bin/env", "perl"]
        case "swift": return ["/usr/bin/env", "swift"]
        case "sh": return ["/bin/sh"]
        case "bash": return ["/bin/bash"]
        default: return ["/bin/zsh"]
        }
    }

    // MARK: New extension

    static let template = """
    #!/bin/zsh
    # name: My Extension
    # icon: sparkles
    # after: show
    #
    # The selected text is in $POPOLI_TEXT (and on stdin).
    # Whatever this script prints is the result. "after" decides what happens with it:
    #   show   shown in a card (the default)
    #   paste  replaces the selection
    #   copy   copied to the clipboard
    #   none   ignored
    #
    # Optional header lines:
    #   # match: ^https?://              only for selections matching this regex
    #   # apps: com.apple.Safari, com.apple.Notes   only in these apps
    #   # for: files                     for files selected in Finder ($@ / $POPOLI_FILES)
    #
    # icon is an SF Symbol name (see the SF Symbols app), up to 3 letters, or an emoji.
    # Any language works: change the first line to #!/usr/bin/env python3, node, ruby…
    #
    # No code needed for links and shortcuts: a file with just the header, e.g.
    #   # url: https://www.google.com/search?q={text}
    #   # keys: cmd shift H

    print -rn -- "$POPOLI_TEXT" | rev

    """

    /// Writes a new extension from the template and returns its URL.
    static func createNew() throws -> URL {
        try create(file: "my-extension.sh", contents: template)
    }

    /// Writes `contents` to a new file in the extensions folder, adding -2, -3… to the
    /// name if it is taken, and returns its URL.
    static func create(file name: String, contents: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var url = folder.appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base)-\(n).\(ext)")
            n += 1
        }
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Keeps README.md in the extensions folder (the cheat sheet) up to date. A README the
    /// user wrote themselves is left alone.
    static func writeGuide() {
        let url = folder.appendingPathComponent("README.md")
        let current = try? String(contentsOf: url, encoding: .utf8)
        guard current == nil || current!.hasPrefix("# Writing Popoli extensions") else { return }
        let markdown = ExtensionGuide.markdown
        if current != markdown {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Process runner

enum Runner {
    private static let queue = DispatchQueue(label: "app.popoli.runner", attributes: .concurrent)

    /// Runs a process off the main thread and calls back on the main thread with stdout
    /// (one trailing newline removed) or an error built from stderr.
    ///
    /// Spawned by hand rather than with `Process`, which turns arguments and environment into
    /// decomposed Unicode (é arrives as e + ◌́) and breaks text comparisons in scripts.
    static func run(executable: URL, arguments: [String], input: String?, environment: [String: String],
                    directory: URL, timeout: TimeInterval,
                    completion: @escaping (Result<String, ExtensionError>) -> Void) {
        queue.async {
            let finish = { (result: Result<String, ExtensionError>) in DispatchQueue.main.async { completion(result) } }
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
            env.merge(environment) { _, new in new }

            var stdinPipe: [Int32] = [-1, -1], outPipe: [Int32] = [-1, -1], errPipe: [Int32] = [-1, -1]
            guard pipe(&outPipe) == 0, pipe(&errPipe) == 0, input == nil || pipe(&stdinPipe) == 0 else {
                return finish(.failure(ExtensionError("Could not create pipes")))
            }

            var actions: posix_spawn_file_actions_t?
            posix_spawn_file_actions_init(&actions)
            defer { posix_spawn_file_actions_destroy(&actions) }
            if input != nil {
                posix_spawn_file_actions_adddup2(&actions, stdinPipe[0], 0)
            } else {
                posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
            }
            posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
            posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)
            posix_spawn_file_actions_addchdir(&actions, directory.path)

            // Its own process group, so a timeout also stops what the script started (curl…);
            // none of Popoli's descriptors; SIGPIPE back to default (Popoli ignores it).
            var attributes: posix_spawnattr_t?
            posix_spawnattr_init(&attributes)
            defer { posix_spawnattr_destroy(&attributes) }
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF))
            posix_spawnattr_setpgroup(&attributes, 0)
            var defaultSignals = sigset_t()
            sigemptyset(&defaultSignals)
            sigaddset(&defaultSignals, SIGPIPE)
            posix_spawnattr_setsigdefault(&attributes, &defaultSignals)

            let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
            let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
            defer {
                argv.forEach { free($0) }
                envp.forEach { free($0) }
            }

            var pid: pid_t = 0
            let spawned = posix_spawn(&pid, executable.path, &actions, &attributes, argv, envp)
            close(outPipe[1])
            close(errPipe[1])
            if input != nil { close(stdinPipe[0]) }
            guard spawned == 0 else {
                close(outPipe[0])
                close(errPipe[0])
                if input != nil { close(stdinPipe[1]) }
                return finish(.failure(ExtensionError("Could not start \(executable.lastPathComponent): \(String(cString: strerror(spawned)))")))
            }

            if let input {
                let fd = stdinPipe[1]
                DispatchQueue.global(qos: .userInitiated).async {
                    let bytes = Array(input.utf8)
                    var offset = 0
                    while offset < bytes.count {
                        let written = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
                        if written > 0 { offset += written } else if written < 0 && errno == EINTR { continue } else { break }
                    }
                    close(fd)
                }
            }

            var timedOut = false
            let timer = DispatchWorkItem {
                timedOut = true
                kill(-pid, SIGTERM)
            }
            queue.asyncAfter(deadline: .now() + timeout, execute: timer)

            var errorData = Data()
            let errorRead = DispatchGroup()
            errorRead.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                errorData = readAll(errPipe[0])
                errorRead.leave()
            }
            let outData = readAll(outPipe[0])
            errorRead.wait()
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            timer.cancel()

            var output = String(decoding: outData, as: UTF8.self)
            if output.hasSuffix("\n") { output.removeLast() }
            let errorText = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let exitedNormally = status & 0x7f == 0
            let exitCode = (status >> 8) & 0xff
            if timedOut {
                finish(.failure(ExtensionError("Timed out")))
            } else if exitedNormally && exitCode == 0 {
                finish(.success(output))
            } else {
                let firstLine = errorText.split(separator: "\n").first.map(String.init)
                finish(.failure(ExtensionError(firstLine ?? (exitedNormally ? "Exited with status \(exitCode)" : "Stopped by a signal"))))
            }
        }
    }

    private static func readAll(_ fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else if count < 0 && errno == EINTR {
                continue
            } else {
                break
            }
        }
        close(fd)
        return data
    }
}
