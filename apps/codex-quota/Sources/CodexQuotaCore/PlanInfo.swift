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

    public static func subscriptionExpiry(
        authData: Data,
        currentPlan: String?,
        now: Date = Date()
    ) -> Date? {
        guard
            let currentPlan,
            let auth = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
            let tokens = auth["tokens"] as? [String: Any],
            let idToken = tokens["id_token"] as? String,
            let claims = jwtPayload(idToken),
            let namespace = claims["https://api.openai.com/auth"] as? [String: Any],
            normalizedName(namespace["chatgpt_plan_type"] as? String) == currentPlan,
            let rawDate = namespace["chatgpt_subscription_active_until"] as? String,
            let expiry = subscriptionExpiryDate(from: rawDate),
            expiry > now
        else {
            return nil
        }
        return expiry
    }

    private static func jwtPayload(_ token: String) -> [String: Any]? {
        let segments = token.components(separatedBy: ".")
        guard segments.count == 3 else {
            return nil
        }

        let payloadSegment = segments[1]
        guard
            payloadSegment.unicodeScalars.allSatisfy({ scalar in
                let value = scalar.value
                return (65...90).contains(value)
                    || (97...122).contains(value)
                    || (48...57).contains(value)
                    || scalar == "-"
                    || scalar == "_"
            }),
            payloadSegment.count % 4 != 1
        else {
            return nil
        }

        var encodedPayload = payloadSegment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encodedPayload += String(
            repeating: "=",
            count: (4 - encodedPayload.count % 4) % 4
        )
        guard
            let payloadData = Data(base64Encoded: encodedPayload),
            let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            return nil
        }
        return payload
    }

    private static func subscriptionExpiryDate(from value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        return standardFormatter.date(from: value)
    }
}
