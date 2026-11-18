import Foundation
import Models
import NaturalLanguage
import ReadAlongCore

/// Splits a chapter's paragraphs into sentences with stable IDs `<spine>.<paragraph>.<sentence>`.
///
/// The IDs are the shared key for progress, alignment caches and recaps, so they must not change for the same book.
/// They are a pure function of this code and of the sentence model shipped with the operating system's
/// `NLTokenizer`: when that model changes between OS versions the split can change, which renumbers every persisted
/// ID. `StableIDGoldenTests` pins the current output for the fixture chapter; if it changes, update it deliberately
/// and migrate saved IDs — never just accept the new list.
///
/// `NLTokenizer(unit: .sentence)` finds the sentence boundaries; the splitter then repairs the boundaries a
/// tokenizer gets wrong in 19th-century prose:
/// - a split after a title (`Mr.`, `Mrs.`, `Dr.`, `Prof.`, …) is always undone; `St.`, `Ft.`, `Vol.`, `Fig.`,
///   `Ch.`, `Pt.`, `est.` and single capital initials merge only when the next fragment continues the sentence
///   (lowercase, a number, or a capitalised word that is not a common sentence opener), or when the name already
///   ends in a run of initials — so `St. James's Square`, `Vol. 2`, `J. R. R. Tolkien` stay whole while
///   `…Baker St. He…` and `…by J. It…` split;
/// - a split before a lowercase word or an opening quote followed by a lowercase word (`“Go away!” she cried.`) is
///   undone, because the fragment is not a sentence;
/// - a split where the preceding sentence does not end with `.`, `!`, `?` or `…` (after any closing quote) is undone,
///   which covers dialogue broken at a dash or colon;
/// - an ellipsis is not an abbreviation: a short fragment ending in `...`/`…` continues only into a very short
///   question or exclamation (`Wait... What?`); otherwise the ellipsis is a boundary (`He paused... Then he left.`);
/// - abbreviations that normally end a sentence (`etc.`, `et al.`, `vs.`, `viz.`) are not merged.
///
/// Closing quotes stay with the sentence they close: the tokenizer includes them, and a final pass also pulls a
/// split-off straight `"` back into the previous sentence when it is followed by whitespace or the paragraph end.
///
/// Empty or whitespace-only paragraphs produce no sentences and **do not consume a paragraph index**: paragraph
/// indexes count text paragraphs only. That is the same rule `XHTMLText` applies when it drops textless blocks, so an
/// inserted `<p/>` or decorative divider never changes an existing `SentenceID`.
public struct SentenceSplitter: Sendable {
    private let language: NLLanguage

    /// `language` is pinned rather than inferred so the same book splits the same way on every device.
    public init(language: NLLanguage = .english) {
        self.language = language
    }

    /// Splits every paragraph, in reading order. Each sentence records its UTF-16 range within its paragraph.
    public func sentences(in paragraphs: [String], spine: Int) -> [ChapterSentence] {
        precondition(spine >= 0, "Spine indexes are zero-based")
        var result: [ChapterSentence] = []
        var paragraphIndex = 0
        for paragraph in paragraphs {
            let ranges = sentenceRanges(in: paragraph)
            guard !ranges.isEmpty else { continue }
            for (sentenceIndex, range) in ranges.enumerated() {
                let lower = paragraph.utf16.distance(from: paragraph.startIndex, to: range.lowerBound)
                let upper = paragraph.utf16.distance(from: paragraph.startIndex, to: range.upperBound)
                let text = String(paragraph[range])
                result.append(ChapterSentence(
                    sentence: SentenceText(
                        id: SentenceID(spine: spine, paragraph: paragraphIndex, sentence: sentenceIndex),
                        text: text
                    ),
                    range: lower..<upper
                ))
            }
            paragraphIndex += 1
        }
        return result
    }

    /// The aligner's input: the same sentences without their paragraph ranges.
    public func sentenceTexts(in paragraphs: [String], spine: Int) -> [SentenceText] {
        sentences(in: paragraphs, spine: spine).map(\.sentence)
    }

    // MARK: - Splitting

    private func sentenceRanges(in paragraph: String) -> [Range<String.Index>] {
        guard paragraph.contains(where: {
            !$0.isWhitespace && !Self.invisibleCharacters.contains($0)
        }) else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.setLanguage(language)
        tokenizer.string = paragraph
        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
            if let trimmed = trimmed(range, in: paragraph) {
                ranges.append(trimmed)
            }
            return true
        }
        if ranges.isEmpty, let whole = trimmed(paragraph.startIndex..<paragraph.endIndex, in: paragraph) {
            ranges = [whole]
        }
        return attachedStraightClosingQuote(merged(ranges, in: paragraph), in: paragraph)
    }

    private func trimmed(_ range: Range<String.Index>, in paragraph: String) -> Range<String.Index>? {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, paragraph[lower].isWhitespace {
            lower = paragraph.index(after: lower)
        }
        while upper > lower {
            let before = paragraph.index(before: upper)
            guard paragraph[before].isWhitespace else { break }
            upper = before
        }
        return lower < upper ? lower..<upper : nil
    }

    /// Rejoins the tokenizer's fragments that are not sentences of their own.
    private func merged(_ ranges: [Range<String.Index>], in paragraph: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        for range in ranges {
            if let last = result.last, shouldMerge(previous: paragraph[last], next: paragraph[range]) {
                result[result.count - 1] = last.lowerBound..<range.upperBound
            } else {
                result.append(range)
            }
        }
        return result
    }

    private func shouldMerge(previous: Substring, next: Substring) -> Bool {
        if startsWithLowercaseWord(next) { return true }
        if !endsWithSentencePunctuation(previous) { return true }
        // A short fragment ending in an ellipsis continues only into a very short question or exclamation
        // (`Wait... What?`); otherwise the ellipsis is a boundary (`He paused... Then he left.`).
        if endsWithEllipsis(previous), wordCount(in: previous) <= 4,
           wordCount(in: next) <= 2, endsWithQuestionOrExclamation(next) {
            return true
        }
        return endsWithAbbreviation(previous, next: next)
    }

    private func endsWithEllipsis(_ text: Substring) -> Bool {
        text.hasSuffix("...") || text.hasSuffix("…")
    }

    private func endsWithQuestionOrExclamation(_ text: Substring) -> Bool {
        guard let last = lastMeaningfulCharacter(of: text) else { return false }
        return last == "?" || last == "!"
    }

    /// If a boundary landed before a straight closing quote, give the quote to the sentence it closes. A closing
    /// quote is followed by whitespace or the paragraph end; an opening quote is followed by the next word.
    private func attachedStraightClosingQuote(
        _ ranges: [Range<String.Index>],
        in paragraph: String
    ) -> [Range<String.Index>] {
        guard ranges.count > 1 else { return ranges }
        var result = ranges
        var index = 1
        while index < result.count {
            var start = result[index].lowerBound
            while start < result[index].upperBound,
                  paragraph[start] == "\"",
                  endsWithSentencePunctuation(paragraph[result[index - 1]]),
                  isFollowedByBoundary(start, in: paragraph) {
                let end = paragraph.index(after: start)
                result[index - 1] = result[index - 1].lowerBound..<end
                start = end
            }
            while start < result[index].upperBound, paragraph[start].isWhitespace {
                start = paragraph.index(after: start)
            }
            if start < result[index].upperBound {
                result[index] = start..<result[index].upperBound
                index += 1
            } else {
                result.remove(at: index)
            }
        }
        return result
    }

    private func isFollowedByBoundary(_ index: String.Index, in paragraph: String) -> Bool {
        let after = paragraph.index(after: index)
        return after == paragraph.endIndex || paragraph[after].isWhitespace
    }

    // MARK: - Boundary tests

    private func startsWithLowercaseWord(_ text: Substring) -> Bool {
        var index = text.startIndex
        while index < text.endIndex, Self.openingCharacters.contains(text[index]) {
            index = text.index(after: index)
        }
        guard index < text.endIndex else { return false }
        return text[index].isLowercase
    }

    private func endsWithSentencePunctuation(_ text: Substring) -> Bool {
        guard let last = lastMeaningfulCharacter(of: text) else { return false }
        return Self.sentenceEndCharacters.contains(last)
    }

    /// True when the text ends with a title (always merged) or with `St.`/an initial where merging is safe.
    private func endsWithAbbreviation(_ text: Substring, next: Substring) -> Bool {
        guard let candidate = lastWordToken(of: text), !candidate.isEmpty else { return false }
        // An ellipsis is a sentence boundary, not an abbreviation (`Wait... What?`).
        if candidate.contains("..") { return false }

        var key = candidate.lowercased()
        while key.hasSuffix(".") { key.removeLast() }
        if Self.titleAbbreviations.contains(key) { return true }

        // `St.`, `Ft.`, `Vol.`, an initial, … are ambiguous: merge when the next fragment continues the sentence
        // (lowercase, a number, or a capitalised word that is not a common sentence opener).
        if Self.conditionalAbbreviations.contains(key) || isInitial(candidate) {
            if isInitial(candidate), endsWithInitialRun(text) { return true }
            return startsWithMidSentenceContinuation(next)
        }

        // Multi-period forms such as `U.S.` and `Ph.D.` (an ellipsis was excluded above).
        let periods = candidate.filter { $0 == "." }.count
        return periods >= 2 && candidate.allSatisfy { $0.isLetter || $0 == "." }
    }

    private func isInitial(_ candidate: String) -> Bool {
        guard candidate.count == 2, candidate.last == "." else { return false }
        guard let first = candidate.first else { return false }
        return first.isLetter && first.isUppercase
    }

    /// `J. R.` or `J. R. R.` at the end of a fragment: a name continues after any run of initials.
    private func endsWithInitialRun(_ text: Substring) -> Bool {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 2 else { return false }
        return isInitial(String(tokens[tokens.count - 1]))
            && isInitial(String(tokens[tokens.count - 2]))
    }

    /// True when the next fragment continues the sentence rather than starting one.
    private func startsWithMidSentenceContinuation(_ text: Substring) -> Bool {
        var index = text.startIndex
        while index < text.endIndex, Self.openingCharacters.contains(text[index]) {
            index = text.index(after: index)
        }
        guard index < text.endIndex else { return false }
        let first = text[index]
        if first.isNumber { return true }
        guard first.isLetter else { return false }

        var word = ""
        while index < text.endIndex {
            let character = text[index]
            guard character.isLetter || character == "'" || character == "\u{2019}" else { break }
            word.append(character)
            index = text.index(after: index)
        }
        return !Self.sentenceOpeners.contains(word.lowercased())
    }

    private func wordCount(in text: Substring) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// The last run of letters, periods and apostrophes, e.g. `Mr.` in `“Well, Mr. Bennet`.
    private func lastWordToken(of text: Substring) -> String? {
        var reversed: [Character] = []
        for character in text.reversed() {
            if character.isLetter || character == "." || character == "'" || character == "\u{2019}" {
                reversed.append(character)
            } else {
                break
            }
        }
        guard !reversed.isEmpty else { return nil }
        return String(reversed.reversed())
    }

    private func lastMeaningfulCharacter(of text: Substring) -> Character? {
        for character in text.reversed() {
            if Self.closingCharacters.contains(character) || character.isWhitespace {
                continue
            }
            return character
        }
        return nil
    }

    private static let sentenceEndCharacters: Set<Character> = [".", "!", "?", "…"]
    private static let invisibleCharacters: Set<Character> = ["\u{00AD}", "\u{200B}", "\u{FEFF}"]
    private static let openingCharacters: Set<Character> = ["“", "‘", "\"", "'", "(", "[", "¿", "¡"]
    private static let closingCharacters: Set<Character> = ["”", "’", "\"", "'", "»", ")", "]", "}"]

    /// Titles and name suffixes: these are virtually never the end of a sentence.
    private static let titleAbbreviations: Set<String> = [
        "mr", "mrs", "ms", "mx", "dr", "prof", "rev", "hon", "capt", "col", "gen", "lt", "sgt", "cpl",
        "maj", "adm", "gov", "sen", "rep", "jr", "sr", "messrs", "mme", "mlle", "pres", "supt", "esq",
    ]

    /// Ambiguous abbreviations, merged only when the next fragment continues the sentence.
    private static let conditionalAbbreviations: Set<String> = [
        "st", "mt", "ft", "ave", "blvd", "rd", "sq", "vol", "vols", "ch", "pt", "fig", "figs", "pp",
        "ed", "eds", "ibid", "ca", "approx", "dept", "est", "co", "corp", "inc", "ltd", "bros",
    ]

    /// Capitalised words that almost always start a new sentence rather than continue one.
    private static let sentenceOpeners: Set<String> = [
        "i", "he", "she", "it", "we", "you", "they", "the", "this", "that", "these", "those",
        "there", "then", "but", "and", "so", "yet", "however", "nobody", "nothing", "when", "if",
        "as", "at", "in", "on", "a", "an", "my", "his", "her", "our", "their",
    ]
}
