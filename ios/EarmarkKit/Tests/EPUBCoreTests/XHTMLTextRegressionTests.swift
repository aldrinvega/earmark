import Foundation
import Testing
import EPUBCore

/// Review-7 findings 2, 4 (parser side), 5, 6, 8 and 10: real-EPUB markup must not leak into sentence text.
@Suite struct XHTMLTextRegressionTests {
    private let text = XHTMLText()

    // MARK: - 2. Footnote references

    private func noterefSentences(in xhtml: String) throws -> [String] {
        let paragraphs = try text.paragraphs(in: xhtml)
        return SentenceSplitter().sentences(in: paragraphs, spine: 0).map(\.text)
    }

    @Test func skipsAnAnchorMarkedAsANoteref() throws {
        let xhtml = #"""
            <html xmlns:epub="http://www.idpf.org/2007/ops"><body>
              <p>He left the house.<a epub:type="noteref" href="#n1">1</a> Then he slept.</p>
            </body></html>
            """#
        #expect(try noterefSentences(in: xhtml) == ["He left the house.", "Then he slept."])
    }

    @Test func skipsASuperscriptNoteref() throws {
        let xhtml = #"""
            <html xmlns:epub="http://www.idpf.org/2007/ops"><body>
              <p>He left the house.<sup><a epub:type="noteref" href="#n1">1</a></sup> Then he slept.</p>
            </body></html>
            """#
        #expect(try noterefSentences(in: xhtml) == ["He left the house.", "Then he slept."])
    }

    @Test func skipsARoleDocNoteref() throws {
        let xhtml = ##"<html><body><p>He left the house.<a role="doc-noteref" href="#n1">1</a> Then he slept.</p></body></html>"##
        #expect(try noterefSentences(in: xhtml) == ["He left the house.", "Then he slept."])
    }

    @Test func aNoterefThatWrapsAWordKeepsTheWord() throws {
        let xhtml = ##"<html xmlns:epub="http://www.idpf.org/2007/ops"><body><p>He left the <a epub:type="noteref" href="#n">house</a> early.</p></body></html>"##
        #expect(try noterefSentences(in: xhtml) == ["He left the house early."])
    }

    @Test func aPlainTypeAttributeIsNotANoteref() throws {
        let xhtml = #"<html><body><p>He left.<a type="noteref">1</a> Then he slept.</p></body></html>"#
        #expect(try text.paragraphs(in: xhtml) == ["He left.1 Then he slept."])
    }

    @Test func symbolAndRomanMarkersAreDropped() throws {
        let marker = ##"<html xmlns:epub="http://www.idpf.org/2007/ops"><body><p>He left.<sup epub:type="noteref">[iv]</sup> Then he slept.</p></body></html>"##
        let symbol = ##"<html xmlns:epub="http://www.idpf.org/2007/ops"><body><p>He left.<a epub:type="noteref" href="#n">*</a> Then he slept.</p></body></html>"##
        #expect(try noterefSentences(in: marker) == ["He left.", "Then he slept."])
        #expect(try noterefSentences(in: symbol) == ["He left.", "Then he slept."])
    }

    // MARK: - 4. Invisible characters

    @Test func removesSoftHyphensZeroWidthSpacesAndBOM() throws {
        let xhtml = "<html><body><p>abso&shy;lutely\u{200B}here\u{FEFF}now</p></body></html>"
        #expect(try text.paragraphs(in: xhtml) == ["absolutelyherenow"])
    }

    @Test func aZeroWidthSpaceOnlyBlockIsDropped() throws {
        let xhtml = "<html><body><p>One.</p><p>\u{200B}</p><p>Two.</p></body></html>"
        #expect(try text.paragraphs(in: xhtml) == ["One.", "Two."])
    }

    @Test func keepsZeroWidthJoinersAndNonJoiners() throws {
        let xhtml = "<html><body><p>a\u{200C}b 🧑\u{200D}🚀</p></body></html>"
        #expect(try text.paragraphs(in: xhtml) == ["a\u{200C}b 🧑\u{200D}🚀"])
    }

    // MARK: - 5. Inline non-text elements

    @Test func anInlineImageSeparatesTheWordsAroundIt() throws {
        let xhtml = #"<html><body><p>before<img src="x"/>after</p></body></html>"#
        #expect(try text.paragraphs(in: xhtml) == ["before after"])
    }

    @Test func aHorizontalRuleFlushesTheParagraph() throws {
        let xhtml = #"<html><body><div>Alpha<hr/>Beta</div></body></html>"#
        #expect(try text.paragraphs(in: xhtml) == ["Alpha", "Beta"])
    }

    @Test func otherNonTextInlineElementsSeparateWords() throws {
        let xhtml = #"<html><body><p>a<wbr/>b<svg/>c<object/>d<iframe/>e<video/>f<audio/>g<embed/>h<input/>i</p></body></html>"#
        #expect(try text.paragraphs(in: xhtml) == ["a b c d e f g h i"])
    }

    // MARK: - 6. Ruby

    @Test func rubyAnnotationsAreSkipped() throws {
        let xhtml = #"<html><body><p><ruby>漢<rp>(</rp><rt>かん</rt><rp>)</rp></ruby>字を読む。</p></body></html>"#
        #expect(try text.paragraphs(in: xhtml) == ["漢字を読む。"])
    }

    // MARK: - 8. CDATA and comments

    @Test func entityRewritingLeavesCDATALiteral() throws {
        let xhtml = #"<html><body><p>a <![CDATA[&mdash; b]]></p></body></html>"#
        #expect(try text.paragraphs(in: xhtml) == ["a &mdash; b"])
    }

    @Test func entityRewritingLeavesCommentsAlone() throws {
        let xhtml = #"<html><body><p>a <!-- &mdash; b -->c</p></body></html>"#
        #expect(try text.paragraphs(in: xhtml) == ["a c"])
    }

    // MARK: - 10. Error position

    @Test func malformedTagErrorHasNonZeroLineAndColumn() {
        let xhtml = #"<html><body><p>One</body></html>"#
        do {
            _ = try text.paragraphs(in: Data(xhtml.utf8))
            Issue.record("Expected malformedXHTML for \(xhtml.debugDescription)")
        } catch let error as EPUBCoreError {
            guard case .malformedXHTML(let reason) = error else {
                Issue.record("Expected .malformedXHTML, got \(error)")
                return
            }
            #expect(reason.range(
                of: #"line [1-9][0-9]*, column [0-9]+"#,
                options: .regularExpression
            ) != nil)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func emptyDataErrorIncludesLineAndColumn() {
        do {
            _ = try text.paragraphs(in: Data())
            Issue.record("Expected malformedXHTML for empty data")
        } catch let error as EPUBCoreError {
            guard case .malformedXHTML(let reason) = error else {
                Issue.record("Expected .malformedXHTML, got \(error)")
                return
            }
            #expect(reason.range(
                of: #"line [0-9]+, column [0-9]+"#,
                options: .regularExpression
            ) != nil)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
