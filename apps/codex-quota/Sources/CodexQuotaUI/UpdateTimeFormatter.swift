import CodexQuotaCore
import Foundation

public enum UpdateTimeFormatter {
    public static func label(
        lastRefreshAt date: Date?,
        timeZone: TimeZone = .current,
        language: AppLanguage = .simplifiedChinese
    ) -> String {
        let value = string(observedAt: date, timeZone: timeZone)
        return language == .simplifiedChinese ? "更新时间：\(value)" : "Updated: \(value)"
    }

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
