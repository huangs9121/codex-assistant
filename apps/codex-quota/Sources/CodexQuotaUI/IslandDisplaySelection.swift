import Foundation

public struct IslandDisplayDescriptor: Equatable, Sendable {
    public let id: String
    public let name: String
    public let isBuiltIn: Bool
    public let isPrimary: Bool
    public let hasNotch: Bool

    public init(id: String, name: String, isBuiltIn: Bool, isPrimary: Bool, hasNotch: Bool) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isPrimary = isPrimary
        self.hasNotch = hasNotch
    }
}

public struct IslandDisplayOption: Equatable, Sendable {
    public let id: String?
    public let title: String
    public let isAvailable: Bool

    public init(id: String?, title: String, isAvailable: Bool) {
        self.id = id
        self.title = title
        self.isAvailable = isAvailable
    }
}

public enum IslandDisplaySelection {
    public static func resolvedDisplayID(
        preferredID: String?,
        displays: [IslandDisplayDescriptor],
        mainDisplayID: String?
    ) -> String? {
        if let preferredID, let display = displays.first(where: { sameID($0.id, preferredID) }) {
            return display.id
        }
        if let notch = displays.first(where: \.hasNotch) { return notch.id }
        if let mainDisplayID, let main = displays.first(where: { sameID($0.id, mainDisplayID) }) {
            return main.id
        }
        return displays.first?.id
    }

    public static func options(
        displays: [IslandDisplayDescriptor],
        preferredID: String?,
        preferredName: String?
    ) -> [IslandDisplayOption] {
        let names = displays.map { display in
            display.isBuiltIn ? "内置显示器" : (nonempty(display.name) ?? "显示器")
        }
        var options = [IslandDisplayOption(id: nil, title: "自动（优先刘海屏）", isAvailable: true)]
        for (index, display) in displays.enumerated() {
            let duplicateCount = names.filter { $0 == names[index] }.count
            let number = names[...index].filter { $0 == names[index] }.count
            var title = names[index]
            if duplicateCount > 1 { title += "（\(number)）" }
            if display.isPrimary { title += "（主显示器）" }
            options.append(IslandDisplayOption(id: display.id, title: title, isAvailable: true))
        }
        if let preferredID, !displays.contains(where: { sameID($0.id, preferredID) }) {
            let name = nonempty(preferredName) ?? "所选显示器"
            options.append(IslandDisplayOption(id: preferredID, title: "\(name)（未连接）", isAvailable: false))
        }
        return options
    }

    private static func sameID(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = UUID(uuidString: lhs), let right = UUID(uuidString: rhs) else {
            return lhs == rhs
        }
        return left == right
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension DisplayPreferences {
    public static let islandDisplayIDKey = "islandDisplayID"
    public static let islandDisplayNameKey = "islandDisplayName"

    public var islandDisplayID: String? {
        get {
            guard let value = defaults.object(forKey: Self.islandDisplayIDKey) as? String else { return nil }
            return UUID(uuidString: value)?.uuidString
        }
        set {
            if let value = newValue, let id = UUID(uuidString: value) {
                defaults.set(id.uuidString, forKey: Self.islandDisplayIDKey)
            } else {
                defaults.removeObject(forKey: Self.islandDisplayIDKey)
            }
        }
    }

    public var islandDisplayName: String? {
        get {
            guard let value = defaults.object(forKey: Self.islandDisplayNameKey) as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                defaults.set(trimmed, forKey: Self.islandDisplayNameKey)
            } else {
                defaults.removeObject(forKey: Self.islandDisplayNameKey)
            }
        }
    }
}
