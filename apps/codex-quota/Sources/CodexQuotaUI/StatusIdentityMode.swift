import CodexQuotaCore

public enum StatusIdentityMode: String, CaseIterable, Sendable {
    case text
    case logo
    case hidden

    public var menuTitle: String {
        menuTitle(language: .simplifiedChinese)
    }

    public func menuTitle(language: AppLanguage) -> String {
        switch self {
        case .text:
            language == .simplifiedChinese ? "显示 Codex 文字" : "Show Codex Text"
        case .logo:
            language == .simplifiedChinese ? "显示 OpenAI Logo" : "Show OpenAI Logo"
        case .hidden:
            language == .simplifiedChinese ? "不显示标识" : "Hide Identity"
        }
    }
}
