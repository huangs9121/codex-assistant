import Foundation

public enum TiboResetSignalKind: String, Codable, Sendable {
    case proposal = "reset_proposal"
    case announced = "reset_announced"
    case completed = "reset_completed"

    public var statusText: String {
        switch self {
        case .proposal:
            return "可能重置"
        case .announced:
            return "已预告"
        case .completed:
            return "已发起"
        }
    }
}

public struct TiboResetSignal: Codable, Equatable, Sendable {
    public let id: String
    public let kind: TiboResetSignalKind
    public let publishedAt: Date
    public let text: String
    public let url: URL
    public let signalStrength: Double
    public let expectedAt: Date?
    public let expectationHint: String?

    public init(
        id: String,
        kind: TiboResetSignalKind,
        publishedAt: Date,
        text: String,
        url: URL,
        signalStrength: Double,
        expectedAt: Date?,
        expectationHint: String?
    ) {
        self.id = id
        self.kind = kind
        self.publishedAt = publishedAt
        self.text = text
        self.url = url
        self.signalStrength = signalStrength
        self.expectedAt = expectedAt
        self.expectationHint = expectationHint
    }

    public func expectedTimeText(
        now: Date = Date(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        guard let expectedAt else {
            return expectationHint ?? (kind == .completed ? "已发起" : "时间待确认")
        }

        var calendar = calendar
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "zh_CN")

        if calendar.isDate(expectedAt, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
            return "今天 \(formatter.string(from: expectedAt)) 前"
        }
        if
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
            calendar.isDate(expectedAt, inSameDayAs: tomorrow)
        {
            formatter.dateFormat = "HH:mm"
            return "明天 \(formatter.string(from: expectedAt)) 前"
        }
        formatter.dateFormat = "M月d日 HH:mm"
        return "\(formatter.string(from: expectedAt)) 前"
    }

    public func shouldDisplay(at now: Date = Date()) -> Bool {
        guard let expectedAt else {
            return true
        }
        return now < expectedAt
    }

    public static func latest(
        from data: Data,
        now: Date = Date(),
        maximumAge: TimeInterval = 72 * 3_600
    ) throws -> TiboResetSignal? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = internetDate(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid internet date"
                )
            }
            return date
        }
        let response = try decoder.decode(ForecastResponse.self, from: data)
        if response.sourceErrors?.hasTiboError == true {
            return nil
        }

        return response.tiboPosts.compactMap { post -> TiboResetSignal? in
            guard
                let category = post.tweetAssessment?.category,
                let kind = TiboResetSignalKind(rawValue: category),
                let strength = post.tweetAssessment?.resetSignalStrength,
                strength >= 50,
                !post.guid.isEmpty,
                !post.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                now.timeIntervalSince(post.pubDate) >= 0,
                now.timeIntervalSince(post.pubDate) <= maximumAge,
                let url = validatedTiboURL(post.link)
            else {
                return nil
            }
            let expectation = expectedTime(
                for: post.title,
                publishedAt: post.pubDate,
                kind: kind
            )
            return TiboResetSignal(
                id: post.guid,
                kind: kind,
                publishedAt: post.pubDate,
                text: post.title.trimmingCharacters(in: .whitespacesAndNewlines),
                url: url,
                signalStrength: strength,
                expectedAt: expectation.date,
                expectationHint: expectation.hint
            )
        }
        .max { $0.publishedAt < $1.publishedAt }
    }

    private struct ForecastResponse: Decodable {
        let sourceErrors: SourceErrors?
        let tiboPosts: [Post]
    }

    private struct SourceErrors: Decodable {
        let hasTiboError: Bool

        private enum CodingKeys: String, CodingKey {
            case tibo
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.tibo) {
                hasTiboError = try !container.decodeNil(forKey: .tibo)
            } else {
                hasTiboError = false
            }
        }
    }

    private struct Post: Decodable {
        let guid: String
        let pubDate: Date
        let title: String
        let link: String
        let tweetAssessment: Assessment?
    }

    private struct Assessment: Decodable {
        let category: String
        let resetSignalStrength: Double?
    }

    private static func validatedTiboURL(_ value: String) -> URL? {
        guard
            let url = URL(string: value),
            url.scheme == "https",
            ["x.com", "twitter.com"].contains(url.host?.lowercased()),
            url.path.range(
                of: #"^/thsottiaux/status/[0-9]+/?$"#,
                options: .regularExpression
            ) != nil
        else {
            return nil
        }
        return url
    }

    private static func expectedTime(
        for text: String,
        publishedAt: Date,
        kind: TiboResetSignalKind
    ) -> (date: Date?, hint: String?) {
        let lowercased = text.lowercased()
        if lowercased.range(
            of: #"(?:in|within|up to)\s+(?:a\s+)?few\s+minutes"#,
            options: .regularExpression
        ) != nil {
            return (publishedAt.addingTimeInterval(15 * 60), nil)
        }

        let pattern = #"(?:in|within|up to)\s+([0-9]+)\s*(minutes?|hours?|days?)"#
        if
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: lowercased,
                range: NSRange(lowercased.startIndex..., in: lowercased)
            ),
            let amountRange = Range(match.range(at: 1), in: lowercased),
            let unitRange = Range(match.range(at: 2), in: lowercased),
            let amount = Double(lowercased[amountRange])
        {
            let unit = lowercased[unitRange]
            let seconds: TimeInterval
            if unit.hasPrefix("minute") {
                seconds = amount * 60
            } else if unit.hasPrefix("hour") {
                seconds = amount * 3_600
            } else {
                seconds = amount * 86_400
            }
            return (publishedAt.addingTimeInterval(seconds), nil)
        }

        if lowercased.range(of: #"\btomorrow\b"#, options: .regularExpression) != nil {
            return (publishedAt.addingTimeInterval(86_400), nil)
        }
        if lowercased.range(
            of: #"\b(?:soon|shortly|imminent|about to)\b"#,
            options: .regularExpression
        ) != nil {
            return (nil, "即将进行")
        }
        return (nil, kind == .completed ? "已发起" : "时间待确认")
    }

    private static func internetDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}
