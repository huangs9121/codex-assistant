import CodexQuotaCore
import CodexQuotaUI
import Foundation

enum CodexResetCalendarTests {
    static var all: [(String, () -> Bool)] { [
        ("AIHOT accepts offset and fractional timestamps from the v1 contract", testDates),
        ("AIHOT latest activity ignores retrospective updatedAt edits", testLatest),
        ("AIHOT confirmation time remains distinct from the original deadline", testConfirmation),
        ("AIHOT receipt verification never fabricates a confirmation time", testReceipt),
        ("AIHOT overdue announcements remain unconfirmed", testOverdue),
        ("AIHOT retains schedule precision and English Beijing labels", testSchedule),
        ("AIHOT first synchronization silently baselines all history", testBootstrap),
        ("AIHOT notices distinguish reset and reset-credit updates", testTypes),
        ("AIHOT notices ignore translation edits and regrouped event IDs", testCorrections),
        ("AIHOT notices include new confirmations and deduplicate delivery", testUpgrade),
        ("AIHOT removes withdrawn records by replacing the full snapshot", testWithdrawal),
        ("AIHOT stale verification and missing checkedAt stay explicit", testFreshness),
        ("AIHOT rejects invalid schemas and unsafe source URLs", testValidation),
        ("AIHOT panel hides confirmed and expired announcements", testUpcomingOnly),
        ("AIHOT panel expires unknown-time announcements after 72 hours", testUnknownTimeExpiry),
        ("AIHOT persists the snapshot ETag and notification ledger together", testPreferences)
    ] }

    static let now = ISO8601DateFormatter().date(from: "2026-09-13T09:00:00Z")!
    static func event(_ id: String = "100", type: String = "direct_reset", status: String = "announced") -> [String: Any] {
        ["id": "event-" + id, "type": type, "label": type == "direct_reset" ? "全员重置" : "发重置卡",
         "status": status, "title": "测试记录", "scope": "", "createdAt": "2026-09-12T11:20:36.000+08:00",
         "updatedAt": "2026-09-12T11:20:36.000+08:00", "confirmedAt": NSNull(), "occurredOn": NSNull(),
         "confirmationBasis": NSNull(), "schedule": ["precision": "deadline", "from": "2026-09-12T15:00:00.000+08:00", "through": "2026-09-12T15:00:00.000+08:00", "label": "北京时间预计 9月12日 15:00 前"],
         "posts": [["id": id, "publishedAt": "2026-09-12T11:20:36.000+08:00", "stage": "预告", "text": "测试译文", "originalText": "Test source", "url": "https://x.com/thsottiaux/status/" + id]],
         "url": "https://aihot.news/codex-reset"]
    }
    static func data(_ events: [[String: Any]], checked: Any = "2026-09-13T16:59:00.000+08:00", version: Int = 1) -> Data {
        try! JSONSerialization.data(withJSONObject: ["schemaVersion": version, "timezone": "Asia/Shanghai", "checkedAt": checked, "historyFrom": "2026-06-12T00:00:00+08:00", "count": events.count, "events": events])
    }
    static func feed(_ events: [[String: Any]]) -> CodexResetFeed { try! .decode(data(events)) }
    static func confirmed() -> [String: Any] {
        var value = event(status: "confirmed")
        value["confirmedAt"] = "2026-09-12T16:09:17.000+08:00"
        value["confirmationBasis"] = "source_post"
        return value
    }

    static func testDates() -> Bool {
        let f = feed([event()])
        return f.count == 1 && f.events[0].createdAt.timeIntervalSince1970 == 1_789_183_236
            && CodexResetEvent.beijingTime(f.events[0].schedule!.through) == "9/12 15:00"
    }
    static func testUpcomingOnly() -> Bool {
        guard feed([confirmed(), event("101")]).upcomingAnnouncement(now: now) == nil else { return false }
        var future = event("102")
        future["schedule"] = ["precision": "deadline", "from": "2026-09-14T15:00:00+08:00", "through": "2026-09-14T15:00:00+08:00", "label": "北京时间预计 9月14日 15:00 前"]
        let f = feed([confirmed(), event("101"), future])
        guard let upcoming = f.upcomingAnnouncement(now: now), upcoming.id == "event-102" else { return false }
        return f.upcomingAnnouncement(now: upcoming.schedule!.through) == nil
            && f.upcomingAnnouncement(now: upcoming.schedule!.through.addingTimeInterval(-1))?.id == upcoming.id
    }
    static func testUnknownTimeExpiry() -> Bool {
        var v = event(); v["schedule"] = NSNull()
        let f = feed([v]); let published = f.events[0].activityAt
        return f.upcomingAnnouncement(now: published.addingTimeInterval(72 * 3_600)) != nil
            && f.upcomingAnnouncement(now: published.addingTimeInterval(72 * 3_600 + 1)) == nil
    }
    static func testLatest() -> Bool {
        var old = event("101", type: "reset_credit", status: "confirmed")
        old["createdAt"] = "2026-09-04T07:12:09+08:00"
        old["updatedAt"] = "2026-09-13T10:36:02+08:00"
        old["posts"] = []
        return feed([old, confirmed()]).latestEvent(now: now)?.type == .directReset
    }
    static func testConfirmation() -> Bool {
        let e = feed([confirmed()]).events[0]
        return e.timeText(now: now) == "9/12 16:09 确认 · 北京时间"
            && e.detailText(now: now).contains("原预告：北京时间预计 9月12日 15:00 前")
            && e.status == .confirmed
    }
    static func testReceipt() -> Bool {
        var v = event(type: "reset_credit", status: "confirmed")
        v["confirmationBasis"] = "receipt_review"
        let unknown = feed([v]).events[0]
        v["occurredOn"] = "2026-09-12"
        let day = feed([v]).events[0]
        return unknown.confirmedAt == nil && unknown.timeText(now: now) == "具体到账时间未知"
            && day.timeText(now: now) == "核验发放日 2026-09-12 · 北京时间"
            && !day.timeText(now: now).contains("15:00")
    }
    static func testOverdue() -> Bool {
        let e = feed([event()]).events[0]
        return e.status == .announced && e.statusText(now: now) == "待确认"
            && e.timeText(now: now).hasPrefix("预期已过") && e.confirmedAt == nil
    }
    static func testSchedule() -> Bool {
        for precision in ["exact", "approximate", "deadline", "date", "window"] {
            var v = event(); var schedule = v["schedule"] as! [String: Any]
            schedule["precision"] = precision; v["schedule"] = schedule
            let e = feed([v]).events[0]
            guard e.schedule?.precision.rawValue == precision,
                  e.timeText(now: now, language: .english).contains("Beijing") else { return false }
        }
        var v = event(); v["schedule"] = NSNull()
        return feed([v]).events[0].timeText(now: now) == "时间未公布"
    }
    static func testBootstrap() -> Bool {
        let f = feed([event(), event("101", type: "reset_credit")])
        let cache = CodexResetCache(feed: f, etag: "first", receivedAt: now)
        return f.notificationCandidates(seen: cache.seenNoticeKeys, now: now).isEmpty
    }
    static func testTypes() -> Bool {
        let f = feed([event(), event("100", type: "reset_credit").merging(["id": "credit-100"], uniquingKeysWith: { _, new in new })])
        let notices = f.notificationCandidates(seen: [], now: now)
        return notices.count == 2 && Set(notices.map(\.noticeKey)).count == 2
            && Set(notices.map { $0.kindText() }) == ["全员重置", "发重置卡"]
    }
    static func testCorrections() -> Bool {
        let original = feed([event()])
        var v = event(); v["id"] = "regrouped"; v["updatedAt"] = "2026-09-13T16:59:00+08:00"
        var posts = v["posts"] as! [[String: Any]]; posts[0]["text"] = "修订译文"; v["posts"] = posts
        return feed([v]).notificationCandidates(seen: original.noticeKeys, now: now).isEmpty
    }
    static func testUpgrade() -> Bool {
        let original = feed([event()]); let updated = feed([confirmed()])
        var cache = CodexResetCache(feed: updated, etag: "next", receivedAt: now, previous: .init(feed: original, etag: "old", receivedAt: now))
        let candidates = updated.notificationCandidates(seen: cache.seenNoticeKeys, now: now)
        guard candidates.count == 1 else { return false }
        cache.seenNoticeKeys.insert(candidates[0].noticeKey)
        return updated.notificationCandidates(seen: cache.seenNoticeKeys, now: now).isEmpty
            && original.notificationCandidates(seen: cache.seenNoticeKeys, now: now).isEmpty
    }
    static func testWithdrawal() -> Bool {
        let original = CodexResetCache(feed: feed([event(), event("101")]), etag: "old", receivedAt: now)
        let cache = CodexResetCache(feed: feed([]), etag: "empty", receivedAt: now, previous: original)
        return cache.feed.events.isEmpty && cache.feed.latestEvent(now: now) == nil
            && cache.seenNoticeKeys == original.seenNoticeKeys && cache.etag == "empty"
    }
    static func testFreshness() -> Bool {
        let missing = try! CodexResetFeed.decode(data([], checked: NSNull()))
        return missing.isVerificationDelayed(now: now)
            && !feed([]).isVerificationDelayed(now: now)
            && feed([]).isVerificationDelayed(now: now.addingTimeInterval(1_800))
    }
    static func testValidation() -> Bool {
        guard (try? CodexResetFeed.decode(data([], version: 2))) == nil else { return false }
        for url in ["http://x.com/thsottiaux/status/100", "https://x.com.evil.test/thsottiaux/status/100", "https://x.com/other/status/100", "https://user@x.com/thsottiaux/status/100"] {
            var v = event(); var posts = v["posts"] as! [[String: Any]]; posts[0]["url"] = url; v["posts"] = posts
            guard (try? CodexResetFeed.decode(data([v]))) == nil else { return false }
        }
        return (try? CodexResetFeed.decode(Data("{}".utf8))) == nil
    }
    static func testPreferences() -> Bool {
        let suite = "CodexResetCalendarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = DisplayPreferences(defaults: defaults)
        let cache = CodexResetCache(feed: feed([event()]), etag: "W/\"test\"", receivedAt: now)
        preferences.resetCalendarCache = cache
        guard DisplayPreferences(defaults: defaults).resetCalendarCache == cache else { return false }
        preferences.resetCalendarCache = nil
        return defaults.object(forKey: DisplayPreferences.resetCalendarCacheKey) == nil
    }
}
