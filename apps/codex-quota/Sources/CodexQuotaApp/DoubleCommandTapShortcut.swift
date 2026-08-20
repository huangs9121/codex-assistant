import CoreGraphics
import CodexQuotaCore
import Foundation

struct DoubleCommandTapShortcut {
    static let targetKeyCodeDefaultsKey = "doubleCommandTapTargetKeyCode"
    static let targetFlagsDefaultsKey = "doubleCommandTapTargetFlags"
    static let defaultKeyCode: CGKeyCode = 8
    static let defaultFlags: CGEventFlags = [.maskControl, .maskCommand]

    let keyCode: CGKeyCode
    let flags: CGEventFlags

    init(keyCode: CGKeyCode, flags: CGEventFlags) {
        self.keyCode = keyCode
        self.flags = flags
    }

    init(defaults: UserDefaults) {
        let storedKeyCode = defaults.object(forKey: Self.targetKeyCodeDefaultsKey) as? Int
        let storedFlags = defaults.object(forKey: Self.targetFlagsDefaultsKey) as? UInt64
        let keyCode = storedKeyCode.flatMap(CGKeyCode.init(exactly:)) ?? Self.defaultKeyCode
        let flags = storedFlags.map(CGEventFlags.init(rawValue:)) ?? Self.defaultFlags
        if KeyboardShortcut.isValid(keyCode: keyCode, flags: flags.rawValue) {
            self.init(keyCode: keyCode, flags: flags)
        } else {
            self.init(keyCode: Self.defaultKeyCode, flags: Self.defaultFlags)
        }
    }

    var displayString: String {
        KeyboardShortcut.displayString(keyCode: keyCode, flags: flags.rawValue)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(Int(keyCode), forKey: Self.targetKeyCodeDefaultsKey)
        defaults.set(flags.rawValue, forKey: Self.targetFlagsDefaultsKey)
    }
}
