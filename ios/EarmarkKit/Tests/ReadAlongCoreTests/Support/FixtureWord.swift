import Foundation

/// One word of a synthetic transcript, with the sentence it came from (for ground truth).
struct FixtureWord: Sendable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let sentence: Int
}
