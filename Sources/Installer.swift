import AppKit
import SwiftUI

/// Installing extensions from outside: selected text, a link (popoli://install?url=… or
/// pasted), or a file. Every way ends in the same review window, which shows what the
/// extension does and its full code; nothing is installed without clicking Install.
enum ExtensionInstaller {
    /// Extensions are small text files; anything bigger is not one.
    static let maxSize = 256 * 1024

    struct Candidate {
        let contents: String
        let fileName: String
        /// Where it came from, shown in the review window.
        let origin: String
        let ext: UserExtension?
        let problem: String?
        /// Set when it came from the catalog unchanged: the fingerprint to remember.
        var catalogFingerprint: String? = nil

        var destination: URL { ExtensionStore.folder.appendingPathComponent(fileName) }
        var replacesExisting: Bool { FileManager.default.fileExists(atPath: destination.path) }
    }

    // MARK: Recognising and naming

    /// True when text starts with a Popoli header that has a name: what the selection bar
    /// checks before offering Install Extension.
    static func looksLikeExtension(_ text: String) -> Bool {
        guard text.utf8.count <= maxSize else { return false }
        let trimmed = normalized(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["#", "//", "--"].contains(where: trimmed.hasPrefix) else { return false }
        return ExtensionStore.header(of: trimmed).contains { $0.0 == "name" }
    }

    static func candidate(text: String, suggestedFileName: String?, origin: String) -> Candidate {
        let contents = normalized(text)
        let fileName = suggestedFileName.flatMap(sanitizedFileName) ?? derivedFileName(for: contents)
        let file = ExtensionStore.folder.appendingPathComponent(fileName)
        do {
            let ext = try ExtensionStore.parse(text: contents, file: file)
            return Candidate(contents: contents, fileName: fileName, origin: origin, ext: ext, problem: nil)
        } catch {
            let message = (error as? ExtensionError)?.message ?? error.localizedDescription
            return Candidate(contents: contents, fileName: fileName, origin: origin, ext: nil, problem: message)
        }
    }

    /// Unix line endings, no stray blank lines around it, non-breaking spaces (which web
    /// pages put into code) turned into plain ones, and a final newline.
    static func normalized(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ")
        s = s.trimmingCharacters(in: .newlines)
        return s + "\n"
    }

    /// A file name from the extension's name and language, e.g. "improve-writing.sh".
    static func derivedFileName(for text: String) -> String {
        let header = ExtensionStore.header(of: text)
        let name = header.first { $0.0 == "name" }?.1 ?? "extension"
        let firstLine = text.prefix { $0 != "\n" }.lowercased()
        let type: String
        if firstLine.hasPrefix("#!") {
            let known = [("python", "py"), ("node", "js"), ("ruby", "rb"), ("perl", "pl"), ("swift", "swift"),
                         ("osascript", "applescript")]
            type = known.first { firstLine.contains($0.0) }?.1 ?? "sh"
        } else if header.contains(where: { $0.0 == "url" || $0.0 == "keys" }) {
            type = "popoli"
        } else if text.hasPrefix("//") {
            type = "js"
        } else if text.hasPrefix("--") {
            type = "applescript"
        } else {
            type = "sh"
        }
        return slug(name) + "." + type
    }

    static func slug(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
        let slug = folded.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "extension" : String(slug.prefix(40))
    }

    /// A downloaded or chosen file keeps its name when it is a safe, extension-like name.
    static func sanitizedFileName(_ name: String) -> String? {
        let base = (name.removingPercentEncoding ?? name).components(separatedBy: "/").last ?? ""
        let safe = base.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
        let type = (safe as NSString).pathExtension.lowercased()
        guard !safe.hasPrefix("."), !type.isEmpty, safe.count <= 80,
              !["md", "txt", "html", "htm", "png", "jpg", "jpeg", "svg", "pdf", "log", "json"].contains(type) else { return nil }
        return safe
    }

    // MARK: Sources

    /// Text from a link. GitHub file and gist pages are turned into their raw file first.
    static func fetch(_ url: URL, completion: @escaping (Result<(String, URL), ExtensionError>) -> Void) {
        let url = rawURL(for: url)
        guard url.scheme?.lowercased() == "https" else {
            return completion(.failure(ExtensionError("Only https:// links can be installed.")))
        }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
            let result: Result<(String, URL), ExtensionError>
            if let error {
                result = .failure(ExtensionError(error.localizedDescription))
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(ExtensionError("The server answered with HTTP \(http.statusCode)."))
            } else if let data, let text = text(from: data) {
                result = .success((text, response?.url ?? url))
            } else {
                result = .failure(ExtensionError("That link is not an extension file (it must be UTF-8 text under 256 KB)."))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    static func text(from data: Data) -> String? {
        guard data.count <= maxSize, !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// github.com/owner/repo/blob/ref/path → raw.githubusercontent.com/owner/repo/ref/path,
    /// gist.github.com/user/id → gist.githubusercontent.com/user/id/raw.
    static func rawURL(for url: URL) -> URL {
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host?.lowercased() ?? "" {
        case "github.com" where parts.count >= 5 && parts[2] == "blob":
            let rest = ([parts[0], parts[1]] + parts[3...]).joined(separator: "/")
            return URL(string: "https://raw.githubusercontent.com/\(rest)") ?? url
        case "gist.github.com" where parts.count >= 2:
            return URL(string: "https://gist.githubusercontent.com/\(parts[0])/\(parts[1])/raw") ?? url
        default:
            return url
        }
    }

    // MARK: Review and install

    static func reviewSelection(_ text: String, appName: String) {
        let origin = appName.isEmpty ? "Selected text" : "Selected text in \(appName)"
        InstallWindowController.shared.review(candidate(text: text, suggestedFileName: nil, origin: origin))
    }

    static func reviewLink(_ url: URL) {
        fetch(url) { result in
            switch result {
            case .success(let (text, finalURL)):
                InstallWindowController.shared.review(
                    candidate(text: text, suggestedFileName: finalURL.lastPathComponent, origin: url.absoluteString))
            case .failure(let error):
                showError("Couldn’t download the extension", error.message)
            }
        }
    }

    static func reviewFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url), let text = text(from: data) else {
            return showError("Couldn’t read \(url.lastPathComponent)", "An extension is a UTF-8 text file under 256 KB.")
        }
        let origin = "File " + (url.path as NSString).abbreviatingWithTildeInPath
        InstallWindowController.shared.review(candidate(text: text, suggestedFileName: url.lastPathComponent, origin: origin))
    }

    static let didInstall = Notification.Name("app.popoli.Popoli.extensionInstalled")

    static func install(_ candidate: Candidate) throws {
        try FileManager.default.createDirectory(at: ExtensionStore.folder, withIntermediateDirectories: true)
        try candidate.contents.write(to: candidate.destination, atomically: true, encoding: .utf8)
        if let ext = candidate.ext { Settings.setEnabled(ext.id, true) }
        if let fingerprint = candidate.catalogFingerprint { Catalog.recordInstall(file: candidate.fileName, fingerprint: fingerprint) }
        Popoli.registry.reload()
        NotificationCenter.default.post(name: didInstall, object: nil)
    }

    /// Settings ▸ Catalog: downloads the file and checks it against the catalog's list
    /// before the usual review.
    static func reviewCatalog(_ entry: Catalog.Entry) {
        fetch(Catalog.fileURL(entry.file)) { result in
            switch result {
            case .success(let (text, _)):
                let unchanged = Catalog.fingerprint(text) == entry.sha256
                var candidate = candidate(text: text, suggestedFileName: entry.file,
                                          origin: unchanged ? "Popoli catalog" : "Popoli catalog, but different from its list")
                candidate.catalogFingerprint = unchanged ? entry.sha256 : nil
                InstallWindowController.shared.review(candidate)
            case .failure(let error):
                showError("Couldn’t download \(entry.name)", error.message)
            }
        }
    }

    static func showError(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    // MARK: What it does, in words

    struct Fact: Hashable {
        enum Level { case info, caution, danger }
        let symbol: String
        let text: String
        var level = Level.info
    }

    /// Things in the code worth a second look, found by simple patterns. They are hints for
    /// the reader, not a verdict: harmless code can match and harmful code can avoid them.
    static func warnings(in code: String, for ext: UserExtension?) -> [Fact] {
        // Links and shortcuts have no code; their facts say where they go.
        if let ext, case .url = ext.kind { return [] }
        if let ext, case .keys = ext.kind { return [] }
        let checks: [(Fact.Level, String, String, String)] = [
            (.danger, "arrow.down.app", "Downloads code from the internet and runs it",
             #"(curl|wget)[^\n]*\|\s*(sudo\s+)?(ba|z|da|k)?sh\b|(curl|wget)[^\n]*\|\s*(python|perl|ruby|node|osascript)|(ba|z)?sh\s+(-c\s+)?["']?\$\(\s*(curl|wget)|<\(\s*(curl|wget)"#),
            (.danger, "trash", "Deletes files", #"\brm\s+-[a-zA-Z]*[rRf]|\bsrm\b|diskutil\s+erase|\bshred\b"#),
            (.danger, "key.horizontal", "Reads keys, passwords or browser data",
             #"\.ssh\b|id_rsa|id_ed25519|\.aws/credentials|\.gnupg|Library/Keychains|security\s+(find|dump|export)|\.netrc|Library/Cookies|Application Support/Google/Chrome|Safari/History|\.config/gh"#),
            (.danger, "lock.open", "Asks for administrator rights", #"\bsudo\b|with administrator privileges"#),
            (.danger, "power", "Changes what runs when you log in or open a terminal",
             #"launchctl|LaunchAgents|LaunchDaemons|crontab|\.zshrc|\.zprofile|\.bash_profile|\.bashrc|login item"#),
            (.danger, "eye.slash", "Contains hidden or encoded code",
             #"base64\s+(-d|-D|--decode)[^\n]*\|\s*(ba|z)?sh|eval\s*\(\s*atob|(\\x[0-9a-fA-F]{2}){24,}|[A-Za-z0-9+/]{400,}={0,2}"#),
            (.caution, "network", "Connects to the internet",
             #"\b(curl|wget|nc|ncat|scp|rsync|ssh|ftp)\b|URLSession|NSURLSession|dataWithContentsOfURL|\bfetch\(|XMLHttpRequest|requests\.|urllib|http\.client|https?://"#),
            (.caution, "hand.point.up.left", "Controls other apps or types for you",
             #"System Events|\bkeystroke\b|key code|CGEventPost|CGEventCreateKeyboardEvent|AXUIElement"#),
        ]
        return checks.compactMap { level, symbol, text, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil else { return nil }
            return Fact(symbol: symbol, text: text, level: level)
        }
    }

    static func facts(about ext: UserExtension) -> [Fact] {
        var facts: [Fact] = []
        switch ext.kind {
        case .script(let interpreter):
            let language = interpreter.count > 1 && interpreter[0].hasSuffix("/env")
                ? interpreter[1] : (interpreter[0] as NSString).lastPathComponent
            facts.append(Fact(symbol: "terminal", text: "Runs a \(language) script on your Mac, with your permissions"))
        case .appleScript:
            facts.append(Fact(symbol: "applescript", text: "Runs an AppleScript, which can control other apps"))
        case .url(let template):
            let host = URL(string: template.replacingOccurrences(of: "{text}", with: "x"))?.host ?? template
            facts.append(Fact(symbol: "link", text: "Opens a link on \(host) with the selected text"))
        case .keys(let combos):
            facts.append(Fact(symbol: "keyboard", text: "Presses \(combos.map(shortcutText).joined(separator: ", ")) in the app with the selection"))
        }
        switch ext.kind {
        case .script, .appleScript:
            switch ext.after {
            case .paste?: facts.append(Fact(symbol: "text.cursor", text: "Replaces the selection with what it prints"))
            case .copy?: facts.append(Fact(symbol: "doc.on.clipboard", text: "Copies what it prints"))
            case .none?: break
            default: facts.append(Fact(symbol: "text.bubble", text: "Shows what it prints in a card"))
            }
        default:
            break
        }
        if ext.target == .files { facts.append(Fact(symbol: "folder", text: "Works on the files selected in Finder")) }
        if ext.input != .text { facts.append(Fact(symbol: "doc.richtext", text: "Reads the selection with its formatting")) }
        let saved = ext.secrets.filter(Keychain.has), new = ext.secrets.filter { !Keychain.has($0) }
        if !saved.isEmpty {
            facts.append(Fact(symbol: "key.fill", text: "Wants your saved \(saved.joined(separator: ", ")); Popoli asks you before giving it",
                              level: .caution))
        }
        if !new.isEmpty {
            facts.append(Fact(symbol: "key", text: "Asks for \(new.joined(separator: ", ")), kept in your keychain"))
        }
        if !ext.settings.isEmpty {
            facts.append(Fact(symbol: "slider.horizontal.3", text: "Has settings: \(ext.settings.map(\.name).joined(separator: ", "))"))
        }
        if !ext.apps.isEmpty { facts.append(Fact(symbol: "macwindow", text: "Only in \(ext.apps.sorted().joined(separator: ", "))")) }
        if let match = ext.match { facts.append(Fact(symbol: "line.3.horizontal.decrease", text: "Only for selections matching \(match.pattern)")) }
        return facts
    }

    private static func shortcutText(_ combo: KeyCombo) -> String {
        var s = ""
        if combo.flags.contains(.maskControl) { s += "⌃" }
        if combo.flags.contains(.maskAlternate) { s += "⌥" }
        if combo.flags.contains(.maskShift) { s += "⇧" }
        if combo.flags.contains(.maskCommand) { s += "⌘" }
        return s + Keyboard.keyName(for: combo.keyCode)
    }
}

// MARK: - Asking for a link or a file

enum InstallPrompt {
    /// "Install Extension…": a link to paste (pre-filled from the clipboard), or a file.
    static func run() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Install an Extension"
        alert.informativeText = "Paste a link to an extension file (a GitHub file or gist works too), or choose a file on your Mac. You’ll see its code before anything is installed."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "https://"
        if let clip = NSPasteboard.general.string(forType: .string)?.trimmed, clip.hasPrefix("https://"), !clip.contains(" ") {
            field.stringValue = clip
        }
        alert.accessoryView = field
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Choose File…")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            guard let url = URL(string: field.stringValue.trimmed), url.scheme != nil else {
                return ExtensionInstaller.showError("That isn’t a link", "Paste a link that starts with https://.")
            }
            ExtensionInstaller.reviewLink(url)
        case .alertSecondButtonReturn:
            chooseFile()
        default:
            break
        }
    }

    static func chooseFile() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.prompt = "Review"
        panel.message = "Choose an extension file to review before installing it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ExtensionInstaller.reviewFile(url)
    }
}

// MARK: - Review window

final class InstallWindowController {
    static let shared = InstallWindowController()
    private var window: NSWindow?

    func review(_ candidate: ExtensionInstaller.Candidate) {
        let view = InstallReviewView(candidate: candidate,
                                     install: { [weak self] in self?.install(candidate) },
                                     cancel: { [weak self] in self?.window?.close() })
        let controller = NSHostingController(rootView: view)
        if let window {
            window.contentViewController = controller
        } else {
            let window = NSWindow(contentViewController: controller)
            window.title = "Install Extension"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            self.window = window
        }
        NSApp.activate()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func install(_ candidate: ExtensionInstaller.Candidate) {
        do {
            try ExtensionInstaller.install(candidate)
        } catch {
            return ExtensionInstaller.showError("Couldn’t install the extension", error.localizedDescription)
        }
        let frame = window?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        window?.close()
        HUD.shared.show(symbol: "checkmark", text: "Installed \(candidate.ext?.name ?? candidate.fileName)",
                        near: NSRect(x: frame.midX, y: frame.midY, width: 0, height: 0))
        // An extension that needs an API key asks for it right away.
        if let ext = candidate.ext, !ext.missingSecrets.isEmpty {
            SettingsWindowController.shared.showSettings(forExtension: ext.id)
        }
    }
}

private struct InstallReviewView: View {
    let candidate: ExtensionInstaller.Candidate
    let install: () -> Void
    let cancel: () -> Void

    private var warnings: [ExtensionInstaller.Fact] { ExtensionInstaller.warnings(in: candidate.contents, for: candidate.ext) }
    private var risky: Bool { warnings.contains { $0.level == .danger } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Group {
                    if let icon = candidate.ext?.icon {
                        Image(nsImage: icon).renderingMode(icon.isTemplate ? .template : .original)
                    } else {
                        Image(systemName: "puzzlepiece.extension")
                    }
                }
                .font(.system(size: 22))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.ext?.name ?? "Extension").font(.title3.weight(.semibold))
                    if candidate.catalogFingerprint != nil {
                        Label("From the Popoli catalog, unchanged", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text(candidate.origin)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            if let problem = candidate.problem {
                Label("This isn’t a valid Popoli extension: \(problem)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if let ext = candidate.ext {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(warnings + ExtensionInstaller.facts(about: ext), id: \.self) { fact in
                        Label(fact.text, systemImage: fact.symbol)
                            .foregroundStyle(fact.level == .danger ? Color.red : fact.level == .caution ? Color.orange : Color.primary)
                            .fontWeight(fact.level == .danger ? .semibold : .regular)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Code").font(.headline)
                ScrollView([.vertical, .horizontal]) {
                    Text(candidate.contents)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize()
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 240)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            }

            Label("Extensions run with your permissions and Popoli’s, so they can also control other apps. Install only code you have read, or that comes from someone you trust.",
                  systemImage: "exclamationmark.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(candidate.replacesExisting ? "Replaces the installed \(candidate.fileName)" : "Saved as \(candidate.fileName)")
                    .font(.caption)
                    .foregroundStyle(candidate.replacesExisting ? Color.orange : Color.secondary)
                Spacer()
                // With a red warning, Return cancels: installing takes a deliberate click.
                Button("Cancel", action: cancel)
                    .keyboardShortcut(risky ? .defaultAction : .cancelAction)
                Button(candidate.replacesExisting ? "Replace" : "Install", action: install)
                    .keyboardShortcut(risky ? nil : .defaultAction)
                    .disabled(candidate.ext == nil)
            }
        }
        .padding(20)
        .frame(width: 580)
    }
}
