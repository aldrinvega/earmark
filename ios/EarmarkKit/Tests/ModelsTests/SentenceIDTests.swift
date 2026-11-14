import Foundation
import Testing
@testable import Models

/// SentenceID is the key shared by the reader, the aligner, the recap and progress (SPEC.md, plan.md).
@Suite struct SentenceIDTests {
    @Test func stringFormIsSpineParagraphSentence() {
        #expect(SentenceID(spine: 4, paragraph: 12, sentence: 3).description == "4.12.3")
    }

    @Test func roundTripsThroughItsStringForm() throws {
        let id = SentenceID(spine: 0, paragraph: 7, sentence: 21)
        #expect(SentenceID(id.description) == id)
    }

    @Test(arguments: ["", "1.2", "1.2.3.4", "a.b.c", "-1.0.0", "1..2", " 1.2.3", "1.2.3 "])
    func rejectsMalformedStrings(_ text: String) {
        #expect(SentenceID(text) == nil)
    }

    @Test func ordersInReadingOrder() {
        let ids = ["2.0.0", "1.10.0", "1.2.5", "1.2.10", "0.99.99"].compactMap(SentenceID.init)
        #expect(ids.sorted().map(\.description) == ["0.99.99", "1.2.5", "1.2.10", "1.10.0", "2.0.0"])
    }

    @Test func encodesAsTheStringForm() throws {
        let id = SentenceID(spine: 3, paragraph: 1, sentence: 0)
        let json = try JSONEncoder().encode(["s": id])
        #expect(String(decoding: json, as: UTF8.self) == #"{"s":"3.1.0"}"#)
        #expect(try JSONDecoder().decode([String: SentenceID].self, from: json)["s"] == id)
    }

    @Test func decodingAMalformedStringFails() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([SentenceID].self, from: Data(#"["1.x.2"]"#.utf8))
        }
    }
}
