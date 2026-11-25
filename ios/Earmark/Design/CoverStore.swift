import ABSClient
import SwiftUI
import UIKit

/// Fetches and remembers cover images (they need the access token, so `AsyncImage` cannot load them).
actor CoverStore {
    private let client: ABSClient
    private let cache = NSCache<NSString, NSData>()

    init(client: ABSClient) {
        self.client = client
    }

    /// The image file's bytes (`Data` crosses actors safely; the view decodes it).
    func imageData(for bookID: String) async -> Data? {
        if let cached = cache.object(forKey: bookID as NSString) { return cached as Data }
        guard let data = try? await client.coverData(bookID: bookID), UIImage(data: data) != nil else { return nil }
        cache.setObject(data as NSData, forKey: bookID as NSString)
        return data
    }
}

/// A Book's cover, square (that is what Audiobookshelf serves). Until the image arrives, or without one, a spine-style
/// card in the design's serif and gold stands in.
struct CoverView: View {
    let book: ABSBookSummary
    let store: CoverStore
    var cornerRadius: CGFloat = 10
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 5)
        .task(id: book.id) {
            if let data = await store.imageData(for: book.id) { image = UIImage(data: data) }
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        let palette: [(UInt32, UInt32)] = [(0x1F3A4D, 0xF2E9D8), (0x2E3B2F, 0xD9E4C8), (0x8A3B2E, 0xF6E3D2),
                                           (0x2C3E6B, 0xE9DDB8), (0x5B2A4A, 0xE8C77A), (0x1A1A1A, 0xE0675C)]
        // A stable pick (hashValue changes every launch), so a Book keeps its colour.
        let pick = palette[book.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % palette.count]
        return ZStack {
            Color(hex: pick.0)
            VStack(spacing: 6) {
                Text((book.authorName ?? "").uppercased())
                    .font(.system(size: 8, weight: .regular)).tracking(1.4).opacity(0.85).lineLimit(1)
                Text(book.title).font(Theme.serif(14, weight: .medium)).multilineTextAlignment(.center).lineLimit(4)
                Rectangle().frame(height: 1).opacity(0.5).padding(.horizontal, 16)
            }
            .padding(10)
            .foregroundStyle(Color(hex: pick.1))
        }
    }
}
