import Foundation

/// Picks the engine the app should use, given what this device supports.
///
/// The checks themselves need `Speech` and only compile on iOS, so they stay in the app target; the order — iOS 26
/// `SpeechAnalyzer` first, the legacy recognizer second, otherwise a clear error — lives here and is tested with
/// `swift test` on the Mac.
public struct TranscriberChooser: Sendable {
    public init() {}

    /// Chooses the best available engine.
    ///
    /// - Parameters:
    ///   - speechAnalyzerAvailable: `SpeechAnalyzer`/`SpeechTranscriber` can run on this device right now.
    ///   - legacyOnDeviceAvailable: `SFSpeechRecognizer` supports on-device recognition for the locale.
    /// - Throws: `TranscriptionError.unavailableOnDevice` when neither engine can work.
    public func choose(
        speechAnalyzerAvailable: Bool,
        legacyOnDeviceAvailable: Bool
    ) throws -> TranscriptionEngine {
        if speechAnalyzerAvailable { return .speechAnalyzer }
        if legacyOnDeviceAvailable { return .legacySpeechRecognizer }
        throw TranscriptionError.unavailableOnDevice
    }
}
