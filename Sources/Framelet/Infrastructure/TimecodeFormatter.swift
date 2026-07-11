import Foundation

enum TimecodeFormatter {
    static func string(from seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00:00.000" }
        let milliseconds = Int((seconds * 1000).rounded())
        let ms = milliseconds % 1000
        let totalSeconds = milliseconds / 1000
        let sec = totalSeconds % 60
        let min = (totalSeconds / 60) % 60
        let hour = totalSeconds / 3600
        return String(format: "%02d:%02d:%02d.%03d", hour, min, sec, ms)
    }
}
