import AppKit

/// One button on the bar. Built-ins and extension actions share this shape.
final class PopAction {
    let id: String
    /// The row in Settings ▸ Buttons it belongs to, which turns it on and off and orders it.
    /// Its own id, except for buttons that one row makes (Open in › makes one per app).
    let rowID: String
    let title: String
    /// nil → the bar shows `title` as text.
    let icon: NSImage?
    /// What ⇧/⌥-clicking does, shown in the button's tooltip.
    let hint: String?
    /// Extensions with the same `group:` share one button that opens them on the bar.
    let group: String?
    /// Returns the context to run with, or nil when the action does not apply.
    let prepare: (SelectionContext) -> SelectionContext?
    /// Runs the action; `ctx.modifiers` holds the keys held while clicking.
    let perform: (SelectionContext) -> Void

    init(id: String, rowID: String? = nil, title: String, icon: NSImage?, hint: String? = nil, group: String? = nil,
         prepare: @escaping (SelectionContext) -> SelectionContext?,
         perform: @escaping (SelectionContext) -> Void) {
        self.id = id
        self.rowID = rowID ?? id
        self.title = title
        self.icon = icon
        self.hint = hint
        self.group = group
        self.prepare = prepare
        self.perform = perform
    }
}

struct BarEntry {
    let action: PopAction
    let context: SelectionContext
}

// MARK: - Icons

enum Icons {
    static let size: CGFloat = 18

    static func symbol(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    /// An extension icon: an SF Symbol name ("speaker.wave.2"), an image file next to the
    /// extension ("icon.png"), or up to 3 characters of text or emoji ("AB", "W", "🔤").
    /// Returns nil when nothing fits, which makes the bar show the title.
    static func load(_ spec: String?, folder: URL) -> NSImage? {
        guard let spec = spec?.trimmingCharacters(in: .whitespaces), !spec.isEmpty else { return nil }
        if let image = symbol(spec) { return image }
        let ext = (spec as NSString).pathExtension.lowercased()
        if ["png", "svg", "pdf", "jpg", "jpeg", "tiff"].contains(ext) {
            return NSImage(contentsOf: folder.appendingPathComponent(spec)).map(normalized)
        }
        return textIcon(spec)
    }

    /// Scales an image to the bar's icon height and makes it a template so it follows
    /// the light/dark appearance.
    static func normalized(_ image: NSImage) -> NSImage {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return image }
        let scale = size / max(s.width, s.height)
        let target = NSSize(width: (s.width * scale).rounded(), height: (s.height * scale).rounded())
        let out = NSImage(size: target, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
        out.isTemplate = true
        return out
    }

    static func textIcon(_ text: String) -> NSImage? {
        guard text.count <= 3 else { return nil }
        let isEmoji = text.unicodeScalars.contains { $0.properties.isEmojiPresentation }
        let fontSize: CGFloat = isEmoji || text.count == 1 ? 15 : text.count == 2 ? 13 : 11
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: max(size, ceil(textSize.width)), height: size), flipped: false) { rect in
            let origin = NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2)
            (text as NSString).draw(at: origin, withAttributes: attributes)
            return true
        }
        // Emoji keep their colors; letters follow the appearance like SF Symbols.
        image.isTemplate = !isEmoji
        return image
    }
}

// MARK: - Built-in actions

enum Builtins {
    /// When each built-in shows up on the bar (shown in Settings ▸ Buttons).
    static let conditions = [
        "builtin.install": "Selected text that is a Popoli extension",
        "builtin.openlink": "When the selection is a link",
        "builtin.search": "Any text",
        "builtin.cut": "In editable text",
        "builtin.copy": "Any text, or files in Finder",
        "builtin.paste": "In editable text",
        "builtin.path": "Files selected in Finder",
        "builtin.terminal": "Files in one folder, selected in Finder",
        "builtin.openin": "Files selected in Finder · choose apps in General",
        "builtin.dictionary": "Up to 4 words",
        "builtin.translate": "Any text",
    ]

    static func all() -> [PopAction] {
        [install, openLink, search, cut, copy, paste, path, terminal, openIn, lookUp, translate]
    }

    private static func hasText(_ ctx: SelectionContext) -> Bool {
        !ctx.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The selection as a web link, if it is one link and nothing else.
    private static func link(in ctx: SelectionContext) -> URL? {
        let trimmed = ctx.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 2000, !trimmed.contains(where: \.isWhitespace) else { return nil }
        guard let url = ctx.webURLs.first else { return nil }
        let bare = trimmed.lowercased()
        if bare.hasPrefix("http://") || bare.hasPrefix("https://") { return URL(string: trimmed) ?? url }
        return bare.contains(".") ? url : nil
    }

    /// Shown when the selection is an extension's text (a gist, a README, a message):
    /// opens the review window to install it.
    static let install = PopAction(
        id: "builtin.install", title: "Install Extension", icon: Icons.symbol("square.and.arrow.down"),
        prepare: { ctx in ExtensionInstaller.looksLikeExtension(ctx.text) ? ctx : nil },
        perform: { ctx in ExtensionInstaller.reviewSelection(ctx.text, appName: ctx.appName) })

    static let openLink = PopAction(
        id: "builtin.openlink", title: "Open Link", icon: Icons.symbol("safari"),
        prepare: { ctx in link(in: ctx) == nil ? nil : ctx },
        perform: { ctx in if let url = link(in: ctx) { NSWorkspace.shared.open(url) } })

    static let search = PopAction(
        id: "builtin.search", title: "Search", icon: Icons.symbol("magnifyingglass"),
        hint: "⇧-click: search for the exact phrase",
        prepare: { ctx in hasText(ctx) && ctx.text.count <= 1000 && link(in: ctx) == nil ? ctx : nil },
        perform: { ctx in
            var query = ctx.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if ctx.modifiers.contains(.shift) { query = "\"\(query)\"" }
            let url = Settings.searchURL.replacingOccurrences(of: "***", with: URLEncoding.encode(query))
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        })

    static let cut = PopAction(
        id: "builtin.cut", title: "Cut", icon: nil,
        prepare: { ctx in hasText(ctx) && ctx.canCut ? ctx : nil },
        perform: { _ in Keyboard.command("x") })

    static let copy = PopAction(
        id: "builtin.copy", title: "Copy", icon: nil,
        hint: "⇧-click: add to what is already on the clipboard",
        prepare: { ctx in (hasText(ctx) || !ctx.files.isEmpty) ? ctx : nil },
        perform: { ctx in
            if ctx.modifiers.contains(.shift), ctx.files.isEmpty {
                let current = NSPasteboard.general.string(forType: .string) ?? ""
                Clipboard.copy(current.isEmpty ? ctx.text : current + "\n" + ctx.text)
                HUD.shared.show(symbol: "plus", text: "Added to clipboard", near: ctx.anchor)
                return
            }
            if ctx.canCopy || !ctx.files.isEmpty { Keyboard.command("c") } else { Clipboard.copy(ctx.text) }
            HUD.shared.show(symbol: "checkmark", text: "Copied", near: ctx.anchor)
        })

    static let paste = PopAction(
        id: "builtin.paste", title: "Paste", icon: nil,
        hint: "⌥-click: paste and match style",
        prepare: { ctx in ctx.canPaste && ctx.files.isEmpty && Clipboard.hasContent ? ctx : nil },
        perform: { ctx in
            if ctx.modifiers.contains(.option), let v = Keyboard.keyCode(for: "v") {
                Keyboard.press(KeyCombo(keyCode: v, flags: [.maskCommand, .maskShift, .maskAlternate]))
            } else {
                Keyboard.command("v")
            }
        })

    static let path = PopAction(
        id: "builtin.path", title: "Path", icon: nil,
        hint: "⌥-click: copy quoted for the shell",
        prepare: { ctx in ctx.files.isEmpty ? nil : ctx },
        perform: { ctx in
            if ctx.modifiers.contains(.option) {
                let quoted = ctx.files.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
                Clipboard.copy(quoted.joined(separator: " "))
            } else {
                Clipboard.copy(ctx.files.joined(separator: "\n"))
            }
            let shown = ctx.files.count == 1
                ? (ctx.files[0] as NSString).abbreviatingWithTildeInPath
                : "\(ctx.files.count) paths"
            HUD.shared.show(symbol: "checkmark", text: "Copied \(shown)", near: ctx.anchor)
        })

    static let terminal = PopAction(
        id: "builtin.terminal", title: "Open in Terminal", icon: Icons.symbol("terminal"),
        prepare: { ctx in TerminalLauncher.target(for: ctx.files) == nil ? nil : ctx },
        perform: { ctx in TerminalLauncher.target(for: ctx.files).map(TerminalLauncher.open(path:)) })

    /// The Settings ▸ Buttons row for Open in ›; the bar gets one button per chosen app or
    /// command from `OpenIn.actions` in its place.
    static let openIn = PopAction(
        id: OpenIn.rowID, title: "Open in", icon: Icons.symbol("arrow.up.forward.app"),
        prepare: { _ in nil }, perform: { _ in })

    static let lookUp = PopAction(
        id: "builtin.dictionary", title: "Look Up", icon: Icons.symbol("character.book.closed"),
        hint: "⌥-click: open in the Dictionary app",
        prepare: { ctx in
            let word = ctx.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = word.split(whereSeparator: \.isWhitespace).count
            guard !word.isEmpty, word.count <= 60, words <= 4, word.contains(where: \.isLetter) else { return nil }
            return ctx
        },
        perform: { ctx in
            if ctx.modifiers.contains(.option) {
                let term = ctx.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: "dict://" + URLEncoding.encode(term)) { NSWorkspace.shared.open(url) }
            } else {
                Popoli.result.showDefinition(ctx)
            }
        })

    static let translate = PopAction(
        id: "builtin.translate", title: "Translate", icon: Icons.symbol("translate"),
        hint: "⌥-click: replace the selection with the translation",
        prepare: { ctx in hasText(ctx) && ctx.text.count <= 5000 && ctx.text.contains(where: \.isLetter) ? ctx : nil },
        perform: { ctx in Popoli.result.showTranslation(ctx, replace: ctx.modifiers.contains(.option)) })
}

// MARK: - Registry

/// Holds built-ins and loaded extensions, and decides what the bar shows.
final class ActionRegistry {
    let builtins = Builtins.all()
    private(set) var extensions: [ExtensionInfo] = []
    private var signature = ""

    func reload() {
        signature = ExtensionStore.signature()
        extensions = ExtensionStore.loadAll()
        SecretAccess.migrate(extensions.compactMap(\.ext))
        if extensions.contains(where: { $0.ext?.showsHTML == true }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { CardWebView.prepare() }
        }
    }

    /// Picks up added, removed or edited extension files without a restart.
    func reloadIfChanged() {
        if ExtensionStore.signature() != signature { reload() }
    }

    /// A row in Settings ▸ Buttons: a built-in or an extension (also ones that failed to load).
    struct Item {
        let id: String
        let title: String
        let icon: NSImage?
        let action: PopAction?
        let file: URL?
        let problem: String?
        /// Where it comes from and when it shows up, e.g. "Built-in · In editable text".
        let detail: String
        var ext: UserExtension? = nil
    }

    /// Every button, in the order chosen in Settings (new ones go to the end).
    func items() -> [Item] {
        reloadIfChanged()
        let all = builtins.map { action in
            Item(id: action.id, title: action.title, icon: action.icon, action: action, file: nil, problem: nil,
                 detail: "Built-in · " + (Builtins.conditions[action.id] ?? "Any text"))
        } + extensions.map { info in
            Item(id: info.id, title: info.name, icon: info.ext?.icon, action: info.action, file: info.file,
                 problem: info.problem,
                 detail: info.file.lastPathComponent + (info.ext.map { " · " + $0.condition } ?? ""),
                 ext: info.ext)
        }
        let order = Settings.buttonOrder
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return all.enumerated()
            .sorted { (rank[$0.element.id] ?? order.count + $0.offset) < (rank[$1.element.id] ?? order.count + $1.offset) }
            .map(\.element)
    }

    func entries(for ctx: SelectionContext) -> [BarEntry] {
        items().flatMap { item -> [BarEntry] in
            guard let action = item.action, Settings.isEnabled(item.id) else { return [] }
            let actions = item.id == OpenIn.rowID ? OpenIn.actions : [action]
            return actions.compactMap { action in action.prepare(ctx).map { BarEntry(action: action, context: $0) } }
        }
    }
}
