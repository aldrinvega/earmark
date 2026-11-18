import Foundation
import Testing
import EarmarkTestSupport
import Models
@testable import EPUBCore

/// Task 6: the public-domain chapter, its audio clip and the reference starts load and agree with each other.
@Suite struct ChapterFixtureTests {
    private struct ExpectedStarts: Decodable {
        struct Start: Decodable {
            let id: SentenceID
            let start: Double
        }
        let clip: String
        let chapter: String
        let toleranceSeconds: Double
        let starts: [Start]
    }

    private func sentences() throws -> [ChapterSentence] {
        let paragraphs = try XHTMLText().paragraphs(in: try Fixtures.data("pp-ch3.xhtml"))
        return SentenceSplitter().sentences(in: paragraphs, spine: 0)
    }

    @Test func chapterSplitsIntoTheKnownSentences() throws {
        let all = try sentences()
        #expect(all.count == 84)
        #expect(all.first?.sentence.text == "Chapter III.")
        #expect(all[1].sentence.text.hasPrefix("NOT all that Mrs. Bennet, however,"))
        // The paragraph split by an illustration in the source edition is one paragraph again.
        let lucas = try #require(all.first { $0.sentence.id.description == "0.4.4" })
        #expect(lucas.sentence.text.contains("his being gone to London only to get a large party for the ball"))
        // Source-edition artefacts must not leak into the text the reader shows and the aligner matches.
        for sentence in all {
            #expect(!sentence.sentence.text.contains("{"))
            #expect(!sentence.sentence.text.contains("Copyright 1894"))
        }
    }

    @Test func expectedStartsPointAtRealSentencesInReadingOrder() throws {
        let expected = try JSONDecoder().decode(ExpectedStarts.self, from: try Fixtures.data("pp-ch3-expected-starts.json"))
        #expect(expected.clip == "pp-ch3-clip.m4a")
        #expect(expected.chapter == "pp-ch3.xhtml")
        #expect(expected.toleranceSeconds == 0.5)
        #expect(expected.starts.count == 8)

        let ids = Set(try sentences().map(\.sentence.id))
        for start in expected.starts {
            #expect(ids.contains(start.id), "\(start.id) is not a sentence of the chapter")
            #expect(start.start >= 14.9 && start.start < 180, "\(start.id) is outside the clip's narration")
        }
        #expect(expected.starts.map(\.id) == expected.starts.map(\.id).sorted())
        #expect(expected.starts.map(\.start) == expected.starts.map(\.start).sorted())
    }

    @Test func audioClipIsPresent() throws {
        let data = try Fixtures.data("pp-ch3-clip.m4a")
        #expect(data.count > 1_000_000 && data.count < 2_500_000)
        // An MPEG-4 file starts with an `ftyp` box.
        #expect(String(decoding: data[4..<8], as: UTF8.self) == "ftyp")
    }
}
