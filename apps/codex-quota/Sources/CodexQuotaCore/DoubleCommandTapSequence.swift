import Foundation

public struct DoubleCommandTapSequence {
    public static let maximumInterval: TimeInterval = 0.3
    public static let cooldownDuration: TimeInterval = 0.5

    private var firstTapAt: TimeInterval?
    private var cooldownEndsAt: TimeInterval?

    public init() {}

    public mutating func registerPureCommandTap(at time: TimeInterval) -> Bool {
        if let cooldownEndsAt, time < cooldownEndsAt {
            firstTapAt = nil
            return false
        }

        guard let firstTapAt else {
            self.firstTapAt = time
            return false
        }

        if time - firstTapAt <= Self.maximumInterval {
            self.firstTapAt = nil
            cooldownEndsAt = time + Self.cooldownDuration
            return true
        }

        self.firstTapAt = time
        return false
    }

    public mutating func cancel() {
        firstTapAt = nil
    }
}
