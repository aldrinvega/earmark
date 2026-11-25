import ABSClient
import Foundation
import Observation

/// The list of Books on the server, with each Book's progress for the shelf and the Continue card.
@Observable @MainActor
public final class LibraryModel {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var books: [ABSBookSummary] = []
    public private(set) var progress: [String: ABSBookProgress] = [:]

    private let client: ABSClient
    private let onSessionExpired: @MainActor () async -> Void

    public init(client: ABSClient, onSessionExpired: @escaping @MainActor () async -> Void) {
        self.client = client
        self.onSessionExpired = onSessionExpired
    }

    public func load() async {
        state = .loading
        do {
            guard let library = try await client.libraries().first(where: { $0.mediaType == "book" }) else {
                state = .failed("The server has no audiobook library.")
                return
            }
            var all: [ABSBookSummary] = []
            var page = 0
            while true {
                let result = try await client.books(inLibrary: library.id, limit: 100, page: page)
                all += result.books
                page += 1
                if result.books.isEmpty || all.count >= result.total { break }
            }
            books = all.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            state = .loaded
            await refreshProgress()
        } catch ABSError.unauthorized {
            await onSessionExpired()
        } catch {
            state = .failed(ABSErrorText.message(for: error))
        }
    }

    /// Progress is decoration: when it can't be read the shelf still shows, without statuses.
    public func refreshProgress() async {
        guard let all = try? await client.allProgress() else { return }
        progress = Dictionary(all.map { ($0.libraryItemId, $0) }, uniquingKeysWith: { first, second in
            first.lastUpdate >= second.lastUpdate ? first : second
        })
    }

    /// The Book you were last listening to and have not finished, for the Continue card.
    public var continueBook: ABSBookSummary? {
        let started = progress.values.filter { !$0.isFinished && $0.progress > 0 }
        for entry in started.sorted(by: { $0.lastUpdate > $1.lastUpdate }) {
            if let book = books.first(where: { $0.id == entry.libraryItemId }) { return book }
        }
        return nil
    }

    /// "34% · 9 h left", "New" or "Finished".
    public func status(for book: ABSBookSummary) -> String {
        guard let entry = progress[book.id] else { return "New" }
        if entry.isFinished { return "Finished" }
        guard entry.progress > 0 else { return "New" }
        let total = entry.duration > 0 ? entry.duration : book.duration
        let left = max(total - entry.currentTime, 0)
        return "\(Int((entry.progress * 100).rounded()))% · \(TimeFormat.left(left))"
    }

    public func fractionDone(for book: ABSBookSummary) -> Double {
        min(max(progress[book.id]?.progress ?? 0, 0), 1)
    }

    /// Case-insensitive match on title or author, for the Search tab.
    public func search(_ text: String) -> [ABSBookSummary] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return books }
        return books.filter {
            $0.title.localizedCaseInsensitiveContains(query) || ($0.authorName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}
