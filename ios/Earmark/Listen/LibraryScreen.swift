import ABSClient
import AppFeatures
import SwiftUI
import UIKit

/// The Books on the server. Owns the player, so playback keeps going while you browse.
struct LibraryScreen: View {
    private let signIn: SignInModel
    @State private var library: LibraryModel
    @State private var player: PlayerController

    init(client: ABSClient, signIn: SignInModel) {
        self.signIn = signIn
        _library = State(initialValue: LibraryModel(client: client, onSessionExpired: { await signIn.sessionExpired() }))
        _player = State(initialValue: PlayerController(client: client))
    }

    var body: some View {
        List {
            if player.loadState == .ready, let bookID = player.loadedBookID,
               let current = library.books.first(where: { $0.id == bookID }) {
                Section("Now playing") {
                    NavigationLink {
                        PlayerScreen(player: player, book: current)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.title).font(.headline)
                            Text(player.chapterTitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("now-playing")
                }
            }
            Section {
                switch library.state {
                case .idle, .loading:
                    HStack { ProgressView(); Text("Loading your Books…").foregroundStyle(.secondary) }
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message).foregroundStyle(.red)
                        Button("Try again") { Task { await library.load() } }
                    }
                case .loaded:
                    ForEach(library.books, id: \.id) { book in
                        NavigationLink {
                            PlayerScreen(player: player, book: book)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.title).font(.headline)
                                Text(subtitle(for: book)).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Books")
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Sign out") {
                    Task {
                        await player.stop()
                        await signIn.signOut()
                    }
                }
            }
        }
        .task { await library.load() }
        .refreshable { await library.load() }
    }

    private func subtitle(for book: ABSBookSummary) -> String {
        [book.authorName, TimeFormat.length(book.duration)].compactMap { $0 }.joined(separator: " · ")
    }
}
