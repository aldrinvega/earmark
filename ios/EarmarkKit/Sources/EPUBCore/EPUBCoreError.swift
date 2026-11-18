import Foundation

/// The typed failure of `EPUBCore`. A chapter that is not well-formed XML fails with this, never with a crash.
public enum EPUBCoreError: Error, Equatable, Sendable {
    /// `XMLParser` rejected the chapter, or the bytes were not a supported text encoding.
    case malformedXHTML(String)
}

extension EPUBCoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .malformedXHTML(let reason):
            "The chapter is not well-formed XHTML: \(reason)"
        }
    }
}
