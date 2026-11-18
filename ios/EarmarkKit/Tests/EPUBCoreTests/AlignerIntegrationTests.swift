import Foundation
import Testing
import Models
import ReadAlongCore
import EPUBCore

/// The real pipeline Task 5 feeds: XHTML → paragraphs → sentences → `Aligner`.
@Suite struct AlignerIntegrationTests {
    @Test func aPerfectTranscriptAlignsEverySentence() throws {
        let xhtml = #"""
            <html><body>
              <h1>Chapter 3</h1>
              <p>Not all that Mrs. Bennet, however, with the assistance of her five daughters, could ask on the
              subject, was sufficient to draw from her husband any satisfactory description of Mr. Bingley.</p>
              <p>“If I can but see one of my daughters happily settled at Netherfield,” said Mrs. Bennet to her
              husband, “and all the others equally well married, I shall have nothing to wish for.”</p>
              <p>Mr. Bennet was among the earliest of those who waited on Mr. Bingley.<br/>
              He had always intended to visit him.</p>
              <p>Well—I don’t know. What do you think?</p>
            </body></html>
            """#

        let paragraphs = try XHTMLText().paragraphs(in: xhtml)
        let sentences = SentenceSplitter().sentences(in: paragraphs, spine: 0)
        #expect(sentences.count == 7)

        // A perfect synthetic transcript: every word in order, 0.3 s long, 0.34 s apart, a pause between sentences.
        var transcript: [TranscriptWord] = []
        var expectedStarts: [TimeInterval] = []
        var time: TimeInterval = 0
        for sentence in sentences {
            expectedStarts.append(time)
            for token in sentence.text.split(whereSeparator: \.isWhitespace) {
                transcript.append(TranscriptWord(text: String(token), start: time, end: time + 0.3))
                time += 0.34
            }
            time += 0.6
        }

        let map = Aligner().align(transcript: transcript, sentences: sentences.map(\.sentence))
        #expect(map.entries.count == sentences.count)

        for (index, sentence) in sentences.enumerated() {
            let start = map.startTime(of: sentence.id)
            #expect(start != nil, "\(sentence.id) should be aligned")
            if let start {
                #expect(abs(start - expectedStarts[index]) < 0.0001)
            }
            #expect(map.entries[index].id == sentence.id)
            #expect(map.entries[index].isAligned)
        }
    }
}
