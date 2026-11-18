import Foundation

/// Turns one XHTML spine item (one EPUB chapter file) into the plain-text paragraphs that sentences are split from.
///
/// Block elements (`p`, `h1`–`h6`, `li`, `blockquote`, a `div` with direct text, …) each form one paragraph; inline
/// elements (`span`, `em`, `i`, `b`, `a`, …) are transparent. `<br/>` becomes a space, `<script>`, `<style>`,
/// `<head>` and ruby annotations are skipped, footnote-reference markers are dropped (a mislabelled reference that
/// wraps real words keeps them), HTML named entities (`&nbsp;`, `&mdash;`, `&rsquo;`, …) are decoded, and whitespace
/// is collapsed to single spaces and trimmed. Soft hyphens, zero-width spaces and byte-order marks are dropped; every
/// other character is kept exactly as in the source.
///
/// A block with no text (an empty `<p/>`, an image-only layout `<div>`) produces **no paragraph**. Paragraph indexes
/// are therefore indexes of text paragraphs, so inserting or removing a decorative, textless block in a new edition
/// never shifts a `SentenceID`.
public struct XHTMLText: Sendable {
    public init() {}

    /// The chapter's paragraphs, in document order.
    ///
    /// - Throws: `EPUBCoreError.malformedXHTML` when the data is not well-formed XML (an unclosed element, an unknown
    ///   entity, …) or is not a text encoding `XMLParser` understands.
    public func paragraphs(in data: Data) throws -> [String] {
        let parser = XMLParser(data: HTMLEntities.dataByReplacingNamedEntities(in: data))
        let delegate = XHTMLTextParser()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            let reason = delegate.failure
                ?? "line \(parser.lineNumber), column \(parser.columnNumber): "
                    + (parser.parserError?.localizedDescription ?? "the XML parser rejected the document")
            throw EPUBCoreError.malformedXHTML(reason)
        }
        delegate.finish()
        return delegate.paragraphs
    }

    /// Convenience for XHTML that is already a string; the bytes are passed through as UTF-8.
    public func paragraphs(in xhtml: String) throws -> [String] {
        try paragraphs(in: Data(xhtml.utf8))
    }
}
