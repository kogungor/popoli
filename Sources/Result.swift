import AppKit
import Combine
import CoreServices
import NaturalLanguage
import SwiftUI
import Translation

// MARK: - Translation & dictionary

/// Languages Apple Translate supports, read from the system at launch.
final class Languages: ObservableObject {
    static let shared = Languages()

    @Published private(set) var codes = ["ar", "de", "en", "es", "fr", "hi", "id", "it", "ja", "ko", "nl",
                                         "pl", "pt", "ru", "th", "tr", "uk", "vi", "zh", "zh-Hant"]

    func load() {
        Task { @MainActor in
            let codes = Set(await LanguageAvailability().supportedLanguages.map(\.minimalIdentifier))
            guard !codes.isEmpty else { return }
            self.codes = codes.sorted { Translator.name($0) < Translator.name($1) }
        }
    }
}

enum Translator {
    static func name(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forIdentifier: code) ?? code
    }

    static func detect(_ text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return Locale.Language(identifier: language.rawValue)
    }

    static func sameLanguage(_ a: Locale.Language?, _ b: Locale.Language?) -> Bool {
        guard let a = a?.languageCode?.identifier, let b = b?.languageCode?.identifier else { return false }
        return a == b
    }

    /// The default target, or the secondary one when the text is already in it.
    static func targetCode(for source: Locale.Language?) -> String {
        let primary = Settings.translateTarget
        let sourceCode = source?.languageCode?.identifier
        let primaryCode = Locale.Language(identifier: primary).languageCode?.identifier
        return sourceCode != nil && sourceCode == primaryCode ? Settings.translateSecondary : primary
    }

    static func googleURL(_ text: String, target: String) -> URL? {
        URL(string: "https://translate.google.com/?sl=auto&tl=\(target)&op=translate&text=\(URLEncoding.encode(text))")
    }
}

enum Definitions {
    /// Looks the term up in the macOS dictionaries (the same data as the Dictionary app).
    static func define(_ term: String) -> String? {
        let length = (term as NSString).length
        guard length > 0,
              let definition = DCSCopyTextDefinition(nil, term as CFString, CFRange(location: 0, length: length))
        else { return nil }
        return (definition.takeRetainedValue() as String)
            .replacingOccurrences(of: " ▶", with: "\n▶")
            .replacingOccurrences(of: " PHRASES ", with: "\n\nPHRASES\n")
            .replacingOccurrences(of: " DERIVATIVES ", with: "\n\nDERIVATIVES\n")
            .replacingOccurrences(of: " ORIGIN ", with: "\n\nORIGIN\n")
    }
}

// MARK: - Model

final class ResultModel: ObservableObject {
    enum Mode { case translate, define, text }

    @Published var mode = Mode.text
    @Published var title = ""
    @Published var subtitle = ""
    @Published var symbol = "text.bubble"
    @Published var output = ""
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var canReplace = false
    @Published var openTitle: String?
    /// "auto" (detect) or a language code.
    @Published var sourceChoice = "auto"
    @Published var detectedCode: String?
    @Published var targetCode = "tr"
    @Published var translationConfig: TranslationSession.Configuration?

    var openURL: URL?
    var sourceText = ""
    /// Bumped for every new translation, so late results of an older one are dropped.
    var requestID = 0
    /// ⌥-click on Translate: put the translation in place of the selection when it is ready.
    var replaceWhenDone = false

    var onClose: () -> Void = {}
    var onCopy: () -> Void = {}
    var onReplace: () -> Void = {}
    var onOpen: () -> Void = {}
    var onChangeSource: (String) -> Void = { _ in }
    var onChangeTarget: (String) -> Void = { _ in }

    var sourceLabel: String {
        if sourceChoice != "auto" { return Translator.name(sourceChoice) }
        return detectedCode.map { "\(Translator.name($0)) (detected)" } ?? "Detect Language"
    }

    func reset() {
        mode = .text; title = ""; subtitle = ""; symbol = "text.bubble"; output = ""
        isLoading = false; errorText = nil; canReplace = false; openTitle = nil; openURL = nil; replaceWhenDone = false
        translationConfig = nil; sourceText = ""
    }

    func finish(_ text: String) {
        output = text
        errorText = nil
        isLoading = false
        if replaceWhenDone {
            replaceWhenDone = false
            DispatchQueue.main.async { self.onReplace() }
        }
    }

    func fail(_ message: String) {
        errorText = message
        isLoading = false
    }

    /// Used through `.translationTask` when language assets are not downloaded yet:
    /// that path lets macOS ask the user to download them.
    @MainActor func translate(using session: TranslationSession) async {
        let id = requestID
        do {
            let response = try await session.translate(sourceText)
            guard id == requestID else { return }
            finish(response.targetText)
        } catch {
            guard id == requestID else { return }
            fail("Translation isn’t available: \(error.localizedDescription)\n\nYou can download languages in System Settings → General → Language & Region → Translation Languages.")
        }
    }
}

// MARK: - View

struct ResultView: View {
    @ObservedObject var model: ResultModel
    @ObservedObject private var languages = Languages.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            footer
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .translationTask(model.translationConfig) { session in
            await model.translate(using: session)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            if model.mode == .translate { languageBar }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: model.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title).font(.headline).lineLimit(1)
                if !model.subtitle.isEmpty {
                    Text(model.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(action: model.onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close (Esc)")
        }
    }

    /// From ▾ → To ▾ for this translation; the defaults live in Settings ▸ Translate.
    private var languageBar: some View {
        HStack(spacing: 6) {
            Menu {
                Button { model.onChangeSource("auto") } label: { checkLabel("Detect Language", model.sourceChoice == "auto") }
                Divider()
                ForEach(languages.codes, id: \.self) { code in
                    Button { model.onChangeSource(code) } label: { checkLabel(Translator.name(code), model.sourceChoice == code) }
                }
            } label: {
                Text(model.sourceLabel).lineLimit(1)
            }
            .fixedSize()
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Menu {
                ForEach(languages.codes, id: \.self) { code in
                    Button { model.onChangeTarget(code) } label: { checkLabel(Translator.name(code), model.targetCode == code) }
                }
            } label: {
                Text(Translator.name(model.targetCode)).lineLimit(1)
            }
            .fixedSize()
            Spacer(minLength: 0)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.small)
    }

    @ViewBuilder private func checkLabel(_ title: String, _ checked: Bool) -> some View {
        if checked { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(model.mode == .translate ? "Translating…" : "Loading…").foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else if let error = model.errorText {
            Text(error)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.output.count > 700 {
            ScrollView { outputText }.frame(height: 280)
        } else {
            outputText
        }
    }

    private var outputText: some View {
        Text(model.output)
            .font(.system(size: 14))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if !model.isLoading && model.errorText == nil && !model.output.isEmpty {
                Button(action: model.onCopy) { Label("Copy", systemImage: "doc.on.doc") }
                if model.canReplace {
                    Button(action: model.onReplace) { Label("Replace", systemImage: "arrow.2.squarepath") }
                }
            }
            Spacer(minLength: 0)
            if let openTitle = model.openTitle {
                Button(action: model.onOpen) { Label(openTitle, systemImage: "arrow.up.right") }
            }
        }
        .buttonStyle(.glass)
    }
}

// MARK: - Controller

/// Glass card that shows translations, definitions and extension output.
final class ResultController {
    let model = ResultModel()
    private let panel = FloatingPanel(allowsKey: true)
    private let hosting: NSHostingView<ResultView>
    private let surface: GlassSurface
    private let margin: CGFloat = 18
    private var anchor = NSRect.zero
    private var growsUp = true
    private var context = SelectionContext()
    private var observer: AnyCancellable?
    /// Sessions for downloaded language pairs, reused so repeat translations start instantly.
    private var sessions: [String: TranslationSession] = [:]

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }
    var window: NSWindow { panel }

    init() {
        hosting = NSHostingView(rootView: ResultView(model: model))
        hosting.sizingOptions = [.intrinsicContentSize]
        surface = GlassSurface(content: hosting, cornerRadius: 24, margin: margin, interactive: false)
        panel.contentView = surface

        model.onClose = { [weak self] in self?.hide() }
        model.onCopy = { [weak self] in self?.copy() }
        model.onReplace = { [weak self] in self?.replace() }
        model.onOpen = { [weak self] in self?.open() }
        // Changing languages in the card applies to this translation only.
        model.onChangeSource = { [weak self] code in
            guard let self else { return }
            self.showTranslation(self.context, source: code, target: self.model.targetCode)
        }
        model.onChangeTarget = { [weak self] code in
            guard let self else { return }
            self.showTranslation(self.context, source: self.model.sourceChoice, target: code)
        }
        observer = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.relayout() }
        }
    }

    /// Translates the selection. `source` is "auto" or a language code; both default to
    /// the choices in Settings ▸ Translate.
    func showTranslation(_ ctx: SelectionContext, source: String? = nil, target: String? = nil, replace: Bool = false) {
        let text = ctx.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceChoice = source ?? Settings.translateSource
        let detected = Translator.detect(text)
        let sourceLanguage = sourceChoice == "auto" ? detected : Locale.Language(identifier: sourceChoice)
        let targetCode = target ?? Translator.targetCode(for: sourceLanguage)
        let targetLanguage = Locale.Language(identifier: targetCode)

        model.reset()
        model.requestID += 1
        model.replaceWhenDone = replace && ctx.canPaste
        let id = model.requestID
        model.mode = .translate
        model.title = "Translate"
        model.symbol = "translate"
        model.sourceText = text
        model.sourceChoice = sourceChoice
        model.detectedCode = detected?.minimalIdentifier
        model.targetCode = targetCode
        model.canReplace = ctx.canPaste
        model.openTitle = "Google"
        model.openURL = Translator.googleURL(text, target: targetCode)
        present(ctx)

        if Translator.sameLanguage(sourceLanguage, targetLanguage) {
            model.fail("The text is already in \(Translator.name(targetCode)). Pick another language above.")
            return
        }
        model.isLoading = true

        Task { @MainActor in
            let availability = LanguageAvailability()
            let status: LanguageAvailability.Status
            if let sourceLanguage {
                status = await availability.status(from: sourceLanguage, to: targetLanguage)
            } else {
                status = (try? await availability.status(for: text, to: targetLanguage)) ?? .unsupported
            }
            guard id == self.model.requestID else { return }
            switch status {
            case .installed where sourceLanguage != nil:
                do {
                    let key = "\(sourceLanguage!.minimalIdentifier)>\(targetCode)"
                    let session = self.sessions[key]
                        ?? TranslationSession(installedSource: sourceLanguage!, target: targetLanguage)
                    self.sessions[key] = session
                    let response = try await session.translate(text)
                    guard id == self.model.requestID else { return }
                    self.model.finish(response.targetText)
                } catch {
                    self.model.translationConfig = .init(source: sourceLanguage, target: targetLanguage)
                }
            case .unsupported:
                self.model.fail("Apple Translate doesn’t support this language pair. Try Google instead.")
            default:
                // Not downloaded yet (or source unknown): let the system handle it.
                self.model.translationConfig = .init(source: sourceLanguage, target: targetLanguage)
            }
        }
    }

    func showDefinition(_ ctx: SelectionContext) {
        let term = ctx.text.trimmingCharacters(in: .whitespacesAndNewlines)
        model.reset()
        model.mode = .define
        model.title = term
        model.subtitle = "Dictionary"
        model.symbol = "character.book.closed"
        if let definition = Definitions.define(term) {
            model.output = definition
        } else {
            model.errorText = "No definition found for “\(term)”."
        }
        model.openTitle = "Dictionary"
        model.openURL = URL(string: "dict://\(URLEncoding.encode(term))")
        present(ctx)
    }

    func showText(title: String, text: String, _ ctx: SelectionContext) {
        model.reset()
        model.title = title
        model.output = text
        model.canReplace = ctx.canPaste
        present(ctx)
    }

    func hide() {
        guard panel.isVisible else { return }
        let wasKey = panel.isKeyWindow
        panel.orderOut(nil)
        model.translationConfig = nil
        if wasKey { context.app?.activate() }
        Popoli.monitor.updateTransient()
    }

    private func present(_ ctx: SelectionContext) {
        surface.applyStyle()
        if panel.isVisible {
            context = ctx
            relayout()
            return
        }
        context = ctx
        anchor = ctx.anchor
        let size = contentSize()
        let frame = Glass.frame(for: size, above: anchor, gap: 10)
        growsUp = frame.minY >= anchor.maxY
        place(frame)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        Popoli.monitor.updateTransient()
    }

    private func contentSize() -> NSSize {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        return NSSize(width: ceil(max(size.width, 380)), height: ceil(max(size.height, 60)))
    }

    /// Keeps the edge next to the selection fixed while the content changes height.
    private func relayout() {
        guard panel.isVisible else { return }
        let size = contentSize()
        let current = panel.frame.insetBy(dx: margin, dy: margin)
        let y = growsUp ? current.minY : current.maxY - size.height
        let frame = NSRect(x: current.minX, y: y, width: size.width, height: size.height)
        place(frame)
    }

    private func place(_ frame: NSRect) {
        panel.setFrame(frame.insetBy(dx: -margin, dy: -margin), display: true)
    }

    private func copy() {
        Clipboard.copy(model.output)
        hide()
        HUD.shared.show(symbol: "checkmark", text: "Copied", near: anchor)
    }

    private func replace() {
        let text = model.output
        let app = context.app
        hide()
        app?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Clipboard.paste(text) }
    }

    private func open() {
        if let url = model.openURL { NSWorkspace.shared.open(url) }
        hide()
    }
}
