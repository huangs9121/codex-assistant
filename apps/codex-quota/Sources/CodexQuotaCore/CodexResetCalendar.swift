import Foundation

/// AIHOT's public calendar contract. Source passages are display data, never instructions.
public struct CodexResetFeed: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let timezone: String
    public let checkedAt: Date?
    public let historyFrom: Date
    public let count: Int
    public let events: [CodexResetEvent]

    public static let apiURL = URL(string: "https://aihot.news/api/v1/codex-resets")!
    public static let calendarURL = URL(string: "https://aihot.news/codex-reset")!
    public static let pollInterval: TimeInterval = 300

    public static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 timestamp")
            }
            return date
        }
        let feed = try decoder.decode(Self.self, from: data)
        guard feed.schemaVersion == 1, feed.timezone == "Asia/Shanghai",
              feed.count == feed.events.count,
              Set(feed.events.map(\.id)).count == feed.count,
              feed.events.allSatisfy({ event in
                  !event.id.isEmpty && event.posts.allSatisfy { $0.sourceURL != nil }
                      && (event.schedule.map { $0.from <= $0.through } ?? true)
              }) else { throw CalendarError.invalidSnapshot }
        return feed
    }

    public enum CalendarError: Error { case invalidSnapshot }

    /// updatedAt includes retrospective corrections; it is not a new reset time.
    public func latestEvent(now: Date = Date()) -> CodexResetEvent? {
        events.filter { $0.activityAt <= now.addingTimeInterval(300) }
            .max { ($0.activityAt, $0.id) < ($1.activityAt, $1.id) }
    }

    public func upcomingAnnouncement(now: Date = Date()) -> CodexResetEvent? {
        events.filter { $0.isUpcoming(now: now) }
            .max { ($0.activityAt, $0.id) < ($1.activityAt, $1.id) }
    }

    public func isVerificationDelayed(now: Date = Date()) -> Bool {
        guard let checkedAt else { return true }
        return now.timeIntervalSince(checkedAt) > 3 * Self.pollInterval
            || checkedAt.timeIntervalSince(now) > 300
    }

    public var noticeKeys: Set<String> {
        Set(events.flatMap(\.noticeKeys))
    }

    public func notificationCandidates(seen: Set<String>, now: Date = Date()) -> [CodexResetEvent] {
        events.filter { event in
            let age = now.timeIntervalSince(event.activityAt)
            return event.latestPost != nil && age >= -300 && age <= 72 * 3_600
                && !seen.contains(event.noticeKey)
                // A correction from confirmed back to announced is not a new announcement.
                && !(event.status == .announced && seen.contains(event.noticeKey(status: .confirmed)))
        }.sorted { ($0.activityAt, $0.id) < ($1.activityAt, $1.id) }
    }
}

public struct CodexResetEvent: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case directReset = "direct_reset", resetCredit = "reset_credit" }
    public enum Status: String, Codable, Sendable { case announced, confirmed }
    public enum ConfirmationBasis: String, Codable, Sendable { case sourcePost = "source_post", receiptReview = "receipt_review" }

    public let id: String
    public let type: Kind
    public let label: String
    public let status: Status
    public let title: String
    public let scope: String
    public let createdAt: Date
    public let updatedAt: Date
    public let confirmedAt: Date?
    public let occurredOn: String?
    public let confirmationBasis: ConfirmationBasis?
    public let schedule: CodexResetSchedule?
    public let posts: [CodexResetPost]
    public let url: URL

    public var latestPost: CodexResetPost? { posts.max { ($0.publishedAt, $0.id) < ($1.publishedAt, $1.id) } }
    public var activityAt: Date { max(createdAt, confirmedAt ?? createdAt, latestPost?.publishedAt ?? createdAt) }
    public var sourceURL: URL? { latestPost?.sourceURL }
    public func isUpcoming(now: Date = Date()) -> Bool {
        guard status == .announced, activityAt <= now.addingTimeInterval(300) else { return false }
        if let schedule { return schedule.through > now }
        // Unknown-time announcements cannot remain on the panel indefinitely.
        return now.timeIntervalSince(activityAt) <= 72 * 3_600
    }
    public var noticeKey: String { noticeKey(status: status) }
    public func noticeKey(status: Status) -> String {
        "\(type.rawValue)|\(status.rawValue)|\(latestPost?.id ?? id)"
    }
    public var noticeKeys: [String] { posts.map { "\(type.rawValue)|\(status.rawValue)|\($0.id)" } }

    public func kindText(language: AppLanguage = .simplifiedChinese) -> String {
        if language == .english { return type == .directReset ? "Global reset" : "Reset credit" }
        return type == .directReset ? "全员重置" : "发重置卡"
    }

    public func statusText(now: Date = Date(), language: AppLanguage = .simplifiedChinese) -> String {
        if status == .confirmed {
            return language == .english ? "Confirmed" : (type == .directReset ? "已确认" : "已发卡")
        }
        if let schedule, now > schedule.through {
            return language == .english ? "Awaiting confirmation" : "待确认"
        }
        return language == .english ? "Announced" : "已预告"
    }

    public func timeText(now: Date = Date(), language: AppLanguage = .simplifiedChinese) -> String {
        if status == .confirmed {
            if let confirmedAt {
                let time = Self.beijingTime(confirmedAt)
                return language == .english ? "Confirmed \(time) · Beijing" : "\(time) 确认 · 北京时间"
            }
            if let occurredOn {
                return language == .english ? "Verified day \(occurredOn) · Beijing" : "核验发放日 \(occurredOn) · 北京时间"
            }
            return language == .english ? "Delivery time unknown" : "具体到账时间未知"
        }
        guard let schedule else {
            return language == .english ? "Time not announced" : "时间未公布"
        }
        let label = schedule.timeText(language: language)
        return now > schedule.through
            ? (language == .english ? "Estimate passed · \(label)" : "预期已过 · \(label)") : label
    }

    public func detailText(now: Date = Date(), language: AppLanguage = .simplifiedChinese) -> String {
        var lines = [kindText(language: language) + " · " + statusText(now: now, language: language), timeText(now: now, language: language)]
        if !scope.isEmpty { lines.append((language == .english ? "Scope: " : "适用范围：") + scope) }
        if let post = latestPost { lines.append(language == .english ? post.originalText : post.text) }
        if status == .confirmed, let schedule {
            lines.append((language == .english ? "Original estimate: " : "原预告：") + schedule.timeText(language: language))
        }
        if confirmationBasis == .receiptReview {
            lines.append(language == .english ? "AIHOT verified delivery reports; no confirmation post time." : "AIHOT 依据到账反馈核验；没有确认帖时间。")
        }
        lines.append(language == .english ? "AIHOT public record; account quota and credit balance are separate." : "AIHOT 公开记录；确认帖时间不等于个人到账时间，发卡不代表额度已恢复。")
        return lines.joined(separator: "\n")
    }

    public static func beijingTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}

public struct CodexResetSchedule: Codable, Equatable, Sendable {
    public enum Precision: String, Codable, Sendable { case exact, approximate, deadline, date, window }
    public let precision: Precision
    public let from: Date
    public let through: Date
    public let label: String

    public func timeText(language: AppLanguage) -> String {
        if language == .simplifiedChinese { return label }
        let start = CodexResetEvent.beijingTime(from)
        let end = CodexResetEvent.beijingTime(through)
        switch precision {
        case .exact: return "Expected \(start) · Beijing"
        case .approximate: return "Around \(start) · Beijing"
        case .deadline: return "Expected by \(end) · Beijing"
        case .date, .window: return "Expected \(start)–\(end) · Beijing"
        }
    }
}

public struct CodexResetPost: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let publishedAt: Date
    public let stage: String
    public let text: String
    public let originalText: String
    public let url: URL

    public var sourceURL: URL? {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              ["x.com", "twitter.com"].contains(url.host?.lowercased() ?? "") else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count == 3, parts[0].lowercased() == "thsottiaux", parts[1] == "status",
              !parts[2].isEmpty, parts[2].allSatisfy(\.isNumber) else { return nil }
        return url
    }
}

/// The ETag and its complete snapshot persist atomically. The first sync is silent.
public struct CodexResetCache: Codable, Equatable, Sendable {
    public var feed: CodexResetFeed
    public var etag: String?
    public var receivedAt: Date
    public var seenNoticeKeys: Set<String>

    public init(feed: CodexResetFeed, etag: String?, receivedAt: Date = Date(), previous: Self? = nil) {
        self.feed = feed
        self.etag = etag
        self.receivedAt = receivedAt
        seenNoticeKeys = previous?.seenNoticeKeys ?? feed.noticeKeys
        let pendingKeys = Set(feed.notificationCandidates(seen: seenNoticeKeys, now: receivedAt).map(\.noticeKey))
        seenNoticeKeys.formUnion(feed.noticeKeys.subtracting(pendingKeys))
    }
}
