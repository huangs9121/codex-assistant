import Foundation

public struct QuotaSnapshot: Equatable, Sendable {
    public let remainingPercent: Int
    public let observedAt: Date
    public let resetsAt: Date?
    public let windowDuration: TimeInterval?
    public let planName: String?

    public init(
        remainingPercent: Int,
        observedAt: Date,
        resetsAt: Date? = nil,
        windowDuration: TimeInterval? = nil,
        planName: String? = nil
    ) {
        self.remainingPercent = remainingPercent
        self.observedAt = observedAt
        self.resetsAt = resetsAt
        self.windowDuration = windowDuration
        self.planName = planName
    }

    public func remainingPercent(at date: Date) -> Int {
        guard let resetsAt, resetsAt <= date else {
            return remainingPercent
        }
        return 100
    }

    public func resetDate(at date: Date) -> Date? {
        guard let resetsAt, resetsAt > date else {
            return nil
        }
        return resetsAt
    }

    public var windowStartedAt: Date? {
        guard
            let resetsAt,
            let windowDuration,
            windowDuration.isFinite,
            windowDuration > 0
        else {
            return nil
        }
        return resetsAt.addingTimeInterval(-windowDuration)
    }
}
