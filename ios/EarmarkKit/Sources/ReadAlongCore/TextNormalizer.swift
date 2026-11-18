import Foundation

/// Turns EPUB and speech-to-text text into the tokens the aligner compares.
///
/// Lowercases, folds accents, removes apostrophes, treats dashes and other punctuation as word breaks, and writes the
/// simple numbers as words ("3" → "three", "21" → "twenty", "one") so "Chapter 3" matches "chapter three". Years
/// 1000–2099 are written as they are spoken ("1813" → "eighteen", "thirteen"; "2005" → "two", "thousand", "five").
/// A hyphen inside one source word ("to-day") may merge to "today"; a space never does, so "from day to day" stays
/// four tokens, and the transcript side (normalised one word at a time) gets the same result for "to-day". The common
/// honorifics become their spoken forms ("Mr." → "mister", "Mrs." → "missus", "Dr." → "doctor"). Other digits above
/// 99 are left alone: speaking every number is not a one-to-one mapping, so the aligner treats those as unmatched.
public struct TextNormalizer: Sendable {
    public init() {}

    /// The normalised tokens of `text`, in order.
    public func words(in text: String) -> [String] {
        // `folding` is Foundation-heavy and the aligner calls this once per transcript word, so plain ASCII text
        // (nearly all of it) skips it.
        let lowered = text.lowercased()
        let folded = lowered.unicodeScalars.allSatisfy(\.isASCII)
            ? lowered
            : lowered.folding(options: .diacriticInsensitive, locale: Self.locale)

        var tokens: [String] = []
        // Parallel to `tokens`: true when the token follows a hyphen in this same source string (so "to-day" may
        // merge, but "to day" may not).
        var afterHyphen: [Bool] = []
        var current = String.UnicodeScalarView()
        var separatorWasHyphen = false

        func flush() {
            if !current.isEmpty {
                let expanded = Self.expansion(of: String(current))
                for (offset, token) in expanded.enumerated() {
                    tokens.append(token)
                    afterHyphen.append(offset == 0 && separatorWasHyphen)
                }
                current.removeAll(keepingCapacity: true)
            }
            separatorWasHyphen = false
        }

        for scalar in folded.unicodeScalars {
            if Self.apostrophes.contains(scalar) {
                continue
            }
            if scalar.properties.generalCategory == .dashPunctuation {
                flush()
                separatorWasHyphen = true
                continue
            }
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                current.append(scalar)
            } else {
                flush()
            }
        }
        flush()
        return Self.canonicalised(tokens, afterHyphen: afterHyphen)
    }

    private static let locale = Locale(identifier: "en_US_POSIX")

    private static let apostrophes: Set<Unicode.Scalar> = ["'", "’", "‘", "`", "´", "ʼ"]

    private static let smallNumberWords = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
        "eighteen", "nineteen",
    ]

    private static let tensNumberWords: [Int: String] = [
        2: "twenty", 3: "thirty", 4: "forty", 5: "fifty", 6: "sixty", 7: "seventy", 8: "eighty", 9: "ninety",
    ]

    /// Period spellings that speech-to-text writes as one word.
    private static let mergedPairs: [String: String] = [
        "to day": "today", "to morrow": "tomorrow", "to night": "tonight",
        "any thing": "anything", "every thing": "everything",
        "some thing": "something", "no thing": "nothing",
    ]

    /// Abbreviations whose spoken form is what the transcriber returns.
    private static let wordAliases: [String: String] = [
        "mr": "mister", "mrs": "missus", "dr": "doctor",
    ]

    private static func expansion(of token: String) -> [String] {
        guard token.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(token) else {
            return [token]
        }
        if value < smallNumberWords.count {
            return [smallNumberWords[value]]
        }
        if value < 100 {
            let tens = value / 10
            let ones = value % 10
            guard let tensWord = tensNumberWords[tens] else { return [token] }
            guard ones > 0 else { return [tensWord] }
            return [tensWord, smallNumberWords[ones]]
        }
        if value >= 1000, value <= 2099 {
            return yearWords(value)
        }
        return [token]
    }

    /// "1000" → one thousand; "1900" → nineteen hundred; "1801" → eighteen, oh, one; "1813" → eighteen, thirteen;
    /// "1984" → nineteen, eighty, four; "2005" → two, thousand, five; "2010" → twenty, ten.
    private static func yearWords(_ value: Int) -> [String] {
        if value == 1000 { return ["one", "thousand"] }
        if value == 2000 { return ["two", "thousand"] }
        if value < 2000 {
            let century = value / 100
            let rest = value % 100
            guard century >= 10, century < smallNumberWords.count else { return [String(value)] }
            let centuryWord = smallNumberWords[century]
            if rest == 0 {
                return [centuryWord, "hundred"]
            }
            if rest < 10 {
                return [centuryWord, "oh"] + expansion(of: String(rest))
            }
            return [centuryWord] + expansion(of: String(rest))
        }
        let rest = value % 100
        if value < 2010 {
            return ["two", "thousand"] + expansion(of: String(rest))
        }
        return ["twenty"] + expansion(of: String(rest))
    }

    private static func canonicalised(_ tokens: [String], afterHyphen: [Bool]) -> [String] {
        var result: [String] = []
        result.reserveCapacity(tokens.count)
        var index = 0
        while index < tokens.count {
            if index + 1 < tokens.count,
               afterHyphen[index + 1],
               let joined = mergedPairs[tokens[index] + " " + tokens[index + 1]] {
                result.append(joined)
                index += 2
                continue
            }
            let token = tokens[index]
            result.append(wordAliases[token] ?? token)
            index += 1
        }
        return result
    }
}
