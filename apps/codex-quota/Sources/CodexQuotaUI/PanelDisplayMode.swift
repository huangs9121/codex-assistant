import Foundation

public enum PanelDisplayMode: String, CaseIterable, Sendable {
    case menuBar
    case island
}

extension DisplayPreferences {
    public static let panelDisplayModeKey = "panelDisplayMode"

    public var panelDisplayMode: PanelDisplayMode {
        get { PanelDisplayMode(rawValue: defaults.string(forKey: Self.panelDisplayModeKey) ?? "") ?? .menuBar }
        set { defaults.set(newValue.rawValue, forKey: Self.panelDisplayModeKey) }
    }
}
