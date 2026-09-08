import Foundation

public struct KeyMappingShortcut: Codable, Equatable, Sendable {
    public static let modifierMask = KeyboardShortcut.controlFlag | KeyboardShortcut.optionFlag
        | KeyboardShortcut.shiftFlag | KeyboardShortcut.commandFlag
    public static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
    public let keyCode: UInt16
    public let flags: UInt64

    public init(keyCode: UInt16, flags: UInt64) {
        self.keyCode = keyCode
        self.flags = flags & Self.modifierMask
    }

    public var isValid: Bool {
        if isFunctionKey { return flags == 0 }
        return keyCode <= 126 && !Self.modifierKeyCodes.contains(keyCode) && flags & ~Self.modifierMask == 0
    }

    public var isFunctionKey: Bool { keyCode == 63 }

    public var displayString: String { KeyboardShortcut.displayString(keyCode: keyCode, flags: flags) }
}

public enum KeyMappingTrigger: Codable, Equatable, Sendable {
    case shortcut(KeyMappingShortcut)
    case modifierTap(keyCodes: Set<UInt16>, tapCount: Int)

    public var isValid: Bool {
        switch self {
        case .shortcut(let shortcut): return shortcut.isValid && !shortcut.isFunctionKey
        case let .modifierTap(keys, count):
            return !keys.isEmpty && Set<UInt16>([54, 55, 56, 58, 59, 60, 61, 62, 63]).isSuperset(of: keys)
                && (1...2).contains(count)
        }
    }

    public func conflicts(with other: Self) -> Bool {
        switch (self, other) {
        case let (.shortcut(a), .shortcut(b)): return a == b
        // A single tap and double tap of the same modifier also compete.
        case let (.modifierTap(a, _), .modifierTap(b, _)): return !a.isDisjoint(with: b)
        default: return false
        }
    }
}

public struct KeyMappingRule: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var trigger: KeyMappingTrigger?
    public var target: KeyMappingShortcut?
    public var note: String
    public var isEnabled: Bool

    public init(id: UUID = UUID(), trigger: KeyMappingTrigger? = nil, target: KeyMappingShortcut? = nil,
                note: String = "", isEnabled: Bool = true) {
        self.id = id; self.trigger = trigger; self.target = target; self.note = note; self.isEnabled = isEnabled
    }

    public var isComplete: Bool { trigger?.isValid == true && target?.isValid == true }

    public static func conflictingRule(for candidate: Self, in rules: [Self]) -> Self? {
        guard candidate.isEnabled, let trigger = candidate.trigger else { return nil }
        return rules.first { $0.id != candidate.id && $0.isEnabled && $0.trigger.map(trigger.conflicts) == true }
    }
}

/// Matches physical key pairs. Generated events bypass the engine, and a held
/// key keeps its original mapping even if modifiers or saved rules change.
public struct KeyMappingEngine {
    public enum Phase { case down, up }
    public private(set) var pressed: [UInt16: KeyMappingShortcut] = [:]
    private var passthroughKeys: Set<UInt16> = []

    public init() {}

    public mutating func process(phase: Phase, keyCode: UInt16, flags: UInt64, isRepeat: Bool = false,
                                 isGenerated: Bool = false, rules: [KeyMappingRule]) -> KeyMappingShortcut? {
        guard !isGenerated else { return nil }
        if phase == .up {
            passthroughKeys.remove(keyCode)
            return pressed.removeValue(forKey: keyCode)
        }
        if let active = pressed[keyCode] { return active }
        // A key first pressed without a match must not turn into a mapped key mid-hold.
        guard !isRepeat, !passthroughKeys.contains(keyCode) else { return nil }
        let input = KeyMappingShortcut(keyCode: keyCode, flags: flags)
        guard let rule = rules.first(where: { $0.isEnabled && $0.isComplete && $0.trigger == .shortcut(input) }),
              let target = rule.target else {
            passthroughKeys.insert(keyCode)
            return nil
        }
        pressed[keyCode] = target
        return target
    }

    public mutating func releaseAll() -> [KeyMappingShortcut] {
        let targets = Array(pressed.values)
        pressed.removeAll()
        passthroughKeys.removeAll()
        return targets
    }
}
