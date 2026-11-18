import Foundation
import Testing
import Models
@testable import ReadAlongCore

/// The reader's two questions: "which sentence is being narrated now?" and "where does this sentence start?".
@Suite struct AlignmentMapTests {
    private let first = SentenceID(spine: 0, paragraph: 0, sentence: 0)
    private let missing = SentenceID(spine: 0, paragraph: 0, sentence: 1)
    private let second = SentenceID(spine: 0, paragraph: 0, sentence: 2)
    private let third = SentenceID(spine: 0, paragraph: 0, sentence: 3)

    private var map: AlignmentMap {
        AlignmentMap(entries: [
            AlignmentEntry(id: first, start: 0, end: 2),
            AlignmentEntry(id: missing, start: nil, end: nil),
            AlignmentEntry(id: second, start: 3, end: 5),
            AlignmentEntry(id: third, start: 6, end: 8),
        ])
    }

    @Test func startTimeIsNilForUnalignedAndUnknownSentences() throws {
        #expect(map.startTime(of: first) == 0)
        #expect(map.startTime(of: second) == 3)
        #expect(map.startTime(of: missing) == nil)
        #expect(map.startTime(of: SentenceID(spine: 9, paragraph: 9, sentence: 9)) == nil)
    }

    @Test func sentenceAtTimeTakesTheLastStartAndHoldsThroughGaps() {
        #expect(map.sentence(at: -1) == nil)
        #expect(map.sentence(at: 0) == first)
        #expect(map.sentence(at: 1.99) == first)
        #expect(map.sentence(at: 2) == first)
        #expect(map.sentence(at: 2.999) == first)
        #expect(map.sentence(at: 3) == second)
        #expect(map.sentence(at: 5.5) == second)
        #expect(map.sentence(at: 6) == third)
        #expect(map.sentence(at: 8) == third)
        #expect(map.sentence(at: 8.001) == nil)
    }

    @Test func anEmptyOrFullyUnalignedMapHasNoAnswer() {
        #expect(AlignmentMap(entries: []).sentence(at: 0) == nil)
        let unaligned = AlignmentMap(entries: [AlignmentEntry(id: first, start: nil, end: nil)])
        #expect(unaligned.sentence(at: 0) == nil)
        #expect(unaligned.startTime(of: first) == nil)
    }

    @Test func jsonRoundTripKeepsStartsEndsAndUnalignedSentences() throws {
        let json = try JSONEncoder().encode(map)
        let decoded = try JSONDecoder().decode(AlignmentMap.self, from: json)

        #expect(decoded.entries == map.entries)
        #expect(decoded.startTime(of: second) == 3)
        #expect(decoded.sentence(at: 7) == third)
        #expect(decoded.startTime(of: missing) == nil)
        #expect(String(decoding: json, as: UTF8.self).contains(#""0.0.2""#))
    }

    @Test func aStartOnlyEntryIsAlignedEverywhere() throws {
        let json = #"{"entries":[{"id":"0.0.0","start":1}]}"#
        let decoded = try JSONDecoder().decode(AlignmentMap.self, from: Data(json.utf8))
        let id = try #require(SentenceID("0.0.0"))

        #expect(decoded.entries[0].isAligned)
        #expect(decoded.startTime(of: id) == 1)
        #expect(decoded.sentence(at: 1) == id)
        #expect(decoded.sentence(at: 1.5) == id)
        #expect(decoded.sentence(at: 0.5) == nil)
    }

    @Test func decodesACachedFileShape() throws {
        let json = #"{"entries":[{"id":"0.0.0","start":1,"end":2},{"id":"0.1.0"}]}"#
        let decoded = try JSONDecoder().decode(AlignmentMap.self, from: Data(json.utf8))
        let aligned = try #require(SentenceID("0.0.0"))
        let unaligned = try #require(SentenceID("0.1.0"))

        #expect(decoded.startTime(of: aligned) == 1)
        #expect(decoded.startTime(of: unaligned) == nil)
        #expect(decoded.entries.count == 2)
    }
}
