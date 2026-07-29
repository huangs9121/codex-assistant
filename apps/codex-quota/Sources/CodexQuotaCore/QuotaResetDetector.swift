import Foundation

public struct QuotaResetNotificationState: Codable, Equatable, Sendable {
    public let lastObservedCycleStart: Date?
    public let isArmed: Bool

    public init(lastObservedCycleStart: Date?, isArmed: Bool) {
        self.lastObservedCycleStart = lastObservedCycleStart
        self.isArmed = isArmed
    }
}

public struct QuotaResetDetection: Equatable, Sendable {
    public let state: QuotaResetNotificationState
    public let cycleStartToNotify: Date?

    public init(
        state: QuotaResetNotificationState,
        cycleStartToNotify: Date?
    ) {
        self.state = state
        self.cycleStartToNotify = cycleStartToNotify
    }
}

public enum QuotaResetDetector {
    private static let sameCycleTimestampTolerance: TimeInterval = 60

    public static func evaluate(
        _ snapshot: QuotaSnapshot,
        state previousState: QuotaResetNotificationState?
    ) -> QuotaResetDetection {
        let currentCycleStart = snapshot.windowStartedAt
        guard let previousState else {
            return QuotaResetDetection(
                state: QuotaResetNotificationState(
                    lastObservedCycleStart: currentCycleStart,
                    isArmed: snapshot.remainingPercent < 100
                ),
                cycleStartToNotify: nil
            )
        }

        let latestCycleStart = latest(
            previousState.lastObservedCycleStart,
            currentCycleStart
        )
        let hasNewCycle: Bool
        if
            let previousCycleStart = previousState.lastObservedCycleStart,
            let currentCycleStart
        {
            hasNewCycle = currentCycleStart.timeIntervalSince(
                previousCycleStart
            ) > sameCycleTimestampTolerance
        } else {
            hasNewCycle = false
        }

        if previousState.isArmed, hasNewCycle {
            return QuotaResetDetection(
                state: QuotaResetNotificationState(
                    lastObservedCycleStart: latestCycleStart,
                    isArmed: false
                ),
                cycleStartToNotify: currentCycleStart
            )
        }

        return QuotaResetDetection(
            state: QuotaResetNotificationState(
                lastObservedCycleStart: latestCycleStart,
                isArmed: previousState.isArmed
                    || snapshot.remainingPercent < 100
            ),
            cycleStartToNotify: nil
        )
    }

    private static func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }
}
