import CodexQuotaCore
import Foundation

public enum ResetCountdownFormatter {
    public static func string(
        resetsAt: Date?,
        now: Date = Date(),
        language: AppLanguage = .simplifiedChinese
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
        let days = totalHours / 24
        let remainingHours = totalHours % 24
        switch language {
        case .simplifiedChinese:
            return "\(days) 天 \(remainingHours) 小时"
        case .english:
            let dayUnit = days == 1 ? "day" : "days"
            let hourUnit = remainingHours == 1 ? "hour" : "hours"
            return "\(days) \(dayUnit) \(remainingHours) \(hourUnit)"
        }
    }

    public static func compactString(
        resetsAt: Date?,
        now: Date = Date(),
        language: AppLanguage = .simplifiedChinese
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
            return language == .simplifiedChinese ? "\(totalHours)小时" : "\(totalHours)h"
        }
        return language == .simplifiedChinese ? "\(totalHours / 24)天" : "\(totalHours / 24)d"
    }
}
