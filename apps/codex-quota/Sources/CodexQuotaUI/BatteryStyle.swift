public enum BatteryStyle: String, CaseIterable, Sendable {
    case native
    case embedded
    case segmented

    public static let defaultStyle: BatteryStyle = .native

    public var menuTitle: String {
        switch self {
        case .native:
            "A · 原生电池"
        case .embedded:
            "B · 数字徽章"
        case .segmented:
            "C · 分段电池"
        }
    }
}
