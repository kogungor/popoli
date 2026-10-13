import AppKit

/// Converts the rich text an app puts on the clipboard (HTML) into Markdown.
enum HTMLToMarkdown {
    static func convert(_ html: String) -> String? {
        guard let data = html.data(using: .utf8),
              let doc = try? XMLDocument(data: data, options: [.documentTidyHTML]) else { return nil }
        let body = (try? doc.nodes(forXPath: "//body").first) ?? doc.rootElement()
        guard let body else { return nil }
        var out = blocks(body.children ?? [], listDepth: 0)
        out = out.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let blockTags: Set<String> = [
        "p", "div", "section", "article", "header", "footer", "main", "h1", "h2", "h3", "h4", "h5", "h6",
        "ul", "ol", "li", "pre", "blockquote", "hr", "table", "tr", "br",
    ]

    private static func blocks(_ nodes: [XMLNode], listDepth: Int) -> String {
        var out = ""
        var inline = ""
        func flush() {
            let text = inline.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { out += text + "\n\n" }
            inline = ""
        }
        for node in nodes {
            guard let element = node as? XMLElement, let name = element.name?.lowercased() else {
                inline += self.inline([node])
                continue
            }
            if !blockTags.contains(name) {
                inline += self.inline([node])
                continue
            }
            flush()
            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                let level = Int(String(name.dropFirst())) ?? 1
                out += String(repeating: "#", count: level) + " " + self.inline(element.children ?? []).trimmed + "\n\n"
            case "ul", "ol":
                out += list(element, ordered: name == "ol", depth: listDepth) + "\n"
            case "pre":
                let code = element.stringValue ?? ""
                out += "```\n" + code.trimmingCharacters(in: .newlines) + "\n```\n\n"
            case "blockquote":
                let inner = blocks(element.children ?? [], listDepth: listDepth).trimmed
                out += inner.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n") + "\n\n"
            case "hr":
                out += "---\n\n"
            case "br":
                out += "\n"
            case "table":
                out += table(element) + "\n"
            default:
                out += blocks(element.children ?? [], listDepth: listDepth)
            }
        }
        flush()
        return out
    }

    private static func list(_ element: XMLElement, ordered: Bool, depth: Int) -> String {
        var out = ""
        var index = 1
        let indent = String(repeating: "  ", count: depth)
        for child in element.children ?? [] {
            guard let li = child as? XMLElement, li.name?.lowercased() == "li" else { continue }
            var text = ""
            var nested = ""
            for node in li.children ?? [] {
                if let sub = node as? XMLElement, ["ul", "ol"].contains(sub.name?.lowercased() ?? "") {
                    nested += list(sub, ordered: sub.name?.lowercased() == "ol", depth: depth + 1)
                } else if let sub = node as? XMLElement, ["p", "div"].contains(sub.name?.lowercased() ?? "") {
                    text += inline(sub.children ?? []) + " "
                } else {
                    text += inline([node])
                }
            }
            out += indent + (ordered ? "\(index). " : "- ") + text.trimmed + "\n" + nested
            index += 1
        }
        return out
    }

    private static func table(_ element: XMLElement) -> String {
        let rows = ((try? element.nodes(forXPath: ".//tr")) ?? []).compactMap { $0 as? XMLElement }
        guard !rows.isEmpty else { return "" }
        let cells = rows.map { row in
            (row.children ?? []).compactMap { $0 as? XMLElement }
                .filter { ["td", "th"].contains($0.name?.lowercased() ?? "") }
                .map { inline($0.children ?? []).trimmed.replacingOccurrences(of: "|", with: "\\|") }
        }
        let width = cells.map(\.count).max() ?? 0
        guard width > 0 else { return "" }
        func line(_ row: [String]) -> String { "| " + (row + Array(repeating: "", count: width - row.count)).joined(separator: " | ") + " |" }
        var out = line(cells[0]) + "\n|" + String(repeating: " --- |", count: width) + "\n"
        for row in cells.dropFirst() { out += line(row) + "\n" }
        return out
    }

    private static func inline(_ nodes: [XMLNode]) -> String {
        var out = ""
        for node in nodes {
            guard let element = node as? XMLElement, let name = element.name?.lowercased() else {
                if node.kind == .text {
                    out += (node.stringValue ?? "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                }
                continue
            }
            let inner = inline(element.children ?? [])
            switch name {
            case "strong", "b":
                out += wrap(inner, "**")
            case "em", "i":
                out += wrap(inner, "*")
            case "del", "s", "strike":
                out += wrap(inner, "~~")
            case "code", "kbd", "samp":
                out += "`" + (element.stringValue ?? "") + "`"
            case "a":
                let href = element.attribute(forName: "href")?.stringValue ?? ""
                out += href.isEmpty || href.hasPrefix("#") ? inner : "[\(inner.trimmed)](\(href))"
            case "img":
                let src = element.attribute(forName: "src")?.stringValue ?? ""
                let alt = element.attribute(forName: "alt")?.stringValue ?? ""
                if !src.isEmpty, !src.hasPrefix("data:") { out += "![\(alt)](\(src))" }
            case "br":
                out += "  \n"
            case "script", "style", "head", "title", "meta":
                break
            default:
                // A <span style="font-weight:bold"> is how some apps (Google Docs, Notes) mark bold.
                let style = (element.attribute(forName: "style")?.stringValue ?? "").lowercased()
                if style.contains("font-weight:700") || style.contains("font-weight: 700") || style.contains("font-weight:bold") || style.contains("font-weight: bold") {
                    out += wrap(inner, "**")
                } else if style.contains("font-style:italic") || style.contains("font-style: italic") {
                    out += wrap(inner, "*")
                } else {
                    out += inner
                }
            }
        }
        return out
    }

    /// `**word**`, keeping surrounding spaces outside the markers.
    private static func wrap(_ text: String, _ marker: String) -> String {
        let core = text.trimmed
        guard !core.isEmpty else { return text }
        let lead = text.prefix { $0 == " " }
        let trail = String(text.reversed().prefix { $0 == " " })
        return lead + marker + core + marker + trail
    }
}

/// Converts common Markdown (headings, lists, quotes, code, emphasis, links) to HTML.
enum MarkdownToHTML {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static let heading = regex(#"^(#{1,6})\s+(.*)$"#)
    private static let rule = regex(#"^([-*_])(\s*\1){2,}\s*$"#)
    private static let listItem = regex(#"^(\s*)([-*+]|\d+[.)])\s+(.*)$"#)

    private static func match(_ re: NSRegularExpression, _ s: String) -> [String]? {
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
        }
    }

    static func convert(_ markdown: String) -> String {
        var html = ""
        var paragraph: [String] = []
        var listStack: [String] = []
        var inCode = false
        var code: [String] = []

        func closeParagraph() {
            if !paragraph.isEmpty { html += "<p>" + paragraph.map(inline).joined(separator: "<br>\n") + "</p>\n" }
            paragraph = []
        }
        func closeLists() {
            while let tag = listStack.popLast() { html += "</li></\(tag)>\n" }
        }

        for raw in markdown.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    html += "<pre><code>" + escape(code.joined(separator: "\n")) + "</code></pre>\n"
                    code = []
                    inCode = false
                } else {
                    closeParagraph(); closeLists()
                    inCode = true
                }
                continue
            }
            if inCode { code.append(raw); continue }
            if trimmed.isEmpty { closeParagraph(); closeLists(); continue }

            if let m = match(heading, trimmed) {
                closeParagraph(); closeLists()
                html += "<h\(m[1].count)>\(inline(m[2]))</h\(m[1].count)>\n"
            } else if match(rule, trimmed) != nil {
                closeParagraph(); closeLists()
                html += "<hr>\n"
            } else if trimmed.hasPrefix(">") {
                closeParagraph(); closeLists()
                html += "<blockquote>" + inline(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)) + "</blockquote>\n"
            } else if let m = match(listItem, line) {
                closeParagraph()
                let depth = m[1].count / 2 + 1
                let tag = m[2].first?.isNumber == true ? "ol" : "ul"
                if listStack.count < depth {
                    while listStack.count < depth { html += "<\(tag)><li>"; listStack.append(tag) }
                } else {
                    while listStack.count > depth { html += "</li></\(listStack.removeLast())>\n" }
                    if listStack.last == tag {
                        html += "</li><li>"
                    } else {
                        // A bulleted list followed directly by a numbered one (or the reverse).
                        html += "</li></\(listStack.removeLast())>\n<\(tag)><li>"
                        listStack.append(tag)
                    }
                }
                html += inline(m[3])
            } else {
                closeLists()
                paragraph.append(trimmed)
            }
        }
        if inCode { html += "<pre><code>" + escape(code.joined(separator: "\n")) + "</code></pre>\n" }
        closeParagraph(); closeLists()
        return html
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let codeSpan = regex(#"`([^`]+)`"#)
    private static let spans: [(NSRegularExpression, String)] = [
        (regex(#"!\[([^\]]*)\]\(([^)\s]+)\)"#), #"<img alt="$1" src="$2">"#),
        (regex(#"\[([^\]]+)\]\(([^)\s]+)\)"#), #"<a href="$2">$1</a>"#),
        (regex(#"&lt;(https?://[^\s&]+)&gt;"#), #"<a href="$1">$1</a>"#),
        (regex(#"\*\*(?=\S)(.+?)(?<=\S)\*\*"#), "<strong>$1</strong>"),
        (regex(#"(?<!\w)__(?=\S)(.+?)(?<=\S)__(?!\w)"#), "<strong>$1</strong>"),
        (regex(#"\*(?=\S)(.+?)(?<=\S)\*"#), "<em>$1</em>"),
        (regex(#"(?<!\w)_(?=\S)(.+?)(?<=\S)_(?!\w)"#), "<em>$1</em>"),
        (regex(#"~~(?=\S)(.+?)(?<=\S)~~"#), "<del>$1</del>"),
    ]

    /// Inline spans. Code spans are cut out first so their content is left alone.
    static func inline(_ text: String) -> String {
        var codes: [String] = []
        var s = ""
        var last = text.startIndex
        for m in codeSpan.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(m.range, in: text), let inner = Range(m.range(at: 1), in: text) else { continue }
            s += String(text[last..<whole.lowerBound]) + "\u{1}\(codes.count)\u{1}"
            codes.append("<code>" + escape(String(text[inner])) + "</code>")
            last = whole.upperBound
        }
        s += String(text[last...])
        s = escape(s)
        for (re, template) in spans {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        for (i, code) in codes.enumerated() { s = s.replacingOccurrences(of: "\u{1}\(i)\u{1}", with: code) }
        return s
    }
}

/// Puts formatted text on the clipboard as HTML, RTF and plain text, so it pastes with
/// formatting in rich editors and as plain text elsewhere. Main thread only.
enum RichClipboard {
    static func write(html: String, plain: String) {
        let document = "<meta charset=\"utf-8\">" + html
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(document, forType: .html)
        if let data = document.data(using: .utf8),
           let attributed = NSAttributedString(html: data, options: [.characterEncoding: String.Encoding.utf8.rawValue],
                                               documentAttributes: nil),
           let rtf = attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]) {
            item.setData(rtf, forType: .rtf)
        }
        item.setString(plain, forType: .string)
        pb.writeObjects([item])
    }

    static func paste(html: String, plain: String) {
        write(html: html, plain: plain)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Keyboard.command("v") }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
