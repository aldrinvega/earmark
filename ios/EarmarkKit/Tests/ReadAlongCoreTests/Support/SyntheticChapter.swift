import Foundation
import Models
import ReadAlongCore

/// A made-up chapter for the performance test: `sentenceCount` sentences of random words from a small vocabulary.
///
/// Nothing here is book text; it only has to look like a long chapter to the aligner.
enum SyntheticChapter {
    static let vocabulary = [
        "the", "of", "and", "to", "in", "a", "was", "that", "he", "it", "with", "as", "his", "on", "be",
        "at", "by", "had", "this", "not", "are", "but", "from", "or", "have", "an", "they", "which", "one",
        "you", "were", "her", "all", "she", "there", "would", "their", "we", "him", "been", "has", "when",
        "who", "will", "more", "no", "if", "out", "so", "said", "what", "up", "its", "about", "into", "than",
        "them", "can", "only", "other", "new", "some", "could", "time", "these", "two", "may", "then", "do",
        "first", "any", "my", "now", "such", "like", "our", "over", "man", "me", "even", "most", "made",
        "after", "also", "did", "many", "before", "must", "through", "back", "years", "where", "much", "your",
        "way", "well", "down", "should", "because", "each", "just", "those", "people", "mr", "how", "too",
        "little", "state", "good", "very", "make", "world", "still", "own", "see", "men", "work", "long",
        "get", "here", "between", "both", "life", "being", "under", "never", "day", "same", "another", "know",
        "while", "last", "might", "us", "great", "old", "year", "off", "come", "since", "against", "go",
        "came", "right", "used", "take", "three", "morning", "house", "room", "lady", "family", "letter",
        "father", "mother", "daughter", "sister", "brother", "friend", "neighbour", "party", "ball", "dance",
        "horse", "coach", "window", "garden", "street", "village", "country", "town", "London", "Netherfield",
        "Bennet", "Bingley", "Darcy", "Lucas", "Hertfordshire", "Meryton", "evening", "minute", "hour",
        "happy", "young", "handsome", "agreeable", "proud", "civil", "quiet", "lively", "pretty", "pleasant",
        "walk", "visit", "answer", "report", "hope", "fear", "wish", "smile", "look", "tell", "think", "hear",
        "find", "leave", "bring", "return", "accept", "invite", "settle", "marry", "dance", "read", "write",
    ]

    /// The chapter plus a perfect transcript (one `TranscriptWord` per word, 0.3 s each, 0.34 s apart).
    static func make(
        sentenceCount: Int,
        wordsPerSentence: Int,
        seed: UInt64
    ) -> (sentences: [SentenceText], transcript: [TranscriptWord], starts: [TimeInterval]) {
        var random = SeededGenerator(seed: seed)
        var sentences: [SentenceText] = []
        var transcript: [TranscriptWord] = []
        var starts: [TimeInterval] = []
        var time: TimeInterval = 0

        for index in 0..<sentenceCount {
            starts.append(time)
            var words: [String] = []
            words.reserveCapacity(wordsPerSentence)
            for _ in 0..<wordsPerSentence {
                let word = vocabulary.randomElement(using: &random) ?? "word"
                words.append(word)
                transcript.append(TranscriptWord(text: word, start: time, end: time + 0.3))
                time += 0.34
            }
            sentences.append(
                SentenceText(
                    id: SentenceID(spine: 0, paragraph: index, sentence: 0),
                    text: words.joined(separator: " ") + "."
                )
            )
            time += 0.5
        }

        return (sentences, transcript, starts)
    }
}
