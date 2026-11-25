import ABSClient
import AppFeatures
import SwiftUI

/// The Search tab: filters the Library by title or author.
struct SearchView: View {
    let library: LibraryModel
    let covers: CoverStore
    let client: ABSClient
    let play: (ABSBookSummary) -> Void
    @State private var text = ""
    @State private var coverBook: ABSBookSummary?

    var body: some View {
        NavigationStack {
            ZStack {
                BlobBackdrop(style: .light)
                List(library.search(text), id: \.id) { book in
                    Button {
                        play(book)
                    } label: {
                        HStack(spacing: 12) {
                            CoverView(book: book, store: covers, cornerRadius: 8).frame(width: 52, height: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.title).font(Theme.serif(16)).lineLimit(2)
                                Text([book.authorName, library.status(for: book)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 13)).foregroundStyle(Theme.mutedInk).lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Find a better cover…", systemImage: "photo.on.rectangle") { coverBook = book }
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .overlay {
                    if library.state == .loaded && library.search(text).isEmpty {
                        ContentUnavailableView.search(text: text)
                    }
                }
            }
            .foregroundStyle(Theme.ink)
            .navigationTitle("Search")
            .searchable(text: $text, prompt: "Title or author")
            .sheet(item: $coverBook) { CoverPickerSheet(book: $0, client: client, covers: covers) }
        }
    }
}
