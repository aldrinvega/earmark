import Foundation
import Testing
import Models
@testable import ReadAlongCore

/// A long chapter must not fall back to a 10k × 10k matrix: anchors keep the dynamic-programming segments small.
///
/// The timing bounds are only meaningful in an optimised build (the app ships Release). Debug `swift test` keeps every
/// correctness assertion but only prints the timings; set `EARMARK_PERF=1` to assert them, and CI does that in a
/// `-c release` run of this suite. `.serialized` keeps the two big DP runs from overlapping.
@Suite(.serialized) struct AlignerPerformanceTests {
    private static var enforcesTiming: Bool {
        ProcessInfo.processInfo.environment["EARMARK_PERF"] == "1"
    }

    private static var configuration: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }

    /// Prints every measurement; asserts the 5 s bound only when `EARMARK_PERF=1`.
    private func report(_ elapsed: Duration, seconds: Double, label: String) {
        let timing = Self.enforcesTiming
            ? "timing asserted"
            : "timing not asserted; set EARMARK_PERF=1"
        print("ReadAlongCore \(label): \(String(format: "%.4f s", seconds)) (\(Self.configuration), \(timing))")
        if Self.enforcesTiming {
            #expect(elapsed < .seconds(5))
        }
    }

    @Test func alignsTenThousandWordsInAboutSixHundredSentencesUnderFiveSeconds() {
        let chapter = SyntheticChapter.make(sentenceCount: 600, wordsPerSentence: 17, seed: 0xC0FFEE)
        #expect(chapter.transcript.count == 10_200)

        let aligner = Aligner()
        var map: AlignmentMap?
        let elapsed = ContinuousClock().measure {
            map = aligner.align(transcript: chapter.transcript, sentences: chapter.sentences)
        }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        report(elapsed, seconds: seconds,
               label: "\(chapter.transcript.count) words / \(chapter.sentences.count) sentences aligned")

        let result = map
        #expect(result?.entries.count == chapter.sentences.count)
        var aligned = 0
        var exact = 0
        for (index, sentence) in chapter.sentences.enumerated() {
            guard let start = result?.startTime(of: sentence.id) else { continue }
            aligned += 1
            if abs(start - chapter.starts[index]) < 0.0001 { exact += 1 }
        }
        #expect(aligned == chapter.sentences.count)
        #expect(exact == chapter.sentences.count)
    }

    /// 600 sentences from four words (so no unique 4-gram exists) with `insertionWords` extra words in the middle.
    private func noAnchorChapter(
        insertionWords: Int
    ) -> (sentences: [SentenceText], transcript: [TranscriptWord], starts: [TimeInterval], firstAfterInsertion: Int) {
        let vocabulary = ["he", "said", "that", "then"]
        var random = SeededGenerator(seed: 0xBADBEEF)
        var sentences: [SentenceText] = []
        var transcript: [TranscriptWord] = []
        var starts: [TimeInterval] = []
        var time: TimeInterval = 0

        for index in 0..<600 {
            starts.append(time)
            var words: [String] = []
            for _ in 0..<17 {
                let word = vocabulary.randomElement(using: &random) ?? "he"
                words.append(word)
                transcript.append(TranscriptWord(text: word, start: time, end: time + 0.3))
                time += 0.34
            }
            sentences.append(SentenceText(
                id: SentenceID(spine: 0, paragraph: index, sentence: 0),
                text: words.joined(separator: " ")
            ))
            time += 0.5
        }

        let cut = 5_000
        var inserted: [TranscriptWord] = []
        var insertedTime = transcript[cut].start
        for index in 0..<insertionWords {
            let word = index.isMultiple(of: 2) ? "and" : "then"
            inserted.append(TranscriptWord(text: word, start: insertedTime, end: insertedTime + 0.3))
            insertedTime += 0.34
        }
        let shift = insertedTime - transcript[cut].start
        let shifted = transcript[cut...].map {
            TranscriptWord(text: $0.text, start: $0.start + shift, end: $0.end + shift)
        }
        transcript = Array(transcript[..<cut]) + inserted + shifted

        // Sentences 295 and later begin after the inserted stretch; their true starts move with it.
        let firstAfterInsertion = (cut + 16) / 17
        for index in firstAfterInsertion..<starts.count {
            starts[index] += shift
        }
        return (sentences, transcript, starts, firstAfterInsertion)
    }

    @Test(arguments: [1_500, 3_000])
    func longInsertionKeepsFollowingSentenceStarts(insertionWords: Int) {
        let input = noAnchorChapter(insertionWords: insertionWords)
        let aligner = Aligner()
        var map: AlignmentMap?
        let elapsed = ContinuousClock().measure {
            map = aligner.align(transcript: input.transcript, sentences: input.sentences)
        }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

        var total = 0
        var withinHalfASecond = 0
        var exact = 0
        for index in input.firstAfterInsertion..<input.sentences.count {
            guard let start = map?.startTime(of: input.sentences[index].id) else { continue }
            total += 1
            let error = abs(start - input.starts[index])
            if error <= 0.5 { withinHalfASecond += 1 }
            if error < 0.0001 { exact += 1 }
        }
        print("ReadAlongCore fallback \(insertionWords): \(input.transcript.count) words, " +
              "\(withinHalfASecond)/\(total) starts within 0.5 s, \(exact) exact")
        report(elapsed, seconds: seconds, label: "fallback with \(insertionWords) inserted words")

        #expect(total == input.sentences.count - input.firstAfterInsertion)
        #expect(map?.entries.count == input.sentences.count)
        #expect(Double(withinHalfASecond) / Double(total) >= 0.95)
    }
}
