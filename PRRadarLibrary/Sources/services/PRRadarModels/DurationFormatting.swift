import Foundation

/// Formats durations for display in summaries and reports.
///
/// Examples:
/// - 500ms → "0.5s"
/// - 12300ms → "12.3s"
/// - 125000ms → "2m 05s"
/// - 3661000ms → "1h 01m 01s"
public enum DurationFormatter {
    public static func format(milliseconds ms: Int) -> String {
        let totalSeconds = ms / 1000
        if totalSeconds < 60 {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.1fs", seconds)
        }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes < 60 {
            return String(format: "%dm %02ds", minutes, seconds)
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return String(format: "%dh %02dm %02ds", hours, remainingMinutes, seconds)
    }
}
