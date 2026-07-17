import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public static var current: AppLanguage {
        preferred(from: Locale.preferredLanguages)
    }

    public static func preferred(from identifiers: [String]) -> AppLanguage {
        for identifier in identifiers {
            let normalized = identifier.lowercased()
            if normalized.hasPrefix("zh") {
                return .simplifiedChinese
            }
            if normalized.hasPrefix("en") {
                return .english
            }
        }
        return .english
    }

    public var locale: Locale {
        switch self {
        case .simplifiedChinese:
            Locale(identifier: "zh_Hans_CN")
        case .english:
            Locale(identifier: "en_US_POSIX")
        }
    }
}
