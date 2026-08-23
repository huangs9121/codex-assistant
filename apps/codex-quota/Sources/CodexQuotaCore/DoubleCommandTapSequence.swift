import Foundation

public struct ModifierTapSequence {
    public struct Configuration: Equatable, Sendable {
        public let keyCodes: Set<UInt16>
        public let requiredTapCount: Int
        public let maximumInterval: TimeInterval
        public let maximumHoldDuration: TimeInterval
        public let cooldownDuration: TimeInterval

        public init(
            keyCodes: Set<UInt16>,
            requiredTapCount: Int,
            maximumInterval: TimeInterval = ModifierTapSequence.maximumInterval,
            maximumHoldDuration: TimeInterval = ModifierTapSequence.maximumHoldDuration,
            cooldownDuration: TimeInterval = ModifierTapSequence.cooldownDuration
        ) {
            precondition(!keyCodes.isEmpty)
            precondition((1...2).contains(requiredTapCount))
            self.keyCodes = keyCodes
            self.requiredTapCount = requiredTapCount
            self.maximumInterval = maximumInterval
            self.maximumHoldDuration = maximumHoldDuration
            self.cooldownDuration = cooldownDuration
        }
    }

    public enum Event: Equatable, Sendable {
        case modifierDown(UInt16)
        case modifierUp(UInt16)
        case keyDown
        case otherModifier
    }

    public static let maximumInterval: TimeInterval = 0.3
    public static let maximumHoldDuration: TimeInterval = 0.4
    public static let cooldownDuration: TimeInterval = 0.5
    public static let defaultConfiguration = Configuration(
        keyCodes: [54, 55],
        requiredTapCount: 2
    )

    public let configuration: Configuration

    private var activePress: ActivePress?
    private var firstTapAt: TimeInterval?
    private var cooldownEndsAt: TimeInterval?

    public init(configuration: Configuration = Self.defaultConfiguration) {
        self.configuration = configuration
    }

    public var isTracking: Bool {
        activePress != nil || firstTapAt != nil
    }

    @discardableResult
    public mutating func register(_ event: Event, at time: TimeInterval) -> Bool {
        switch event {
        case .keyDown, .otherModifier:
            cancel()
            return false
        case .modifierDown(let keyCode):
            return registerModifierDown(keyCode: keyCode, at: time)
        case .modifierUp(let keyCode):
            return registerModifierUp(keyCode: keyCode, at: time)
        }
    }

    public mutating func cancel() {
        activePress = nil
        firstTapAt = nil
    }

    private mutating func registerModifierDown(keyCode: UInt16, at time: TimeInterval) -> Bool {
        guard configuration.keyCodes.contains(keyCode), activePress == nil else {
            cancel()
            return false
        }
        guard !isCoolingDown(at: time) else {
            return false
        }

        activePress = ActivePress(keyCode: keyCode, beganAt: time)
        guard configuration.requiredTapCount == 2 else {
            return false
        }

        guard let firstTapAt else {
            self.firstTapAt = time
            return false
        }

        let interval = time - firstTapAt
        guard interval >= 0, interval <= configuration.maximumInterval else {
            self.firstTapAt = time
            return false
        }

        activePress = nil
        self.firstTapAt = nil
        cooldownEndsAt = time + configuration.cooldownDuration
        return true
    }

    private mutating func registerModifierUp(keyCode: UInt16, at time: TimeInterval) -> Bool {
        guard let activePress, activePress.keyCode == keyCode else {
            if isTracking {
                cancel()
            }
            return false
        }

        self.activePress = nil
        guard configuration.requiredTapCount == 1 else {
            return false
        }

        let duration = time - activePress.beganAt
        guard duration >= 0, duration < configuration.maximumHoldDuration else {
            cancel()
            return false
        }

        firstTapAt = nil
        cooldownEndsAt = time + configuration.cooldownDuration
        return true
    }

    private mutating func isCoolingDown(at time: TimeInterval) -> Bool {
        guard let cooldownEndsAt else {
            return false
        }
        guard time < cooldownEndsAt else {
            self.cooldownEndsAt = nil
            return false
        }
        cancel()
        return true
    }

    private struct ActivePress {
        let keyCode: UInt16
        let beganAt: TimeInterval
    }
}
