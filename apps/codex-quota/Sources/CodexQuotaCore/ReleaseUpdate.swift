import Foundation

public struct SemanticVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ rawValue: String) {
        let value = rawValue.hasPrefix("v") ? String(rawValue.dropFirst()) : rawValue
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else {
            return nil
        }

        var numbers: [Int] = []
        numbers.reserveCapacity(3)
        for component in components {
            guard
                !component.isEmpty,
                component.count == 1 || component.first != "0",
                component.utf8.allSatisfy({ (48...57).contains($0) }),
                let number = Int(component)
            else {
                return nil
            }
            numbers.append(number)
        }

        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}

public struct GitHubRelease: Decodable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL
    public let draft: Bool
    public let prerelease: Bool

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
    }

    public var eligibleVersion: SemanticVersion? {
        guard
            !draft,
            !prerelease,
            htmlURL.scheme?.lowercased() == "https",
            htmlURL.host?.lowercased() == "github.com",
            htmlURL.user == nil,
            htmlURL.password == nil,
            htmlURL.fragment == nil
        else {
            return nil
        }
        return SemanticVersion(tagName)
    }

    public static func latestRequest() -> URLRequest? {
        guard let url = URL(
            string: "https://api.github.com/repos/huangs9121/codex-assistant/releases/latest"
        ) else {
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Codex-Quota/1.1.0", forHTTPHeaderField: "User-Agent")
        return request
    }
}

public enum UpdatePolicy {
    public static func shouldAutomaticallyCheck(
        lastSuccess: Date?,
        lastFailure: Date?,
        now: Date
    ) -> Bool {
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            return false
        }
        if let lastSuccess {
            let elapsed = now.timeIntervalSince(lastSuccess)
            guard elapsed.isFinite, elapsed >= 24 * 60 * 60 else {
                return false
            }
        }
        if let lastFailure {
            let elapsed = now.timeIntervalSince(lastFailure)
            guard elapsed.isFinite, elapsed >= 60 * 60 else {
                return false
            }
        }
        return true
    }

    public static func shouldPrompt(
        version: SemanticVersion,
        lastPromptedVersion: String?
    ) -> Bool {
        guard
            let lastPromptedVersion,
            let promptedVersion = SemanticVersion(lastPromptedVersion)
        else {
            return true
        }
        return promptedVersion != version
    }
}
