import Foundation
import Testing
import Models
import ReadAlongCore
@testable import AppFeatures

/// Task 8: the Diagnostics "Align test chapter" logic, run with fake engines (the real ones need an iPhone).
@MainActor @Suite struct AlignTestModelTests {
    /// A tiny chapter: a heading and two paragraphs (public-domain Pride and Prejudice sentences).
    static let chapter = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><body>
        <h2>Chapter III.</h2>
        <p>Her report was highly favourable. Sir William had been delighted with him.</p>
        <p>Nothing could be more delightful!</p>
        </body></html>
        """.utf8)

    /// What a perfect transcriber hears, 0.4 s per word, starting after a 2 s preamble.
    static let spoken = "chapter three her report was highly favourable sir william had been delighted with him "
        + "nothing could be more delightful"

    static func words(_ text: String = spoken, startingAt t0: Double = 2.0) -> [TranscriptWord] {
        text.split(separator: " ").enumerated().map { index, word in
            let start = t0 + Double(index) * 0.4
            return TranscriptWord(text: String(word), start: start, end: start + 0.3)
        }
    }

    /// Reference starts matching `words()`: "her" is word 2, "sir" word 7, "nothing" word 15.
    static let expected = Data("""
        {"clip":"clip.m4a","chapter":"chapter.xhtml","toleranceSeconds":0.5,
         "starts":[{"id":"0.1.0","start":2.8},{"id":"0.1.1","start":4.8},{"id":"0.2.0","start":8.0}]}
        """.utf8)

    private func model(_ engines: [NamedTranscriber], timeout: Duration = .seconds(5)) -> AlignTestModel {
        AlignTestModel(engines: engines, audioFile: URL(fileURLWithPath: "/tmp/clip.m4a"), audioDuration: 60,
                       chapter: Self.chapter, expectedStarts: Self.expected, timeout: timeout)
    }

    @Test func aPerfectEngineScoresEveryStartAndIsAGo() async {
        let model = model([NamedTranscriber(name: "Fake", transcriber: StubTranscriber(.words(Self.words())))])
        #expect(model.setupError == nil)
        #expect(model.sentences.map(\.id.description) == ["0.0.0", "0.1.0", "0.1.1", "0.2.0"])

        await model.run()

        let run = model.runs[0]
        #expect(run.state == .finished)
        #expect(run.words == 19)
        #expect(run.score?.checked == 3)
        #expect(run.score?.withinTolerance == 3)
        #expect(run.score?.fraction == 1)
        #expect((run.secondsPerAudioMinute ?? .infinity) < 1)
        #expect(run.verdict == .go)
        #expect(model.isRunning == false)
        // Live playback follows the best engine's map.
        #expect(model.sentence(at: 5.0)?.id.description == "0.1.1")
        #expect(model.sentence(at: 0.5) == nil)
    }

    @Test func oneFailingEngineDoesNotStopTheNext() async {
        let model = model([
            NamedTranscriber(name: "Broken", transcriber: StubTranscriber(.error(.unavailableOnDevice))),
            NamedTranscriber(name: "Fake", transcriber: StubTranscriber(.words(Self.words()))),
        ])
        await model.run()
        #expect(model.runs[0].state == .failed(TranscriptionError.unavailableOnDevice.localizedDescription))
        #expect(model.runs[0].verdict == nil)
        #expect(model.runs[1].state == .finished)
        #expect(model.overallVerdict == .go)
    }

    @Test func aSlowEngineIsANoGoEvenWhenAccurate() {
        let verdict = SpikeVerdict(fraction: 1, secondsPerAudioMinute: 45)
        #expect(verdict == .noGo(reasons: ["45.0 s of processing per audio minute (limit 30)"]))
        #expect(SpikeVerdict(fraction: 0.875, secondsPerAudioMinute: 10)
            == .noGo(reasons: ["87.5% of starts within 0.5 s (needs 90%)"]))
        #expect(SpikeVerdict(fraction: 0.9, secondsPerAudioMinute: 30) == .go)
    }

    @Test func aDriftingEngineIsScoredHonestly() async {
        // Same words, but everything 2 s late: far outside the 0.5 s tolerance. (A smaller drift is muddied by the
        // heading: "Chapter III." vs spoken "three" leaves "three" unmatched — logged as a TextNormalizer follow-up.)
        let late = Self.words(startingAt: 4.0)
        let model = model([NamedTranscriber(name: "Late", transcriber: StubTranscriber(.words(late)))])
        await model.run()
        #expect(model.runs[0].score?.withinTolerance == 0)
        #expect(model.runs[0].score?.worstError == 2.0)
        #expect(model.runs[0].verdict == .noGo(reasons: ["0.0% of starts within 0.5 s (needs 90%)"]))
    }

    @Test func cancelStopsTheRunAndMarksEveryUnfinishedEngine() async {
        let model = model([
            NamedTranscriber(name: "Hangs", transcriber: StubTranscriber(.hang)),
            NamedTranscriber(name: "Never reached", transcriber: StubTranscriber(.words(Self.words()))),
        ], timeout: .seconds(30))
        model.start()
        #expect(model.isRunning)
        try? await Task.sleep(for: .milliseconds(100))
        model.cancel()
        await model.waitUntilIdle()
        #expect(model.runs.map(\.state) == [.cancelled, .cancelled])
        #expect(model.isRunning == false)
    }

    @Test func aHangingEngineTimesOut() async {
        let model = model([NamedTranscriber(name: "Hangs", transcriber: StubTranscriber(.hang))],
                          timeout: .milliseconds(200))
        await model.run()
        #expect(model.runs[0].state == .failed(AlignTestError.timedOut(seconds: 0.2).localizedDescription))
    }

    @Test func noEngineOrBadFixtureIsASetupErrorNotACrash() {
        #expect(model([]).setupError == AlignTestError.noEngine.localizedDescription)
        let broken = AlignTestModel(engines: [], audioFile: URL(fileURLWithPath: "/tmp/x.m4a"), audioDuration: 60,
                                    chapter: Data("<p>unclosed".utf8), expectedStarts: Data("{}".utf8))
        #expect(broken.setupError != nil)
    }
}

/// A transcriber that returns fixed words, throws, or never finishes (until cancelled).
struct StubTranscriber: Transcribing {
    enum Behaviour: Sendable {
        case words([TranscriptWord])
        case error(TranscriptionError)
        case hang
    }

    let behaviour: Behaviour
    init(_ behaviour: Behaviour) { self.behaviour = behaviour }

    func transcribe(audioFile: URL) async throws -> [TranscriptWord] {
        switch behaviour {
        case .words(let words):
            return words
        case .error(let error):
            throw error
        case .hang:
            do {
                try await Task.sleep(for: .seconds(3600))
            } catch {
                throw TranscriptionError.cancelled
            }
            return []
        }
    }
}
