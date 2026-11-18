import Foundation

/// Problems the Diagnostics test can report besides an engine's own `TranscriptionError`.
public enum AlignTestError: Error, Equatable, Sendable {
    case noEngine
    case timedOut(seconds: Double)
    case badFixture(String)
}

extension AlignTestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noEngine:
            "No on-device speech engine is available on this iPhone."
        case .timedOut(let seconds):
            String(format: "Stopped after %.1f s without a result.", seconds)
        case .badFixture(let message):
            "The bundled test chapter could not be read: \(message)"
        }
    }
}
