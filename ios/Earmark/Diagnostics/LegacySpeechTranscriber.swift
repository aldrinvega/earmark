import AVFoundation
import Foundation
import ReadAlongCore
import Speech

/// The pre-iOS-26 engine: `SFSpeechRecognizer` with on-device recognition forced on.
///
/// This is the fallback for a device (or locale) the iOS 26 `SpeechAnalyzer` model cannot serve. It refuses to run
/// when `supportsOnDeviceRecognition` is false rather than letting a request reach Apple's servers:
/// `requiresOnDeviceRecognition` is always true, and nothing here ever removes that guard.
///
/// The file is fed through `SFSpeechAudioBufferRecognitionRequest`, not `SFSpeechURLRecognitionRequest`: a URL request
/// ends at the first pause it treats as the end of an utterance (spike run 1 heard 4 words of a 3-minute clip). A
/// buffer request keeps listening until `endAudio()`, and the words of every final result are collected.
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

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: audioFile)
        } catch {
            throw TranscriptionError.failed("Could not open the audio: \(error.localizedDescription)")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        let session = RecognitionSession()
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    session.install(continuation)
                    let task = recognizer.recognitionTask(with: request) { result, error in
                        session.handle(result: result, error: error)
                    }
                    session.attach(task)
                    do {
                        try Self.feed(file, into: request, session: session)
                    } catch {
                        session.fail(error: TranscriptionError.failed(
                            "Could not read the audio: \(error.localizedDescription)"))
                        return
                    }
                    request.endAudio()
                    session.audioDidEnd()
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

    /// Appends the whole file to the request in small buffers, in the file's own processing format.
    private static func feed(
        _ file: AVAudioFile,
        into request: SFSpeechAudioBufferRecognitionRequest,
        session: RecognitionSession
    ) throws {
        let chunk: AVAudioFrameCount = 8192
        while file.framePosition < file.length {
            if session.isCancelled { return }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else {
                throw TranscriptionError.failed("Could not allocate an audio buffer.")
            }
            try file.read(into: buffer, frameCount: chunk)
            if buffer.frameLength == 0 { break }
            request.append(buffer)
        }
    }

    /// Collects words from every result, and resumes the caller exactly once: after the audio has ended and the
    /// recognizer has delivered its final result (or an error), or on cancellation.
    ///
    /// `SFSpeechRecognitionTask` is not `Sendable`, so it and the continuation are only touched while holding the lock;
    /// the class crosses the recognition callback, the feeding code and the cancellation handler by design.
    private final class RecognitionSession: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<[TranscriptWord], any Error>?
        private var task: SFSpeechRecognitionTask?
        private var cancelled = false
        private var audioEnded = false
        private var finalSeen = false
        private var lastError: (any Error)?
        /// Words keyed by start time in milliseconds, so repeated final results don't duplicate them.
        private var words: [Int: TranscriptWord] = [:]

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func install(_ continuation: CheckedContinuation<[TranscriptWord], any Error>) {
            lock.lock()
            if cancelled {
                lock.unlock()
                continuation.resume(throwing: TranscriptionError.cancelled)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func attach(_ task: SFSpeechRecognitionTask) {
            lock.lock()
            if cancelled {
                lock.unlock()
                task.cancel()
                return
            }
            self.task = task
            lock.unlock()
        }

        func handle(result: SFSpeechRecognitionResult?, error: (any Error)?) {
            lock.lock()
            if let result {
                for segment in result.bestTranscription.segments {
                    let text = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let key = Int((segment.timestamp * 1000).rounded())
                    words[key] = TranscriptWord(
                        text: text, start: segment.timestamp, end: segment.timestamp + segment.duration)
                }
                if result.isFinal { finalSeen = true }
            }
            if let error { lastError = error }
            let outcome = finishIfDone()
            lock.unlock()
            outcome?()
        }

        func audioDidEnd() {
            lock.lock()
            audioEnded = true
            let outcome = finishIfDone()
            lock.unlock()
            outcome?()
        }

        func fail(error: any Error) {
            lock.lock()
            let continuation = takeContinuation()
            lock.unlock()
            continuation?.resume(throwing: error)
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let task = self.task
            self.task = nil
            let continuation = takeContinuation()
            lock.unlock()
            task?.cancel()
            continuation?.resume(throwing: TranscriptionError.cancelled)
        }

        /// Called with the lock held. Returns the resume action once the audio has ended and the recognizer is done.
        private func finishIfDone() -> (() -> Void)? {
            guard audioEnded, finalSeen || lastError != nil, let continuation = takeContinuation() else { return nil }
            let collected = words.values.sorted { $0.start < $1.start }
            if !collected.isEmpty {
                return { continuation.resume(returning: collected) }
            }
            let error = lastError ?? TranscriptionError.failed("The recognizer heard no speech.")
            return { continuation.resume(throwing: error) }
        }

        /// Called with the lock held. Removes and returns the continuation so it is resumed at most once.
        private func takeContinuation() -> CheckedContinuation<[TranscriptWord], any Error>? {
            let continuation = self.continuation
            self.continuation = nil
            if continuation != nil { task = nil }
            return continuation
        }
    }
}
