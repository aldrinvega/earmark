import Foundation
import Testing
import EPUBCore

/// Review-7 finding 3: the shared key must only change deliberately, so the exact IDs and texts are pinned here.
///
/// These IDs are a contract with saved progress, alignment caches and recaps. If `NLTokenizer`'s shipped sentence
/// model changes, this test fails; updating it means migrating every saved `SentenceID`.
@Suite struct StableIDGoldenTests {
    @Test func prideAndPrejudiceExcerptHasTheseExactIDsAndTexts() throws {
        let paragraphs = try XHTMLText().paragraphs(in: PrideAndPrejudiceExcerpt.xhtml)
        let sentences = SentenceSplitter().sentences(in: paragraphs, spine: 0)

        #expect(sentences.map(\.id.description) == [
            "0.0.0",
            "0.1.0",
            "0.2.0",
            "0.3.0",
            "0.3.1",
            "0.4.0",
            "0.4.1",
            "0.5.0",
            "0.5.1",
        ])
        #expect(sentences.map(\.text) == [
            "Chapter 3",
            "Not all that Mrs. Bennet, however, with the assistance of her five daughters, could ask on the subject, "
                + "was sufficient to draw from her husband any satisfactory description of Mr. Bingley.",
            "“If I can but see one of my daughters happily settled at Netherfield,” said Mrs. Bennet to her husband, "
                + "“and all the others equally well married, I shall have nothing to wish for.”",
            "Mr. Bennet was among the earliest of those who waited on Mr. Bingley.",
            "He had always intended to visit him.",
            "Well—I don’t know.",
            "What do you think?",
            "St. Albans is a city.",
            "It is old.",
        ])
    }
}
