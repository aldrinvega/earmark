import Foundation

/// The failures a `Transcribing` implementation reports.
///
/// The app turns each case into one sentence of user-facing text (the rule that strings live in the package), so
/// the Diagnostics screen and the read-along status line say the same thing. Implementations map engine-specific
/// errors to `.failed` and never leak an `SFSpeechRecognizer`/`SpeechAnalyzer` error to the caller.
public enum TranscriptionError: Error, Equatable, Sendable {
    /// The person has not granted Speech Recognition permission (or it is restricted).
    case notAuthorized
    /// The device cannot run this engine on device: no model, no permission for on-device work, or an older OS.
    case unavailableOnDevice
    /// The engine has no on-device model for the requested language.
    case unsupportedLocale
    /// The engine failed for another reason; `message` is the engine's description, for the log and Diagnostics.
    case failed(String)
    /// The calling task was cancelled before transcription finished.
    case cancelled
}

extension TranscriptionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "Earmark needs permission to recognise speech. Turn it on in Settings."
        case .unavailableOnDevice:
            "On-device speech recognition is not available on this iPhone."
        case .unsupportedLocale:
            "On-device speech recognition does not support this book's language on this iPhone."
        case .failed(let message):
            "Speech recognition failed: \(message)"
        case .cancelled:
            "Speech recognition was cancelled."
        }
    }
}
