import Foundation
import Testing
import Models
import EPUBCore

/// Review-7 findings 4 (ID side), 7 and 9: invisible characters, straight quotes and UTF-16 ranges.
@Suite struct SentenceSplitterRegressionTests {
    private let splitter = SentenceSplitter()

    // MARK: - 4. A zero-width paragraph keeps later IDs

    @Test func aZeroWidthSpaceOnlyBlockDoesNotShiftIDs() throws {
        let xhtml = "<html><body><p>One.</p><p>\u{200B}</p><p>Two.</p></body></html>"
        let paragraphs = try XHTMLText().paragraphs(in: xhtml)
        #expect(paragraphs == ["One.", "Two."])
        #expect(splitter.sentences(in: paragraphs, spine: 0).map(\.id.description) == ["0.0.0", "0.1.0"])
    }

    @Test func anInvisibleOnlyParagraphDoesNotConsumeAnIndex() {
        #expect(splitter.sentences(in: ["One.", "\u{200B}", "Two."], spine: 0)
            .map(\.id.description) == ["0.0.0", "0.1.0"])
    }

    // MARK: - 7. Straight closing quote

    @Test func aStraightClosingQuoteStaysWithItsSentence() {
        let paragraph = #"He said "Stop. " Then he left."#
        // The tokenizer can hand the closing quote to the next fragment; it belongs to the quoted sentence. The
        // source has a space before the quote, which is kept exactly (`text` is the source characters).
        #expect(splitter.sentences(in: [paragraph], spine: 0).map(\.text) == [
            #"He said "Stop. ""#,
            "Then he left.",
        ])
    }

    // MARK: - 9. UTF-16 ranges

    @Test func rangesCoverAstralAndCombiningCharactersInXHTML() throws {
        let paragraphs = try XHTMLText().paragraphs(in: PrideAndPrejudiceExcerpt.nonASCIIXHTML)
        #expect(paragraphs == ["👩🏽‍🚀 greeted Cafe\u{301} Rouge. They left 👩🏽‍🚀."])

        let sentences = splitter.sentences(in: paragraphs, spine: 0)
        #expect(sentences.map(\.text) == [
            "👩🏽‍🚀 greeted Cafe\u{301} Rouge.",
            "They left 👩🏽‍🚀.",
        ])
        let paragraph = paragraphs[0]
        for sentence in sentences {
            #expect(sentence.text(in: paragraph) == sentence.text)
            let expected = (paragraph as NSString).range(of: sentence.text)
            #expect(sentence.range == expected.location..<(expected.location + expected.length))
        }
    }

    @Test func anAstralSentenceStartAndEndUseUTF16Offsets() {
        let paragraph = "👩🏽‍🚀 arrived. They left 👩🏽‍🚀."
        let sentences = splitter.sentences(in: [paragraph], spine: 3)
        #expect(sentences.map(\.text) == ["👩🏽‍🚀 arrived.", "They left 👩🏽‍🚀."])
        #expect(paragraph.utf16.count > paragraph.count) // surrogate pairs are why the range is UTF-16
        for sentence in sentences {
            #expect(sentence.text(in: paragraph) == sentence.text)
            let expected = (paragraph as NSString).range(of: sentence.text)
            #expect(sentence.range == expected.location..<(expected.location + expected.length))
        }
    }
}
