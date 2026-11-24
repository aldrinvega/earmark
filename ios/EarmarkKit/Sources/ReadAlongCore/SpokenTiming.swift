import Foundation

/// Turns one transcript word's times into times for each of its normalised tokens, correcting two engine quirks
/// seen on the iPhone SE (spike run 3):
///
/// - **A word stretched over the pause before it.** SpeechAnalyzer sometimes starts a word where the previous one
///   ended (`Not` 10.56–15.66 s after a 5 s pause). When a word is much longer than its letters allow, its start moves
///   to `end − plausible length`; the end, where speech really is, stays.
/// - **Several words in one segment.** SFSpeechRecognizer sometimes returns `library he` as one segment, so the
///   next sentence's first word would inherit the segment's start. The segment's time is split by letter count.
public enum SpokenTiming {
    /// Seconds a spoken token of `letters` letters plausibly takes: generous, so only clear outliers change.
    static func plausibleDuration(letters: Int) -> TimeInterval {
        0.15 + 0.09 * Double(letters)
    }

    /// Times for each token of `word`; `letters` holds each token's letter count (`tokenCount` entries).
    static func tokenTimes(
        for word: TranscriptWord,
        tokenCount: Int,
        letters: [Int]
    ) -> [(start: TimeInterval, end: TimeInterval)] {
        guard tokenCount > 0 else { return [] }
        var start = word.start
        let end = word.end
        let duration = end - start
        guard duration > 0 else { return Array(repeating: (start, end), count: tokenCount) }

        let totalLetters = max(letters.reduce(0, +), 1)
        let plausible = plausibleDuration(letters: totalLetters)
        if duration > max(2 * plausible, plausible + 0.4) {
            start = end - plausible
        }
        if tokenCount == 1 { return [(start, end)] }

        var result: [(start: TimeInterval, end: TimeInterval)] = []
        var cursor = start
        let span = end - start
        for index in 0..<tokenCount {
            let share = Double(index < letters.count ? max(letters[index], 1) : 1) / Double(totalLetters)
            let tokenEnd = index == tokenCount - 1 ? end : cursor + span * share
            result.append((cursor, tokenEnd))
            cursor = tokenEnd
        }
        return result
    }
}
