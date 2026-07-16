import Foundation

public enum ResetCountdownFormatter {
    public static func string(
        resetsAt: Date?,
        now: Date = Date()
    ) -> String {
        guard let resetsAt else {
            return "--"
        }
        let interval = resetsAt.timeIntervalSince(now)
        guard interval.isFinite else {
            return "--"
        }
        let hours = floor(max(0, interval) / 3_600)
        guard hours.isFinite, hours < Double(Int.max) else {
            return "--"
        }
        let totalHours = Int(hours)
        return "\(totalHours / 24) 天 \(totalHours % 24) 小时"
    }

    public static func compactString(
        resetsAt: Date?,
        now: Date = Date()
    ) -> String {
        guard let resetsAt else {
            return "--"
        }
        let interval = resetsAt.timeIntervalSince(now)
        guard interval.isFinite else {
            return "--"
        }
        let hours = floor(max(0, interval) / 3_600)
        guard hours.isFinite, hours < Double(Int.max) else {
            return "--"
        }
        let totalHours = Int(hours)
        if totalHours < 24 {
            return "\(totalHours)小时"
        }
        return "\(totalHours / 24)天"
    }
}
