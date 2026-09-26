import CodexQuotaCore
import Foundation

enum ClaudeUsageTests {
    static var all: [(String, () -> Bool)] { [
        ("Claude CLI usage keeps exact five-hour and weekly resets", cliWindows),
        ("Claude CLI usage keeps a missing session reset empty", cliMissingSessionReset),
        ("Claude CLI reset text handles whole hours, years and rollover", cliResetVariants),
        ("Claude CLI usage ignores other lines and rejects bad values", cliIgnoresNoise),
        ("Claude CLI weekly-only account remains readable", cliWeeklyOnly),
        ("Claude CLI auth status keeps only login state and plan", cliAuthStatus),
        ("Claude Desktop history uses newest complete sample", latestHistory),
        ("Claude Desktop history never invents resets", historyHasNoReset),
        ("Claude Desktop history rejects malformed values", malformedHistory)
    ] }

    private static func data(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    /// Output captured from Claude Code 2.1.281 on 2026-09-25 17:31 Asia/Shanghai.
    private static func cliWindows() -> Bool {
        let text = """
        You are currently using your subscription to power your Claude Code usage

        Current session: 15% used · resets Sep 25 at 10:09pm (Asia/Shanghai)
        Current week (all models): 3% used · resets Sep 30 at 3:59am (Asia/Shanghai)
        """
        let snapshot = ClaudeUsageParser.cliUsageSnapshot(
            from: text, now: date("2026-09-25T09:31:36Z"), planName: "Pro")
        return snapshot?.remainingPercent == 85
            && snapshot?.windowDuration == 18_000
            && snapshot?.resetsAt == date("2026-09-25T14:09:00Z")
            && snapshot?.planBadgeName == "Pro"
            && snapshot?.secondaryWindow?.usedPercent == 3
            && snapshot?.secondaryWindow?.windowDuration == 604_800
            && snapshot?.secondaryWindow?.resetsAt == date("2026-09-29T19:59:00Z")
    }

    private static func cliMissingSessionReset() -> Bool {
        let text = """
        Current session: 0% used
        Current week (all models): 2% used · resets Sep 30 at 4am (Asia/Shanghai)
        """
        let snapshot = ClaudeUsageParser.cliUsageSnapshot(from: text, now: date("2026-09-25T08:29:00Z"))
        return snapshot?.remainingPercent == 100
            && snapshot?.resetsAt == nil
            && snapshot?.secondaryWindow?.resetsAt == date("2026-09-29T20:00:00Z")
    }

    private static func cliResetVariants() -> Bool {
        func weekReset(_ reset: String, now: String) -> Date? {
            ClaudeUsageParser.cliUsageSnapshot(
                from: "Current week (all models): 50% used · resets \(reset)", now: date(now))?.resetsAt
        }
        let wholeHour = weekReset("Sep 30 at 4am (Asia/Shanghai)", now: "2026-09-26T00:00:00Z")
        let withYear = weekReset("Jan 2, 2027 at 1:05am (UTC)", now: "2026-12-31T22:00:00Z")
        let rollover = weekReset("Jan 2 at 9am (UTC)", now: "2026-12-31T20:00:00Z")
        let olderFormat = weekReset("Sep 30, 4:00 AM (Asia/Shanghai)", now: "2026-09-26T00:00:00Z")
        let otherZone = weekReset("Oct 1 at 9:15pm (America/Los_Angeles)", now: "2026-09-26T00:00:00Z")
        let unknownZone = ClaudeUsageParser.cliUsageSnapshot(
            from: "Current week (all models): 10% used · resets Oct 1 at 9am (Mars/Base)",
            now: date("2026-09-26T00:00:00Z"))
        let impossibleDay = weekReset("Feb 30 at 9am (UTC)", now: "2026-02-20T00:00:00Z")
        return wholeHour == date("2026-09-29T20:00:00Z")
            && withYear == date("2027-01-02T01:05:00Z")
            && rollover == date("2027-01-02T09:00:00Z")
            && olderFormat == date("2026-09-29T20:00:00Z")
            && otherZone == date("2026-10-02T04:15:00Z")
            && unknownZone?.remainingPercent == 90 && unknownZone?.resetsAt == nil
            && impossibleDay == nil
    }

    private static func cliIgnoresNoise() -> Bool {
        let text = """
        You are currently using your subscription to power your Claude Code usage
        Current session: 150% used · resets Sep 25 at 10:09pm (Asia/Shanghai)
        Current week (Sonnet only): 40% used · resets Sep 30 at 4am (Asia/Shanghai)
        Current week (all models): 3% used · resets Sep 30 at 4am (Asia/Shanghai)

        What's contributing to your limits usage?
        Last 24h · 114 requests · 2 sessions
          77% of your usage was at >150k context
        """
        let snapshot = ClaudeUsageParser.cliUsageSnapshot(from: text, now: date("2026-09-25T09:31:36Z"))
        return snapshot?.remainingPercent == 97
            && snapshot?.windowDuration == 604_800
            && snapshot?.secondaryWindow == nil
            && ClaudeUsageParser.cliUsageSnapshot(from: "Not logged in · Please run /login") == nil
            && ClaudeUsageParser.cliUsageSnapshot(from: "") == nil
    }

    private static func cliWeeklyOnly() -> Bool {
        let snapshot = ClaudeUsageParser.cliUsageSnapshot(
            from: "Current week (all models): 13% used · resets Sep 30 at 8pm (UTC)",
            now: date("2026-09-26T00:00:00Z"))
        return snapshot?.remainingPercent == 87
            && snapshot?.windowDuration == 604_800
            && snapshot?.resetsAt == date("2026-09-30T20:00:00Z")
            && snapshot?.secondaryWindow == nil
    }

    private static func cliAuthStatus() -> Bool {
        let pro = ClaudeUsageParser.cliAuthStatus(from: data([
            "loggedIn": true, "authMethod": "claude.ai", "subscriptionType": "pro",
            "email": "someone@example.com", "orgId": "org"
        ]))
        let max = ClaudeUsageParser.cliAuthStatus(from: data(["loggedIn": true, "subscriptionType": "max"]))
        let loggedOut = ClaudeUsageParser.cliAuthStatus(from: data(["loggedIn": false]))
        return pro?.loggedIn == true && pro?.planName == "Pro"
            && max?.planName == "Max"
            && loggedOut?.loggedIn == false && loggedOut?.planName == nil
            && ClaudeUsageParser.cliAuthStatus(from: Data("not json".utf8)) == nil
    }

    private static func latestHistory() -> Bool {
        let snapshot = ClaudeUsageParser.desktopHistorySnapshot(from: data([
            "version": 2,
            "samples": [
                ["t": 2_000, "org": "account-a", "u": ["fh": 4, "sd": 1]],
                ["t": 1_000, "org": "account-b", "u": ["fh": 90, "sd": 95]],
                ["t": 3_000, "org": "account-a", "u": ["fh": 7, "sd": 2]]
            ]
        ]))
        return snapshot?.remainingPercent == 93
            && snapshot?.secondaryWindow?.usedPercent == 2
            && snapshot?.observedAt.timeIntervalSince1970 == 3
    }

    private static func historyHasNoReset() -> Bool {
        let snapshot = ClaudeUsageParser.desktopHistorySnapshot(from: data([
            "version": 2,
            "samples": [["t": 1_000, "u": ["fh": 4, "sd": 0]]]
        ]))
        return snapshot?.remainingPercent == 96
            && snapshot?.resetsAt == nil
            && snapshot?.secondaryWindow?.resetsAt == nil
    }

    private static func malformedHistory() -> Bool {
        ClaudeUsageParser.desktopHistorySnapshot(from: data([
            "samples": [["t": 1_000, "u": ["fh": true, "sd": 500]]]
        ])) == nil
    }
}
