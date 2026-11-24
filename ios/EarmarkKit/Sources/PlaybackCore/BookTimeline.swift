import Foundation

/// One audio file's place in the Book, in seconds from the Book's start.
public struct TrackSpan: Sendable, Equatable {
    public let start: TimeInterval
    public let duration: TimeInterval
    public var end: TimeInterval { start + duration }

    public init(start: TimeInterval, duration: TimeInterval) {
        self.start = start
        self.duration = duration
    }
}

public struct ChapterSpan: Sendable, Equatable {
    public let id: Int
    public let title: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(id: Int, title: String, start: TimeInterval, end: TimeInterval) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
    }
}

/// Maps a position in the whole Book to a track and offset, and to a chapter. Pure values, no AVFoundation.
public struct BookTimeline: Sendable, Equatable {
    public let tracks: [TrackSpan]
    public let chapters: [ChapterSpan]
    public let duration: TimeInterval

    public init(tracks: [TrackSpan], chapters: [ChapterSpan], duration: TimeInterval) {
        self.tracks = tracks
        self.chapters = chapters
        self.duration = duration
    }

    public func clamped(_ time: TimeInterval) -> TimeInterval {
        min(max(time, 0), duration)
    }

    /// The track that plays `time` and the offset inside it. A boundary belongs to the next track; the very end
    /// of the Book is the end of the last track.
    public func locate(_ time: TimeInterval) -> (track: Int, offset: TimeInterval)? {
        guard !tracks.isEmpty else { return nil }
        let time = clamped(time)
        if let index = tracks.lastIndex(where: { $0.start <= time && time < $0.end }) {
            return (index, time - tracks[index].start)
        }
        let last = tracks.count - 1
        return (last, min(time - tracks[last].start, tracks[last].duration))
    }

    public func globalTime(track: Int, offset: TimeInterval) -> TimeInterval {
        guard tracks.indices.contains(track) else { return 0 }
        return clamped(tracks[track].start + min(max(offset, 0), tracks[track].duration))
    }

    /// The chapter playing at `time`; past the last chapter's end it stays on the last one.
    public func chapter(at time: TimeInterval) -> ChapterSpan? {
        let time = clamped(time)
        return chapters.last(where: { $0.start <= time }) ?? chapters.first
    }

    /// How far into the chapter, 0...1.
    public func chapterProgress(at time: TimeInterval) -> Double {
        guard let chapter = chapter(at: time), chapter.end > chapter.start else { return 0 }
        return min(max((clamped(time) - chapter.start) / (chapter.end - chapter.start), 0), 1)
    }

    /// The start of the chapter after the current one, or `nil` on the last chapter.
    public func nextChapterStart(after time: TimeInterval) -> TimeInterval? {
        chapters.first(where: { $0.start > clamped(time) })?.start
    }

    /// Where "previous chapter" goes: the current chapter start, or the one before it within 3 s of its start.
    public func previousChapterStart(before time: TimeInterval) -> TimeInterval? {
        guard let current = chapter(at: time) else { return nil }
        if clamped(time) - current.start > 3 { return current.start }
        return chapters.last(where: { $0.start < current.start })?.start ?? current.start
    }
}
