import Foundation
import ReadAlongCore

/// The app-side half of the engine choice: checks what this device supports and builds that transcriber.
///
/// The preference order itself is `TranscriberChooser` in `ReadAlongCore` (tested with `swift test`); this type only
/// supplies the `Speech` availability checks, which need iOS.
struct DeviceTranscriberChooser: Sendable {
    /// English (US) for the first Earmark build.
    let locale: Locale

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    /// The best on-device transcriber this device can run.
    ///
    /// - Throws: `TranscriptionError.unavailableOnDevice` when neither engine can work on this iPhone.
    func makeTranscriber() throws -> any Transcribing {
        let engine = try TranscriberChooser().choose(
            speechAnalyzerAvailable: SpeechAnalyzerTranscriber.isAvailable,
            legacyOnDeviceAvailable: LegacySpeechTranscriber.isAvailable(for: locale)
        )
        switch engine {
        case .speechAnalyzer:
            return SpeechAnalyzerTranscriber(locale: locale)
        case .legacySpeechRecognizer:
            return LegacySpeechTranscriber(locale: locale)
        }
    }
}
