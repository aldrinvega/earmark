import Foundation

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
    /// Wall-clock time for speech-to-text plus alignment.
    public var processingSeconds: Double?
    public var secondsPerAudioMinute: Double?
    public var score: AlignmentScore?
    public var verdict: SpikeVerdict?

    public init(id: String) {
        self.id = id
    }
}
