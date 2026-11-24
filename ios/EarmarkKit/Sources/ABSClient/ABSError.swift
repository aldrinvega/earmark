import Foundation

/// What can go wrong talking to Audiobookshelf. User-facing wording lives in `AppFeatures`.
public enum ABSError: Error, Equatable, Sendable {
    /// The server could not be reached (Mac off, tailnet down).
    case unreachable
    /// Wrong credentials, or the session cannot be renewed: sign in again.
    case unauthorized
    case notFound
    case decoding(String)
    case server(status: Int)
}
