public enum BatteryStyle: String, CaseIterable, Sendable {
    case native
    case embedded
    case segmented
    case digits

    public static let defaultStyle: BatteryStyle = .native

    public var menuTitle: String {
        switch self {
        case .native:
            "原生电池"
        case .embedded:
            "数字徽章"
        case .segmented:
            "分段电池"
        case .digits:
            "纯数字"
        }
    }
}
