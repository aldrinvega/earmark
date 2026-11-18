import Foundation
import ReadAlongCore
import Speech

/// The pre-iOS-26 engine: `SFSpeechRecognizer` with on-device recognition forced on.
///
/// This is the fallback for a device (or locale) the iOS 26 `SpeechAnalyzer` model cannot serve. It refuses to run
/// when `supportsOnDeviceRecognition` is false rather than letting a request reach Apple's servers:
/// `requiresOnDeviceRecognition` is always true, and nothing here ever removes that guard.
struct LegacySpeechTranscriber: Transcribing {
    /// English (US) for the first Earmark build; the EPUB's language will pick this later.
    let locale: Locale

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    /// Whether this device can recognise speech on device for `locale` with the legacy engine.
    static func isAvailable(for locale: Locale = Locale(identifier: "en-US")) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
        return recognizer.supportsOnDeviceRecognition
    }

    func transcribe(audioFile: URL) async throws -> [TranscriptWord] {
        if Task.isCancelled { throw TranscriptionError.cancelled }

        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscriptionError.unsupportedLocale
        }
        // The whole point of this adapter: no audio leaves the iPhone. If the on-device model is missing, say so
        // instead of falling back to the server.
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.unavailableOnDevice
        }

        try await SpeechRecognitionAuthorization.ensureAuthorized()
        if Task.isCancelled { throw TranscriptionError.cancelled }

        let request = SFSpeechURLRecognitionRequest(url: audioFile)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        let session = RecognitionSession()
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    session.install(continuation)
                    let task = recognizer.recognitionTask(with: request) { result, error in
                        if let error {
                            session.fail(error: error)
                        } else if let result, result.isFinal {
                            session.finish(words: Self.words(from: result))
                        }
                    }
                    session.attach(task)
                }
            } onCancel: {
                session.cancel()
            }
        } catch {
            if Task.isCancelled || error is CancellationError {
                throw TranscriptionError.cancelled
            }
            if let transcriptionError = error as? TranscriptionError {
                throw transcriptionError
            }
            throw TranscriptionError.failed(error.localizedDescription)
        }
    }

    /// One `TranscriptWord` per final segment, with the segment's own start and duration.
    private static func words(from result: SFSpeechRecognitionResult) -> [TranscriptWord] {
        result.bestTranscription.segments.compactMap { segment in
            let text = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TranscriptWord(
                text: text,
                start: segment.timestamp,
                end: segment.timestamp + segment.duration
            )
        }
    }

    /// Holds the continuation and recognition task so cancellation can stop the engine and resume exactly once.
    ///
    /// `SFSpeechRecognitionTask` is not `Sendable`, so both it and the continuation are only touched while holding
    /// the lock; the class crosses task boundaries (the recognition callback and the cancellation handler) by design.
    private final class RecognitionSession: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<[TranscriptWord], any Error>?
        private var task: SFSpeechRecognitionTask?
        private var isCancelled = false

        func install(_ continuation: CheckedContinuation<[TranscriptWord], any Error>) {
            lock.lock()
            if isCancelled {
                lock.unlock()
                continuation.resume(throwing: TranscriptionError.cancelled)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func attach(_ task: SFSpeechRecognitionTask) {
            lock.lock()
            if isCancelled {
                lock.unlock()
                task.cancel()
                return
            }
            self.task = task
            lock.unlock()
        }

        func finish(words: [TranscriptWord]) {
            takeContinuation()?.resume(returning: words)
        }

        func fail(error: any Error) {
            takeContinuation()?.resume(throwing: error)
        }

        func cancel() {
            lock.lock()
            isCancelled = true
            let task = self.task
            self.task = nil
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()

            task?.cancel()
            continuation?.resume(throwing: TranscriptionError.cancelled)
        }

        /// Removes and returns the continuation, so a late engine callback cannot resume it a second time.
        private func takeContinuation() -> CheckedContinuation<[TranscriptWord], any Error>? {
            lock.lock()
            defer { lock.unlock() }
            let continuation = self.continuation
            self.continuation = nil
            self.task = nil
            return continuation
        }
    }
}
