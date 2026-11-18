import Foundation
import Models

/// Reference sentence start times for a test clip (`pp-ch3-expected-starts.json`), used to score an alignment.
public struct ExpectedStarts: Decodable, Sendable, Equatable {
    public struct Start: Decodable, Sendable, Equatable {
        public let id: SentenceID
        public let start: TimeInterval

        public init(id: SentenceID, start: TimeInterval) {
            self.id = id
            self.start = start
        }
    }

    public let clip: String
    public let chapter: String
    /// How far a computed start may be from the reference and still count as right.
    public let toleranceSeconds: Double
    public let starts: [Start]

    public init(clip: String, chapter: String, toleranceSeconds: Double, starts: [Start]) {
        self.clip = clip
        self.chapter = chapter
        self.toleranceSeconds = toleranceSeconds
        self.starts = starts
    }
}
