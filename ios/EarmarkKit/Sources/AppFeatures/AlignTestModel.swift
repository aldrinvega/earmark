import Foundation
import Observation
import Models
import ReadAlongCore
import EPUBCore

/// Settings → Diagnostics → "Align test chapter" (tasks/todo.md Task 8).
///
/// Runs each available on-device engine over the bundled public-domain clip, aligns the words to the bundled chapter,
/// and scores the result against the reference starts. Engines run one after another, so their timings don't
/// compete; one engine failing never stops the next. The whole run can be cancelled, and each engine has a timeout,
/// so the screen never hangs.
@MainActor @Observable
public final class AlignTestModel {
    public private(set) var runs: [EngineRun]
    public private(set) var isRunning = false
    /// Why the test cannot run at all (no engine, unreadable fixture); shown instead of the Run button.
    public private(set) var setupError: String?
    public private(set) var sentences: [SentenceText] = []
    /// The verdict of the best engine, once at least one finished.
    public private(set) var overallVerdict: SpikeVerdict?

    private let engines: [NamedTranscriber]
    private let audioFile: URL
    private let audioDuration: TimeInterval
    private let timeout: Duration
    private var expected: ExpectedStarts?
    private var bestMap: AlignmentMap?
    private var bestFraction = -1.0
    private var task: Task<Void, Never>?

    public init(
        engines: [NamedTranscriber],
        audioFile: URL,
        audioDuration: TimeInterval,
        chapter: Data,
        expectedStarts: Data,
        timeout: Duration = .seconds(600)
    ) {
        self.engines = engines
        self.audioFile = audioFile
        self.audioDuration = audioDuration
        self.timeout = timeout
        runs = engines.map { EngineRun(id: $0.name) }
        do {
            expected = try JSONDecoder().decode(ExpectedStarts.self, from: expectedStarts)
            let paragraphs = try XHTMLText().paragraphs(in: chapter)
            sentences = SentenceSplitter().sentenceTexts(in: paragraphs, spine: 0)
        } catch {
            setupError = AlignTestError.badFixture(error.localizedDescription).localizedDescription
            return
        }
        if engines.isEmpty {
            setupError = AlignTestError.noEngine.localizedDescription
        }
    }

    /// Starts a run in the background; the screen observes `runs` and `isRunning`.
    public func start() {
        guard !isRunning, setupError == nil else { return }
        isRunning = true
        task = Task { await self.runEngines() }
    }

    /// Runs every engine and returns when they are all done (used by `start()` and by tests).
    public func run() async {
        guard setupError == nil else { return }
        if !isRunning {
            isRunning = true
        }
        await runEngines()
    }

    public func cancel() {
        task?.cancel()
    }

    /// Waits for a run started with `start()` to finish or be cancelled.
    public func waitUntilIdle() async {
        await task?.value
    }

    /// The sentence being read at `time`, from the best-scoring engine's alignment (for live playback).
    public func sentence(at time: TimeInterval) -> SentenceText? {
        guard let id = bestMap?.sentence(at: time) else { return nil }
        return sentences.first { $0.id == id }
    }

    private func runEngines() async {
        defer {
            isRunning = false
            task = nil
        }
        guard let expected else { return }
        for index in engines.indices {
            if Task.isCancelled {
                markUnfinishedCancelled(from: index)
                return
            }
            runs[index] = EngineRun(id: engines[index].name)
            runs[index].state = .running
            do {
                let result = try await Self.process(
                    engines[index].transcriber, audioFile: audioFile, sentences: sentences, timeout: timeout
                )
                let score = AlignmentScore(map: result.map, expected: expected)
                let perMinute = result.seconds / max(audioDuration, 1) * 60
                runs[index].words = result.words.count
                runs[index].preview = result.words.prefix(14).map(\.text).joined(separator: " ")
                runs[index].heardFrom = result.words.first?.start
                runs[index].heardUntil = result.words.last?.end
                runs[index].processingSeconds = result.seconds
                runs[index].secondsPerAudioMinute = perMinute
                runs[index].score = score
                let verdict = SpikeVerdict(fraction: score.fraction, secondsPerAudioMinute: perMinute)
                runs[index].verdict = verdict
                runs[index].state = .finished
                if score.fraction > bestFraction {
                    bestFraction = score.fraction
                    bestMap = result.map
                }
                if overallVerdict != .go { overallVerdict = verdict }
            } catch {
                if Task.isCancelled || (error as? TranscriptionError) == .cancelled || error is CancellationError {
                    markUnfinishedCancelled(from: index)
                    return
                }
                runs[index].state = .failed(error.localizedDescription)
            }
        }
    }

    private func markUnfinishedCancelled(from index: Int) {
        for later in index..<runs.count where runs[later].state == .running || runs[later].state == .waiting {
            runs[later].state = .cancelled
        }
    }

    /// Speech-to-text with a timeout, then alignment — off the main actor.
    private nonisolated static func process(
        _ transcriber: any Transcribing,
        audioFile: URL,
        sentences: [SentenceText],
        timeout: Duration
    ) async throws -> (words: [TranscriptWord], map: AlignmentMap, seconds: Double) {
        let clock = ContinuousClock()
        let started = clock.now
        let words = try await withThrowingTaskGroup(of: [TranscriptWord].self) { group in
            group.addTask { try await transcriber.transcribe(audioFile: audioFile) }
            group.addTask {
                try await Task.sleep(for: timeout)
                let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
                throw AlignTestError.timedOut(seconds: seconds)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TranscriptionError.cancelled }
            return first
        }
        try Task.checkCancellation()
        let map = Aligner().align(transcript: words, sentences: sentences)
        let elapsed = started.duration(to: clock.now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return (words, map, seconds)
    }
}
