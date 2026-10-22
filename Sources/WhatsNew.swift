import AppKit
import AVFoundation
import SwiftUI

/// After an update, a small window with what's new: a few highlights per version, each with a
/// button to try it. Shown once, on the first launch of the new version, with every version
/// skipped since the last one; **What's New…** in the menu shows it again. The highlights are
/// part of the app, so nothing is fetched. Buttons a highlight introduces get a "New" dot on
/// the bar for their first few appearances.
///
/// Releasing: add 2–4 highlights for the version here, next to its CHANGELOG section. A highlight
/// can bring a short clip (a 16:10 MP4 in Assets/whats-new, which build.sh copies into the app),
/// shown above the highlights.
enum WhatsNew {
    struct Highlight: Identifiable {
        enum Action {
            case settings(SettingsModel.Tab)
            case link(URL)
            case collections
        }

        let version: String
        let symbol: String
        let title: String
        let text: String
        var button: (title: String, action: Action)? = nil
        /// Settings ▸ Buttons rows this brings, which get the dot.
        var newButtons: [String] = []
        /// Who to thank for it, e.g. "Thanks to … for the idea."
        var credit: String? = nil
        /// A clip in Assets/whats-new, e.g. "collect.mp4".
        var video: String? = nil

        var id: String { version + title }
    }

    static let highlights: [Highlight] = [
        Highlight(version: "0.10.0", symbol: "tray.and.arrow.down", title: "Collect as you read",
                  text: "Collect on the bar gathers snippets from chats, pages and documents, each source in a collection of its own. Then paste or copy them all at once, with links back to where they came from.",
                  button: ("Show Collections", .collections), newButtons: ["builtin.collect"],
                  credit: "Thanks to Ömür Şahiner for the idea.", video: "collect.mp4"),
        Highlight(version: "0.10.0", symbol: "highlighter", title: "Back to the exact passage",
                  text: "In the Collections window, ↗ opens the page a snippet came from, scrolled to it and highlighted."),
        Highlight(version: "0.9.7", symbol: "arrow.up.forward.app", title: "Open in your editor or AI tool",
                  text: "Right-click a folder in Finder, or click it: Open in › opens it in VS Code, Cursor, Zed or Xcode, or starts Claude Code or Codex there.",
                  button: ("Choose Apps…", .settings(.general)), newButtons: [OpenIn.rowID]),
        Highlight(version: "0.9.7", symbol: "hand.point.up.left", title: "An all-icon bar",
                  text: "Every button is an icon now. Point at one and its name slides in above the bar."),
        Highlight(version: "0.9.6", symbol: "textformat", title: "Case, Lines and Ask in the catalog",
                  text: "camelCase, snake_case, Sort Lines, Remove Duplicates, and ChatGPT, Claude, Perplexity or Gemini with your own account.",
                  button: ("Open Catalog", .settings(.catalog))),
        Highlight(version: "0.9.6", symbol: "square.2.layers.3d", title: "Shortcuts and Services as buttons",
                  text: "An extension with shortcut: or service: runs a shortcut from the Shortcuts app or an item of the Services menu, without code.",
                  button: ("Open Guide", .settings(.guide))),
        Highlight(version: "0.9.5", symbol: "puzzlepiece.extension", title: "The extension catalog",
                  text: "Settings ▸ Catalog lists ready-made extensions to install with a click.",
                  button: ("Open Catalog", .settings(.catalog))),
        Highlight(version: "0.9.5", symbol: "arrow.down.circle", title: "Updates you notice",
                  text: "A dot on the menu bar icon says when a new version is ready."),
    ]

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static let seenKey = "whatsNewVersion"
    private static let newKey = "newButtons"
    /// How many times a new button shows its dot.
    private static let dotShows = 5

    /// Whether Popoli had run on this Mac before this launch: its extensions folder exists.
    /// Set before the first launch creates it, so a new install gets no "What's new".
    static var wasInstalled = true

    // MARK: After an update

    /// On the first launch of a version: the highlights since the last version seen. A version
    /// from before this window existed is not known, so it gets the current version's.
    static func showIfUpdated() {
        let defaults = UserDefaults.standard
        let last = defaults.string(forKey: seenKey)
        defaults.set(version, forKey: seenKey)
        guard wasInstalled, last.map({ isOlder($0, than: version) }) ?? true else { return }
        let since = last ?? previous(before: version)
        let shown = highlights.filter { isOlder(since, than: $0.version) && !isOlder(version, than: $0.version) }
        guard !shown.isEmpty else { return }
        markNew(shown.flatMap(\.newButtons))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { show(shown) }
    }

    /// What's New… in the menu: this version's highlights, or the latest ones there are.
    static func showLatest() {
        let current = highlights.filter { $0.version == version }
        let latest = highlights.first.map { first in highlights.filter { $0.version == first.version } } ?? []
        show(current.isEmpty ? latest : current)
    }

    /// The version just before `version` among the highlights (or "0").
    private static func previous(before version: String) -> String {
        highlights.map(\.version).first { isOlder($0, than: version) } ?? "0"
    }

    static func isOlder(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedAscending
    }

    // MARK: The window

    private static var window: NSWindow?

    static func show(_ shown: [Highlight]) {
        guard !shown.isEmpty else { return }
        let view = WhatsNewView(highlights: shown, version: version) { window?.close() }
        let hosting = NSHostingController(rootView: view)
        let made = window ?? NSWindow(contentViewController: hosting)
        made.contentViewController = hosting
        made.title = "What’s New in Popoli"
        made.styleMask = [.titled, .closable, .fullSizeContentView]
        made.titlebarAppearsTransparent = true
        made.titleVisibility = .hidden
        made.isMovableByWindowBackground = true
        made.isReleasedWhenClosed = false
        made.setContentSize(hosting.view.fittingSize)
        made.center()
        window = made
        NSApp.activate()
        made.makeKeyAndOrderFront(nil)
        // macOS may keep the app in use in front; the card comes forward anyway, without
        // taking the keyboard from it.
        made.orderFrontRegardless()
    }

    static func perform(_ action: Highlight.Action) {
        switch action {
        case .settings(let tab): SettingsWindowController.shared.show(tab)
        case .link(let url): NSWorkspace.shared.open(url)
        case .collections: CollectionsWindow.show()
        }
    }

    // MARK: The "New" dot

    /// Buttons that show their dot, with how many more times.
    private static var fresh: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: newKey) as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: newKey) }
    }

    private static func markNew(_ rows: [String]) {
        var all = fresh
        for row in rows { all[row] = dotShows }
        fresh = all
    }

    static func isNew(_ row: String) -> Bool { (fresh[row] ?? 0) > 0 }

    /// The bar appeared with these buttons: one show fewer for each new one.
    static func shown(_ rows: Set<String>) {
        var all = fresh
        var changed = false
        for row in rows where (all[row] ?? 0) > 0 {
            all[row]! -= 1
            changed = true
        }
        if changed { fresh = all.filter { $0.value > 0 } }
    }

    /// Clicked: it isn't new any more.
    static func used(_ row: String) {
        guard isNew(row) else { return }
        fresh = fresh.filter { $0.key != row }
    }
}

private struct WhatsNewView: View {
    let highlights: [WhatsNew.Highlight]
    let version: String
    let close: () -> Void

    /// The first clip among the highlights shown, if it is in the app.
    private var video: URL? {
        highlights.lazy.compactMap(\.video)
            .compactMap { Bundle.main.url(forResource: $0, withExtension: nil, subdirectory: "WhatsNew") }.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What’s New in Popoli").font(.title2.weight(.semibold))
                    Text("Version \(version)").foregroundStyle(.secondary)
                }
            }
            if let video {
                LoopingVideo(url: video)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator))
                    .help("Click to pause or play")
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(highlights) { highlight in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: highlight.symbol)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.accentColor.opacity(0.13)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(highlight.title).font(.headline)
                            Text(highlight.text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if let credit = highlight.credit {
                                Label(credit, systemImage: "heart.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 1)
                            }
                            if let button = highlight.button {
                                Button(button.title) { WhatsNew.perform(button.action) }
                                    .buttonStyle(.link)
                                    .padding(.top, 2)
                            }
                        }
                    }
                }
            }
            HStack {
                Link("All Changes", destination: URL(string: "https://github.com/kogungor/popoli/blob/main/CHANGELOG.md")!)
                Spacer()
                Button("Continue", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 34)
        .padding(.bottom, 22)
        // Wider with a clip, so the text in it stays readable.
        .frame(width: video == nil ? 470 : 580)
    }
}

/// A clip that plays muted, in a loop, while its window is open: video decoding is done by the
/// hardware, so it costs little, and it stops when the window closes. With Reduce Motion on, it
/// shows the clip's last frame instead. A click pauses or plays it.
private struct LoopingVideo: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> LoopingVideoView { LoopingVideoView(url: url) }
    func updateNSView(_ view: LoopingVideoView, context: Context) {}
}

private final class LoopingVideoView: NSView {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var closing: NSObjectProtocol?

    init(url: URL) {
        super.init(frame: .zero)
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        layer = playerLayer
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let closing { NotificationCenter.default.removeObserver(closing) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let closing { NotificationCenter.default.removeObserver(closing) }
        closing = nil
        guard let window else { return player.pause() }
        closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                         queue: .main) { [weak self] _ in self?.player.pause() }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            showLastFrame()
        } else {
            player.play()
        }
    }

    private func showLastFrame() {
        guard let asset = player.currentItem?.asset else { return }
        Task { @MainActor in
            guard let duration = try? await asset.load(.duration) else { return }
            await player.seek(to: duration - CMTime(seconds: 0.5, preferredTimescale: 600))
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if player.rate == 0 { player.play() } else { player.pause() }
    }
}
