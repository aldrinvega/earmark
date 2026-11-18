import Foundation
import ReadAlongCore
import Speech

/// Asks for Speech Recognition permission, once, through the same system prompt the Settings app controls.
///
/// Both engines use the `Speech` framework, so the app needs `NSSpeechRecognitionUsageDescription` (in
/// `ios/project.yml`) and the person's yes. The wrapper keeps the callback API out of the adapters and gives the
/// package's typed error.
enum SpeechRecognitionAuthorization {
    /// Returns when the app may recognise speech; asks the person if they have not decided yet.
    ///
    /// - Throws: `TranscriptionError.notAuthorized` when permission is denied or restricted.
    static func ensureAuthorized() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .notDetermined:
            let status = await requestAuthorization()
            guard status == .authorized else { throw TranscriptionError.notAuthorized }
        case .denied, .restricted:
            throw TranscriptionError.notAuthorized
        @unknown default:
            throw TranscriptionError.notAuthorized
        }
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
