import Foundation
import CodexQuotaCore

enum MouseGesturePreferencesTests {
    static var all: [(name: String, run: () -> Bool)] { [
        ("fresh install has seven valid presets but never enables monitoring", {
            withDefaults { defaults in
                let rules = MouseGestureRuleDefaults.load(from: defaults)
                return rules.count == 7 && rules.allSatisfy { $0.hasValidGesture && $0.hasValidShortcut && $0.isEnabled }
                    && !MouseGesturePreferences(defaults: defaults).isEnabled
                    && !MouseGesturePreferences(defaults: defaults).allows(bundleIdentifier: "com.apple.Safari")
                    && MouseGestureRuleDefaults.load(from: defaults) == rules
            }
        }),
        ("editing presets cannot enable a fresh installation", {
            withDefaults { defaults in
                guard !MouseGesturePreferences(defaults: defaults).isEnabled else { return false }
                defaults.set(try! JSONEncoder().encode(MouseGestureRuleDefaults.rules), forKey: "mouseGestureRules")
                return !MouseGesturePreferences(defaults: defaults).isEnabled
            }
        }),
        ("saved empty and custom rules override presets and explicit switch is preserved", {
            withDefaults { defaults in
                defaults.set(Data("[]".utf8), forKey: "mouseGestureRules")
                defaults.set(false, forKey: MouseGesturePreferences.enabledDefaultsKey)
                guard MouseGestureRuleDefaults.load(from: defaults).isEmpty,
                      !MouseGesturePreferences(defaults: defaults).isEnabled else { return false }
                let custom = [MouseGestureRule(gesture: [.left], keyCode: 17, modifierFlags: KeyboardShortcut.commandFlag)]
                defaults.set(try! JSONEncoder().encode(custom), forKey: "mouseGestureRules")
                defaults.set(true, forKey: MouseGesturePreferences.enabledDefaultsKey)
                return MouseGestureRuleDefaults.load(from: defaults) == custom
                    && MouseGesturePreferences(defaults: defaults).isEnabled
            }
        }),
        ("existing gesture settings migrate with Blender excluded and rules intact", {
            withDefaults { defaults in
                let legacyRules = Data("existing rules".utf8)
                defaults.set(legacyRules, forKey: "mouseGestureRules")
                let preferences = MouseGesturePreferences(defaults: defaults)
                preferences.save(to: defaults)
                return preferences.isEnabled
                    && !preferences.allows(bundleIdentifier: "ORG.BLENDERFOUNDATION.BLENDER")
                    && preferences.allows(bundleIdentifier: "com.apple.Safari")
                    && defaults.data(forKey: "mouseGestureRules") == legacyRules
            }
        }),
        ("master switch persists without changing exclusions", {
            withDefaults { defaults in
                var preferences = MouseGesturePreferences(defaults: defaults)
                preferences.isEnabled = false
                preferences.save(to: defaults)
                var restored = MouseGesturePreferences(defaults: defaults)
                guard !restored.isEnabled, !restored.allows(bundleIdentifier: nil),
                      !restored.allows(bundleIdentifier: "com.apple.Safari") else { return false }
                restored.isEnabled = true
                restored.save(to: defaults)
                let enabled = MouseGesturePreferences(defaults: defaults)
                return enabled.allows(bundleIdentifier: "com.apple.Safari")
                    && !enabled.allows(bundleIdentifier: "org.blenderfoundation.blender")
            }
        }),
        ("removing all exclusions remains empty after restart", {
            withDefaults { defaults in
                var preferences = MouseGesturePreferences(defaults: defaults)
                preferences.isEnabled = true
                preferences.removeExclusion(bundleIdentifier: "org.blenderfoundation.blender")
                preferences.save(to: defaults)
                let restored = MouseGesturePreferences(defaults: defaults)
                return restored.excludedApplications.isEmpty
                    && restored.allows(bundleIdentifier: "org.blenderfoundation.blender")
            }
        }),
        ("excluded applications deduplicate by exact case insensitive bundle identifier", {
            withDefaults { defaults in
                var preferences = MouseGesturePreferences(defaults: defaults)
                preferences.isEnabled = true
                preferences.exclude(.init(bundleIdentifier: " com.apple.Safari ", name: "Safari"))
                preferences.exclude(.init(bundleIdentifier: "COM.APPLE.SAFARI", name: "Safari"))
                preferences.save(to: defaults)
                let restored = MouseGesturePreferences(defaults: defaults)
                return restored.excludedApplications.count == 2
                    && !restored.allows(bundleIdentifier: "com.apple.Safari")
                    && restored.allows(bundleIdentifier: "com.apple.SafariTechnologyPreview")
                    && restored.allows(bundleIdentifier: "other.Blender")
            }
        })
    ] }

    private static func withDefaults(_ test: (UserDefaults) -> Bool) -> Bool {
        let suite = "CodexQuotaGestureTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return false }
        defer { defaults.removePersistentDomain(forName: suite) }
        return test(defaults)
    }
}
