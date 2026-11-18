import Foundation
@testable import ReadAlongCore

/// A transcriber with no audio at all: it hands back words with made-up timings, so tests can drive the real
/// `Aligner` through the `Transcribing` protocol and test failure/cancellation paths without a Speech engine.
struct FakeTranscriber: Transcribing {
    enum Behaviour: Sendable {
        /// Return the words immediately.
        case succeed
        /// Throw this error instead of transcribing.
        case fail(TranscriptionError)
        /// Wait until the calling task is cancelled, then throw `.cancelled`.
        case waitForCancellation
    }

    let words: [TranscriptWord]
    let behaviour: Behaviour

    /// Builds words from plain text: `start` for the first word, then `wordDuration` of speech and `gap` of silence.
    init(
        text: String,
        start: TimeInterval = 0.5,
        wordDuration: TimeInterval = 0.3,
        gap: TimeInterval = 0.1
    ) {
        var time = start
        var words: [TranscriptWord] = []
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            words.append(TranscriptWord(text: String(token), start: time, end: time + wordDuration))
            time += wordDuration + gap
        }
        self.words = words
        self.behaviour = .succeed
    }

    init(words: [TranscriptWord], behaviour: Behaviour = .succeed) {
        self.words = words
        self.behaviour = behaviour
    }

    func transcribe(audioFile: URL) async throws -> [TranscriptWord] {
        switch behaviour {
        case .succeed:
            if Task.isCancelled { throw TranscriptionError.cancelled }
            return words
        case .fail(let error):
            throw error
        case .waitForCancellation:
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                throw TranscriptionError.cancelled
            }
            throw TranscriptionError.cancelled
        }
    }
}
