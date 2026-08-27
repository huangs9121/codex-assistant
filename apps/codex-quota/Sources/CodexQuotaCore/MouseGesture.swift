import Foundation

public enum MouseGestureDirection: String, CaseIterable, Codable, Sendable {
    case up = "U"
    case down = "D"
    case left = "L"
    case right = "R"
    case upLeft = "UL"
    case upRight = "UR"
    case downLeft = "DL"
    case downRight = "DR"

    public static func direction(dx: Double, dy: Double) -> MouseGestureDirection {
        let horizontal = abs(dx)
        let vertical = abs(dy)
        if horizontal > 0, vertical / horizontal >= 0.414_213_562, vertical / horizontal <= 2.414_213_562 {
            if dx < 0 { return dy < 0 ? .upLeft : .downLeft }
            return dy < 0 ? .upRight : .downRight
        }
        if horizontal > vertical {
            return dx < 0 ? .left : .right
        }
        // Quartz global coordinates start at the top-left, so y increases downward.
        return dy < 0 ? .up : .down
    }

    public var symbol: String {
        switch self {
        case .up: "⬆️"; case .down: "⬇️"; case .left: "⬅️"; case .right: "➡️"
        case .upLeft: "↖️"; case .upRight: "↗️"; case .downLeft: "↙️"; case .downRight: "↘️"
        }
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
    public static let maximumSegments = 2

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

    public var sequence: [MouseGestureDirection] {
        directions
    }
}

public struct MouseGestureRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var gesture: [MouseGestureDirection]
    public var appFilter: String
    public var keyCode: UInt16
    public var modifierFlags: UInt64
    public var note: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        gesture: [MouseGestureDirection] = [],
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

    public var hasValidGesture: Bool {
        (1...2).contains(gesture.count)
    }

    public var hasValidShortcut: Bool {
        if SystemGestureAction.isSystemActionKeyCode(keyCode) {
            return SystemGestureAction.action(
                keyCode: keyCode,
                modifierFlags: modifierFlags
            ) != nil
        }
        return KeyboardShortcut.isValid(keyCode: keyCode, flags: modifierFlags)
    }

    public var displayGesture: String {
        gesture.map(\.symbol).joined()
    }

    private enum CodingKeys: String, CodingKey { case id, gesture, appFilter, keyCode, modifierFlags, note, isEnabled }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        if let directions = try? values.decode([MouseGestureDirection].self, forKey: .gesture) {
            gesture = Array(directions.prefix(2))
        } else {
            let legacy = try values.decode(String.self, forKey: .gesture)
            gesture = Self.legacyDirections(legacy)
        }
        appFilter = try values.decode(String.self, forKey: .appFilter)
        keyCode = try values.decode(UInt16.self, forKey: .keyCode)
        modifierFlags = try values.decode(UInt64.self, forKey: .modifierFlags)
        note = try values.decode(String.self, forKey: .note)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
    }

    public static func legacyDirections(_ value: String) -> [MouseGestureDirection] {
        var result: [MouseGestureDirection] = []
        for character in value.uppercased() {
            let direction: MouseGestureDirection?
            switch character { case "U": direction = .up; case "D": direction = .down; case "L": direction = .left; case "R": direction = .right; default: direction = nil }
            if let direction { result.append(direction) }
            if result.count == 2 { break }
        }
        return result
    }
}

public enum MouseGestureRuleMatcher {
    public static func firstMatch(
        sequence: [MouseGestureDirection],
        bundleIdentifier: String?,
        rules: [MouseGestureRule]
    ) -> MouseGestureRule? {
        return rules.first { rule in
            rule.isEnabled
                && rule.hasValidShortcut
                && rule.gesture == sequence
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
