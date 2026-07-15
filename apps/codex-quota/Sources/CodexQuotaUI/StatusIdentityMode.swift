public enum StatusIdentityMode: String, CaseIterable, Sendable {
    case text
    case logo
    case hidden

    public var menuTitle: String {
        switch self {
        case .text:
            "显示 Codex 文字"
        case .logo:
            "显示 OpenAI Logo"
        case .hidden:
            "不显示标识"
        }
    }
}
