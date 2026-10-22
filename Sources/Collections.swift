import AppKit

/// Collect: text selected here and there, gathered with the Collect button and used together
/// later (pasted or copied as one, or run through an extension). Snippets are kept apart by
/// where they come from: each page, conversation or document gets its own collection, so a
/// Claude chat and a web page read in between don't mix. A pinned collection takes everything
/// instead, wherever it comes from.
///
/// Collections stay on this Mac, in ~/Library/Application Support/Popoli/collections.json
/// (or only in memory, see Settings), and go away 7 days after the last snippet was added,
/// unless pinned.
struct Snippet: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var added = Date()
    /// The app it was collected in (bundle ID and name).
    var app: String
    var appName: String
    /// The page, conversation or window title.
    var title: String
    /// The page or document, when the app tells: a web address or a file.
    var url: String?

    /// A link to the page that scrolls to this text and highlights it (a text fragment).
    var link: URL? {
        guard let url else { return nil }
        return TextFragment.link(url, text: text) ?? URL(string: url)
    }
}

struct SnippetCollection: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// What it collects from: a page or document address, or an app and its window title.
    var source: String
    var snippets: [Snippet] = []
    var created = Date()
    var updated = Date()
    /// Collects everything, wherever it comes from.
    var pinned = false

    /// The snippets as one text, a blank line apart.
    var text: String { snippets.map(\.text).joined(separator: "\n\n") }

    /// The snippets as Markdown quotes, each followed by a link to where it came from.
    var markdown: String {
        snippets.map { snippet in
            let quote = snippet.text.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }
            let title = (snippet.title.isEmpty ? snippet.appName : snippet.title)
                .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            let source = snippet.link.flatMap { link -> String? in
                guard ["http", "https"].contains(link.scheme ?? "") else { return nil }
                let address = link.absoluteString.replacingOccurrences(of: "(", with: "%28")
                    .replacingOccurrences(of: ")", with: "%29")
                return "[\(title)](\(address))"
            } ?? title
            return (quote + [">", "> — " + source]).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    /// The apps it was collected in, most used first.
    var appNames: [String] {
        let counts = Dictionary(snippets.map { ($0.appName, 1) }, uniquingKeysWith: +)
        return counts.keys.sorted { counts[$0]! > counts[$1]! }
    }
}

final class Collections: ObservableObject {
    static let shared = Collections()

    /// Most recently added to first.
    @Published private(set) var all: [SnippetCollection] = []
    /// The collection the bar offers to paste or copy: the one last added to, until it is used.
    @Published private(set) var activeID: UUID?

    /// Unpinned collections go away this long after their last snippet.
    static let lifetime: TimeInterval = 7 * 24 * 3600
    /// POPOLI_COLLECTIONS_FILE: another file, for demos and tests.
    static var file: URL = {
        if let path = ProcessInfo.processInfo.environment["POPOLI_COLLECTIONS_FILE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Popoli/collections.json")
    }()

    var active: SnippetCollection? { all.first { $0.id == activeID } }

    private struct Saved: Codable {
        var collections: [SnippetCollection]
        var active: UUID?
    }

    // MARK: Saving

    func load() {
        guard Settings.keepCollections else { return save() }
        guard let data = try? Data(contentsOf: Self.file),
              let saved = try? JSONDecoder.iso.decode(Saved.self, from: data) else { return }
        all = saved.collections
        activeID = saved.active
        prune()
    }

    /// Writes the collections, readable only by this user; with Settings ▸ "Keep collections"
    /// off, removes the file instead (they live in memory until Popoli quits).
    func save() {
        guard Settings.keepCollections else {
            try? FileManager.default.removeItem(at: Self.file)
            return
        }
        guard let data = try? JSONEncoder.iso.encode(Saved(collections: all, active: activeID)) else { return }
        let folder = Self.file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: Self.file, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.file.path)
    }

    /// Removes collections not added to in `lifetime`, except pinned ones.
    func prune() {
        let limit = Date().addingTimeInterval(-Self.lifetime)
        let kept = all.filter { $0.pinned || $0.updated > limit }
        guard kept.count != all.count else { return }
        all = kept
        if active == nil { activeID = nil }
        save()
    }

    // MARK: Collecting

    /// Adds the selection to the collection of where it comes from (or the pinned one), or to a
    /// new one with `startNew`. Reading where it comes from asks the app over Accessibility, so
    /// it happens off the main thread.
    func collect(_ ctx: SelectionContext, startNew: Bool) {
        let text = ctx.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let app = ctx.app else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let source = SnippetSource.read(app)
            DispatchQueue.main.async {
                let snippet = Snippet(text: text, app: app.bundleIdentifier ?? "", appName: app.localizedName ?? "",
                                      title: source.title, url: source.url)
                let (collection, added) = self.add(snippet, source: source.key, startNew: startNew)
                let name = collection.name.count > 40 ? String(collection.name.prefix(39)) + "…" : collection.name
                if added {
                    HUD.shared.show(symbol: "tray.and.arrow.down",
                                    text: "Added to \(name) · \(collection.snippets.count)", near: ctx.anchor)
                } else {
                    HUD.shared.show(symbol: "checkmark", text: "Already in \(name)", near: ctx.anchor)
                }
            }
        }
    }

    /// Returns the collection it went into, and false when it was already there.
    @discardableResult
    func add(_ snippet: Snippet, source: String, startNew: Bool = false) -> (SnippetCollection, Bool) {
        prune()
        let index: Int
        if !startNew, let pinned = all.firstIndex(where: \.pinned) {
            index = pinned
        } else if !startNew, let same = all.firstIndex(where: { $0.source == source }) {
            index = same
        } else {
            let name = snippet.title.isEmpty ? snippet.appName : snippet.title
            all.insert(SnippetCollection(name: String(name.prefix(80)), source: source), at: 0)
            index = 0
        }
        // Selecting the same text twice and collecting it again adds nothing.
        if all[index].snippets.contains(where: { $0.text == snippet.text }) {
            activeID = all[index].id
            return (all[index], false)
        }
        var collection = all.remove(at: index)
        collection.snippets.append(snippet)
        collection.updated = Date()
        all.insert(collection, at: 0)
        activeID = collection.id
        save()
        return (collection, true)
    }

    // MARK: Changing

    func update(_ id: UUID, _ change: (inout SnippetCollection) -> Void) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        change(&all[index])
        save()
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.name = trimmed }
    }

    /// Pins one collection (only one at a time collects everything) or unpins it.
    func setPinned(_ id: UUID, _ on: Bool) {
        for index in all.indices { all[index].pinned = on && all[index].id == id }
        if on { activeID = id }
        save()
    }

    func delete(_ id: UUID) {
        all.removeAll { $0.id == id }
        if activeID == id { activeID = nil }
        save()
    }

    func delete(snippet: UUID, from id: UUID) {
        update(id) { $0.snippets.removeAll { $0.id == snippet } }
        if all.first(where: { $0.id == id })?.snippets.isEmpty == true { delete(id) }
    }

    func moveSnippets(in id: UUID, from offsets: IndexSet, to destination: Int) {
        update(id) { $0.snippets.move(fromOffsets: offsets, toOffset: destination) }
    }

    /// Moves a snippet to another collection, or to a new one when `target` is nil.
    func move(snippet: UUID, to target: UUID?) {
        guard let from = all.firstIndex(where: { $0.snippets.contains { $0.id == snippet } }),
              let moved = all[from].snippets.first(where: { $0.id == snippet }) else { return }
        let source = all[from].id
        if source == target { return }
        all[from].snippets.removeAll { $0.id == snippet }
        if let target, let index = all.firstIndex(where: { $0.id == target }) {
            all[index].snippets.append(moved)
            all[index].updated = Date()
        } else {
            let name = moved.title.isEmpty ? moved.appName : moved.title
            // A collection of its own, which nothing else collects into by itself.
            all.insert(SnippetCollection(name: String(name.prefix(80)), source: UUID().uuidString, snippets: [moved]), at: 0)
        }
        if all.first(where: { $0.id == source })?.snippets.isEmpty == true {
            all.removeAll { $0.id == source }
            if activeID == source { activeID = nil }
        }
        save()
    }

    /// Adds a collection's snippets to another one and removes it.
    func merge(_ id: UUID, into target: UUID) {
        guard id != target, let collection = all.first(where: { $0.id == id }),
              let index = all.firstIndex(where: { $0.id == target }) else { return }
        all[index].snippets += collection.snippets
        all[index].updated = max(all[index].updated, collection.updated)
        all.removeAll { $0.id == id }
        if activeID == id { activeID = target }
        save()
    }

    /// The collection was pasted or copied: the bar stops offering it.
    func used(_ id: UUID) {
        guard activeID == id else { return }
        activeID = nil
        save()
    }

    // MARK: On the bar

    static let rowID = "builtin.collected"
    static let group = "Collected"

    /// The Collected › button's label: which collection, and how much is in it.
    static var summary: String? {
        guard let collection = shared.active else { return nil }
        let count = collection.snippets.count
        return "“\(collection.name)”, \(count) snippet\(count == 1 ? "" : "s")"
    }

    /// The buttons for the active collection, under Collected › on the bar.
    static var actions: [PopAction] {
        guard let collection = shared.active, !collection.snippets.isEmpty else { return [] }
        let count = collection.snippets.count
        let about = "“\(collection.name)”, \(count) snippet\(count == 1 ? "" : "s") · ⌥-click: as Markdown with sources"
        let id = collection.id
        return [
            PopAction(id: rowID + ".paste", rowID: rowID, title: "Paste All", icon: Icons.symbol("doc.on.clipboard"),
                      hint: about, group: group,
                      prepare: { ctx in ctx.canPaste && ctx.files.isEmpty ? ctx : nil },
                      perform: { ctx in
                          guard let collection = shared.all.first(where: { $0.id == id }) else { return }
                          Clipboard.paste(ctx.modifiers.contains(.option) ? collection.markdown : collection.text)
                          shared.used(id)
                      }),
            PopAction(id: rowID + ".copy", rowID: rowID, title: "Copy All", icon: Icons.symbol("doc.on.doc"),
                      hint: about, group: group,
                      prepare: { ctx in ctx.files.isEmpty ? ctx : nil },
                      perform: { ctx in
                          guard let collection = shared.all.first(where: { $0.id == id }) else { return }
                          Clipboard.copy(ctx.modifiers.contains(.option) ? collection.markdown : collection.text)
                          HUD.shared.show(symbol: "checkmark", text: "Copied \(collection.snippets.count) snippets",
                                          near: ctx.anchor)
                          shared.used(id)
                      }),
            PopAction(id: rowID + ".show", rowID: rowID, title: "Show Collections", icon: Icons.symbol("tray.full"),
                      hint: "“\(collection.name)”", group: group,
                      prepare: { ctx in ctx.files.isEmpty ? ctx : nil },
                      perform: { _ in CollectionsWindow.show(id) }),
        ]
    }
}

// MARK: - Where a snippet comes from

/// Where a selection is: the page or document address when the app tells, and a title.
struct SnippetSource {
    /// Snippets with the same key go into the same collection.
    var key: String
    var title: String
    var url: String?

    /// Asks the app over Accessibility; call off the main thread.
    ///
    /// Browsers, and apps made of web pages (Claude, Slack, Notion…), have a web area around
    /// the focused element that knows its page's address and title, so each page and each
    /// conversation is a source of its own. Chromium browsers also give the page as the
    /// window's document, and document apps (TextEdit, Preview…) their file. Other apps are
    /// told apart by their window title.
    static func read(_ app: NSRunningApplication) -> SnippetSource {
        let appName = app.localizedName ?? ""
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        let window = AX.element(element, kAXFocusedWindowAttribute)
        let windowTitle = window.flatMap { AX.string($0, kAXTitleAttribute) }.map { trimmed($0, appName: appName) } ?? ""

        // The outermost web area: a frame inside a page has one of its own.
        var page: SnippetSource?
        var current = AX.element(element, kAXFocusedUIElementAttribute)
        for _ in 0..<80 {
            guard let node = current else { break }
            if AX.string(node, kAXRoleAttribute) == "AXWebArea", let url = (AX.value(node, "AXURL") as? URL).flatMap(usable) {
                let title = [AX.string(node, kAXTitleAttribute), AX.string(node, kAXDescriptionAttribute)]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
                page = SnippetSource(key: key(url), title: title ?? windowTitle, url: url.absoluteString)
            }
            current = AX.element(node, kAXParentAttribute)
        }
        if let page { return page }
        if let window, let document = AX.string(window, kAXDocumentAttribute), let url = URL(string: document).flatMap(usable) {
            return SnippetSource(key: key(url), title: windowTitle, url: url.absoluteString)
        }
        return SnippetSource(key: (app.bundleIdentifier ?? appName) + "|" + windowTitle, title: windowTitle, url: nil)
    }

    /// Web pages and documents; not the page an app is built from (file:///…/Claude.app/…).
    private static func usable(_ url: URL) -> URL? {
        switch url.scheme?.lowercased() {
        case "http", "https": return url
        case "file": return url.path.contains(".app/") ? nil : url
        default: return nil
        }
    }

    /// The page without the part that only scrolls it (#…).
    private static func key(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    /// "Page - Google Chrome - Work" → "Page", "Page - Brave" (Brave Browser) → "Page".
    private static func trimmed(_ title: String, appName: String) -> String {
        let names = [appName, appName.components(separatedBy: " ").first ?? appName]
        for name in names where !name.isEmpty {
            for separator in [" - ", " — ", " – "] {
                if let range = title.range(of: separator + name, options: .backwards) {
                    return String(title[..<range.lowerBound])
                }
            }
        }
        return title
    }
}

// MARK: - Text fragments

/// Links that open a page scrolled to a passage, highlighted by the browser (Chrome, Edge,
/// Safari and Firefox understand them): https://example.com/#:~:text=start,end
enum TextFragment {
    /// Words from the start and the end of the passage, each within one line, since a
    /// fragment's words can't span paragraphs.
    static func link(_ address: String, text: String) -> URL? {
        guard var components = URLComponents(string: address),
              ["http", "https"].contains(components.scheme?.lowercased() ?? "") else { return nil }
        let lines = text.components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .filter { !$0.isEmpty }
        guard let first = lines.first, let last = lines.last else { return nil }
        let directive: String
        if lines.count == 1 && first.count <= 10 {
            directive = encode(first.joined(separator: " "))
        } else {
            directive = encode(first.prefix(5).joined(separator: " ")) + "," + encode(last.suffix(5).joined(separator: " "))
        }
        components.fragment = nil
        guard let base = components.string else { return nil }
        return URL(string: base + "#:~:text=" + directive)
    }

    /// Letters, digits and ._~ stay; everything else (also - , & which mean something here)
    /// is percent-encoded.
    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._~")

    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

private extension JSONEncoder {
    static let iso: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - Self test

extension Collections {
    /// `Popoli --collections-selftest`: collects into a temporary file and prints what happened.
    static func selfTest() {
        Settings.registerDefaults()
        file = FileManager.default.temporaryDirectory.appendingPathComponent("popoli-collections-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = Collections()
        func snippet(_ text: String, _ title: String, _ url: String? = nil) -> Snippet {
            Snippet(text: text, app: "com.example.app", appName: "Example", title: title, url: url)
        }
        let chat = "https://claude.ai/chat/1"
        store.add(snippet("first idea", "Chat", chat), source: chat)
        store.add(snippet("a page quote", "Page", "https://example.com/a"), source: "https://example.com/a")
        store.add(snippet("second idea", "Chat", chat), source: chat)
        let (_, again) = store.add(snippet("second idea", "Chat", chat), source: chat)
        print("collections by source: \(store.all.map { "\($0.name)=\($0.snippets.count)" }.joined(separator: " "))")
        print("same text again added: \(again)")
        print("active: \(store.active?.name ?? "-")")
        store.add(snippet("third idea", "Chat", chat), source: chat, startNew: true)
        print("start new: \(store.all.count) collections, newest \(store.all[0].name)=\(store.all[0].snippets.count)")
        let page = store.all.first { $0.name == "Page" }!.id
        store.setPinned(page, true)
        store.add(snippet("from elsewhere", "Other"), source: "com.example.app|Other")
        print("pinned takes everything: Page=\(store.all.first { $0.id == page }!.snippets.count), \(store.all.count) collections")
        store.setPinned(page, false)
        let moved = store.all.first { $0.id == page }!.snippets.last!.id
        store.move(snippet: moved, to: nil)
        print("moved to a new collection: \(store.all.count) collections, newest \(store.all[0].name)=\(store.all[0].snippets.count)")
        let newest = store.all[0].id
        store.merge(newest, into: page)
        print("merged: \(store.all.count) collections, Page=\(store.all.first { $0.id == page }!.snippets.count)")
        print("markdown:\n" + store.all.first { $0.id == page }!.markdown)
        let reloaded = Collections()
        reloaded.load()
        print("saved and loaded: \(reloaded.all.count == store.all.count), file is private: \((try? FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int) == 0o600)")
        reloaded.update(page) { $0.updated = Date().addingTimeInterval(-8 * 24 * 3600) }
        reloaded.prune()
        print("a week later: \(reloaded.all.count) collections")
    }
}
