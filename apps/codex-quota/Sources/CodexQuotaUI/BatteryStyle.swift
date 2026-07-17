import CodexQuotaCore

public enum BatteryStyle: String, CaseIterable, Sendable {
    case native
    case embedded
    case segmented
    case digits

    public static let defaultStyle: BatteryStyle = .native

    public var menuTitle: String {
        menuTitle(language: .simplifiedChinese)
    }

    public func menuTitle(language: AppLanguage) -> String {
        switch self {
        case .native:
            language == .simplifiedChinese ? "原生电池" : "Native Battery"
        case .embedded:
            language == .simplifiedChinese ? "数字徽章" : "Number Badge"
        case .segmented:
            language == .simplifiedChinese ? "分段电池" : "Segmented Battery"
        case .digits:
            language == .simplifiedChinese ? "纯数字" : "Number Only"
        }
    }
}
