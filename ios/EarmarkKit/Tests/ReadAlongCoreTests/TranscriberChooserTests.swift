import Testing
@testable import ReadAlongCore

/// The engine order: the iOS 26 analyzer wins, the legacy recognizer is the fallback, and no engine is an error.
@Suite struct TranscriberChooserTests {
    private let chooser = TranscriberChooser()

    @Test func prefersSpeechAnalyzerWhenThisDeviceSupportsIt() throws {
        let engine = try chooser.choose(
            speechAnalyzerAvailable: true,
            legacyOnDeviceAvailable: true
        )
        #expect(engine == .speechAnalyzer)
    }

    @Test func fallsBackToTheLegacyRecognizerWithOnDeviceSupport() throws {
        let engine = try chooser.choose(
            speechAnalyzerAvailable: false,
            legacyOnDeviceAvailable: true
        )
        #expect(engine == .legacySpeechRecognizer)
    }

    @Test func noOnDeviceEngineIsAClearError() {
        #expect(throws: TranscriptionError.unavailableOnDevice) {
            try chooser.choose(
                speechAnalyzerAvailable: false,
                legacyOnDeviceAvailable: false
            )
        }
    }

    @Test func engineNamesSayTheyRunOnDevice() {
        for engine in TranscriptionEngine.allCases {
            #expect(engine.displayName.contains("on-device"))
        }
    }
}
