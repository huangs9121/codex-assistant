import Foundation

public enum QuotaResetDetector {
    public static func newCycleStart(
        in snapshot: QuotaSnapshot,
        after lastObservedCycleStart: Date?
    ) -> Date? {
        guard
            let currentCycleStart = snapshot.windowStartedAt,
            let lastObservedCycleStart,
            currentCycleStart > lastObservedCycleStart
        else {
            return nil
        }
        return currentCycleStart
    }
}
