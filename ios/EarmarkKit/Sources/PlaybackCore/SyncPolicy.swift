import Foundation

public struct SyncReport: Sendable, Equatable {
    public let currentTime: TimeInterval
    public let timeListened: TimeInterval
}

/// When progress goes to the server: after every 15 s listened, plus on pause and when the app leaves the
/// foreground. Keeps the listening time the server records between reports.
public struct SyncPolicy: Sendable, Equatable {
    public static let interval: TimeInterval = 15
    private var listenedSinceReport: TimeInterval = 0

    public init() {}

    public mutating func played(_ seconds: TimeInterval) {
        listenedSinceReport += max(seconds, 0)
    }

    public var isDue: Bool { listenedSinceReport >= Self.interval }

    /// Takes the report to send (also for pause / background) and starts counting again.
    public mutating func report(at position: TimeInterval) -> SyncReport {
        let report = SyncReport(currentTime: position, timeListened: listenedSinceReport)
        listenedSinceReport = 0
        return report
    }
}
