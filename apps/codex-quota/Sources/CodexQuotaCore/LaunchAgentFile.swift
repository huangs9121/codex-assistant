import Foundation

public struct LaunchAgentFile {
    public static let defaultLabel = "local.openclaw.codexquota"

    public let fileURL: URL
    public let executableURL: URL
    public let label: String

    public init(
        homeDirectory: URL,
        executableURL: URL,
        label: String = defaultLabel
    ) {
        self.fileURL = homeDirectory
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
        self.executableURL = executableURL
        self.label = label
    }

    public var isInstalled: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    public func install() throws {
        let properties: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: properties,
            format: .xml,
            options: 0
        )
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: fileURL.path
        )
    }

    public func uninstall() throws {
        guard isInstalled else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }
}
