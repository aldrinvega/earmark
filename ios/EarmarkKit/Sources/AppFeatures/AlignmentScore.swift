import Foundation
import ReadAlongCore

/// How many reference starts an alignment got right (SPEC.md criterion 6, plan.md Checkpoint B).
public struct AlignmentScore: Sendable, Equatable {
    /// Reference starts checked.
    public let checked: Int
    /// Computed starts within the tolerance of the reference.
    public let withinTolerance: Int
    /// Reference sentences the aligner left unaligned (they count as wrong).
    public let unaligned: Int
    /// The largest distance between a computed and a reference start, among aligned sentences.
    public let worstError: TimeInterval?

    public var fraction: Double {
        checked == 0 ? 0 : Double(withinTolerance) / Double(checked)
    }

    public init(map: AlignmentMap, expected: ExpectedStarts) {
        var within = 0
        var unaligned = 0
        var worst: TimeInterval?
        for reference in expected.starts {
            guard let start = map.startTime(of: reference.id) else {
                unaligned += 1
                continue
            }
            // Round to the millisecond so float noise can't push an exact boundary over the tolerance.
            let error = (abs(start - reference.start) * 1000).rounded() / 1000
            worst = max(worst ?? 0, error)
            if error <= expected.toleranceSeconds { within += 1 }
        }
        checked = expected.starts.count
        withinTolerance = within
        self.unaligned = unaligned
        worstError = worst
    }
}
