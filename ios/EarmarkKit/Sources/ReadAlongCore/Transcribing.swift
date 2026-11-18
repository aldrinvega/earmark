import Foundation

/// Turns one audio file into the words the aligner compares against the EPUB.
///
/// An implementation is one of the on-device speech engines (or a fake in tests). Audio must never leave the device:
/// both app adapters force on-device recognition, and this package only knows about local file URLs.
///
/// Implementations must honour Task cancellation: check `Task.isCancelled` (or `Task.checkCancellation()`) between
/// steps, stop the recognition they started, and throw `TranscriptionError.cancelled` — not a bare
/// `CancellationError` — so callers only have to handle one error type.
public protocol Transcribing: Sendable {
    /// Transcribes the whole audio file and returns its words in spoken order with their times.
    ///
    /// - Parameter audioFile: A local file URL the process can read.
    /// - Throws: `TranscriptionError` for the expected failures: permission, an unavailable engine, an unsupported
    ///   locale, a failed recognition, or cancellation of the calling task.
    func transcribe(audioFile: URL) async throws -> [TranscriptWord]
}
