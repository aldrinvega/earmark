import Foundation
import Testing
import EarmarkTestSupport
import EPUBCore
import Models
import ReadAlongCore
@testable import AppFeatures

/// Replays spike run 3 — the words both on-device engines heard on the owner's iPhone SE (pp-ch3-run3-report.txt) —
/// through the real splitter, aligner and scoring, so the Checkpoint B evidence is checked on every CI run.
@Suite struct RecordedSpikeRunTests {
    /// Parses the "-- words" block of each engine section: `start<TAB>end<TAB>text` per line.
    static func transcripts() throws -> [String: [TranscriptWord]] {
        let report = String(decoding: try Fixtures.data("pp-ch3-run3-report.txt"), as: UTF8.self)
        var result: [String: [TranscriptWord]] = [:]
        var engine: String?
        var inWords = false
        for line in report.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("== ") {
                engine = String(line.dropFirst(3))
                inWords = false
            } else if line.hasPrefix("-- words") {
                inWords = true
            } else if inWords, let engine {
                let fields = line.split(separator: "\t", maxSplits: 2)
                guard fields.count == 3, let start = Double(fields[0]), let end = Double(fields[1]) else { continue }
                result[engine, default: []].append(TranscriptWord(text: String(fields[2]), start: start, end: end))
            }
        }
        return result
    }

    static func sentences() throws -> [SentenceText] {
        SentenceSplitter().sentenceTexts(in: try XHTMLText().paragraphs(in: try Fixtures.data("pp-ch3.xhtml")), spine: 0)
    }

    static func expected() throws -> ExpectedStarts {
        try JSONDecoder().decode(ExpectedStarts.self, from: try Fixtures.data("pp-ch3-expected-starts.json"))
    }

    @Test func theRecordingHasBothEnginesWithAllTheirWords() throws {
        let transcripts = try Self.transcripts()
        #expect(transcripts["SpeechAnalyzer (on-device)"]?.count == 509)
        #expect(transcripts["SFSpeechRecognizer (on-device)"]?.count == 508)
    }

    @Test(arguments: ["SpeechAnalyzer (on-device)", "SFSpeechRecognizer (on-device)"])
    func eachRecordedEngineMeetsCheckpointB(engine: String) throws {
        let words = try #require(try Self.transcripts()[engine])
        let map = Aligner().align(transcript: words, sentences: try Self.sentences())
        let score = AlignmentScore(map: map, expected: try Self.expected())
        for check in score.details where !check.isWithinTolerance {
            print("\(engine) MISS \(check.id) expected \(check.expected) measured \(String(describing: check.measured))")
        }
        print("\(engine): \(score.withinTolerance)/\(score.checked) within 0.5 s, worst \(score.worstError ?? -1)")
        #expect(score.checked == 20)
        // Checkpoint B accuracy, on the run's real transcripts: every reference start within 0.5 s.
        #expect(score.withinTolerance == score.checked)
        #expect(SpikeVerdict(fraction: score.fraction, secondsPerAudioMinute: 2.3) == .go)
    }
}
