import ABSClient
import AppFeatures
import SwiftUI
import UIKit

struct PlayerScreen: View {
    let player: PlayerController
    let book: ABSBookSummary
    @State private var scrub: Double?

    private static let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                cover
                VStack(spacing: 4) {
                    Text(book.title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    if let author = book.authorName { Text(author).foregroundStyle(.secondary) }
                    if !player.chapterTitle.isEmpty {
                        Text(player.chapterTitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                switch player.loadState {
                case .idle, .loading:
                    ProgressView("Opening…")
                case .failed(let message):
                    VStack(spacing: 10) {
                        Text(message).foregroundStyle(.red).multilineTextAlignment(.center)
                        Button("Try again") { Task { await player.load(book, deviceID: Self.deviceID) } }
                            .buttonStyle(.glass)
                    }
                case .ready:
                    controls
                }
            }
            .padding(20)
        }
        .navigationTitle("Now playing")
        .navigationBarTitleDisplayMode(.inline)
        .task { await player.load(book, deviceID: Self.deviceID) }
    }

    private var cover: some View {
        Group {
            if let image = player.cover {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "book.closed").font(.system(size: 60)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 220, maxHeight: 220)
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityHidden(true)
    }

    private var controls: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Slider(
                    value: Binding(get: { scrub ?? player.position }, set: { scrub = $0 }),
                    in: 0...max(player.duration, 1),
                    onEditingChanged: { editing in
                        if !editing, let target = scrub {
                            player.seek(to: target)
                            scrub = nil
                        }
                    })
                    .accessibilityIdentifier("position-slider")
                HStack {
                    Text(TimeFormat.clock(scrub ?? player.position))
                    Spacer()
                    Text("-" + TimeFormat.clock(player.duration - (scrub ?? player.position)))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 18) {
                Button { player.previousChapter() } label: { Image(systemName: "backward.end.fill") }
                    .accessibilityLabel("Previous chapter")
                Button { player.skipBack() } label: { Image(systemName: "gobackward.15").font(.title2) }
                    .accessibilityLabel("Back 15 seconds")
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.largeTitle).frame(width: 56, height: 44)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("play-pause")
                Button { player.skipForward() } label: { Image(systemName: "goforward.30").font(.title2) }
                    .accessibilityLabel("Forward 30 seconds")
                Button { player.nextChapter() } label: { Image(systemName: "forward.end.fill") }
                    .accessibilityLabel("Next chapter")
            }
            .buttonStyle(.glass)

            HStack(spacing: 12) {
                Menu {
                    ForEach(Self.rates, id: \.self) { rate in
                        Button(rateLabel(rate)) { player.setRate(rate) }
                    }
                } label: {
                    Label(rateLabel(player.rate), systemImage: "speedometer")
                }
                Menu {
                    Button("Off") { player.cancelSleepTimer() }
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in
                        Button("\(minutes) minutes") { player.setSleepTimer(minutes: minutes) }
                    }
                    Button("End of chapter") { player.setSleepTimerToEndOfChapter() }
                } label: {
                    Label(player.sleepLabel ?? "Sleep timer", systemImage: "moon.zzz")
                }
            }
            .buttonStyle(.glass)
        }
    }

    private func rateLabel(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : String(format: "%g×", rate)
    }

    private static var deviceID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "earmark-iphone"
    }
}
