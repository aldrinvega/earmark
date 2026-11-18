import Foundation
import Testing
@testable import ReadAlongCore

/// The acceptance criterion, repeated over fixed seeds so it cannot depend on a lucky one.
///
/// The synthetic chapter has 200 sentences (95% = 190), an extra intro, ±0.2 s timing jitter on every word, variable
/// durations, 10% substituted words, 5% dropped words, a longer paraphrase at one sentence start, and merged
/// ("to-day" → "today") and joined ("any-thing" → "anything") spellings.
@Suite struct NoisyAlignmentTests {
    @Test(arguments: [UInt64(0x5EED_1234), 14, 47, 52])
    func noisyTranscriptKeepsMostSentenceStartsWithinHalfASecond(seed: UInt64) {
        let input = SyntheticNoisyChapter.make(seed: seed)
        let map = Aligner().align(transcript: input.transcript, sentences: input.sentences)

        var aligned = 0
        var withinHalfASecond = 0
        for (index, sentence) in input.sentences.enumerated() {
            guard let start = map.startTime(of: sentence.id) else { continue }
            aligned += 1
            if abs(start - input.starts[index]) <= 0.5 {
                withinHalfASecond += 1
            }
        }
        let fraction = Double(withinHalfASecond) / Double(input.sentences.count)
        print("seed \(seed): \(withinHalfASecond)/\(input.sentences.count) starts within 0.5 s " +
              String(format: "(%.2f%%), %d aligned", fraction * 100, aligned))

        #expect(aligned == input.sentences.count)
        #expect(fraction >= 0.95)
    }
}
