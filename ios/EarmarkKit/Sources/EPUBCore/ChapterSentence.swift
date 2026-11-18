import Foundation
import Models
import ReadAlongCore

/// One sentence of a chapter: its stable `SentenceText` (the aligner's input) plus where it sits in its paragraph.
///
/// `range` is a half-open range of **UTF-16 code units** into the paragraph text that `SentenceSplitter.sentences`
/// was given. UTF-16 is what `NSString` and JavaScript (the reader's `WKWebView`) index strings by, so the reader can
/// highlight exactly `paragraph[range]` without recomputing the split.
public struct ChapterSentence: Hashable, Sendable {
    public let sentence: SentenceText
    public let range: Range<Int>

    public init(sentence: SentenceText, range: Range<Int>) {
        precondition(range.lowerBound >= 0, "Sentence ranges are non-negative")
        precondition(range.lowerBound <= range.upperBound, "Sentence ranges are not inverted")
        self.sentence = sentence
        self.range = range
    }

    public var id: SentenceID { sentence.id }
    public var text: String { sentence.text }

    /// The slice of `paragraph` that `range` points at, or nil when the paragraph is shorter than the range.
    public func text(in paragraph: String) -> String? {
        let view = paragraph.utf16
        guard range.upperBound <= view.count else { return nil }
        let lower = view.index(view.startIndex, offsetBy: range.lowerBound)
        let upper = view.index(view.startIndex, offsetBy: range.upperBound)
        return String(decoding: view[lower..<upper], as: UTF16.self)
    }
}
