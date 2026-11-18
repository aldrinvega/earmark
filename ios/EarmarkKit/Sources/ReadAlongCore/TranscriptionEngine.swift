import Foundation

/// The speech-to-text engines the app can use, in the order it prefers them.
///
/// `speechAnalyzer` is the iOS 26 `SpeechAnalyzer` + `SpeechTranscriber` engine; `legacySpeechRecognizer` is
/// `SFSpeechRecognizer` with on-device recognition forced on. Both keep the audio on the phone.
public enum TranscriptionEngine: String, Sendable, CaseIterable {
    /// iOS 26 `SpeechAnalyzer` with `SpeechTranscriber` (the long-form on-device model).
    case speechAnalyzer
    /// `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`.
    case legacySpeechRecognizer

    /// The engine name as the Diagnostics screen shows it.
    public var displayName: String {
        switch self {
        case .speechAnalyzer: "SpeechAnalyzer (on-device)"
        case .legacySpeechRecognizer: "SFSpeechRecognizer (on-device)"
        }
    }
}
