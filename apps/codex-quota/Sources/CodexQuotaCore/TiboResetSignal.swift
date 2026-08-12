import Foundation

public enum TiboResetSignalKind: String, Codable, Sendable {
    case proposal = "reset_proposal"
    case announced = "reset_announced"
    case completed = "reset_completed"

    public var statusText: String {
        statusText(language: .simplifiedChinese)
    }

    public func statusText(language: AppLanguage) -> String {
        switch self {
        case .proposal:
            return language == .simplifiedChinese ? "可能重置" : "Possible"
        case .announced:
            return language == .simplifiedChinese ? "已预告" : "Announced"
        case .completed:
            return language == .simplifiedChinese ? "已发起" : "Started"
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
        timeZone: TimeZone = .current,
        language: AppLanguage = .simplifiedChinese
    ) -> String {
        guard let expectedAt else {
            return localizedExpectationHint(language: language)
        }

        var calendar = calendar
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = language.locale

        if calendar.isDate(expectedAt, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
            let value = formatter.string(from: expectedAt)
            return language == .simplifiedChinese ? "今天 \(value) 前" : "Today by \(value)"
        }
        if
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
            calendar.isDate(expectedAt, inSameDayAs: tomorrow)
        {
            formatter.dateFormat = "HH:mm"
            let value = formatter.string(from: expectedAt)
            return language == .simplifiedChinese ? "明天 \(value) 前" : "Tomorrow by \(value)"
        }
        formatter.dateFormat = language == .simplifiedChinese ? "M月d日 HH:mm" : "MMM d, HH:mm"
        let value = formatter.string(from: expectedAt)
        return language == .simplifiedChinese ? "\(value) 前" : "By \(value)"
    }

    private func localizedExpectationHint(language: AppLanguage) -> String {
        switch expectationHint {
        case "即将进行":
            return language == .simplifiedChinese ? "即将进行" : "Soon"
        case "已发起":
            return language == .simplifiedChinese ? "已发起" : "Started"
        case "时间待确认", nil:
            if kind == .completed {
                return language == .simplifiedChinese ? "已发起" : "Started"
            }
            return language == .simplifiedChinese ? "时间待确认" : "Time to be confirmed"
        default:
            return expectationHint ?? (language == .simplifiedChinese ? "时间待确认" : "Time to be confirmed")
        }
    }

    public func shouldDisplay(at now: Date = Date()) -> Bool {
        guard let expectedAt else {
            return true
        }
        return now < expectedAt
    }

    public func shouldDisplay(
        at now: Date = Date(),
        quotaSnapshot: QuotaSnapshot?
    ) -> Bool {
        guard shouldDisplay(at: now) else {
            return false
        }
        guard let windowStartedAt = quotaSnapshot?.windowStartedAt else {
            return true
        }
        return windowStartedAt < publishedAt
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
                let assessment = assessment(for: post),
                let category = assessment.category,
                let kind = TiboResetSignalKind(rawValue: category),
                let strength = assessment.resetSignalStrength,
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
        let activityType: String?
        let guid: String
        let pubDate: Date
        let title: String
        let link: String
        let tweetAssessment: Assessment?
    }

    private struct Assessment: Decodable {
        let category: String?
        let resetSignalStrength: Double?
    }

    private static func assessment(for post: Post) -> Assessment? {
        if
            let assessment = post.tweetAssessment,
            let category = assessment.category,
            TiboResetSignalKind(rawValue: category) != nil
        {
            return assessment
        }
        guard post.activityType == "post" else {
            return nil
        }

        let text = post.title.lowercased()
        let futureTimingPattern = #"\b(?:(?:in|within|up to)\s+(?:a\s+)?(?:few|[0-9]+)\s+(?:minutes?|hours?|days?)|tomorrow|tonight|this\s+week|this\s+weekend|next\s+week)\b"#
        let intentLanguagePattern = #"\b(?:feel(?:ing)? like|time for|thinking about|might|may|soon|shortly|about to|surprise|stay tuned|coming)\b"#
        let resetPairPattern = #"\b(?:codex|quotas?|limits?|usage)\s+resets?\b|\bresets?\s+(?:the\s+)?(?:codex|quotas?|limits?|usage)\b"#
        let resetPattern = #"\bresets?\b"#
        let resetContextPattern = #"\b(?:codex|quotas?|limits?|usage)\b"#
        let unrelatedResetPattern = #"\bresets?\s+(?:(?:my|your|our|the)\s+)?(?:passwords?|settings?|preferences?|devices?|accounts?)\b|\b(?:passwords?|settings?|preferences?|devices?|accounts?)\s+resets?\b"#

        let assertions = text.split(whereSeparator: { ".!?\n".contains($0) }).map(String.init)
        let resetAssertions = assertions.filter { assertion in
            guard assertion.range(
                of: unrelatedResetPattern,
                options: .regularExpression
            ) == nil else {
                return false
            }
            if assertion.range(of: resetPairPattern, options: .regularExpression) != nil {
                return true
            }
            return assertion.range(of: resetPattern, options: .regularExpression) != nil
                && assertion.range(of: resetContextPattern, options: .regularExpression) != nil
        }
        guard !resetAssertions.isEmpty else {
            return nil
        }

        let hasFutureTiming = text.range(
            of: futureTimingPattern,
            options: .regularExpression
        ) != nil
        let hasIntentLanguage = text.range(
            of: intentLanguagePattern,
            options: .regularExpression
        ) != nil
        guard hasFutureTiming || hasIntentLanguage else {
            return nil
        }
        let hasFutureTimingWithReset = resetAssertions.contains { assertion in
            assertion.range(of: futureTimingPattern, options: .regularExpression) != nil
        }

        return Assessment(
            category: hasFutureTimingWithReset
                ? TiboResetSignalKind.announced.rawValue
                : TiboResetSignalKind.proposal.rawValue,
            resetSignalStrength: hasFutureTimingWithReset ? 75 : 60
        )
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
        if lowercased.range(
            of: #"(?:in|within|up to)\s+(?:a\s+)?few\s+hours"#,
            options: .regularExpression
        ) != nil {
            return (publishedAt.addingTimeInterval(3 * 3_600), nil)
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
