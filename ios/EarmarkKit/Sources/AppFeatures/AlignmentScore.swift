import Foundation
import Models
import ReadAlongCore

/// How many reference starts an alignment got right (SPEC.md criterion 6, plan.md Checkpoint B).
public struct AlignmentScore: Sendable, Equatable {
    /// One reference start, and what the alignment made of it.
    public struct ReferenceCheck: Sendable, Equatable {
        public let id: SentenceID
        public let expected: TimeInterval
        /// The aligner's start for this sentence; nil when it left the sentence unaligned.
        public let measured: TimeInterval?
        /// `|measured − expected|`, rounded to the millisecond; nil when unaligned.
        public let error: TimeInterval?
        public let isWithinTolerance: Bool
    }

    /// Every reference start, in the reference file's order.
    public let details: [ReferenceCheck]
    /// Reference starts checked.
    public var checked: Int { details.count }
    /// Computed starts within the tolerance of the reference.
    public var withinTolerance: Int { details.filter(\.isWithinTolerance).count }
    /// Reference sentences the aligner left unaligned (they count as wrong).
    public var unaligned: Int { details.filter { $0.measured == nil }.count }
    /// The largest distance between a computed and a reference start, among aligned sentences.
    public var worstError: TimeInterval? { details.compactMap(\.error).max() }

    public var fraction: Double {
        checked == 0 ? 0 : Double(withinTolerance) / Double(checked)
    }

    public init(map: AlignmentMap, expected: ExpectedStarts) {
        details = expected.starts.map { reference in
            guard let start = map.startTime(of: reference.id) else {
                return ReferenceCheck(id: reference.id, expected: reference.start, measured: nil, error: nil,
                                      isWithinTolerance: false)
            }
            // Round to the millisecond so float noise can't push an exact boundary over the tolerance.
            let error = (abs(start - reference.start) * 1000).rounded() / 1000
            return ReferenceCheck(id: reference.id, expected: reference.start, measured: start, error: error,
                                  isWithinTolerance: error <= expected.toleranceSeconds)
        }
    }
}
