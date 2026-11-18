import Foundation
import Testing
import Models
@testable import ReadAlongCore

/// The contract the app's Speech adapters implement, exercised with a fake: the aligner runs end to end through the
/// protocol, cancellation is `.cancelled`, and engine errors reach the caller unchanged.
@Suite struct TranscribingTests {
    private let audioFile = URL(fileURLWithPath: "/tmp/chapter.m4a")

    @Test func aFakeTranscriberDrivesTheAlignerEndToEnd() async throws {
        let transcriber = FakeTranscriber(
            text: "The door opened. Elizabeth looked up. Mister Darcy said nothing."
        )
        let words = try await transcriber.transcribe(audioFile: audioFile)
        #expect(words.count == 10)

        let sentences = [
            SentenceText(
                id: SentenceID(spine: 0, paragraph: 0, sentence: 0),
                text: "The door opened."
            ),
            SentenceText(
                id: SentenceID(spine: 0, paragraph: 0, sentence: 1),
                text: "Elizabeth looked up."
            ),
            SentenceText(
                id: SentenceID(spine: 0, paragraph: 0, sentence: 2),
                text: "Mr. Darcy said nothing."
            ),
        ]

        let map = Aligner().align(transcript: words, sentences: sentences)

        #expect(map.entries.count == 3)
        #expect(map.entries.allSatisfy { $0.isAligned })
        // "Elizabeth" is the fourth spoken word, "Mister" (from "Mr.") the seventh.
        #expect(map.startTime(of: sentences[0].id) == words[0].start)
        #expect(map.startTime(of: sentences[1].id) == words[3].start)
        #expect(map.startTime(of: sentences[2].id) == words[6].start)
        #expect(map.sentence(at: words[4].start) == sentences[1].id)
        #expect(map.sentence(at: words[7].start) == sentences[2].id)
    }

    @Test func cancellationSurfacesAsCancelledNotBareCancellationError() async {
        let transcriber = FakeTranscriber(
            words: [TranscriptWord(text: "hello", start: 0, end: 0.4)],
            behaviour: .waitForCancellation
        )

        let task = Task {
            try await transcriber.transcribe(audioFile: audioFile)
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("A cancelled transcription should throw")
        } catch let error as TranscriptionError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("Expected TranscriptionError.cancelled, got \(error)")
        }
    }

    @Test func engineErrorsPropagateUnchanged() async {
        let failure = TranscriptionError.failed("the audio file is unreadable")
        let transcriber = FakeTranscriber(words: [], behaviour: .fail(failure))

        do {
            _ = try await transcriber.transcribe(audioFile: audioFile)
            Issue.record("A failed transcription should throw")
        } catch let error as TranscriptionError {
            #expect(error == failure)
        } catch {
            Issue.record("Expected TranscriptionError.failed, got \(error)")
        }
    }

    @Test func permissionAndLocaleFailuresKeepTheirCases() async {
        for expected in [TranscriptionError.notAuthorized, .unsupportedLocale, .cancelled] {
            let transcriber = FakeTranscriber(words: [], behaviour: .fail(expected))
            do {
                _ = try await transcriber.transcribe(audioFile: audioFile)
                Issue.record("Expected \(expected)")
            } catch let error as TranscriptionError {
                #expect(error == expected)
            } catch {
                Issue.record("Expected \(expected), got \(error)")
            }
        }
    }

    @Test func everyErrorHasAUserFacingSentence() {
        let errors: [TranscriptionError] = [
            .notAuthorized,
            .unavailableOnDevice,
            .unsupportedLocale,
            .failed("boom"),
            .cancelled,
        ]
        for error in errors {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
        }
    }
}
