import Foundation

/// The read-along spike's GO / NO-GO rule (tasks/plan.md, Checkpoint B).
public enum SpikeVerdict: Sendable, Equatable {
    case go
    case noGo(reasons: [String])

    /// At least this share of reference starts must be within tolerance.
    public static let minimumFraction = 0.9
    /// At most this many seconds of processing per minute of audio.
    public static let maximumSecondsPerAudioMinute = 30.0

    public init(fraction: Double, secondsPerAudioMinute: Double) {
        var reasons: [String] = []
        if fraction < Self.minimumFraction {
            reasons.append(String(format: "%.1f%% of starts within 0.5 s (needs %.0f%%)",
                                  fraction * 100, Self.minimumFraction * 100))
        }
        if secondsPerAudioMinute > Self.maximumSecondsPerAudioMinute {
            reasons.append(String(format: "%.1f s of processing per audio minute (limit %.0f)",
                                  secondsPerAudioMinute, Self.maximumSecondsPerAudioMinute))
        }
        self = reasons.isEmpty ? .go : .noGo(reasons: reasons)
    }

    public var title: String {
        switch self {
        case .go: "GO"
        case .noGo: "NO-GO"
        }
    }
}
