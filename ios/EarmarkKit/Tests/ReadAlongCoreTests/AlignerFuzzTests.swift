import Foundation
import Testing
import Models
@testable import ReadAlongCore

/// Seeded noise on tiny vocabularies (many repeated 4-grams, so anchors collide and the banded fallback runs).
/// This is the shape of input that used to crash the aligner on overlapping anchor runs.
@Suite struct AlignerFuzzTests {
    private struct Configuration {
        let sentences: Int
        let words: Int
        let vocabulary: Int
    }

    private func chapter(
        _ configuration: Configuration,
        seed: UInt64
    ) -> (sentences: [SentenceText], transcript: [TranscriptWord]) {
        var random = SeededGenerator(seed: seed)
        let vocabulary = (0..<configuration.vocabulary).map { "w\($0)" }
        var sentences: [SentenceText] = []
        var transcript: [TranscriptWord] = []
        var time: TimeInterval = 0

        for index in 0..<configuration.sentences {
            var words: [String] = []
            for _ in 0..<configuration.words {
                let word = vocabulary.randomElement(using: &random) ?? "w0"
                words.append(word)
                transcript.append(TranscriptWord(text: word, start: time, end: time + 0.3))
                time += 0.4
            }
            sentences.append(SentenceText(
                id: SentenceID(spine: 0, paragraph: index, sentence: 0),
                text: words.joined(separator: " ")
            ))
            time += 0.4
        }

        // 10% dropped, 10% substituted, 3% extra words.
        var noisy: [TranscriptWord] = []
        var noisyTime: TimeInterval = 0
        for word in transcript {
            let roll = Double.random(in: 0..<1, using: &random)
            if roll < 0.10 { continue }
            let text = roll < 0.20 ? (vocabulary.randomElement(using: &random) ?? "w0") : word.text
            noisy.append(TranscriptWord(text: text, start: noisyTime, end: noisyTime + 0.3))
            noisyTime += 0.4
            if Double.random(in: 0..<1, using: &random) < 0.03 {
                let inserted = vocabulary.randomElement(using: &random) ?? "w0"
                noisy.append(TranscriptWord(text: inserted, start: noisyTime, end: noisyTime + 0.3))
                noisyTime += 0.4
            }
        }
        return (sentences, noisy)
    }

    @Test func noisyInputWithRepeatedPhrasesNeverProducesInvertedStarts() {
        let configurations = [
            Configuration(sentences: 10, words: 5, vocabulary: 5),
            Configuration(sentences: 5, words: 20, vocabulary: 6),
            Configuration(sentences: 8, words: 20, vocabulary: 6),
            Configuration(sentences: 10, words: 20, vocabulary: 6),
            Configuration(sentences: 5, words: 40, vocabulary: 6),
            Configuration(sentences: 8, words: 40, vocabulary: 6),
            Configuration(sentences: 30, words: 200, vocabulary: 8),
        ]

        for configuration in configurations {
            // The 6,000-word shape costs ~60 ms per run in debug; the smaller shapes (which reproduce the
            // overlapping-anchor crash) get all 101 seeds, the big one a representative 11.
            let seeds = configuration.sentences == 30 ? 0...10 : 0...100
            for seed in seeds {
                let input = chapter(configuration, seed: UInt64(seed))
                let map = Aligner().align(transcript: input.transcript, sentences: input.sentences)

                #expect(map.entries.count == input.sentences.count)
                var previous = -TimeInterval.infinity
                for entry in map.entries {
                    guard let start = entry.start else { continue }
                    #expect(
                        start >= previous,
                        "seed \(seed), \(configuration.sentences)x\(configuration.words)/\(configuration.vocabulary)"
                    )
                    previous = start
                }
            }
        }
    }
}
