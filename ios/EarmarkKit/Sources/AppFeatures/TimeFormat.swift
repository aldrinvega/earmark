import Foundation

public enum TimeFormat {
    /// 75 → "1:15", 3725 → "1:02:05". Negative and non-finite values show as zero.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(Int(seconds), 0) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// 25199 → "7 h 0 min", 1800 → "30 min".
    public static func length(_ seconds: TimeInterval) -> String {
        let minutes = seconds.isFinite ? max(Int((seconds / 60).rounded()), 0) : 0
        if minutes >= 60 { return "\(minutes / 60) h \(minutes % 60) min" }
        return "\(minutes) min"
    }
}
