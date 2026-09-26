import Foundation

/// Parses Claude's own usage response and the small, local Claude Desktop history file.
/// Neither source contains a reliable plan name; callers must not infer one here.
public enum ClaudeUsageParser {
    /// Replaces only OAuth fields after a successful refresh; all unrelated
    /// Claude Code credential fields remain intact.
    public static func refreshedCredentialData(
        from original: Data,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date
    ) -> Data? {
        guard !accessToken.isEmpty, !refreshToken.isEmpty,
              var root = try? JSONSerialization.jsonObject(with: original) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any] else { return nil }
        oauth["accessToken"] = accessToken
        oauth["refreshToken"] = refreshToken
        oauth["expiresAt"] = expiresAt.timeIntervalSince1970 * 1_000
        root["claudeAiOauth"] = oauth
        return try? JSONSerialization.data(withJSONObject: root)
    }

    public static func oauthSnapshot(
        from data: Data,
        observedAt: Date = Date(),
        subscriptionType: String? = nil,
        rateLimitTier: String? = nil
    ) -> QuotaSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let fiveHour = oauthWindow(root["five_hour"], duration: 5 * 3_600)
        let sevenDay = oauthWindow(root["seven_day"], duration: 7 * 24 * 3_600)
        let plan = planLabels(subscriptionType: subscriptionType, rateLimitTier: rateLimitTier)
        return snapshot(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            observedAt: observedAt,
            planName: plan
        )
    }

    public static func desktopHistorySnapshot(from data: Data) -> QuotaSnapshot? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let samples = root["samples"] as? [[String: Any]]
        else {
            return nil
        }
        // Samples can be out of order. Do not splice windows from different accounts/times.
        return samples.compactMap { sample -> QuotaSnapshot? in
            guard
                let milliseconds = number(sample["t"]),
                milliseconds >= 0,
                milliseconds <= 253_402_300_799_000
            else {
                return nil
            }
            let values = (sample["u"] as? [String: Any]) ?? sample // v1 layout
            let fiveHour = historyWindow(values["fh"], duration: 5 * 3_600)
            let sevenDay = historyWindow(values["sd"], duration: 7 * 24 * 3_600)
            return snapshot(
                fiveHour: fiveHour,
                sevenDay: sevenDay,
                observedAt: Date(timeIntervalSince1970: milliseconds / 1_000)
            )
        }.max { $0.observedAt < $1.observedAt }
    }

    private static func snapshot(
        fiveHour: QuotaWindow?,
        sevenDay: QuotaWindow?,
        observedAt: Date,
        planName: String? = nil
    ) -> QuotaSnapshot? {
        // Claude's 5-hour session is the main meter; the weekly meter is secondary.
        guard let primary = fiveHour ?? sevenDay else { return nil }
        return QuotaSnapshot(
            remainingPercent: Int((100 - primary.usedPercent).rounded()),
            observedAt: observedAt,
            resetsAt: primary.resetsAt,
            windowDuration: primary.windowDuration,
            planName: planName,
            planBadgeName: planName,
            secondaryWindow: fiveHour == nil ? nil : sevenDay
        )
    }

    private static func planLabels(
        subscriptionType: String?,
        rateLimitTier: String?
    ) -> String? {
        let type = subscriptionType?.lowercased()
        let tier = rateLimitTier?.lowercased() ?? ""
        if type == "max" || type == "claude_max" || tier.contains("claude_max_") {
            if tier.contains("max_20x") { return "Max 20X" }
            if tier.contains("max_5x") { return "Max 5X" }
            return "Max"
        }
        switch type {
        case "pro", "claude_pro": return "Pro"
        case "team", "claude_team": return "Team"
        case "enterprise", "claude_enterprise": return "Enterprise"
        case "free", "claude_free": return "Free"
        default: return nil
        }
    }

    private static func oauthWindow(_ value: Any?, duration: TimeInterval) -> QuotaWindow? {
        guard
            let object = value as? [String: Any],
            let used = percent(object["utilization"])
        else { return nil }
        let reset = (object["resets_at"] as? String).flatMap(parseDate)
        return QuotaWindow(usedPercent: used, resetsAt: reset, windowDuration: duration)
    }

    private static func historyWindow(_ value: Any?, duration: TimeInterval) -> QuotaWindow? {
        guard let used = percent(value) else { return nil }
        // Claude Desktop history has percentages, but no reset timestamps.
        return QuotaWindow(usedPercent: used, windowDuration: duration)
    }

    private static func percent(_ value: Any?) -> Double? {
        guard let number = number(value), (0...100).contains(number) else { return nil }
        return number
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
