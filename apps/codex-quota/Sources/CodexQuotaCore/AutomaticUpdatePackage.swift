import CryptoKit
import Foundation

public struct PreparedUpdatePackage: Sendable {
    public let appURL: URL
    public let workingDirectory: URL

    public init(appURL: URL, workingDirectory: URL) {
        self.appURL = appURL
        self.workingDirectory = workingDirectory
    }
}

public enum AutomaticUpdatePackage {
    public enum ValidationError: Error {
        case invalidAsset
        case sizeMismatch
        case digestMismatch
        case extractionFailed
        case unsafeArchive
        case invalidBundle
        case invalidSignature
        case invalidArchitecture
    }

    public static func prepare(
        archiveURL: URL,
        asset: GitHubReleaseAsset,
        version: SemanticVersion,
        workingDirectory: URL
    ) throws -> PreparedUpdatePackage {
        guard let expectedDigest = asset.expectedSHA256 else {
            throw ValidationError.invalidAsset
        }
        let attributes = try FileManager.default.attributesOfItem(
            atPath: archiveURL.path
        )
        guard
            let fileSize = attributes[.size] as? NSNumber,
            fileSize.int64Value == Int64(asset.size)
        else {
            throw ValidationError.sizeMismatch
        }
        guard try sha256(of: archiveURL) == expectedDigest else {
            throw ValidationError.digestMismatch
        }

        let expandedURL = workingDirectory.appendingPathComponent(
            "expanded",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: expandedURL,
            withIntermediateDirectories: false
        )
        guard run(
            "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, expandedURL.path]
        ) else {
            throw ValidationError.extractionFailed
        }

        let rootItems = try FileManager.default.contentsOfDirectory(
            at: expandedURL,
            includingPropertiesForKeys: nil,
            options: []
        )
        guard
            rootItems.count == 1,
            rootItems[0].lastPathComponent == "Codex Quota.app"
        else {
            throw ValidationError.unsafeArchive
        }
        let appURL = rootItems[0]
        guard try containsNoSymbolicLinks(in: appURL) else {
            throw ValidationError.unsafeArchive
        }

        let canonicalVersion = "\(version.major).\(version.minor).\(version.patch)"
        guard
            appURL.pathExtension == "app",
            let bundle = Bundle(url: appURL),
            bundle.bundleIdentifier == "local.openclaw.codexquota",
            bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String == canonicalVersion,
            let executableURL = bundle.executableURL,
            FileManager.default.isExecutableFile(atPath: executableURL.path)
        else {
            throw ValidationError.invalidBundle
        }
        guard run(
            "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", appURL.path]
        ) else {
            throw ValidationError.invalidSignature
        }
        guard run(
            "/usr/bin/lipo",
            arguments: [executableURL.path, "-verify_arch", "arm64"]
        ) else {
            throw ValidationError.invalidArchitecture
        }
        guard run("/usr/bin/xattr", arguments: ["-cr", appURL.path]) else {
            throw ValidationError.invalidBundle
        }

        return PreparedUpdatePackage(
            appURL: appURL,
            workingDirectory: workingDirectory
        )
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func containsNoSymbolicLinks(in rootURL: URL) throws -> Bool {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            return false
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true {
                return false
            }
        }
        return true
    }

    private static func run(_ executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
