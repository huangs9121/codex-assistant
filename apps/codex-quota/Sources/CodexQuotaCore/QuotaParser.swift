import Foundation

public enum QuotaParser {
    public static func snapshot(from line: String) -> QuotaSnapshot? {
        guard
            let data = line.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["type"] as? String == "event_msg",
            let payload = root["payload"] as? [String: Any],
            payload["type"] as? String == "token_count",
            let rateLimits = payload["rate_limits"] as? [String: Any],
            rateLimits["limit_id"] as? String == "codex",
            let observedAt = observedAt(from: root["timestamp"])
        else {
            return nil
        }

        let windows = ["primary", "secondary"].compactMap { name -> QuotaWindow? in
            guard
                let limit = rateLimits[name] as? [String: Any],
                let usedPercent = limit["used_percent"] as? Double,
                usedPercent.isFinite
            else {
                return nil
            }
            return QuotaWindow(
                usedPercent: usedPercent,
                resetsAt: resetDate(from: limit["resets_at"]),
                windowDuration: duration(fromMinutes: limit["window_minutes"])
            )
        }

        guard !windows.isEmpty else {
            return nil
        }
        var selectedIndex = 0
        for index in windows.indices.dropFirst()
            where windows[index].usedPercent > windows[selectedIndex].usedPercent
        {
            selectedIndex = index
        }
        let selectedWindow = windows[selectedIndex]
        let secondaryWindow = windows.indices
            .first { $0 != selectedIndex }
            .map { windows[$0] }

        let roundedRemaining = (100 - selectedWindow.usedPercent).rounded()
        let remainingPercent = Int(min(max(roundedRemaining, 0), 100))
        let planName = PlanInfo.normalizedName(rateLimits["plan_type"] as? String)
        return QuotaSnapshot(
            remainingPercent: remainingPercent,
            observedAt: observedAt,
            resetsAt: selectedWindow.resetsAt,
            windowDuration: selectedWindow.windowDuration,
            planName: planName,
            secondaryWindow: secondaryWindow
        )
    }

    private static func resetDate(from value: Any?) -> Date? {
        guard
            !(value is Bool),
            let number = value as? NSNumber,
            number.doubleValue.isFinite,
            (0...253_402_300_799).contains(number.doubleValue)
        else {
            return nil
        }
        return Date(timeIntervalSince1970: number.doubleValue)
    }

    private static func observedAt(from value: Any?) -> Date? {
        guard let timestamp = value as? String else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: timestamp) {
            return date
        }

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        return standardFormatter.date(from: timestamp)
    }

    private static func duration(fromMinutes value: Any?) -> TimeInterval? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite,
            number.doubleValue > 0
        else {
            return nil
        }
        return number.doubleValue * 60
    }
}
