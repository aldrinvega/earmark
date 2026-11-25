import ABSClient
import SwiftUI

/// The pill above the tab bar while a Book is open and you are not on Listen Now.
struct MiniPlayerView: View {
    let player: PlayerController
    let covers: CoverStore
    let open: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: open) {
                HStack(spacing: 10) {
                    if let book = player.currentBook {
                        CoverView(book: book, store: covers, cornerRadius: 22).frame(width: 40, height: 40)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(player.chapterTitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Now playing: \(player.title)")
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20)).frame(width: 44, height: 44)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Button { player.skipForward() } label: {
                Image(systemName: "goforward.30").font(.system(size: 22)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Forward 30 seconds")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}
