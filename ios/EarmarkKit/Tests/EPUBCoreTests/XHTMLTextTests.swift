import Foundation
import Testing
import EPUBCore

/// One XHTML spine item → paragraphs of plain text (SPEC.md: EPUB parsed with Foundation's `XMLParser`).
@Suite struct XHTMLTextTests {
    private let text = XHTMLText()

    @Test func extractsParagraphsAndSkipsTheHead() throws {
        let paragraphs = try text.paragraphs(in: PrideAndPrejudiceExcerpt.xhtml)
        #expect(paragraphs == PrideAndPrejudiceExcerpt.paragraphs)
    }

    @Test func skipsScriptAndStyleInTheBody() throws {
        let xhtml = """
            <html><body>
              <p>Kept.</p>
              <script type="text/javascript">document.write("not text")</script>
              <style>p { color: red; }</style>
              <p>Also kept.</p>
            </body></html>
            """
        #expect(try text.paragraphs(in: xhtml) == ["Kept.", "Also kept."])
    }

    @Test func keepsNestedInlineText() throws {
        let xhtml = ##"<html><body><p>Hello <em>dear</em> <strong>Mr.</strong> <a href="#x">Bennet</a>.</p></body></html>"##
        #expect(try text.paragraphs(in: xhtml) == ["Hello dear Mr. Bennet."])
    }

    @Test func normalisesWhitespaceButKeepsOtherCharacters() throws {
        let xhtml = "<html><body><p>  “Two   spaces”\n\tand\na newline;  </p></body></html>"
        #expect(try text.paragraphs(in: xhtml) == ["“Two spaces” and a newline;"])
    }

    @Test func decodesNamedAndNumericEntities() throws {
        let xhtml = "<html><body><p>a&nbsp;b &mdash; c&rsquo;s &amp; d &#8212; e&#x2014;f &hellip;</p></body></html>"
        #expect(try text.paragraphs(in: xhtml) == ["a b — c’s & d — e—f …"])
    }

    @Test func brBecomesASpace() throws {
        let xhtml = #"<html><body><p>One<br/>two<br />three</p></body></html>"#
        #expect(try text.paragraphs(in: xhtml) == ["One two three"])
    }

    @Test func textlessBlocksProduceNoParagraph() throws {
        let xhtml = #"""
            <html><body>
              <p/>
              <p>   </p>
              <div class="ornament"><img src="ornament.png" alt=""/></div>
              <p>Real.</p>
            </body></html>
            """#
        #expect(try text.paragraphs(in: xhtml) == ["Real."])
    }

    @Test func divWithDirectTextIsItsOwnParagraph() throws {
        let xhtml = #"<html><body><div>Direct <span>text</span><p>Nested.</p> after</div></body></html>"#
        #expect(try text.paragraphs(in: xhtml) == ["Direct text", "Nested.", "after"])
    }

    @Test func malformedChapterThrowsATypedError() {
        let xhtml = #"<html><body><p>One</body></html>"#
        #expect(throws: EPUBCoreError.self) {
            _ = try text.paragraphs(in: xhtml)
        }
    }

    @Test func anUnknownEntityThrowsInsteadOfCrashing() {
        let xhtml = #"<html><body><p>&notARealEntity;</p></body></html>"#
        #expect(throws: EPUBCoreError.self) {
            _ = try text.paragraphs(in: xhtml)
        }
    }
}
