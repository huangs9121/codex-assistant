import Foundation

public enum SystemGestureAction {
    public enum Invocation: Equatable, Sendable {
        case keyboardShortcut(keyCode: UInt16, flags: UInt64)
        case openApplication(path: String)
        case runCommand(executablePath: String, arguments: [String])
    }

    public struct Definition: Equatable, Identifiable, Sendable {
        public let id: String
        public let keyCode: UInt16
        public let chineseName: String
        public let englishName: String
        public let invocation: Invocation

        public init(
            id: String,
            keyCode: UInt16,
            chineseName: String,
            englishName: String,
            invocation: Invocation
        ) {
            self.id = id
            self.keyCode = keyCode
            self.chineseName = chineseName
            self.englishName = englishName
            self.invocation = invocation
        }

        public func localizedName(language: AppLanguage) -> String {
            language == .simplifiedChinese ? chineseName : englishName
        }
    }

    public static let all: [Definition] = [
        Definition(id: "captureSelection", keyCode: 0xFFFC, chineseName: "选区截图并复制", englishName: "Copy Selected Screenshot",
            invocation: .keyboardShortcut(keyCode: 21, flags: KeyboardShortcut.controlFlag | KeyboardShortcut.commandFlag | KeyboardShortcut.shiftFlag)),
        Definition(id: "captureScreen", keyCode: 0xFFFB, chineseName: "全屏截图并复制", englishName: "Copy Full Screenshot",
            invocation: .keyboardShortcut(keyCode: 20, flags: KeyboardShortcut.controlFlag | KeyboardShortcut.commandFlag | KeyboardShortcut.shiftFlag)),
        Definition(id: "recordScreen", keyCode: 0xFFFA, chineseName: "录屏", englishName: "Screen Recording",
            invocation: .openApplication(path: "/System/Applications/Utilities/Screenshot.app")),
        Definition(
            id: "missionControl",
            keyCode: 0xFFFF,
            chineseName: "调度中心",
            englishName: "Mission Control",
            invocation: .openApplication(path: "/System/Applications/Mission Control.app")
        ),
        Definition(
            id: "screenSaver",
            keyCode: 0xFFFE,
            chineseName: "屏幕保护程序",
            englishName: "Screen Saver",
            invocation: .openApplication(path: "/System/Library/CoreServices/ScreenSaverEngine.app")
        ),
        Definition(
            id: "sleepDisplay",
            keyCode: 0xFFFD,
            chineseName: "关闭显示器",
            englishName: "Sleep Display",
            invocation: .runCommand(
                executablePath: "/usr/bin/pmset",
                arguments: ["displaysleepnow"]
            )
        )
    ]

    public static func action(keyCode: UInt16, modifierFlags: UInt64) -> Definition? {
        guard modifierFlags == 0 else { return nil }
        return all.first { $0.keyCode == keyCode }
    }

    public static func isSystemActionKeyCode(_ keyCode: UInt16) -> Bool {
        all.contains { $0.keyCode == keyCode }
    }
}
