import Foundation
import Testing
import Models
import EPUBCore

/// Review-7 finding 1: an abbreviation repair must not join two real sentences.
@Suite struct AbbreviationRegressionTests {
    private let splitter = SentenceSplitter()

    @Test(arguments: [
        (
            "The address is 12 Baker St. He lives there.",
            ["The address is 12 Baker St.", "He lives there."]
        ),
        (
            "We bought apples, pears, etc. Then we left.",
            ["We bought apples, pears, etc.", "Then we left."]
        ),
        (
            "Smith et al. Then Jones.",
            ["Smith et al.", "Then Jones."]
        ),
        (
            "The book was written by J. It sold well.",
            ["The book was written by J.", "It sold well."]
        ),
        (
            "Wait... What? Really?!",
            ["Wait... What?", "Really?!"]
        ),
    ])
    func doesNotJoinRealSentenceBoundaries(paragraph: String, expected: [String]) {
        #expect(splitter.sentences(in: [paragraph], spine: 0).map(\.text) == expected)
    }

    @Test func titlesAndShortFragmentsStillMerge() {
        let paragraphs = [
            "Mr. Bennet was among the earliest of those who waited on Mr. Bingley.",
            "St. Albans is a city. It is old.",
            "She met J. R. Smith at the door. He smiled.",
        ]
        #expect(splitter.sentences(in: paragraphs, spine: 0).map(\.text) == [
            paragraphs[0],
            "St. Albans is a city.",
            "It is old.",
            "She met J. R. Smith at the door.",
            "He smiled.",
        ])
    }

    /// Review-9 finding 1: `St.`, `Ft.`, `Vol.`, `Fig.`, `Ch.`, `Pt.`, `est.` are ordinary mid-sentence words.
    @Test(arguments: [
        ("The office is on St. James's Square.", ["The office is on St. James's Square."]),
        ("We walked slowly down St. James's Street.", ["We walked slowly down St. James's Street."]),
        ("The service was held at St. Paul's Cathedral.", ["The service was held at St. Paul's Cathedral."]),
        ("They met at the old Ft. Sumter.", ["They met at the old Ft. Sumter."]),
        (
            "The paper is in Vol. 2. The first volume is lost.",
            ["The paper is in Vol. 2.", "The first volume is lost."]
        ),
        (
            "The building was designed by a famous firm, est. 1890.",
            ["The building was designed by a famous firm, est. 1890."]
        ),
    ])
    func midSentenceAbbreviationsDoNotSplit(paragraph: String, expected: [String]) {
        #expect(splitter.sentences(in: [paragraph], spine: 0).map(\.text) == expected)
    }

    /// Review-9 finding 2: three adjacent initials followed by a surname are one name.
    @Test func initialsRunsMergeAtAnyLength() {
        let paragraphs = [
            "The novel was written by J. R. R. Tolkien.",
            "The letter came from Prof. J. R. R. Tolkien.",
        ]
        #expect(splitter.sentences(in: paragraphs, spine: 0).map(\.text) == paragraphs)
    }

    /// Review-9 finding 3: an ellipsis swallows only a very short question/exclamation, never a short statement.
    @Test func ellipsisContinuationOnlySwallowsShortQuestions() {
        let paragraphs = [
            "Wait... What? Really?!",
            "He paused... Then he left.",
            "I waited... Nothing.",
            "Well... Perhaps.",
        ]
        #expect(splitter.sentences(in: paragraphs, spine: 0).map(\.text) == [
            "Wait... What?",
            "Really?!",
            "He paused...",
            "Then he left.",
            "I waited...",
            "Nothing.",
            "Well...",
            "Perhaps.",
        ])
    }
}
