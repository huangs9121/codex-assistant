import Foundation

/// Parses Claude usage printed by the official Claude Code CLI and the small, local
/// Claude Desktop history file. Reset times come only from the CLI; the desktop
/// history has none and callers must not infer them.
public enum ClaudeUsageParser {
    public struct CLIAuthStatus: Equatable, Sendable {
        public let loggedIn: Bool
        public let planName: String?
    }

    /// `claude auth status` prints JSON. Only the login state and plan are kept;
    /// account identifiers in the same payload are ignored.
    public static func cliAuthStatus(from data: Data) -> CLIAuthStatus? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let loggedIn = root["loggedIn"] as? Bool
        else { return nil }
        return CLIAuthStatus(
            loggedIn: loggedIn,
            planName: planLabels(subscriptionType: root["subscriptionType"] as? String, rateLimitTier: nil)
        )
    }

    /// `claude -p "/usage"` prints one line per limit, for example
    /// `Current session: 15% used · resets Sep 25 at 10:09pm (Asia/Shanghai)`.
    /// A limit without a `resets` part keeps a nil reset time.
    public static func cliUsageSnapshot(
        from text: String,
        now: Date = Date(),
        planName: String? = nil
    ) -> QuotaSnapshot? {
        var fiveHour: QuotaWindow?
        var sevenDay: QuotaWindow?
        for line in text.split(whereSeparator: \.isNewline) {
            guard let limit = cliLimit(String(line)) else { continue }
            let reset = limit.reset.flatMap { cliResetDate($0, now: now) }
            if limit.title == "current session", fiveHour == nil {
                fiveHour = QuotaWindow(usedPercent: limit.used, resetsAt: reset, windowDuration: 5 * 3_600)
            } else if limit.title == "current week (all models)", sevenDay == nil {
                sevenDay = QuotaWindow(usedPercent: limit.used, resetsAt: reset, windowDuration: 7 * 24 * 3_600)
            }
        }
        return snapshot(fiveHour: fiveHour, sevenDay: sevenDay, observedAt: now, planName: planName)
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

    /// Parses the CLI's English reset text, e.g. `Sep 25 at 10:09pm (Asia/Shanghai)`,
    /// `Sep 30 at 4am (Asia/Shanghai)` or `Jan 2, 2027 at 1am (UTC)`. Unknown formats
    /// or time zones return nil instead of a guess.
    private static func cliResetDate(_ text: String, now: Date) -> Date? {
        let pattern = #"^(?:([A-Za-z]{3,4})\.?\s+(\d{1,2})(?:,\s*(\d{4}))?(?:,|\s+at)?\s+)?(\d{1,2})(?::(\d{2}))?\s*([ap]m)\s*\(([^()]+)\)$"#
        let value = text.replacingOccurrences(of: "\u{202F}", with: " ").trimmingCharacters(in: .whitespaces)
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
        else { return nil }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: value).map { String(value[$0]) }
        }
        guard
            let zoneName = group(7)?.trimmingCharacters(in: .whitespaces),
            let zone = TimeZone(identifier: zoneName) ?? TimeZone(abbreviation: zoneName),
            let hour12 = group(4).flatMap(Int.init), (1...12).contains(hour12),
            let meridiem = group(6)?.lowercased()
        else { return nil }
        let minute = group(5).flatMap(Int.init) ?? 0
        guard (0...59).contains(minute) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        let hasDate = group(1) != nil
        if hasDate {
            guard
                let month = group(1).flatMap(monthNumber),
                let day = group(2).flatMap(Int.init), (1...31).contains(day)
            else { return nil }
            components.month = month
            components.day = day
            if let year = group(3).flatMap(Int.init) { components.year = year }
        }
        components.hour = hour12 % 12 + (meridiem == "pm" ? 12 : 0)
        components.minute = minute
        components.second = 0
        guard var date = calendar.date(from: components) else { return nil }
        // Reject days the calendar would silently roll over, such as Feb 30.
        if hasDate, calendar.component(.day, from: date) != components.day { return nil }
        if hasDate, group(3) == nil, date < now.addingTimeInterval(-86_400) {
            // "Jan 2" printed late in December belongs to the next year.
            guard let next = calendar.date(byAdding: .year, value: 1, to: date) else { return nil }
            date = next
        } else if !hasDate, date < now.addingTimeInterval(-60) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            date = next
        }
        return date
    }

    private static func cliLimit(_ line: String) -> (title: String, used: Double, reset: String?)? {
        let pattern = #"^\s*(Current session|Current week \(all models\)):\s*(\d{1,3}(?:\.\d+)?)%\s+used(?:\s*[·•]\s*resets\s+(.+?))?\s*$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let titleRange = Range(match.range(at: 1), in: line),
            let usedRange = Range(match.range(at: 2), in: line),
            let used = Double(line[usedRange]),
            (0...100).contains(used)
        else { return nil }
        let reset = Range(match.range(at: 3), in: line).map { String(line[$0]) }
        return (line[titleRange].lowercased(), used, reset)
    }

    private static func monthNumber(_ name: String) -> Int? {
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let key = name.lowercased()
        if key == "sept" { return 9 }
        return months.firstIndex(of: key).map { $0 + 1 }
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
}
