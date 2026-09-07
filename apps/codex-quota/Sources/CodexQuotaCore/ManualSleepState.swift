public enum ManualSleepState: Equatable, Sendable {
    case off
    case on
    case pending
    case failed
}

public struct ManualSleepAcknowledgement: Equatable, Sendable {
    public let scannedAt: Int64
    public let active: Bool
    public let sleepDisabled: Bool
    public let success: Bool

    public init(scannedAt: Int64, active: Bool, sleepDisabled: Bool, success: Bool) {
        self.scannedAt = scannedAt
        self.active = active
        self.sleepDisabled = sleepDisabled
        self.success = success
    }

    public func confirms(scannedAtOrAfter requestedAt: Int64, active requestedActive: Bool) -> Bool {
        scannedAt >= requestedAt
            && success
            && active == requestedActive
            && sleepDisabled == requestedActive
    }
}

public enum ManualSleepOperation {
    public static func acceptsCompletion(requestGeneration: Int, currentGeneration: Int) -> Bool {
        requestGeneration == currentGeneration
    }
}
