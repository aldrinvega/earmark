import Foundation
import ReadAlongCore

/// One speech engine's run on the Diagnostics test chapter.
public struct EngineRun: Identifiable, Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case waiting
        case running
        case finished
        case failed(String)
        case cancelled
    }

    /// The engine's display name, unique per run.
    public let id: String
    public var state: State = .waiting
    /// Words the engine heard.
    public var words: Int?
    /// The first words heard (up to 14), to see at a glance whether the engine heard the book.
    public var preview: String?
    /// Start of the first and end of the last heard word, in seconds of the clip.
    public var heardFrom: Double?
    public var heardUntil: Double?
    /// Every word heard with its times, for the copied report (to check alignment and the references off the phone).
    public var transcript: [TranscriptWord]?
    /// Wall-clock time for speech-to-text plus alignment.
    public var processingSeconds: Double?
    public var secondsPerAudioMinute: Double?
    public var score: AlignmentScore?
    public var verdict: SpikeVerdict?

    public init(id: String) {
        self.id = id
    }
}
