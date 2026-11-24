import Foundation
import Testing
@testable import ReadAlongCore

/// Engine timing quirks seen in spike run 3 on the iPhone SE (Fixtures/pp-ch3-run3-report.txt).
@Suite struct SpokenTimingTests {
    private func times(_ text: String, _ start: Double, _ end: Double) -> [(start: Double, end: Double)] {
        let word = TranscriptWord(text: text, start: start, end: end)
        return SpokenTiming.tokenTimes(for: word, tokenCount: TextNormalizer().words(in: text).count,
                                       letters: TextNormalizer().words(in: text).map(\.count))
    }

    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.005 }

    @Test func aWordStretchedOverThePauseBeforeItKeepsOnlyAPlausibleLength() {
        // SpeechAnalyzer: "Not" 10.56–15.66 (it swallowed the 5 s pause); the other engine heard it at 15.36.
        let t = times("Not", 10.56, 15.66)
        #expect(t.count == 1)
        #expect(close(t[0].start, 15.24) && close(t[0].end, 15.66))
        // SpeechAnalyzer: "But" 32.58–33.60; the other engine heard it at 33.21.
        let but = times("But", 32.58, 33.60)
        #expect(close(but[0].start, 33.18))
    }

    @Test func ordinaryWordsAreUntouched() {
        for (text, start, end) in [("LibriVox", 3.66, 4.44), ("housekeeping,", 106.50, 107.58),
                                   ("gentlemanlike,", 168.78, 169.68), ("and,", 49.32, 50.04)] {
            let t = times(text, start, end)
            #expect(close(t[0].start, start) && close(t[t.count - 1].end, end), "\(text) changed")
        }
    }

    @Test func aMultiWordSegmentSplitsItsTimeByLetters() {
        // SFSpeechRecognizer: "library he" 82.41–83.10, where "He" starts the next sentence.
        let t = times("library he", 82.41, 83.10)
        #expect(t.count == 2)
        #expect(close(t[0].start, 82.41) && close(t[0].end, 82.947))
        #expect(close(t[1].start, 82.947) && close(t[1].end, 83.10))
    }

    @Test func aStretchedMultiWordSegmentIsClampedThenSplit() {
        let t = times("him in his", 70.0, 76.0)       // 8 letters → plausible 0.15 + 0.72 = 0.87 s
        #expect(close(t[0].start, 75.13))
        #expect(close(t[2].end, 76.0))
        #expect(t[0].end <= t[1].start + 0.0001 && t[1].end <= t[2].start + 0.0001)
    }

    @Test func zeroOrNegativeDurationsAreKeptAsGiven() {
        let t = times("hello world", 5.0, 5.0)
        #expect(t.count == 2)
        #expect(t.allSatisfy { close($0.start, 5.0) && close($0.end, 5.0) })
    }
}
