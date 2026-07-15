import Foundation

public enum UpdateTimeFormatter {
    public static func string(
        observedAt: Date?,
        timeZone: TimeZone = .current
    ) -> String {
        guard let observedAt else {
            return "--:--:--"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = timeZone
        return formatter.string(from: observedAt)
    }
}
