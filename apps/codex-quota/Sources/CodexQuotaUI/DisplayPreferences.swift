import Foundation

public struct DisplayPreferences {
    public static let batteryStyleKey = "batteryStyle"
    public static let showsCodexLabelKey = "showsCodexLabel"
    public static let hasShownAutoRefreshNoticeKey = "hasShownAutoRefreshNotice"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var batteryStyle: BatteryStyle {
        get {
            guard
                let rawValue = defaults.string(forKey: Self.batteryStyleKey),
                let style = BatteryStyle(rawValue: rawValue)
            else {
                return .native
            }
            return style
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.batteryStyleKey)
        }
    }

    public var showsCodexLabel: Bool {
        get {
            guard defaults.object(forKey: Self.showsCodexLabelKey) != nil else {
                return true
            }
            return defaults.bool(forKey: Self.showsCodexLabelKey)
        }
        set {
            defaults.set(newValue, forKey: Self.showsCodexLabelKey)
        }
    }

    public var hasShownAutoRefreshNotice: Bool {
        get {
            defaults.bool(forKey: Self.hasShownAutoRefreshNoticeKey)
        }
        set {
            defaults.set(newValue, forKey: Self.hasShownAutoRefreshNoticeKey)
        }
    }
}
