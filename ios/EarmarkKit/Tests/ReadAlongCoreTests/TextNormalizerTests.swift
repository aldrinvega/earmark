import Testing
@testable import ReadAlongCore

/// Normalisation is what lets "“Chapter 3,”" in the EPUB meet "chapter three" from speech-to-text.
@Suite struct TextNormalizerTests {
    private let normalizer = TextNormalizer()

    @Test func lowercasesAndStripsPunctuation() {
        #expect(normalizer.words(in: "“Hello,” said Mrs. Bennet—don’t be hasty!") ==
            ["hello", "said", "missus", "bennet", "dont", "be", "hasty"])
    }

    @Test func foldsAccents() {
        #expect(normalizer.words(in: "Café résumé naïve") == ["cafe", "resume", "naive"])
    }

    @Test func turnsSimpleDigitsIntoWords() {
        #expect(normalizer.words(in: "Chapter 3") == ["chapter", "three"])
        #expect(normalizer.words(in: "21 and 99 and 100") ==
            ["twenty", "one", "and", "ninety", "nine", "and", "100"])
    }

    @Test func treatsDashesAndQuotesAsWordBreaks() {
        #expect(normalizer.words(in: "well-known ‘quoted’ text") == ["well", "known", "quoted", "text"])
        #expect(normalizer.words(in: "—") == [])
        #expect(normalizer.words(in: "") == [])
    }

    @Test func keepsPossessivesTogether() {
        #expect(normalizer.words(in: "Bingley’s heart") == ["bingleys", "heart"])
    }

    @Test func splitsOnAllWhitespace() {
        #expect(normalizer.words(in: "one\ttwo\nthree   four") == ["one", "two", "three", "four"])
    }

    @Test func mergesPeriodHyphenations() {
        #expect(normalizer.words(in: "to-day any-thing to-morrow") == ["today", "anything", "tomorrow"])
    }

    @Test func doesNotMergeAcrossWhitespace() {
        #expect(normalizer.words(in: "from day to day") == ["from", "day", "to", "day"])
        #expect(normalizer.words(in: "any thing at all") == ["any", "thing", "at", "all"])
    }

    @Test func aTranscriptWordWithAHyphenMatchesTheMergedBookWord() {
        #expect(normalizer.words(in: "to-day") == ["today"])
        #expect(normalizer.words(in: "any-thing") == ["anything"])
    }

    @Test func usesTheSpokenHonorifics() {
        #expect(normalizer.words(in: "Mr. Bennet met Mrs. Bennet and Dr. Jones.") ==
            ["mister", "bennet", "met", "missus", "bennet", "and", "doctor", "jones"])
    }

    @Test func spellsYearsAsTheyAreSpoken() {
        #expect(normalizer.words(in: "1000") == ["one", "thousand"])
        #expect(normalizer.words(in: "1800") == ["eighteen", "hundred"])
        #expect(normalizer.words(in: "1900") == ["nineteen", "hundred"])
        #expect(normalizer.words(in: "1001") == ["ten", "oh", "one"])
        #expect(normalizer.words(in: "1005") == ["ten", "oh", "five"])
        #expect(normalizer.words(in: "1801") == ["eighteen", "oh", "one"])
        #expect(normalizer.words(in: "1813") == ["eighteen", "thirteen"])
        #expect(normalizer.words(in: "1984") == ["nineteen", "eighty", "four"])
        #expect(normalizer.words(in: "2000") == ["two", "thousand"])
        #expect(normalizer.words(in: "2005") == ["two", "thousand", "five"])
        #expect(normalizer.words(in: "2010") == ["twenty", "ten"])
        #expect(normalizer.words(in: "2099") == ["twenty", "ninety", "nine"])
    }
}
