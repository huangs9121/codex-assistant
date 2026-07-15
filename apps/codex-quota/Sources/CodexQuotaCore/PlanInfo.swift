import Foundation

public enum PlanInfo {
    public static func normalizedName(_ rawValue: String?) -> String? {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "prolite", "pro": "Pro"
        case "plus": "Plus"
        case "free": "Free"
        case "team": "Team"
        case "business": "Business"
        case "enterprise": "Enterprise"
        default: nil
        }
    }
}
