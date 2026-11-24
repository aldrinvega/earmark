import Foundation

/// Skip and resume rules (SPEC: back 15 s, forward 30 s, resume 15 s before where you stopped).
public enum SkipRules {
    public static let back: TimeInterval = 15
    public static let forward: TimeInterval = 30
    public static let resumeRewind: TimeInterval = 15

    public static func skippedBack(from time: TimeInterval, in timeline: BookTimeline) -> TimeInterval {
        timeline.clamped(time - back)
    }

    public static func skippedForward(from time: TimeInterval, in timeline: BookTimeline) -> TimeInterval {
        timeline.clamped(time + forward)
    }

    /// Where playback starts when the user resumes from a saved position.
    public static func resumeTime(saved: TimeInterval, in timeline: BookTimeline) -> TimeInterval {
        timeline.clamped(saved - resumeRewind)
    }
}
