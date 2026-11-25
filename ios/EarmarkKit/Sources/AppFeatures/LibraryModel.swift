import ABSClient
import Foundation
import Observation

/// The list of Books on the server.
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
        } catch ABSError.unauthorized {
            await onSessionExpired()
        } catch {
            state = .failed(ABSErrorText.message(for: error))
        }
    }
}
