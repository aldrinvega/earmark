import ABSClient
import AppFeatures
import SwiftUI

/// "Find a cover": the server looks the Book up at a provider; you pick one and it is saved to the Book.
struct CoverPickerSheet: View {
    @State private var model: CoverPickerModel
    private let covers: CoverStore
    @State private var pending: URL?
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    init(book: ABSBookSummary, client: ABSClient, covers: CoverStore) {
        _model = State(initialValue: CoverPickerModel(book: book, client: client))
        self.covers = covers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Find a cover").font(.system(size: 24, weight: .bold))
                    Text(model.book.title).font(.system(size: 14)).foregroundStyle(Theme.mutedInk).lineLimit(1)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 40, height: 40)
                        .background(Theme.ink.opacity(0.08), in: .circle)
                }
                .accessibilityLabel("Close")
            }
            .padding(.top, 22)

            Picker("Source", selection: $model.provider) {
                ForEach(CoverPickerModel.Provider.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.top, 14)
            .onChange(of: model.provider) { _, _ in Task { await model.search() } }

            ScrollView {
                results.padding(.top, 14)
            }

            Text("Audiobookshelf looks these up and saves the one you pick to the Book, for every app that uses your library. "
                 + "Previews load from the source's image servers.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.mutedInk)
                .padding(.vertical, 10)
        }
        .padding(.horizontal, 16)
        .foregroundStyle(Theme.ink)
        .background(Theme.paper.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
        .task { if model.state == .idle { await model.search() } }
        .confirmationDialog("Use this cover?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button("Use for “\(model.book.title)”") {
                guard let url = pending else { return }
                pending = nil
                Task {
                    if await model.choose(url) {
                        await covers.invalidate(model.book.id)
                        NotificationCenter.default.post(name: .coverChanged, object: model.book.id)
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This changes the cover in your Audiobookshelf library.")
        }
    }

    @ViewBuilder
    private var results: some View {
        switch model.state {
        case .idle, .searching:
            HStack(spacing: 10) {
                ProgressView()
                Text("Looking…").foregroundStyle(Theme.mutedInk)
            }
        case .empty:
            Text("No covers found at \(model.provider.title). Try another source.").foregroundStyle(Theme.mutedInk)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message).foregroundStyle(.red)
                Button("Try again") { Task { await model.search() } }.buttonStyle(.glass)
            }
        case .saving:
            HStack(spacing: 10) {
                ProgressView()
                Text("Saving…").foregroundStyle(Theme.mutedInk)
            }
        case .results:
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.candidates, id: \.self) { url in
                    Button {
                        pending = url
                    } label: {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit()
                            case .failure:
                                Image(systemName: "photo").foregroundStyle(Theme.mutedInk)
                            default:
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(Theme.ink.opacity(0.06), in: .rect(cornerRadius: 10))
                        .clipShape(.rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cover option")
                }
            }
        }
    }
}
