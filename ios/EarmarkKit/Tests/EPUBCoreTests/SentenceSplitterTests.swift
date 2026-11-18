import Foundation
import Testing
import Models
import EPUBCore

/// Stable sentence IDs `<spine>.<paragraph>.<sentence>` and the 19th-century punctuation rules from Task 5.
@Suite struct SentenceSplitterTests {
    private let splitter = SentenceSplitter()

    private func lines(_ texts: [String], spine: Int = 0) -> [ChapterSentence] {
        splitter.sentences(in: texts, spine: spine)
    }

    // MARK: - Stability

    @Test func sameInputGivesTheSameIDsOnTwoRuns() throws {
        let paragraphs = try XHTMLText().paragraphs(in: PrideAndPrejudiceExcerpt.xhtml)
        let first = splitter.sentences(in: paragraphs, spine: 4)
        let second = splitter.sentences(in: paragraphs, spine: 4)

        #expect(first == second)
        #expect(first.map(\.id.description) == second.map(\.id.description))
        #expect(first.map(\.text) == second.map(\.text))
    }

    @Test func idsStrictlyIncreaseInReadingOrder() throws {
        let paragraphs = try XHTMLText().paragraphs(in: PrideAndPrejudiceExcerpt.xhtml)
        let sentences = splitter.sentences(in: paragraphs, spine: 0)

        #expect(sentences.count > 3)
        #expect(Set(sentences.map(\.id)).count == sentences.count)
        for (earlier, later) in zip(sentences, sentences.dropFirst()) {
            #expect(earlier.id < later.id)
        }
        // Sentence indexes restart at zero in every paragraph.
        let grouped = Dictionary(grouping: sentences, by: \.id.paragraph)
        for (_, group) in grouped {
            #expect(group.map(\.id.sentence) == Array(0..<group.count))
        }
    }

    // MARK: - Abbreviations

    @Test func doesNotSplitAfterTitlesAndInitials() {
        let paragraphs = [
            "Mr. Bennet was among the earliest of those who waited on Mr. Bingley.",
            "Mrs. Bennet was quite disconcerted.",
            "Dr. Smith arrived. He was late.",
            "She met J. R. Smith at the door. He smiled.",
            "St. Albans is a city. It is old.",
        ]
        let sentences = lines(paragraphs)
        #expect(sentences.map(\.text) == [
            paragraphs[0],
            paragraphs[1],
            "Dr. Smith arrived.",
            "He was late.",
            "She met J. R. Smith at the door.",
            "He smiled.",
            "St. Albans is a city.",
            "It is old.",
        ])
    }

    // MARK: - Dialogue and quotes

    @Test func keepsDialogueInQuotesWithItsSentence() {
        let paragraph = "“Come, Darcy,” said he, “I must have you dance.”"
        let sentences = lines([paragraph])
        #expect(sentences.map(\.text) == [paragraph])
    }

    @Test func aSentenceEndingInAClosingQuoteIsOneSentence() {
        let paragraph = PrideAndPrejudiceExcerpt.paragraphs[2]
        let sentences = lines([paragraph])
        #expect(sentences.count == 1)
        #expect(sentences.first?.text == paragraph)
        #expect(sentences.first?.text.hasSuffix("nothing to wish for.”") == true)
    }

    @Test func dialogueAttributionStaysWithTheSpokenSentence() {
        let paragraph = "“Go away!” she cried. “I mean it.”"
        #expect(lines([paragraph]).map(\.text) == ["“Go away!” she cried.", "“I mean it.”"])
    }

    @Test func emDashesAndNineteenthCenturyPunctuationDoNotCreateFragments() {
        let paragraphs = [
            "Well—I don’t know. What do you think?",
            "It was over—she had left. Nobody knew why.",
            "He replied—and nobody expected it—that he would go. Then he left.",
        ]
        #expect(lines(paragraphs).map(\.text) == [
            "Well—I don’t know.",
            "What do you think?",
            "It was over—she had left.",
            "Nobody knew why.",
            "He replied—and nobody expected it—that he would go.",
            "Then he left.",
        ])
    }

    // MARK: - Text and ranges

    @Test func outputTextMatchesTheSourceAndRangesPointAtIt() throws {
        let paragraphs = try XHTMLText().paragraphs(in: PrideAndPrejudiceExcerpt.xhtml)
        let sentences = splitter.sentences(in: paragraphs, spine: 2)
        let grouped = Dictionary(grouping: sentences, by: \.id.paragraph)

        for (index, paragraph) in paragraphs.enumerated() {
            let group = grouped[index] ?? []
            #expect(!group.isEmpty)
            // Only whitespace was normalised: joining the sentences with single spaces gives the paragraph back.
            #expect(group.map(\.text).joined(separator: " ") == paragraph)
            for sentence in group {
                #expect(sentence.text(in: paragraph) == sentence.text)
                #expect(sentence.range.lowerBound < sentence.range.upperBound)
            }
        }
    }

    @Test func rangesAreContiguousAndInsideTheParagraph() {
        let paragraph = "One. Two! Three? Four."
        let sentences = lines([paragraph])
        #expect(sentences.map(\.text) == ["One.", "Two!", "Three?", "Four."])

        var expectedStart = 0
        for sentence in sentences {
            #expect(sentence.range.lowerBound == expectedStart)
            expectedStart = sentence.range.upperBound + 1 // the single space between sentences
        }
        #expect(sentences.last?.range.upperBound == paragraph.utf16.count)
    }

    // MARK: - Empty paragraphs

    @Test func emptyParagraphsProduceNoSentencesAndNoIndex() {
        let sentences = lines(["", "   ", "First real one.", "Mr. Bennet arrived."])
        #expect(sentences.map(\.id.description) == ["0.0.0", "0.1.0"])
        #expect(sentences.map(\.text) == ["First real one.", "Mr. Bennet arrived."])
    }

    @Test func textlessBlocksInXHTMLDoNotShiftLaterIDs() throws {
        let xhtml = #"<html><body><p>One.</p><p/><div class="sep"><img src="x"/></div><p>Two.</p></body></html>"#
        let paragraphs = try XHTMLText().paragraphs(in: xhtml)
        let sentences = splitter.sentences(in: paragraphs, spine: 0)
        #expect(sentences.map(\.id.description) == ["0.0.0", "0.1.0"])
    }

    // MARK: - Spine

    @Test func spineIndexIsCarriedIntoEveryID() {
        let sentences = lines(["One. Two."], spine: 7)
        #expect(sentences.map(\.id.description) == ["7.0.0", "7.0.1"])
    }
}
