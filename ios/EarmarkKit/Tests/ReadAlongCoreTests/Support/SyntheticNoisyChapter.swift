import Foundation
import Models
import ReadAlongCore

/// A 200-sentence made-up chapter and a noisy transcript of it, for the honest acceptance test.
///
/// The transcript has an extra intro, per-word timing jitter (±0.2 s), variable word durations, 10% substitutions,
/// 5% dropped words, a sentence whose first two words are replaced by a longer paraphrase, and both merged
/// ("to-day" → "today") and joined ("any-thing" → "anything") spellings.
enum SyntheticNoisyChapter {
    static let sentenceCount = 200

    static func make(
        seed: UInt64
    ) -> (sentences: [SentenceText], transcript: [TranscriptWord], starts: [TimeInterval]) {
        var random = SeededGenerator(seed: seed)
        var sentences: [SentenceText] = []
        var transcript: [TranscriptWord] = []
        var starts: [TimeInterval] = []
        var time: TimeInterval = 0

        let intro = ["This", "chapter", "is", "read", "for", "you", "by", "a", "volunteer", "narrator", "today"]
        for word in intro {
            let (start, end) = Self.timing(after: time, random: &random)
            transcript.append(TranscriptWord(text: word, start: start, end: end))
            time = end + 0.05
        }
        time += 0.5

        for index in 0..<sentenceCount {
            let (bookWords, audioWords) = Self.words(for: index, random: &random)
            sentences.append(SentenceText(
                id: SentenceID(spine: 0, paragraph: index, sentence: 0),
                text: bookWords.joined(separator: " ")
            ))

            // Ground truth is the first word of the sentence as it is spoken, even when the transcriber drops it.
            var firstSpoken: TimeInterval?
            for word in audioWords {
                let (start, end) = Self.timing(after: time, random: &random)
                time = end
                if firstSpoken == nil { firstSpoken = start }

                let roll = Double.random(in: 0..<1, using: &random)
                if roll < 0.05 { continue } // the transcriber missed this word; it is still in the audio
                let text = roll < 0.15
                    ? (SyntheticChapter.vocabulary.randomElement(using: &random) ?? "mumble")
                    : word
                transcript.append(TranscriptWord(text: text, start: start, end: end))
            }
            starts.append(firstSpoken ?? time)

            time += 0.4 + Double.random(in: 0..<0.5, using: &random)
        }

        return (sentences, transcript, starts)
    }

    /// A jittered start and a variable duration, always after `time`.
    private static func timing(
        after time: TimeInterval,
        random: inout SeededGenerator
    ) -> (start: TimeInterval, end: TimeInterval) {
        let gap = 0.02 + Double.random(in: 0..<0.1, using: &random)
        let jitter = Double.random(in: -0.2...0.2, using: &random)
        let start = max(time + gap + jitter, time + 0.02)
        return (start, start + 0.18 + Double.random(in: 0..<0.22, using: &random))
    }

    private static func words(
        for index: Int,
        random: inout SeededGenerator
    ) -> (book: [String], audio: [String]) {
        switch index {
        case 40:
            // The audio replaces the first two book words with a longer paraphrase.
            let rest = (0..<11).map { _ in SyntheticChapter.vocabulary.randomElement(using: &random) ?? "word" }
            return (["the", "young"] + rest, ["quite", "unexpectedly", "and", "rather"] + rest)
        case 80:
            var book = ["To-day", "was", "the", "first", "day", "of", "the", "ball"]
            book += (0..<8).map { _ in SyntheticChapter.vocabulary.randomElement(using: &random) ?? "word" }
            var audio = book
            audio[0] = "Today"
            return (book, audio)
        case 81:
            var book = ["Any-thing", "could", "happen", "at", "the", "assembly"]
            book += (0..<10).map { _ in SyntheticChapter.vocabulary.randomElement(using: &random) ?? "word" }
            var audio = book
            audio[0] = "Anything"
            return (book, audio)
        default:
            let words = (0..<16).map { _ in
                SyntheticChapter.vocabulary.randomElement(using: &random) ?? "word"
            }
            return (words, words)
        }
    }
}
