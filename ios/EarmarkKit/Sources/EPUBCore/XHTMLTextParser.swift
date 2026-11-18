import Foundation

/// Collects the text of one XHTML document into paragraphs while `XMLParser` walks it.
///
/// Block elements flush a paragraph when they start and when they end, so `p`, `h1`–`h6`, `li`, `blockquote`, `div`
/// and friends each become their own paragraph. Inline elements are transparent, except that non-text ones (`img`,
/// `svg`, `hr`, …) separate the words around them. `<br/>` contributes a space, `<script>`, `<style>`, `<head>` and
/// ruby annotations (`rt`, `rp`) are skipped entirely, and footnote references (`a`/`sup` with
/// `epub:type="noteref"` or `role="doc-noteref"`) are buffered: number/roman/symbol markers are dropped, while a
/// mislabelled reference that wraps real words keeps them. Every block with no text is dropped (it would only be an
/// empty paragraph).
final class XHTMLTextParser: NSObject, XMLParserDelegate {
    private(set) var paragraphs: [String] = []
    private(set) var failure: String?

    private var buffer = ""
    private var skipDepth = 0
    private var noterefDepth = 0
    private var noterefBuffer = ""

    /// Flushes text left outside any block (rare, but valid XHTML allows it in `<body>`).
    func finish() {
        flush()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(of: elementName)
        if noterefDepth > 0 {
            noterefDepth += 1
            return
        }
        if skipDepth > 0 {
            skipDepth += 1
            return
        }
        guard let name else { return }
        if Self.skippedElements.contains(name) {
            skipDepth = 1
            return
        }
        if Self.isNoteref(element: name, attributes: attributeDict) {
            noterefDepth = 1
            noterefBuffer.removeAll(keepingCapacity: true)
            return
        }
        if name == "br" {
            append(" ")
            return
        }
        if name == "hr" {
            flush()
            return
        }
        if Self.nonTextInlineElements.contains(name) {
            append(" ")
            return
        }
        if Self.blockElements.contains(name) {
            flush()
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if noterefDepth > 0 {
            noterefDepth -= 1
            if noterefDepth == 0 {
                flushNoteref()
            }
            return
        }
        if skipDepth > 0 {
            skipDepth -= 1
            return
        }
        guard let name = localName(of: elementName) else { return }
        if Self.blockElements.contains(name) {
            flush()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        append(string)
    }

    func parser(_ parser: XMLParser, foundIgnorableWhitespace whitespaceString: String) {
        append(whitespaceString)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let text = String(data: CDATABlock, encoding: .utf8) else { return }
        append(text)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if failure == nil {
            let message = (parseError as NSError).localizedDescription
            failure = "line \(parser.lineNumber), column \(parser.columnNumber): \(message)"
        }
    }

    // MARK: - Text

    private func append(_ text: String) {
        if noterefDepth > 0 {
            noterefBuffer.append(text)
            return
        }
        guard skipDepth == 0 else { return }
        buffer.append(text)
    }

    /// A footnote reference is kept or dropped by what it contains: a real word wrapped by a mislabelled `noteref`
    /// stays in the text, a number/roman numeral/symbol marker is dropped.
    private func flushNoteref() {
        let text = normalized(noterefBuffer)
        noterefBuffer.removeAll(keepingCapacity: true)
        guard !text.isEmpty, !Self.isMarker(text) else { return }
        buffer.append(text)
    }

    private func flush() {
        let text = normalized(buffer)
        if !text.isEmpty {
            paragraphs.append(text)
        }
        buffer.removeAll(keepingCapacity: true)
    }

    /// Collapses every run of whitespace (including the non-breaking space from `&nbsp;`) to one space and trims.
    /// Soft hyphens, zero-width spaces and byte-order marks are dropped (they are typographic hints, not text); ZWJ
    /// and ZWNJ are kept because they are meaningful in emoji and in Persian. Every other character is kept exactly
    /// as it arrived from the parser.
    private func normalized(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var pendingSpace = false
        for character in text {
            if Self.removedCharacters.contains(character) {
                continue
            }
            if character.isWhitespace {
                if !result.isEmpty {
                    pendingSpace = true
                }
            } else {
                if pendingSpace {
                    result.append(" ")
                    pendingSpace = false
                }
                result.append(character)
            }
        }
        return result
    }

    /// `<xhtml:p>`-style names lose their prefix; comparisons are case-insensitive.
    private func localName(of elementName: String) -> String? {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        let lowered = local.lowercased()
        return lowered.isEmpty ? nil : lowered
    }

    // MARK: - Elements

    /// `a`/`sup` markers that point at a footnote. Only the `epub:` namespace (`epub:type="noteref"`) or
    /// `role="doc-noteref"` counts; a plain `type="noteref"` is just another attribute.
    private static func isNoteref(element: String, attributes: [String: String]) -> Bool {
        guard element == "a" || element == "sup" else { return false }
        for (key, value) in attributes {
            let parts = key.split(separator: ":")
            let values = value.lowercased().split(whereSeparator: \.isWhitespace)
            if parts.count == 2,
               parts[0].lowercased() == "epub",
               parts[1].lowercased() == "type",
               values.contains("noteref") {
                return true
            }
            if parts.count == 1, parts[0].lowercased() == "role", values.contains("doc-noteref") {
                return true
            }
        }
        return false
    }

    /// A marker is short and made only of digits, whitespace, roman-numeral letters, brackets/parens/periods or the
    /// usual reference symbols.
    private static func isMarker(_ text: String) -> Bool {
        guard text.count <= 16 else { return false }
        for character in text {
            if character.isWhitespace || character.isNumber { continue }
            if markerCharacters.contains(character) { continue }
            return false
        }
        return true
    }

    private static let blockElements: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "div", "dt", "dd",
        "figcaption", "caption", "td", "th", "pre", "address", "section", "article", "aside",
        "header", "footer", "main", "nav",
    ]

    private static let skippedElements: Set<String> = ["script", "style", "head", "title", "rt", "rp"]

    /// Elements that have no text of their own but separate the words around them.
    private static let nonTextInlineElements: Set<String> = [
        "img", "svg", "object", "iframe", "video", "audio", "embed", "input", "wbr",
    ]

    private static let removedCharacters: Set<Character> = ["\u{00AD}", "\u{200B}", "\u{FEFF}"]

    private static let markerCharacters: Set<Character> = Set("ivxlcdmIVXLCDM*†‡§¶#[]().")
}
