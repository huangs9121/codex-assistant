import CodexQuotaCore
import Darwin
import Foundation

@MainActor
final class AutomaticUpdateInstaller {
    enum Result {
        case restarting
        case failure
    }

    private let session: URLSession
    private var installTask: Task<Void, Never>?

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func install(
        release: GitHubRelease,
        currentVersion: SemanticVersion,
        currentAppURL: URL,
        completion: @escaping @MainActor (Result) -> Void
    ) {
        guard
            installTask == nil,
            let version = release.eligibleVersion,
            let asset = release.eligibleUpdateAsset,
            let request = asset.downloadRequest(appVersion: currentVersion),
            currentAppURL.pathExtension == "app"
        else {
            completion(.failure)
            return
        }

        installTask = Task { [weak self] in
            guard let self else {
                return
            }
            var workingDirectory: URL?
            do {
                let (downloadURL, response) = try await session.download(for: request)
                guard
                    !Task.isCancelled,
                    let httpResponse = response as? HTTPURLResponse,
                    httpResponse.statusCode == 200
                else {
                    throw InstallError.downloadFailed
                }

                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "CodexQuotaUpdate-\(UUID().uuidString)",
                        isDirectory: true
                    )
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
                workingDirectory = directory
                let archiveURL = directory.appendingPathComponent(
                    "Codex.Quota-arm64.zip"
                )
                try FileManager.default.moveItem(at: downloadURL, to: archiveURL)

                let prepared = try await Task.detached(priority: .utility) {
                    try AutomaticUpdatePackage.prepare(
                        archiveURL: archiveURL,
                        asset: asset,
                        version: version,
                        workingDirectory: directory
                    )
                }.value
                guard !Task.isCancelled else {
                    throw CancellationError()
                }
                try launchReplacement(
                    prepared: prepared,
                    currentAppURL: currentAppURL
                )
                installTask = nil
                completion(.restarting)
            } catch {
                if let workingDirectory {
                    try? FileManager.default.removeItem(at: workingDirectory)
                }
                installTask = nil
                completion(.failure)
            }
        }
    }

    func invalidate() {
        installTask?.cancel()
        installTask = nil
        session.invalidateAndCancel()
    }

    private func launchReplacement(
        prepared: PreparedUpdatePackage,
        currentAppURL: URL
    ) throws {
        let targetURL = currentAppURL.standardizedFileURL
        guard
            targetURL.pathExtension == "app",
            Bundle(url: targetURL)?.bundleIdentifier == "local.openclaw.codexquota"
        else {
            throw InstallError.invalidInstallLocation
        }
        let helperURL = prepared.workingDirectory.appendingPathComponent(
            "install-update.zsh"
        )
        try Self.replacementScript.write(
            to: helperURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: helperURL.path
        )

        let backupURL = targetURL.deletingLastPathComponent().appendingPathComponent(
            ".Codex Quota.app.backup-\(UUID().uuidString)",
            isDirectory: true
        )
        let arguments = [
            prepared.appURL.path,
            targetURL.path,
            backupURL.path,
            prepared.workingDirectory.path,
            String(ProcessInfo.processInfo.processIdentifier),
            String(getuid())
        ]
        let parentURL = targetURL.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: parentURL.path) {
            let process = Process()
            process.executableURL = helperURL
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        } else {
            try launchPrivilegedHelper(helperURL: helperURL, arguments: arguments)
        }
    }

    private func launchPrivilegedHelper(
        helperURL: URL,
        arguments: [String]
    ) throws {
        let script = """
        on run argv
            set commandText to "/usr/bin/nohup " & quoted form of item 1 of argv
            repeat with itemIndex from 2 to count of argv
                set commandText to commandText & " " & quoted form of item itemIndex of argv
            end repeat
            set commandText to commandText & " >/dev/null 2>&1 &"
            do shell script commandText with administrator privileges
        end run
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, "--", helperURL.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallError.authorizationFailed
        }
    }

    private enum InstallError: Error {
        case downloadFailed
        case invalidInstallLocation
        case authorizationFailed
    }

    private static let replacementScript = """
    #!/bin/zsh
    set -euo pipefail

    source_app="$1"
    target_app="$2"
    backup_app="$3"
    work_dir="$4"
    old_pid="$5"
    user_uid="$6"
    staged_app="${target_app}.update-${old_pid}"

    cleanup_stage() {
        /bin/rm -rf "$staged_app"
    }
    trap cleanup_stage EXIT

    for _ in {1..120}; do
        if ! /bin/kill -0 "$old_pid" 2>/dev/null; then
            break
        fi
        /bin/sleep 0.25
    done
    if /bin/kill -0 "$old_pid" 2>/dev/null; then
        exit 70
    fi
    if [[ ! -d "$source_app" || ! -d "$target_app" || -e "$backup_app" ]]; then
        exit 71
    fi

    /usr/bin/ditto "$source_app" "$staged_app"
    /bin/mv "$target_app" "$backup_app"
    if /bin/mv "$staged_app" "$target_app"; then
        if [[ "$EUID" -eq 0 ]]; then
            if /bin/launchctl asuser "$user_uid" /usr/bin/open -n "$target_app"; then
                /bin/rm -rf "$backup_app" "$work_dir"
                exit 0
            fi
        elif /usr/bin/open -n "$target_app"; then
            /bin/rm -rf "$backup_app" "$work_dir"
            exit 0
        fi
        /bin/rm -rf "$target_app"
    fi

    /bin/mv "$backup_app" "$target_app"
    if [[ "$EUID" -eq 0 ]]; then
        /bin/launchctl asuser "$user_uid" /usr/bin/open -n "$target_app" || true
    else
        /usr/bin/open -n "$target_app" || true
    fi
    exit 72
    """
}
