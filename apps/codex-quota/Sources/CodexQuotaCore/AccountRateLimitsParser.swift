import Foundation

public enum AccountRateLimitsParser {
    public static func snapshot(
        from data: Data,
        observedAt: Date = Date()
    ) -> QuotaSnapshot? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = root["result"] as? [String: Any],
            let rateLimits = codexRateLimits(from: result)
        else {
            return nil
        }

        let windows = ["primary", "secondary"].compactMap { name -> Window? in
            guard
                let window = rateLimits[name] as? [String: Any],
                let number = window["usedPercent"] as? NSNumber,
                CFGetTypeID(number) != CFBooleanGetTypeID(),
                number.doubleValue.isFinite
            else {
                return nil
            }
            return Window(
                usedPercent: number.doubleValue,
                resetsAt: resetDate(from: window["resetsAt"]),
                duration: duration(fromMinutes: window["windowDurationMins"])
            )
        }

        guard var selectedWindow = windows.first else {
            return nil
        }
        for window in windows.dropFirst() where window.usedPercent > selectedWindow.usedPercent {
            selectedWindow = window
        }

        let remaining = Int(min(
            max((100 - selectedWindow.usedPercent).rounded(), 0),
            100
        ))
        return QuotaSnapshot(
            remainingPercent: remaining,
            observedAt: observedAt,
            resetsAt: selectedWindow.resetsAt,
            windowDuration: selectedWindow.duration,
            planName: PlanInfo.normalizedName(rateLimits["planType"] as? String)
        )
    }

    private struct Window {
        let usedPercent: Double
        let resetsAt: Date?
        let duration: TimeInterval?
    }

    private static func codexRateLimits(
        from result: [String: Any]
    ) -> [String: Any]? {
        if
            let byLimitID = result["rateLimitsByLimitId"] as? [String: Any],
            let codex = byLimitID["codex"] as? [String: Any]
        {
            return codex
        }
        guard
            let rateLimits = result["rateLimits"] as? [String: Any],
            rateLimits["limitId"] as? String == "codex"
        else {
            return nil
        }
        return rateLimits
    }

    private static func resetDate(from value: Any?) -> Date? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite,
            (0...253_402_300_799).contains(number.doubleValue)
        else {
            return nil
        }
        return Date(timeIntervalSince1970: number.doubleValue)
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
