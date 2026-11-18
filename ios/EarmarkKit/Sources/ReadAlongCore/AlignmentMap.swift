import Foundation
import Models

/// The alignment of one EPUB chapter: every sentence in reading order, with its audio start and end or "unaligned".
///
/// It is cached as one JSON file per chapter, so it encodes only `entries` (in reading order; `SentenceID` is the
/// string form `"spine.paragraph.sentence"`). The reader asks two questions, and nothing else:
/// `startTime(of:)` for tap-to-seek and `sentence(at:)` for the live highlight.
public struct AlignmentMap: Sendable {
    /// One entry per input sentence, in reading order, unaligned sentences included.
    public let entries: [AlignmentEntry]

    /// Entries with a start, sorted by start time. Parallel to `alignedStarts`.
    private let alignedEntries: [AlignmentEntry]
    private let alignedStarts: [TimeInterval]
    private let indexByID: [SentenceID: Int]
    private let maxEnd: TimeInterval?

    public init(entries: [AlignmentEntry]) {
        self.entries = entries

        var indexByID: [SentenceID: Int] = [:]
        for (index, entry) in entries.enumerated() where indexByID[entry.id] == nil {
            indexByID[entry.id] = index
        }
        self.indexByID = indexByID

        var order: [Int] = []
        var starts: [TimeInterval] = []
        for (index, entry) in entries.enumerated() {
            if let start = entry.start {
                order.append(index)
                starts.append(start)
            }
        }
        let sorted = order.indices.sorted {
            starts[$0] == starts[$1] ? order[$0] < order[$1] : starts[$0] < starts[$1]
        }
        self.alignedEntries = sorted.map { entries[order[$0]] }
        self.alignedStarts = sorted.map { starts[$0] }

        // A start without an end is still aligned (as `isAligned` and `startTime(of:)` say). If the last sentence
        // is open-ended, the chapter has no known end, so the lookup has no upper bound either.
        var latestEnd: TimeInterval?
        for entry in entries {
            guard let end = entry.end else { continue }
            if let current = latestEnd {
                if end > current { latestEnd = end }
            } else {
                latestEnd = end
            }
        }
        self.maxEnd = alignedEntries.last?.end == nil ? nil : latestEnd
    }

    /// The sentence being narrated at `time`, or nil before the first aligned start and after the last known end.
    ///
    /// Once a sentence starts it stays current through the pause before the next aligned sentence, so the highlight
    /// does not blink off between sentences. Unaligned sentences are never returned. A last sentence without an end
    /// (a partial cache) is treated as open-ended.
    public func sentence(at time: TimeInterval) -> SentenceID? {
        guard let firstStart = alignedStarts.first, time >= firstStart else { return nil }
        if let lastEnd = maxEnd, time > lastEnd { return nil }

        var low = 0
        var high = alignedStarts.count - 1
        var found = 0
        while low <= high {
            let middle = (low + high) / 2
            if alignedStarts[middle] <= time {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return alignedEntries[found].id
    }

    /// Where the sentence starts in the chapter's audio, or nil when it is unaligned or not in this chapter.
    public func startTime(of id: SentenceID) -> TimeInterval? {
        guard let index = indexByID[id] else { return nil }
        return entries[index].start
    }
}

extension AlignmentMap: Codable {
    private enum CodingKeys: String, CodingKey {
        case entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(entries: try container.decode([AlignmentEntry].self, forKey: .entries))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
    }
}
