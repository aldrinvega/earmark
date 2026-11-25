import ABSClient
import AppFeatures
import SwiftUI

/// Library from the design: the Continue card and the shelf of covers.
struct LibraryView: View {
    let library: LibraryModel
    let covers: CoverStore
    let signIn: SignInModel
    let player: PlayerController
    let play: (ABSBookSummary) -> Void
    @State private var showDiagnostics = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12, alignment: .top)]

    var body: some View {
        NavigationStack {
            ZStack {
                BlobBackdrop(style: .light)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        if let book = library.continueBook { continueCard(book).padding(.top, 18) }
                        shelf.padding(.top, 26)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .refreshable { await library.load() }
            }
            .foregroundStyle(Theme.ink)
            .preferredColorScheme(.light)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showDiagnostics) { DiagnosticsView() }
        }
    }

    private var header: some View {
        HStack {
            Text("Library").font(.system(size: 34, weight: .bold)).tracking(-0.7)
            Spacer()
            Menu {
                Button("Diagnostics", systemImage: "stethoscope") { showDiagnostics = true }
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task {
                        await player.stop()
                        await signIn.signOut()
                    }
                }
            } label: {
                Image(systemName: "person")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .accessibilityLabel("Account")
        }
        .padding(.top, 8)
    }

    private func continueCard(_ book: ABSBookSummary) -> some View {
        HStack(alignment: .top, spacing: 16) {
            CoverView(book: book, store: covers, cornerRadius: 12).frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 0) {
                Text("CONTINUE").font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Theme.plum)
                Text(book.title).font(Theme.serif(21)).lineLimit(2).padding(.top, 4)
                if let author = book.authorName {
                    Text(author).font(.system(size: 14)).foregroundStyle(Theme.mutedInk).padding(.top, 3)
                }
                Text(library.status(for: book)).font(.system(size: 13)).foregroundStyle(Theme.mutedInk).padding(.top, 8)
                ProgressView(value: library.fractionDone(for: book))
                    .tint(Theme.plum)
                    .padding(.top, 6)
                Button {
                    play(book)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.plum, in: Capsule())
                }
                .padding(.top, 12)
                .accessibilityIdentifier("resume")
            }
        }
        .padding(16)
        .background(.white, in: .rect(cornerRadius: 26))
        .shadow(color: Color(hex: 0x3C1E32).opacity(0.09), radius: 17, y: 10)
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On your shelf").font(.system(size: 20, weight: .bold))
            shelfBody
        }
    }

    @ViewBuilder
    private var shelfBody: some View {
        switch library.state {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading your Books…").foregroundStyle(Theme.mutedInk)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message).foregroundStyle(.red)
                Button("Try again") { Task { await library.load() } }.buttonStyle(.glass)
            }
        case .loaded:
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(library.books, id: \.id) { book in
                    Button {
                        play(book)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            CoverView(book: book, store: covers)
                            Text(library.status(for: book))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.mutedInk)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(book.title), \(library.status(for: book))")
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }
}
