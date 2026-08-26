import Foundation

public enum MouseGestureDirection: String, CaseIterable, Codable, Sendable {
    case up = "U"
    case down = "D"
    case left = "L"
    case right = "R"

    public static func direction(dx: Double, dy: Double) -> MouseGestureDirection {
        if abs(dx) > abs(dy) {
            return dx < 0 ? .left : .right
        }
        // Quartz global coordinates start at the top-left, so y increases downward.
        return dy < 0 ? .up : .down
    }
}

public struct MouseGesturePoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: MouseGesturePoint) -> Double {
        hypot(other.x - x, other.y - y)
    }
}

public struct MouseGestureRecognizer: Sendable {
    public static let activationDistance = 10.0
    public static let segmentDistance = 30.0
    public static let maximumSegments = 4

    private let start: MouseGesturePoint
    private var segmentStart: MouseGesturePoint
    public private(set) var directions: [MouseGestureDirection] = []

    public init(start: MouseGesturePoint) {
        self.start = start
        segmentStart = start
    }

    public mutating func update(point: MouseGesturePoint, isRecognizing: Bool) -> Bool {
        guard isRecognizing else {
            return start.distance(to: point) >= Self.activationDistance
        }
        guard directions.count < Self.maximumSegments,
              segmentStart.distance(to: point) >= Self.segmentDistance else {
            return true
        }

        let direction = MouseGestureDirection.direction(
            dx: point.x - segmentStart.x,
            dy: point.y - segmentStart.y
        )
        guard directions.last != direction else {
            return true
        }
        directions.append(direction)
        segmentStart = point
        return true
    }

    public var sequence: String {
        directions.map(\.rawValue).joined()
    }
}

public struct MouseGestureRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var gesture: String
    public var appFilter: String
    public var keyCode: UInt16
    public var modifierFlags: UInt64
    public var note: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        gesture: String = "",
        appFilter: String = "*",
        keyCode: UInt16 = 0,
        modifierFlags: UInt64 = 0,
        note: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.gesture = gesture
        self.appFilter = appFilter
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.note = note
        self.isEnabled = isEnabled
    }

    public var normalizedGesture: String {
        MouseGestureRule.normalizedGesture(gesture)
    }

    public var hasValidGesture: Bool {
        let value = normalizedGesture
        return (1...4).contains(value.count) && value.allSatisfy { "UDLR".contains($0) }
    }

    public var hasValidShortcut: Bool {
        KeyboardShortcut.isValid(keyCode: keyCode, flags: modifierFlags)
    }

    public static func normalizedGesture(_ value: String) -> String {
        String(value.uppercased().filter { "UDLR".contains($0) }.prefix(4))
    }
}

public enum MouseGestureRuleMatcher {
    public static func firstMatch(
        sequence: String,
        bundleIdentifier: String?,
        rules: [MouseGestureRule]
    ) -> MouseGestureRule? {
        let normalizedSequence = MouseGestureRule.normalizedGesture(sequence)
        return rules.first { rule in
            rule.isEnabled
                && rule.hasValidShortcut
                && rule.normalizedGesture == normalizedSequence
                && matches(filter: rule.appFilter, bundleIdentifier: bundleIdentifier)
        }
    }

    public static func matches(filter: String, bundleIdentifier: String?) -> Bool {
        let target = (bundleIdentifier ?? "").lowercased()
        return filter.split(separator: "|", omittingEmptySubsequences: true).contains {
            wildcardMatches(String($0).trimmingCharacters(in: .whitespacesAndNewlines), target: target)
        }
    }

    public static func wildcardMatches(_ pattern: String, target: String) -> Bool {
        let pattern = pattern.lowercased()
        let target = target.lowercased()
        var patternIndex = pattern.startIndex
        var targetIndex = target.startIndex
        var starIndex: String.Index?
        var starMatchIndex: String.Index?

        while targetIndex < target.endIndex {
            if patternIndex < pattern.endIndex,
               pattern[patternIndex] != "*",
               pattern[patternIndex] == target[targetIndex] {
                pattern.formIndex(after: &patternIndex)
                target.formIndex(after: &targetIndex)
            } else if patternIndex < pattern.endIndex, pattern[patternIndex] == "*" {
                starIndex = patternIndex
                pattern.formIndex(after: &patternIndex)
                starMatchIndex = targetIndex
            } else if let starIndex, let matchedStarIndex = starMatchIndex {
                patternIndex = pattern.index(after: starIndex)
                let nextTargetIndex = target.index(after: matchedStarIndex)
                starMatchIndex = nextTargetIndex
                targetIndex = nextTargetIndex
            } else {
                return false
            }
        }
        while patternIndex < pattern.endIndex, pattern[patternIndex] == "*" {
            pattern.formIndex(after: &patternIndex)
        }
        return patternIndex == pattern.endIndex
    }
}
