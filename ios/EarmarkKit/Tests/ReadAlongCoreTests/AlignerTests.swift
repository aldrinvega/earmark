import Foundation
import Testing
import Models
@testable import ReadAlongCore

/// The aligner on *Pride and Prejudice* chapter 3 (public domain): exact, noisy, and with a missing paragraph.
@Suite struct AlignerTests {
    private func transcript(from words: [FixtureWord], offset: TimeInterval = 0) -> [TranscriptWord] {
        words.map {
            TranscriptWord(text: $0.text, start: $0.start + offset, end: $0.end + offset)
        }
    }

    @Test func perfectTranscriptGivesEverySentenceStartAndEndExactly() {
        let fixture = PrideAndPrejudiceChapter3.chapter()
        let words = transcript(from: fixture.words)
        let map = Aligner().align(transcript: words, sentences: fixture.sentences)

        #expect(map.entries.count == fixture.sentences.count)
        for (index, sentence) in fixture.sentences.enumerated() {
            let start = map.startTime(of: sentence.id)
            #expect(start != nil, "sentence \(index) should be aligned")
            if let start {
                #expect(abs(start - fixture.starts[index]) < 0.0001)
            }
            let lastWord = fixture.words.last { $0.sentence == index }
            if let lastWord, let entry = map.entries.first(where: { $0.id == sentence.id }) {
                #expect(entry.end == lastWord.end)
            }
        }
    }

    @Test func aParagraphMissingFromTheAudioIsUnalignedWithoutShiftingWhatFollows() {
        let fixture = PrideAndPrejudiceChapter3.chapter()
        let missing = 14..<17
        let kept = fixture.words.filter { !missing.contains($0.sentence) }
        let map = Aligner().align(transcript: transcript(from: kept), sentences: fixture.sentences)

        for index in missing {
            #expect(map.startTime(of: fixture.sentences[index].id) == nil)
        }
        for index in missing.upperBound..<fixture.sentences.count {
            #expect(map.startTime(of: fixture.sentences[index].id) == fixture.starts[index])
        }
        let before = missing.lowerBound - 1
        #expect(map.startTime(of: fixture.sentences[before].id) == fixture.starts[before])
        #expect(map.sentence(at: fixture.starts[missing.upperBound]) == fixture.sentences[missing.upperBound].id)
    }

    @Test func overlappingAnchorRunsDoNotCrash() {
        let sentences = [
            SentenceText(
                id: SentenceID(spine: 0, paragraph: 0, sentence: 0),
                text: "a b c d e f g h i j"
            ),
        ]
        let spoken = ["a", "b", "c", "d"]
            + Array(repeating: "x", count: 16)
            + ["d", "e", "f", "g"]
        let transcript = spoken.enumerated().map {
            TranscriptWord(text: $0.element, start: Double($0.offset), end: Double($0.offset) + 0.5)
        }

        let map = Aligner().align(transcript: transcript, sentences: sentences)

        #expect(map.entries.count == 1)
        #expect(map.startTime(of: sentences[0].id) == 0)
    }

    @Test func periodSpellingsStillFindTheSentenceStart() {
        let pairs: [(book: String, spoken: String)] = [
            ("To-day was the day of the ball.", "Today was the day of the ball."),
            ("Today was the first day of the ball.", "To-day was the first day of the ball."),
            ("To day was the start of it all.", "To day was the start of it all."),
            ("Mr. Bennet walked into the room.", "Mister Bennet walked into the room."),
            ("Mrs. Bennet smiled at her husband.", "Missus Bennet smiled at her husband."),
            ("Dr. Jones arrived before dinner.", "Doctor Jones arrived before dinner."),
            ("1813 was the year they moved to London.", "Eighteen thirteen was the year they moved to London."),
        ]
        let sentences = pairs.enumerated().map {
            SentenceText(id: SentenceID(spine: 0, paragraph: 0, sentence: $0.offset), text: $0.element.book)
        }
        var transcript: [TranscriptWord] = []
        var starts: [TimeInterval] = []
        var time: TimeInterval = 0
        for pair in pairs {
            starts.append(time)
            for token in pair.spoken.split(whereSeparator: \.isWhitespace) {
                transcript.append(TranscriptWord(text: String(token), start: time, end: time + 0.3))
                time += 0.4
            }
            time += 0.6
        }

        let map = Aligner().align(transcript: transcript, sentences: sentences)
        for (index, sentence) in sentences.enumerated() {
            #expect(abs((map.startTime(of: sentence.id) ?? -1) - starts[index]) < 0.0001)
        }
    }

    @Test func emptyInputsAreHarmless() {
        #expect(Aligner().align(transcript: [], sentences: []).entries.isEmpty)

        let sentences = PrideAndPrejudiceChapter3.chapter().sentences
        let map = Aligner().align(transcript: [], sentences: sentences)
        #expect(map.entries.count == sentences.count)
        #expect(map.entries.allSatisfy { $0.start == nil })
    }
}
