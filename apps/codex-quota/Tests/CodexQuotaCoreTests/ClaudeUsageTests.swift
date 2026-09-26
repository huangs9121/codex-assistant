import CodexQuotaCore
import Foundation

enum ClaudeUsageTests {
    static var all: [(String, () -> Bool)] { [
        ("Claude OAuth keeps exact five-hour and weekly resets", oauthWindows),
        ("Claude trusted credential metadata sets Pro and Max badges", planBadges),
        ("Claude Desktop history uses newest complete sample", latestHistory),
        ("Claude Desktop history never invents resets", historyHasNoReset),
        ("Claude refresh preserves unrelated credential fields", preservesCredentialFields),
        ("Claude rejects malformed and out-of-range usage", malformedValues),
        ("Claude weekly-only account remains readable", weeklyOnly)
    ] }

    private static func data(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private static func oauthWindows() -> Bool {
        let snapshot = ClaudeUsageParser.oauthSnapshot(from: data([
            "five_hour": ["utilization": 4, "resets_at": "2026-09-25T06:40:00Z"],
            "seven_day": ["utilization": 0, "resets_at": "2026-09-29T20:00:00.000Z"]
        ]))
        return snapshot?.remainingPercent == 96
            && snapshot?.windowDuration == 18_000
            && snapshot?.resetsAt != nil
            && snapshot?.secondaryWindow?.usedPercent == 0
            && snapshot?.secondaryWindow?.windowDuration == 604_800
            && snapshot?.secondaryWindow?.resetsAt != nil
    }

    private static func planBadges() -> Bool {
        let payload = data(["five_hour": ["utilization": 4]])
        let pro = ClaudeUsageParser.oauthSnapshot(
            from: payload, subscriptionType: "pro")
        let max = ClaudeUsageParser.oauthSnapshot(
            from: payload,
            subscriptionType: "max",
            rateLimitTier: "default_claude_max_20x"
        )
        let unknown = ClaudeUsageParser.oauthSnapshot(
            from: payload, subscriptionType: "unexpected")
        return pro?.planName == "Pro" && pro?.planBadgeName == "Pro"
            && max?.planName == "Max 20X" && max?.planBadgeName == "Max 20X"
            && unknown?.planName == nil
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

    private static func preservesCredentialFields() -> Bool {
        let original = data([
            "claudeAiOauth": [
                "accessToken": "old-access", "refreshToken": "old-refresh",
                "expiresAt": 1_000, "scopes": ["user:profile"],
                "subscriptionType": "pro"
            ],
            "mcpOAuth": ["example": "untouched"],
            "unrelated": true
        ])
        let updated = ClaudeUsageParser.refreshedCredentialData(
            from: original,
            accessToken: "new-access",
            refreshToken: "new-refresh",
            expiresAt: Date(timeIntervalSince1970: 2_000)
        )
        guard let updated,
              let root = try? JSONSerialization.jsonObject(with: updated) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any] else { return false }
        return oauth["accessToken"] as? String == "new-access"
            && oauth["refreshToken"] as? String == "new-refresh"
            && (oauth["expiresAt"] as? NSNumber)?.doubleValue == 2_000_000
            && oauth["scopes"] as? [String] == ["user:profile"]
            && oauth["subscriptionType"] as? String == "pro"
            && root["mcpOAuth"] as? [String: String] == ["example": "untouched"]
            && root["unrelated"] as? Bool == true
    }

    private static func malformedValues() -> Bool {
        ClaudeUsageParser.oauthSnapshot(from: data([
            "five_hour": ["utilization": 101],
            "seven_day": ["utilization": -1]
        ])) == nil
            && ClaudeUsageParser.desktopHistorySnapshot(from: data([
                "samples": [["t": 1_000, "u": ["fh": true, "sd": 500]]]
            ])) == nil
    }

    private static func weeklyOnly() -> Bool {
        let snapshot = ClaudeUsageParser.oauthSnapshot(from: data([
            "five_hour": NSNull(),
            "seven_day": ["utilization": 13, "resets_at": "2026-09-30T12:00:00Z"]
        ]))
        return snapshot?.remainingPercent == 87
            && snapshot?.windowDuration == 604_800
            && snapshot?.secondaryWindow == nil
    }
}
