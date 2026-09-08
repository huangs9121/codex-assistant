import Foundation

public struct MouseGestureExcludedApplication: Codable, Equatable, Sendable {
    public let bundleIdentifier: String
    public let name: String

    public init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name
    }
}

public struct MouseGesturePreferences: Equatable, Sendable {
    public static let enabledDefaultsKey = "mouseGesturesEnabled"
    public static let exclusionsDefaultsKey = "mouseGestureExcludedApplications"
    public static let defaultExclusions = [
        MouseGestureExcludedApplication(bundleIdentifier: "org.blenderfoundation.blender", name: "Blender")
    ]

    public var isEnabled: Bool
    public private(set) var excludedApplications: [MouseGestureExcludedApplication]

    public init(defaults: UserDefaults) {
        isEnabled = defaults.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
        // Missing settings migrate to Blender; an explicitly empty list stays empty.
        excludedApplications = defaults.data(forKey: Self.exclusionsDefaultsKey)
            .flatMap { try? JSONDecoder().decode([MouseGestureExcludedApplication].self, from: $0) }
            ?? Self.defaultExclusions
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(excludedApplications) else { return }
        defaults.set(isEnabled, forKey: Self.enabledDefaultsKey)
        defaults.set(data, forKey: Self.exclusionsDefaultsKey)
    }

    public mutating func exclude(_ application: MouseGestureExcludedApplication) {
        guard !application.bundleIdentifier.isEmpty else { return }
        excludedApplications.removeAll {
            $0.bundleIdentifier.caseInsensitiveCompare(application.bundleIdentifier) == .orderedSame
        }
        excludedApplications.append(application)
        excludedApplications.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public mutating func removeExclusion(bundleIdentifier: String) {
        excludedApplications.removeAll {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
    }

    public func allows(bundleIdentifier: String?) -> Bool {
        guard isEnabled else { return false }
        guard let bundleIdentifier else { return true }
        return !excludedApplications.contains {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
    }
}
