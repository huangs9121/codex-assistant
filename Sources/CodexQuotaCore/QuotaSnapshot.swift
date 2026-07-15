import Foundation

public struct QuotaSnapshot: Equatable, Sendable {
    public let remainingPercent: Int
    public let observedAt: Date
    public let resetsAt: Date?

    public init(
        remainingPercent: Int,
        observedAt: Date,
        resetsAt: Date? = nil
    ) {
        self.remainingPercent = remainingPercent
        self.observedAt = observedAt
        self.resetsAt = resetsAt
    }
}
