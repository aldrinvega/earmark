import ABSClient
import AppFeatures
import AVKit
import SwiftUI

/// Now Playing from the design: dark glass, big cover, scrubber, round play button and the bottom bar.
struct NowPlayingView: View {
    let player: PlayerController
    let covers: CoverStore
    @State private var scrub: Double?
    @State private var showChapters = false

    private static let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        ZStack {
            BlobBackdrop(style: .dark)
            if let book = player.currentBook {
                content(for: book)
            } else {
                emptyState
            }
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $showChapters) { ChaptersSheet(player: player, covers: covers) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "headphones").font(.system(size: 40)).foregroundStyle(Theme.gold)
            Text("Nothing playing").font(Theme.serif(24, weight: .medium))
            Text("Pick a Book in your Library.").foregroundStyle(.white.opacity(0.75))
        }
        .accessibilityElement(children: .combine)
    }

    private func content(for book: ABSBookSummary) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                if player.chapters.count > 0, let index = player.currentChapterIndex {
                    Text("CHAPTER \(index + 1) OF \(player.chapters.count)")
                        .font(.system(size: 11)).tracking(0.9).foregroundStyle(.white.opacity(0.72))
                }
                Text(book.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)

            CoverView(book: book, store: covers, cornerRadius: 16)
                .frame(maxWidth: 300)
                .padding(.horizontal, 44)
                .padding(.top, 22)

            switch player.loadState {
            case .idle, .loading:
                ProgressView("Opening…").tint(.white).padding(.top, 40)
                Spacer()
            case .failed(let message):
                Text(message).foregroundStyle(Theme.coral).multilineTextAlignment(.center).padding(24)
                Spacer()
            case .ready:
                Text(player.chapterTitle)
                    .font(Theme.serif(16, weight: .regular).italic())
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .frame(minHeight: 40)
                scrubber.padding(.top, 14)
                transport.padding(.top, 10)
                Spacer(minLength: 12)
                bottomBar
            }
        }
        .padding(.bottom, 8)
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(get: { scrub ?? player.position }, set: { scrub = $0 }),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    if !editing, let target = scrub {
                        player.seek(to: target)
                        scrub = nil
                    }
                })
                .tint(.white)
                .accessibilityIdentifier("position-slider")
            HStack {
                Text(TimeFormat.clock(scrub ?? player.position))
                Spacer()
                Text(player.chapterTitle).lineLimit(1)
                Spacer()
                Text("−" + TimeFormat.clock(player.duration - (scrub ?? player.position)))
            }
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 28)
    }

    private var transport: some View {
        HStack(spacing: 30) {
            Button { player.skipBack() } label: {
                Image(systemName: "gobackward.15").font(.system(size: 30, weight: .regular)).frame(width: 56, height: 56)
            }
            .accessibilityLabel("Back 15 seconds")
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32))
                    .frame(width: 80, height: 80)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("play-pause")
            Button { player.skipForward() } label: {
                Image(systemName: "goforward.30").font(.system(size: 30, weight: .regular)).frame(width: 56, height: 56)
            }
            .accessibilityLabel("Forward 30 seconds")
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack {
            Menu {
                ForEach(Self.rates, id: \.self) { rate in
                    Button(Self.rateLabel(rate)) { player.setRate(rate) }
                }
            } label: {
                Text(Self.rateLabel(player.rate)).font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel("Playback speed")
            Menu {
                Button("Off") { player.cancelSleepTimer() }
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") { player.setSleepTimer(minutes: minutes) }
                }
                Button("End of chapter") { player.setSleepTimerToEndOfChapter() }
            } label: {
                Image(systemName: "moon").font(.system(size: 19)).frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel(player.sleepLabel ?? "Sleep timer")
            RoutePickerButton().frame(maxWidth: .infinity, minHeight: 44)
            Button { showChapters = true } label: {
                Image(systemName: "list.bullet").font(.system(size: 19)).frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel("Chapters")
            .accessibilityIdentifier("chapters")
        }
        .padding(.horizontal, 6)
        .frame(height: 56)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 28)
        .overlay(alignment: .top) {
            if let label = player.sleepLabel {
                Text(label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8)).offset(y: -22)
            }
        }
    }

    private static func rateLabel(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : String(format: "%g×", rate)
    }
}

/// The system AirPlay / output picker.
struct RoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .white
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
