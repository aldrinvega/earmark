import ABSClient
import AppFeatures
import PlaybackCore
import SwiftUI

/// Contents from the design: the Book, then one row per chapter (done, current, to come).
struct ChaptersSheet: View {
    let player: PlayerController
    let covers: CoverStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Contents").font(.system(size: 24, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 40, height: 40)
                        .background(Theme.ink.opacity(0.08), in: .circle)
                }
                .accessibilityLabel("Close")
            }
            .padding(.top, 22)

            if let book = player.currentBook { summary(book).padding(.top, 14) }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(player.chapters.enumerated()), id: \.element.id) { index, chapter in
                            row(index: index, chapter: chapter)
                                .id(chapter.id)
                        }
                    }
                    .padding(.top, 10)
                }
                .onAppear {
                    if let index = player.currentChapterIndex, player.chapters.indices.contains(index) {
                        proxy.scrollTo(player.chapters[index].id, anchor: .center)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .foregroundStyle(Theme.ink)
        .background(Theme.paper.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
    }

    private func summary(_ book: ABSBookSummary) -> some View {
        HStack(spacing: 12) {
            CoverView(book: book, store: covers, cornerRadius: 8).frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title).font(Theme.serif(17)).lineLimit(2)
                Text("\(player.chapters.count) chapters · \(TimeFormat.length(player.duration))")
                    .font(.system(size: 12)).foregroundStyle(Theme.mutedInk)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.white.opacity(0.7), in: .rect(cornerRadius: 20))
    }

    private func row(index: Int, chapter: ChapterSpan) -> some View {
        let current = index == player.currentChapterIndex
        let done = (player.currentChapterIndex ?? 0) > index
        return Button {
            player.seek(to: chapter.start)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(current ? Theme.plum : done ? Color(hex: 0x3E7A55).opacity(0.14) : Theme.ink.opacity(0.07), in: .circle)
                    .foregroundStyle(current ? .white : done ? Color(hex: 0x2F5E41) : Color(hex: 0x4A4450))
                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.title).font(.system(size: 15, weight: current ? .semibold : .medium)).lineLimit(1)
                    if current {
                        ProgressView(value: player.chapterProgress).tint(Theme.plum)
                    }
                }
                if done {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0x3E7A55))
                }
                Text(TimeFormat.clock(chapter.end - chapter.start))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Theme.mutedInk)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(current ? Theme.plum.opacity(0.1) : .clear, in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chapter.title), \(TimeFormat.clock(chapter.end - chapter.start))")
    }
}
