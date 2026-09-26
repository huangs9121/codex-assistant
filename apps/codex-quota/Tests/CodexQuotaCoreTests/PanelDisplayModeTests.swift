import CodexQuotaUI
import Foundation

enum PanelDisplayModeTests {
    static var all: [(name: String, run: () -> Bool)] { [
        (
            "panel display mode defaults to menu bar without writing a preference",
            testDefaultMenuBar
        ),
        (
            "panel display mode persists island and menu bar in both directions",
            testBidirectionalPersistence
        ),
        (
            "invalid panel display mode values fall back without changing display preferences",
            testInvalidValuesPreserveOtherPreferences
        )
    ] }

    private static func testDefaultMenuBar() -> Bool {
        withDefaults { defaults in
            let preferences = DisplayPreferences(defaults: defaults)
            return preferences.panelDisplayMode == .menuBar
                && defaults.object(
                    forKey: DisplayPreferences.panelDisplayModeKey
                ) == nil
        }
    }

    private static func testBidirectionalPersistence() -> Bool {
        withDefaults { defaults in
            var preferences = DisplayPreferences(defaults: defaults)
            preferences.panelDisplayMode = .island
            guard
                DisplayPreferences(defaults: defaults).panelDisplayMode == .island,
                defaults.string(
                    forKey: DisplayPreferences.panelDisplayModeKey
                ) == PanelDisplayMode.island.rawValue
            else {
                return false
            }

            preferences.panelDisplayMode = .menuBar
            return DisplayPreferences(defaults: defaults).panelDisplayMode == .menuBar
                && defaults.string(
                    forKey: DisplayPreferences.panelDisplayModeKey
                ) == PanelDisplayMode.menuBar.rawValue
        }
    }

    private static func testInvalidValuesPreserveOtherPreferences() -> Bool {
        withDefaults { defaults in
            defaults.set(
                PanelDisplayMode.island.rawValue,
                forKey: DisplayPreferences.panelDisplayModeKey
            )
            var preferences = DisplayPreferences(defaults: defaults)
            preferences.batteryStyle = .segmented
            preferences.identityMode = .logo
            preferences.showsResetCountdownInStatusBar = true

            defaults.set(
                "future-mode",
                forKey: DisplayPreferences.panelDisplayModeKey
            )
            guard DisplayPreferences(defaults: defaults).panelDisplayMode == .menuBar else {
                return false
            }

            defaults.set(
                Data([0xFF]),
                forKey: DisplayPreferences.panelDisplayModeKey
            )
            let restored = DisplayPreferences(defaults: defaults)
            return restored.panelDisplayMode == .menuBar
                && restored.batteryStyle == .segmented
                && restored.identityMode == .logo
                && restored.showsResetCountdownInStatusBar
        }
    }

    private static func withDefaults(_ test: (UserDefaults) -> Bool) -> Bool {
        let suiteName = "PanelDisplayModeTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return false
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        return test(defaults)
    }
}
