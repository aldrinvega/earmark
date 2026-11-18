import Foundation

/// A few paragraphs of *Pride and Prejudice*, chapter 3 (Jane Austen, public domain; Project Gutenberg), typed in as
/// one small XHTML spine item. It exercises headings, nested inline markup, entities, `<br/>` and textless blocks.
///
/// Task 6 adds the real chapter file; this stays inline so the splitter tests need no fixture on disk.
enum PrideAndPrejudiceExcerpt {
    static let xhtml = #"""
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head>
            <title>Chapter 3</title>
            <style type="text/css">p { margin: 0; }</style>
          </head>
          <body>
            <h1>Chapter 3</h1>
            <p class="first">Not all that <em>Mrs. Bennet</em>, however, with the assistance of her five daughters,
            could ask on the subject, was sufficient to draw from her husband any satisfactory description of
            Mr.&nbsp;Bingley.</p>
            <p>“If I can but see one of my daughters happily settled at Netherfield,” said Mrs. Bennet to her husband,
            “and all the others equally well married, I shall have nothing to wish for.”</p>
            <p>Mr. Bennet was among the earliest of those who waited on Mr. Bingley.<br/>
            He had always intended to visit him.</p>
            <p/>
            <p> </p>
            <p>Well—I don’t know. What do you think?</p>
            <p>St. Albans is a city. It is old.</p>
          </body>
        </html>
        """#

    /// What `XHTMLText` makes of `xhtml`: the two textless `<p>`s are gone, `<br/>` is a space.
    static let paragraphs: [String] = [        "Chapter 3",
        "Not all that Mrs. Bennet, however, with the assistance of her five daughters, could ask on the subject, "
            + "was sufficient to draw from her husband any satisfactory description of Mr. Bingley.",
        "“If I can but see one of my daughters happily settled at Netherfield,” said Mrs. Bennet to her husband, "
            + "“and all the others equally well married, I shall have nothing to wish for.”",
        "Mr. Bennet was among the earliest of those who waited on Mr. Bingley. "
            + "He had always intended to visit him.",
        "Well—I don’t know. What do you think?",
        "St. Albans is a city. It is old.",
    ]

    /// Made-up non-ASCII text (ours, so public domain): an astral emoji with a ZWJ sequence at the start and end of
    /// sentences, and a combining acute accent encoded as a numeric reference.
    static let nonASCIIXHTML = #"<html><body><p>👩🏽‍🚀 greeted Cafe&#x301; Rouge. They left 👩🏽‍🚀.</p></body></html>"#
}
