import Foundation

public enum PlanInfo {
    public static func normalizedName(_ rawValue: String?) -> String? {
        switch normalizedRawValue(rawValue) {
        case "prolite", "pro": "Pro"
        case "plus": "Plus"
        case "free": "Free"
        case "team": "Team"
        case "business": "Business"
        case "enterprise": "Enterprise"
        default: nil
        }
    }

    public static func normalizedBadgeName(_ rawValue: String?) -> String? {
        switch normalizedRawValue(rawValue) {
        case "prolite": "Pro 5X"
        case "pro": "Pro 20X"
        default: normalizedName(rawValue)
        }
    }

    private static func normalizedRawValue(_ rawValue: String?) -> String? {
        rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
