import Foundation
import Models

/// Where one sentence sits in the chapter's audio, or "unaligned" when no word of it was matched.
///
/// Unaligned sentences keep their place in `AlignmentMap.entries` so the reader can show them in order; they simply
/// have no start or end.
public struct AlignmentEntry: Hashable, Sendable, Codable {
    public let id: SentenceID
    /// Seconds from the start of the chapter's audio, or nil when the sentence was not matched.
    public let start: TimeInterval?
    /// Seconds from the start of the chapter's audio, or nil when the sentence was not matched.
    public let end: TimeInterval?

    public init(id: SentenceID, start: TimeInterval?, end: TimeInterval?) {
        self.id = id
        self.start = start
        self.end = end
    }

    public var isAligned: Bool { start != nil }
}
