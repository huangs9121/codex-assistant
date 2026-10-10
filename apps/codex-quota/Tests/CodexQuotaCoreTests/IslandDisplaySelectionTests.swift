import CodexQuotaUI
import Foundation

enum IslandDisplaySelectionTests {
    private static let builtInID = "11111111-1111-1111-1111-111111111111"
    private static let externalID = "22222222-2222-2222-2222-222222222222"
    private static let otherID = "33333333-3333-3333-3333-333333333333"

    private static let builtIn = IslandDisplayDescriptor(
        id: builtInID, name: "Color LCD", isBuiltIn: true, isPrimary: false, hasNotch: true
    )
    private static let external = IslandDisplayDescriptor(
        id: externalID, name: "Studio Display", isBuiltIn: false, isPrimary: true, hasNotch: false
    )
    private static let other = IslandDisplayDescriptor(
        id: otherID, name: "Studio Display", isBuiltIn: false, isPrimary: false, hasNotch: false
    )

    static var all: [(name: String, run: () -> Bool)] { [
        ("island auto selection prefers notch over main display", testAutoPrefersNotch),
        ("island explicit selection survives screen ordering changes", testExplicitSelection),
        ("island offline selection falls back and reconnects", testOfflineAndReconnect),
        ("island auto selection falls back to main then first then none", testAutoFallbacks),
        ("island options label built-in primary and duplicate displays", testOptions),
        ("island options retain unavailable selection", testOfflineOption),
        ("island display preferences restore and return to auto", testPreferences)
    ] }

    private static func testAutoPrefersNotch() -> Bool {
        IslandDisplaySelection.resolvedDisplayID(
            preferredID: nil, displays: [external, builtIn], mainDisplayID: externalID
        ) == builtInID
    }

    private static func testExplicitSelection() -> Bool {
        let first = IslandDisplaySelection.resolvedDisplayID(
            preferredID: externalID.lowercased(), displays: [builtIn, external], mainDisplayID: externalID
        )
        let reordered = IslandDisplaySelection.resolvedDisplayID(
            preferredID: externalID, displays: [external, builtIn], mainDisplayID: builtInID
        )
        return first == externalID && reordered == externalID
    }

    private static func testOfflineAndReconnect() -> Bool {
        withDefaults { defaults in
            var preferences = DisplayPreferences(defaults: defaults)
            preferences.islandDisplayID = externalID
            let offline = IslandDisplaySelection.resolvedDisplayID(
                preferredID: preferences.islandDisplayID, displays: [builtIn], mainDisplayID: builtInID
            )
            guard offline == builtInID, preferences.islandDisplayID == externalID else { return false }
            let restored = IslandDisplaySelection.resolvedDisplayID(
                preferredID: preferences.islandDisplayID, displays: [builtIn, external], mainDisplayID: builtInID
            )
            return restored == externalID
        }
    }

    private static func testAutoFallbacks() -> Bool {
        let main = IslandDisplaySelection.resolvedDisplayID(
            preferredID: nil, displays: [other, external], mainDisplayID: externalID
        )
        let first = IslandDisplaySelection.resolvedDisplayID(
            preferredID: nil, displays: [other, external], mainDisplayID: nil
        )
        let empty = IslandDisplaySelection.resolvedDisplayID(
            preferredID: externalID, displays: [], mainDisplayID: nil
        )
        return main == externalID && first == otherID && empty == nil
    }

    private static func testOptions() -> Bool {
        let options = IslandDisplaySelection.options(
            displays: [builtIn, external, other], preferredID: nil, preferredName: nil
        )
        return options == [
            .init(id: nil, title: "自动（优先刘海屏）", isAvailable: true),
            .init(id: builtInID, title: "内置显示器", isAvailable: true),
            .init(id: externalID, title: "Studio Display（1）（主显示器）", isAvailable: true),
            .init(id: otherID, title: "Studio Display（2）", isAvailable: true)
        ]
    }

    private static func testOfflineOption() -> Bool {
        let options = IslandDisplaySelection.options(
            displays: [builtIn], preferredID: externalID, preferredName: "Studio Display"
        )
        return options.last == IslandDisplayOption(
            id: externalID, title: "Studio Display（未连接）", isAvailable: false
        ) && options.count == 3
    }

    private static func testPreferences() -> Bool {
        withDefaults { defaults in
            var preferences = DisplayPreferences(defaults: defaults)
            guard preferences.islandDisplayID == nil,
                  preferences.islandDisplayName == nil,
                  defaults.object(forKey: DisplayPreferences.islandDisplayIDKey) == nil,
                  defaults.object(forKey: DisplayPreferences.islandDisplayNameKey) == nil else {
                return false
            }
            preferences.islandDisplayID = externalID.lowercased()
            preferences.islandDisplayName = " Studio Display "
            let restored = DisplayPreferences(defaults: defaults)
            guard restored.islandDisplayID == externalID,
                  restored.islandDisplayName == "Studio Display" else { return false }
            defaults.set(Data([0xFF]), forKey: DisplayPreferences.islandDisplayIDKey)
            defaults.set("  ", forKey: DisplayPreferences.islandDisplayNameKey)
            guard preferences.islandDisplayID == nil,
                  preferences.islandDisplayName == nil,
                  defaults.object(forKey: DisplayPreferences.islandDisplayIDKey) != nil else {
                return false
            }
            preferences.islandDisplayID = nil
            preferences.islandDisplayName = nil
            return defaults.object(forKey: DisplayPreferences.islandDisplayIDKey) == nil
                && defaults.object(forKey: DisplayPreferences.islandDisplayNameKey) == nil
        }
    }

    private static func withDefaults(_ test: (UserDefaults) -> Bool) -> Bool {
        let suiteName = "IslandDisplaySelectionTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return false }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        return test(defaults)
    }
}
