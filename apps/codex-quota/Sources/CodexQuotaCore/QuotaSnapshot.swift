import Foundation

public struct QuotaWindow: Equatable, Sendable {
    public let usedPercent: Double
    public let resetsAt: Date?
    public let windowDuration: TimeInterval?

    public init(
        usedPercent: Double,
        resetsAt: Date? = nil,
        windowDuration: TimeInterval? = nil
    ) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowDuration = windowDuration
    }

    public func remainingPercent(at date: Date) -> Int {
        guard let resetsAt, resetsAt <= date else {
            return Int(min(max((100 - usedPercent).rounded(), 0), 100))
        }
        return 100
    }
}

public struct QuotaSnapshot: Equatable, Sendable {
    public let remainingPercent: Int
    public let observedAt: Date
    public let resetsAt: Date?
    public let windowDuration: TimeInterval?
    public let planName: String?
    public let secondaryWindow: QuotaWindow?

    public init(
        remainingPercent: Int,
        observedAt: Date,
        resetsAt: Date? = nil,
        windowDuration: TimeInterval? = nil,
        planName: String? = nil,
        secondaryWindow: QuotaWindow? = nil
    ) {
        self.remainingPercent = remainingPercent
        self.observedAt = observedAt
        self.resetsAt = resetsAt
        self.windowDuration = windowDuration
        self.planName = planName
        self.secondaryWindow = secondaryWindow
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
