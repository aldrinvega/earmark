import Foundation

/// Lines a transcript up with the EPUB's sentences.
///
/// The token streams are matched in order with gaps allowed, so an intro, a cough, a dropped word or a substituted
/// word does not push everything after it out of place. Long exact runs are found first (unique 4-grams, longest
/// increasing sequence) and used as anchors; the stretches between anchors are aligned with a banded
/// Needleman–Wunsch pass. A sentence with no matched word stays unaligned, and the sentences after it keep their own
/// matches instead of sliding up.
public struct Aligner: Sendable {
    public init() {}

    /// Aligns one chapter. `sentences` must be in reading order; the returned map has one entry per sentence.
    public func align(transcript: [TranscriptWord], sentences: [SentenceText]) -> AlignmentMap {
        let normalizer = TextNormalizer()

        // EPUB side: one token stream plus the sentence each token came from.
        var bookTokens: [String] = []
        var sentenceOfToken: [Int] = []
        bookTokens.reserveCapacity(sentences.count * 12)
        for (index, sentence) in sentences.enumerated() {
            let tokens = normalizer.words(in: sentence.text)
            bookTokens.append(contentsOf: tokens)
            sentenceOfToken.append(contentsOf: repeatElement(index, count: tokens.count))
        }

        // Audio side: one token stream plus the word's times (a word can normalise to two tokens).
        var spokenTokens: [String] = []
        var spokenStarts: [TimeInterval] = []
        var spokenEnds: [TimeInterval] = []
        spokenTokens.reserveCapacity(transcript.count)
        for word in transcript {
            let tokens = normalizer.words(in: word.text)
            let times = SpokenTiming.tokenTimes(for: word, tokenCount: tokens.count, letters: tokens.map(\.count))
            for (token, time) in zip(tokens, times) {
                spokenTokens.append(token)
                spokenStarts.append(time.start)
                spokenEnds.append(time.end)
            }
        }

        guard !bookTokens.isEmpty, !spokenTokens.isEmpty else {
            return unalignedMap(for: sentences)
        }

        let anchors = anchorRuns(book: bookTokens, transcript: spokenTokens, k: 4)
        var pairs: [(book: Int, transcript: Int)] = []
        pairs.reserveCapacity(min(bookTokens.count, spokenTokens.count))

        var bookCursor = 0
        var spokenCursor = 0
        for anchor in anchors {
            // Defensive: an anchor behind either cursor is trimmed (or skipped), so the ranges below can never
            // be inverted, whatever `anchorRuns` returns.
            let skip = max(bookCursor - anchor.book, spokenCursor - anchor.transcript, 0)
            guard skip < anchor.length else { continue }
            let anchorBook = anchor.book + skip
            let anchorTranscript = anchor.transcript + skip
            let anchorLength = anchor.length - skip

            if bookCursor < anchorBook || spokenCursor < anchorTranscript {
                alignSegment(
                    book: bookTokens, bookRange: bookCursor..<anchorBook,
                    transcript: spokenTokens, transcriptRange: spokenCursor..<anchorTranscript,
                    into: &pairs
                )
            }
            for offset in 0..<anchorLength {
                pairs.append((anchorBook + offset, anchorTranscript + offset))
            }
            bookCursor = anchorBook + anchorLength
            spokenCursor = anchorTranscript + anchorLength
        }
        if bookCursor < bookTokens.count || spokenCursor < spokenTokens.count {
            alignSegment(
                book: bookTokens, bookRange: bookCursor..<bookTokens.count,
                transcript: spokenTokens, transcriptRange: spokenCursor..<spokenTokens.count,
                into: &pairs
            )
        }

        var firstStarts = [TimeInterval?](repeating: nil, count: sentences.count)
        var lastEnds = [TimeInterval?](repeating: nil, count: sentences.count)
        for pair in pairs {
            let sentence = sentenceOfToken[pair.book]
            let start = spokenStarts[pair.transcript]
            let end = spokenEnds[pair.transcript]
            if let current = firstStarts[sentence] {
                if start < current { firstStarts[sentence] = start }
            } else {
                firstStarts[sentence] = start
            }
            if let current = lastEnds[sentence] {
                if end > current { lastEnds[sentence] = end }
            } else {
                lastEnds[sentence] = end
            }
        }

        return AlignmentMap(entries: sentences.indices.map { index in
            AlignmentEntry(id: sentences[index].id, start: firstStarts[index], end: lastEnds[index])
        })
    }

    private func unalignedMap(for sentences: [SentenceText]) -> AlignmentMap {
        AlignmentMap(entries: sentences.map {
            AlignmentEntry(id: $0.id, start: nil, end: nil)
        })
    }

    // MARK: - Anchors

    private typealias Anchor = (book: Int, transcript: Int, length: Int)

    /// Long exact runs (at least `k` tokens) that are in the same order on both sides.
    private func anchorRuns(book: [String], transcript: [String], k: Int) -> [Anchor] {
        guard k > 1, book.count >= k, transcript.count >= k else { return [] }

        let bookKGrams = kGramOccurrences(book, k: k)
        let transcriptKGrams = kGramOccurrences(transcript, k: k)

        var candidates: [(book: Int, transcript: Int)] = []
        for (hash, occurrence) in bookKGrams where occurrence.count == 1 {
            guard let other = transcriptKGrams[hash], other.count == 1 else { continue }
            guard Self.tokensEqual(book, occurrence.position, transcript, other.position, count: k) else { continue }
            candidates.append((occurrence.position, other.position))
        }
        candidates.sort { $0.book < $1.book }
        guard !candidates.isEmpty else { return [] }

        // Longest increasing subsequence on the transcript position keeps the anchors in audio order.
        var tailValues: [Int] = []
        var tailCandidates: [Int] = []
        var previous = [Int](repeating: -1, count: candidates.count)
        for (index, candidate) in candidates.enumerated() {
            var low = 0
            var high = tailValues.count
            while low < high {
                let middle = (low + high) / 2
                if tailValues[middle] < candidate.transcript {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            previous[index] = low > 0 ? tailCandidates[low - 1] : -1
            if low == tailValues.count {
                tailValues.append(candidate.transcript)
                tailCandidates.append(index)
            } else {
                tailValues[low] = candidate.transcript
                tailCandidates[low] = index
            }
        }

        var selected: [(book: Int, transcript: Int)] = []
        var cursor = tailCandidates.last ?? -1
        while cursor >= 0 {
            selected.append(candidates[cursor])
            cursor = previous[cursor]
        }
        selected.reverse()

        // Overlapping and adjacent candidates become one run.
        var runs: [Anchor] = []
        for candidate in selected {
            if let last = runs.last {
                // A candidate that starts inside the previous run cannot be a separate run: with a different
                // transcript offset it would make the book and audio cursors disagree, so drop it.
                if candidate.book < last.book + last.length
                    || candidate.transcript < last.transcript + last.length {
                    continue
                }
                if candidate.book == last.book + last.length,
                   candidate.transcript == last.transcript + last.length {
                    runs[runs.count - 1].length += k
                    continue
                }
            }
            runs.append((candidate.book, candidate.transcript, k))
        }

        // Follow each run forward so the last tokens of a chapter are anchored too.
        for index in runs.indices {
            var run = runs[index]
            let bookLimit = index + 1 < runs.count ? runs[index + 1].book : book.count
            let transcriptLimit = index + 1 < runs.count ? runs[index + 1].transcript : transcript.count
            while run.book + run.length < bookLimit,
                  run.transcript + run.length < transcriptLimit,
                  book[run.book + run.length] == transcript[run.transcript + run.length] {
                run.length += 1
            }
            runs[index] = run
        }
        return runs
    }

    private func kGramOccurrences(
        _ tokens: [String],
        k: Int
    ) -> [Int: (count: Int, position: Int)] {
        var occurrences: [Int: (count: Int, position: Int)] = [:]
        occurrences.reserveCapacity(tokens.count)
        for position in 0...(tokens.count - k) {
            var hasher = Hasher()
            for offset in 0..<k {
                hasher.combine(tokens[position + offset])
            }
            let hash = hasher.finalize()
            if let existing = occurrences[hash] {
                occurrences[hash] = (existing.count + 1, existing.position)
            } else {
                occurrences[hash] = (1, position)
            }
        }
        return occurrences
    }

    private static func tokensEqual(
        _ lhs: [String], _ lhsStart: Int,
        _ rhs: [String], _ rhsStart: Int,
        count: Int
    ) -> Bool {
        var offset = 0
        while offset < count {
            if lhs[lhsStart + offset] != rhs[rhsStart + offset] { return false }
            offset += 1
        }
        return true
    }

    // MARK: - Between anchors

    private func alignSegment(
        book: [String], bookRange: Range<Int>,
        transcript: [String], transcriptRange: Range<Int>,
        into pairs: inout [(book: Int, transcript: Int)]
    ) {
        let n = bookRange.count
        let m = transcriptRange.count
        guard n > 0, m > 0 else { return }

        // The band is centred on the straight line between the segment's ends. A long insertion (or deletion) at one
        // point pushes the path away from that line by up to the whole length difference, so the band must cover it.
        // Directions are one byte per cell; keep the worst case near 50 MB and shrink the band only for absurdly
        // longer streams.
        let cellBudget = 50_000_000
        let maxBand = max(32, (cellBudget / (n + 1) - 1) / 2)
        let band = min(abs(n - m) + 64, maxBand)
        let stride = 2 * band + 1
        let negative = Int.min / 4

        func center(_ row: Int) -> Int { (row * m + n / 2) / n }
        func bandRange(_ row: Int) -> (low: Int, high: Int) {
            (max(0, center(row) - band), min(m, center(row) + band))
        }

        var previous = [Int](repeating: negative, count: m + 1)
        var current = [Int](repeating: negative, count: m + 1)
        var directions = [UInt8](repeating: 0, count: (n + 1) * stride)

        previous[0] = 0
        var previousLow = 0
        var previousHigh = 0
        let firstHigh = bandRange(0).high
        if firstHigh >= 1 {
            for column in 1...firstHigh {
                previous[column] = -column
            }
            previousHigh = firstHigh
        }

        for row in 1...n {
            let (low, high) = bandRange(row)
            let rowCenter = center(row)
            for column in low...high {
                var best = negative
                var direction: UInt8 = 0

                if column > 0,
                   column - 1 >= previousLow, column - 1 <= previousHigh,
                   previous[column - 1] > negative {
                    let same = book[bookRange.lowerBound + row - 1]
                        == transcript[transcriptRange.lowerBound + column - 1]
                    best = previous[column - 1] + (same ? 2 : -1)
                    direction = 0
                }
                if column >= previousLow, column <= previousHigh, previous[column] > negative {
                    let value = previous[column] - 1
                    if value > best {
                        best = value
                        direction = 1
                    }
                }
                if column > low, current[column - 1] > negative {
                    let value = current[column - 1] - 1
                    if value > best {
                        best = value
                        direction = 2
                    }
                }

                current[column] = best
                directions[row * stride + (column - rowCenter + band)] = direction
            }
            swap(&previous, &current)
            previousLow = low
            previousHigh = high
        }

        var row = n
        var column = m
        var reversed: [(book: Int, transcript: Int)] = []
        while row > 0 || column > 0 {
            if row == 0 {
                column -= 1
                continue
            }
            if column == 0 {
                row -= 1
                continue
            }
            let offset = column - center(row) + band
            guard offset >= 0, offset < stride else {
                row -= 1
                continue
            }
            switch directions[row * stride + offset] {
            case 0:
                reversed.append((
                    book: bookRange.lowerBound + row - 1,
                    transcript: transcriptRange.lowerBound + column - 1
                ))
                row -= 1
                column -= 1
            case 1:
                row -= 1
            default:
                column -= 1
            }
        }
        pairs.append(contentsOf: reversed.reversed())
    }
}
