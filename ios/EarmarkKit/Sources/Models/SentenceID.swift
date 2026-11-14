/// Identifies one sentence of an EPUB: `<spine index>.<paragraph index>.<sentence index>`, all zero-based.
///
/// It is the key shared by the reader, the aligner, the recap and saved progress, so it is computed the same way every
/// time from the same EPUB (see EPUBCore) and stored as its string form, e.g. `"4.12.3"`.
public struct SentenceID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let spine: Int
    public let paragraph: Int
    public let sentence: Int

    public init(spine: Int, paragraph: Int, sentence: Int) {
        precondition(spine >= 0 && paragraph >= 0 && sentence >= 0, "SentenceID parts are zero-based indexes")
        self.spine = spine
        self.paragraph = paragraph
        self.sentence = sentence
    }

    /// Parses the string form. Returns nil unless it is exactly three non-negative decimal integers joined by dots.
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var values: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCIIDigit), let value = Int(part) else { return nil }
            values.append(value)
        }
        self.init(spine: values[0], paragraph: values[1], sentence: values[2])
    }

    public var description: String { "\(spine).\(paragraph).\(sentence)" }

    /// Reading order: spine item, then paragraph, then sentence.
    public static func < (lhs: SentenceID, rhs: SentenceID) -> Bool {
        (lhs.spine, lhs.paragraph, lhs.sentence) < (rhs.spine, rhs.paragraph, rhs.sentence)
    }
}

extension SentenceID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let id = SentenceID(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a sentence ID: \(text)")
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isWholeNumber }
}
