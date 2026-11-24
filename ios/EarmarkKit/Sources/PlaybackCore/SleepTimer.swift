import Foundation

/// Sleep timer. A duration counts seconds actually played (not Book seconds, so the speed does not matter); the
/// end-of-chapter mode pauses at the chapter end that was current when it was set.
public struct SleepTimer: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case off
        case duration(TimeInterval)
        case endOfChapter(chapterEnd: TimeInterval)
    }

    public private(set) var mode: Mode = .off
    private var played: TimeInterval = 0

    public init() {}

    public mutating func set(_ mode: Mode) {
        self.mode = mode
        played = 0
    }

    public mutating func cancel() {
        set(.off)
    }

    /// Time left for a duration timer, for display.
    public var remaining: TimeInterval? {
        if case .duration(let total) = mode { return max(total - played, 0) }
        return nil
    }

    /// Call while playing with the seconds played since the last call and the Book position.
    /// Returns `true` when playback should pause now; the timer then switches itself off.
    public mutating func tick(playedSeconds: TimeInterval, position: TimeInterval) -> Bool {
        switch mode {
        case .off:
            return false
        case .duration(let total):
            played += max(playedSeconds, 0)
            guard played >= total else { return false }
        case .endOfChapter(let chapterEnd):
            // A little early, so the first words of the next chapter are not heard.
            guard position >= chapterEnd - 0.25 else { return false }
        }
        cancel()
        return true
    }
}
