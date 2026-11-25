import ABSClient
import Foundation
import Observation

/// "Find a cover": asks the Audiobookshelf server to look a Book up at a cover provider, then saves the pick to the
/// Book. The server makes the lookup and downloads the chosen image; saving changes the library for every client.
@Observable @MainActor
public final class CoverPickerModel {
    public enum Provider: String, CaseIterable, Sendable, Identifiable {
        case audible
        case itunes
        case google
        case openlibrary

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .audible: "Audible"
            case .itunes: "iTunes"
            case .google: "Google Books"
            case .openlibrary: "Open Library"
            }
        }
    }

    public enum State: Equatable, Sendable {
        case idle
        case searching
        case results
        case empty
        case saving
        case failed(String)
    }

    public let book: ABSBookSummary
    public var provider: Provider = .audible
    public private(set) var candidates: [URL] = []
    public private(set) var state: State = .idle

    private let client: ABSClient
    private static let maxCandidates = 24

    public init(book: ABSBookSummary, client: ABSClient) {
        self.book = book
        self.client = client
    }

    /// Providers match titles better without the subtitle: "Atomic Habits: An Easy & Proven Way…" → "Atomic Habits".
    public static func searchTitle(for title: String) -> String {
        let main = title.split(separator: ":", maxSplits: 1).first.map(String.init) ?? title
        let trimmed = main.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? title : trimmed
    }

    public func search() async {
        state = .searching
        candidates = []
        do {
            let found = try await client.searchCovers(
                title: Self.searchTitle(for: book.title), author: book.authorName, provider: provider.rawValue)
            candidates = Array(found.prefix(Self.maxCandidates))
            state = candidates.isEmpty ? .empty : .results
        } catch {
            state = .failed(ABSErrorText.message(for: error))
        }
    }

    /// Saves `url` as the Book's cover. Returns `true` when the server accepted it.
    public func choose(_ url: URL) async -> Bool {
        state = .saving
        do {
            try await client.setCover(bookID: book.id, from: url)
            state = .results
            return true
        } catch {
            state = .failed(ABSErrorText.message(for: error))
            return false
        }
    }
}
