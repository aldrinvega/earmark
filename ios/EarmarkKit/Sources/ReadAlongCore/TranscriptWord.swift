import Foundation

/// One word from speech-to-text, with the time it is spoken in the chapter's audio.
///
/// `text` is the word as the transcriber heard it (punctuation included); `TextNormalizer` turns it into the tokens
/// the aligner compares against the EPUB.
public struct TranscriptWord: Hashable, Sendable, Codable {
    public let text: String
    /// Start in seconds from the beginning of the chapter's audio.
    public let start: TimeInterval
    /// End in seconds from the beginning of the chapter's audio.
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}
