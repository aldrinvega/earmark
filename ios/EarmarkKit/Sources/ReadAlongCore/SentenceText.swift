import Foundation
import Models

/// One EPUB sentence and its text, before alignment: the input side of `Aligner`.
public struct SentenceText: Hashable, Sendable, Codable {
    public let id: SentenceID
    public let text: String

    public init(id: SentenceID, text: String) {
        self.id = id
        self.text = text
    }
}
