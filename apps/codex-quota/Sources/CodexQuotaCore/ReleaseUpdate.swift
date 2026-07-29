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
    public let assets: [GitHubReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        draft = try container.decode(Bool.self, forKey: .draft)
        prerelease = try container.decode(Bool.self, forKey: .prerelease)
        assets = try container.decodeIfPresent(
            [GitHubReleaseAsset].self,
            forKey: .assets
        ) ?? []
    }

    public var eligibleVersion: SemanticVersion? {
        guard let version = SemanticVersion(tagName) else {
            return nil
        }
        let expectedPath = "/huangs9121/codex-assistant/releases/tag/\(tagName)"
        guard
            !draft,
            !prerelease,
            htmlURL.scheme?.lowercased() == "https",
            htmlURL.host?.lowercased() == "github.com",
            htmlURL.port == nil,
            htmlURL.user == nil,
            htmlURL.password == nil,
            htmlURL.query == nil,
            htmlURL.path == expectedPath,
            URLComponents(
                url: htmlURL,
                resolvingAgainstBaseURL: false
            )?.percentEncodedPath == expectedPath,
            htmlURL.fragment == nil
        else {
            return nil
        }
        return version
    }

    public var eligibleUpdateAsset: GitHubReleaseAsset? {
        guard eligibleVersion != nil else {
            return nil
        }
        let eligibleAssets = assets.filter { $0.isEligible(for: tagName) }
        guard eligibleAssets.count == 1 else {
            return nil
        }
        return eligibleAssets[0]
    }

    public static func latestRequest(appVersion: SemanticVersion) -> URLRequest? {
        guard let url = URL(
            string: "https://api.github.com/repos/huangs9121/codex-assistant/releases/latest"
        ) else {
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let canonicalVersion = "\(appVersion.major).\(appVersion.minor).\(appVersion.patch)"
        request.setValue("Codex-Quota/\(canonicalVersion)", forHTTPHeaderField: "User-Agent")
        return request
    }
}

public struct GitHubReleaseAsset: Decodable, Sendable {
    public let name: String
    public let browserDownloadURL: URL
    public let contentType: String
    public let size: Int
    public let digest: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case contentType = "content_type"
        case size
        case digest
    }

    public var expectedSHA256: String? {
        guard let digest, digest.hasPrefix("sha256:") else {
            return nil
        }
        let value = String(digest.dropFirst("sha256:".count))
        guard
            value.count == 64,
            value.utf8.allSatisfy({
                (48...57).contains($0) || (97...102).contains($0)
            })
        else {
            return nil
        }
        return value
    }

    fileprivate func isEligible(for tagName: String) -> Bool {
        let expectedName = "Codex.Quota-arm64.zip"
        let expectedPath = "/huangs9121/codex-assistant/releases/download/\(tagName)/\(expectedName)"
        guard
            name == expectedName,
            contentType == "application/zip",
            size > 0,
            size <= 100 * 1024 * 1024,
            expectedSHA256 != nil,
            browserDownloadURL.scheme?.lowercased() == "https",
            browserDownloadURL.host?.lowercased() == "github.com",
            browserDownloadURL.port == nil,
            browserDownloadURL.user == nil,
            browserDownloadURL.password == nil,
            browserDownloadURL.query == nil,
            browserDownloadURL.path == expectedPath,
            URLComponents(
                url: browserDownloadURL,
                resolvingAgainstBaseURL: false
            )?.percentEncodedPath == expectedPath,
            browserDownloadURL.fragment == nil
        else {
            return false
        }
        return true
    }

    public func downloadRequest(appVersion: SemanticVersion) -> URLRequest? {
        guard expectedSHA256 != nil else {
            return nil
        }
        var request = URLRequest(url: browserDownloadURL, timeoutInterval: 60)
        request.httpMethod = "GET"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let canonicalVersion = "\(appVersion.major).\(appVersion.minor).\(appVersion.patch)"
        request.setValue("Codex-Quota/\(canonicalVersion)", forHTTPHeaderField: "User-Agent")
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
