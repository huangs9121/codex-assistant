import Foundation

public enum KeyboardShortcut {
    public static var missionControlKeyCode: UInt16 {
        SystemGestureAction.all.first { $0.id == "missionControl" }!.keyCode
    }
    public static let controlFlag: UInt64 = 1 << 18
    public static let optionFlag: UInt64 = 1 << 19
    public static let shiftFlag: UInt64 = 1 << 17
    public static let commandFlag: UInt64 = 1 << 20

    public static func isValid(keyCode: UInt16, flags: UInt64) -> Bool {
        flags & (controlFlag | optionFlag | shiftFlag | commandFlag) != 0
    }

    public static func isMissionControl(keyCode: UInt16, flags: UInt64) -> Bool {
        SystemGestureAction.action(keyCode: keyCode, modifierFlags: flags)?.id == "missionControl"
    }

    public static func displayString(keyCode: UInt16, flags: UInt64) -> String {
        if let action = SystemGestureAction.action(keyCode: keyCode, modifierFlags: flags) {
            return action.localizedName(language: .english)
        }
        return modifierSymbols(flags: flags) + keyName(for: keyCode)
    }

    private static func modifierSymbols(flags: UInt64) -> String {
        var result = ""
        if flags & controlFlag != 0 { result += "⌃" }
        if flags & optionFlag != 0 { result += "⌥" }
        if flags & shiftFlag != 0 { result += "⇧" }
        if flags & commandFlag != 0 { result += "⌘" }
        return result
    }

    private static func keyName(for keyCode: UInt16) -> String {
        let specialKeys: [UInt16: String] = [
            63: "Fn / 🌐",
            110: "Menu",
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        if let specialKey = specialKeys[keyCode] { return specialKey }

        let ansiKeys: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y",
            17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
            25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U",
            33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`"
        ]
        return ansiKeys[keyCode] ?? "Key \(keyCode)"
    }
}
