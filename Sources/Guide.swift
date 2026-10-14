import AppKit
import SwiftUI

/// The extension cheat sheet. One source for the Guide tab in Settings and for the
/// README.md written into the extensions folder.
enum ExtensionGuide {
    struct Key {
        let name: String
        let values: String
        let meaning: String
    }

    struct Variable {
        let name: String
        let meaning: String
    }

    struct Example {
        let title: String
        let file: String
        let code: String
    }

    static let keys = [
        Key(name: "name", values: "any text (required)", meaning: "The button’s title and tooltip."),
        Key(name: "icon", values: "speaker.wave.2 · AB · 🔤 · icon.png",
            meaning: "An SF Symbol name, up to 3 letters, an emoji, or an image next to the file. Without it, the bar shows the name."),
        Key(name: "after", values: "show · paste · copy · none",
            meaning: "What happens with what the script prints: shown in a card (default), replaces the selection, copied, or ignored."),
        Key(name: "match", values: "a regular expression, e.g. ^https?://",
            meaning: "Only show the button when the selection matches."),
        Key(name: "apps", values: "com.apple.Safari, com.apple.Notes",
            meaning: "Only show the button in these apps (bundle IDs, comma-separated)."),
        Key(name: "for", values: "text · files",
            meaning: "files: work on files selected in Finder instead of text."),
        Key(name: "url", values: "https://…{text}…",
            meaning: "No code: open this link. {text} becomes the selection, {url} the browser's page."),
        Key(name: "keys", values: "cmd shift H",
            meaning: "No code: press this shortcut in the app where the text is selected."),
        Key(name: "shortcut", values: "Clean Up Text",
            meaning: "No code: run this shortcut from the Shortcuts app with the selection. What it returns is the result, as with a script."),
        Key(name: "service", values: "Make Sticky",
            meaning: "No code: run this service from the Services menu with the selection. Text it returns is the result."),
        Key(name: "input", values: "text · html · markdown",
            meaning: "What the script gets: plain text (default), or the selection with its formatting as HTML or Markdown."),
        Key(name: "output", values: "text · html · markdown",
            meaning: "With html or markdown, the card shows what the script prints formatted (images as data: URLs), and paste and copy keep the formatting."),
        Key(name: "group", values: "Encode",
            meaning: "Extensions with the same group share one button on the bar (Encode ›) that opens them."),
        Key(name: "setting", values: "MODEL = claude-opus-5-5",
            meaning: "A value the user can change under Settings ▸ Buttons ▸ Settings…; the script gets it as $MODEL. Repeat the line for more."),
        Key(name: "secret", values: "ANTHROPIC_API_KEY",
            meaning: "An API key kept in the macOS keychain, never in the file; the script gets it as $ANTHROPIC_API_KEY."),
        Key(name: "description", values: "one line of text",
            meaning: "What the extension does, for the catalog. Put it last: older versions of Popoli stop reading the header at it."),
    ]

    static let variables = [
        Variable(name: "$POPOLI_TEXT", meaning: "The selected text. It is also on stdin."),
        Variable(name: "\"$@\" · $POPOLI_FILES", meaning: "With for: files — the selected files (one per line in $POPOLI_FILES)."),
        Variable(name: "$POPOLI_APP", meaning: "Bundle ID of the app with the selection, e.g. com.apple.Safari."),
        Variable(name: "$POPOLI_APP_NAME", meaning: "Its name, e.g. Safari."),
        Variable(name: "$POPOLI_MARKDOWN · $POPOLI_HTML", meaning: "With input: markdown or html — the formatted selection."),
        Variable(name: "$POPOLI_SHIFT · $POPOLI_OPTION", meaning: "1 when ⇧ or ⌥ was held while clicking the button (also $POPOLI_MODIFIERS)."),
        Variable(name: "$NAME", meaning: "Each setting: and secret: value, under its own name."),
        Variable(name: "$POPOLI_BROWSER_URL · _TITLE", meaning: "The page open in the browser in front (only for scripts that use them)."),
        Variable(name: "stdout", meaning: "What the script prints is the result (see after:)."),
        Variable(name: "stderr + exit code", meaning: "A non-zero exit shows the first line of stderr as an error."),
    ]

    static let examples = [
        Example(title: "Shell: replace the selection", file: "uppercase.sh", code: #"""
            #!/bin/zsh
            # name: Uppercase
            # icon: AB
            # after: paste

            print -rn -- ${(U)POPOLI_TEXT}
            """#),
        Example(title: "Python: show a result", file: "count-lines.py", code: #"""
            #!/usr/bin/env python3
            # name: Count Lines
            # icon: list.number

            import sys
            text = sys.stdin.read()
            print(f"{len(text.splitlines())} lines")
            """#),
        Example(title: "Only for some selections", file: "pretty-json.js", code: #"""
            #!/usr/bin/env node
            // name: Pretty JSON
            // icon: curlybraces
            // match: ^\s*[\[{]
            // after: paste

            let input = "";
            process.stdin.on("data", d => input += d);
            process.stdin.on("end", () => process.stdout.write(JSON.stringify(JSON.parse(input), null, 2)));
            """#),
        Example(title: "Link (no code)", file: "maps.popoli", code: #"""
            # name: Maps
            # icon: map
            # url: https://maps.apple.com/?q={text}
            """#),
        Example(title: "Keyboard shortcut, only in one app (no code)", file: "bold-in-notes.popoli", code: #"""
            # name: Bold
            # icon: bold
            # keys: cmd B
            # apps: com.apple.Notes
            """#),
        Example(title: "Run a shortcut from the Shortcuts app (no code)", file: "clean-up-text.popoli", code: #"""
            # name: Clean Up
            # icon: sparkles
            # shortcut: Clean Up Text
            # after: paste
            """#),
        Example(title: "Run a service from the Services menu (no code)", file: "new-sticky.popoli", code: #"""
            # name: Sticky
            # icon: note.text
            # service: Make Sticky
            """#),
        Example(title: "Files selected in Finder", file: "open-in-vscode.sh", code: #"""
            #!/bin/zsh
            # name: Open in VS Code
            # icon: chevron.left.forwardslash.chevron.right
            # for: files
            # after: none

            open -a "Visual Studio Code" "$@"
            """#),
        Example(title: "Ask Claude (with an API key)", file: "improve-writing.sh",
                code: (try? String(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("Extensions/improve-writing.sh"),
                                   encoding: .utf8))?.trimmingCharacters(in: .newlines) ?? ""),
        Example(title: "Copy formatted text as Markdown", file: "copy-as-markdown.sh", code: #"""
            #!/bin/zsh
            # name: Copy as Markdown
            # icon: MD
            # input: markdown
            # after: copy

            cat
            """#),
        Example(title: "Turn Markdown into formatted text", file: "markdown-to-rich-text.sh", code: #"""
            #!/bin/zsh
            # name: Rich Text
            # icon: textformat
            # output: markdown
            # after: paste
            # match: (?m)^(#{1,6} |[-*+] |\d+\. |> |```)|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)

            cat
            """#),
        Example(title: "AppleScript", file: "new-note.applescript", code: #"""
            -- name: New Note
            -- icon: note.text
            -- after: none

            on run argv
                tell application "Notes" to make new note with properties {body:item 1 of argv}
            end run
            """#),
    ]

    static let docsURL = URL(string: "https://github.com/kogungor/popoli/blob/main/docs/extensions.md")!
    static let catalogURL = URL(string: "https://github.com/kogungor/popoli/tree/main/catalog")!

    static let tips = [
        "Save the file and the button appears; there is no need to restart Popoli.",
        "Header lines are comments: # for most languages, // for JavaScript, -- for AppleScript. The header ends at the first other line.",
        "The first line (#!…) picks the language. Scripts do not need to be executable.",
        "Browse icon names in the SF Symbols app.",
        "API keys: add `# secret: NAME`, then enter the key once under Settings ▸ Buttons ▸ Settings…. It stays in the keychain and is shared by every extension that uses the same name.",
        "Hold ⇧ or ⌥ when clicking a button: built-in buttons do something else (see their tooltips), and scripts can check $POPOLI_SHIFT and $POPOLI_OPTION.",
        "Find an app’s bundle ID:  osascript -e 'id of app \"Safari\"'",
        "Test a script in Terminal:  POPOLI_TEXT=\"hello\" zsh ~/.config/popoli/extensions/uppercase.sh",
        "Turn extensions on or off and reorder them in Settings ▸ Buttons. A broken one shows the reason there in red.",
        "Share an extension by sending its text or a link to the file. Whoever selects the text gets an Install Extension button, and a popoli://install?url=https://… link opens the same review window, with the code shown before anything is installed.",
    ]

    /// The same guide as Markdown, for README.md in the extensions folder.
    static var markdown: String {
        var md = """
        # Writing Popoli extensions

        An extension is one file in this folder. It starts with a few `# key: value` comment
        lines; code in any language can follow. Save the file and the button appears.

        ## Header

        | Key | Values | Meaning |
        |---|---|---|

        """
        for key in keys { md += "| `\(key.name):` | `\(key.values)` | \(key.meaning) |\n" }
        md += "\n## Inside a script\n\n| | |\n|---|---|\n"
        for variable in variables { md += "| `\(variable.name)` | \(variable.meaning) |\n" }
        md += "\n## Examples\n"
        for example in examples {
            // A longer fence when the example itself contains ``` (a regex, for instance).
            let fence = example.code.contains("```") ? "````" : "```"
            md += "\n### \(example.title) — `\(example.file)`\n\n\(fence)\n\(example.code)\n\(fence)\n"
        }
        md += "\n## Tips\n\n"
        for tip in tips { md += "- \(tip)\n" }
        md += "\nFull documentation: \(docsURL.absoluteString)\n"
        md += "Ready-made extensions: \(catalogURL.absoluteString)\n"
        return md
    }
}

// MARK: - Guide tab

struct GuideTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        ScrollView { GuideContent(model: model) }
    }
}

struct GuideContent: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Writing Extensions").font(.title2.weight(.semibold))
                    Text("An extension is one file in ~/.config/popoli/extensions. It starts with a few `# key: value` comment lines; code in any language can follow. Save the file and the button appears.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("New Extension…", action: model.newExtension)
                        Button("Open Extensions Folder") {
                            try? FileManager.default.createDirectory(at: ExtensionStore.folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(ExtensionStore.folder)
                        }
                        Link("Full Documentation", destination: ExtensionGuide.docsURL)
                        Button("Extension Catalog") { model.tab = .catalog }
                    }
                }

                section("Header") {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        ForEach(ExtensionGuide.keys, id: \.name) { key in
                            GridRow(alignment: .firstTextBaseline) {
                                Text(key.name + ":").font(.system(.body, design: .monospaced).weight(.semibold))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(key.meaning).fixedSize(horizontal: false, vertical: true)
                                    Text(key.values).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                section("Inside a script") {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                        ForEach(ExtensionGuide.variables, id: \.name) { variable in
                            GridRow(alignment: .firstTextBaseline) {
                                Text(variable.name).font(.system(.callout, design: .monospaced).weight(.semibold))
                                Text(variable.meaning).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                section("Examples") {
                    ForEach(ExtensionGuide.examples, id: \.file) { example in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(example.title).font(.headline)
                                Spacer()
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(example.code + "\n", forType: .string)
                                }
                                Button("Use This") { model.useExample(example) }
                                    .help("Creates \(example.file) in the extensions folder and opens it")
                            }
                            .controlSize(.small)
                            Text(example.code)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                        }
                        .padding(.bottom, 6)
                    }
                }

                section("Tips") {
                    ForEach(ExtensionGuide.tips, id: \.self) { tip in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                            Text(tip).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            content()
        }
    }
}
