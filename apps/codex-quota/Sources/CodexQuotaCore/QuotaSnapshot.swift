import Foundation

public struct QuotaSnapshot: Equatable, Sendable {
    public let remainingPercent: Int
    public let observedAt: Date
    public let resetsAt: Date?
    public let planName: String?

    public init(
        remainingPercent: Int,
        observedAt: Date,
        resetsAt: Date? = nil,
        planName: String? = nil
    ) {
        self.remainingPercent = remainingPercent
        self.observedAt = observedAt
        self.resetsAt = resetsAt
        self.planName = planName
    }
}
