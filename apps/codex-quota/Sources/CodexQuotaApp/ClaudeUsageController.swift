import CodexQuotaCore
import Foundation
import Security

/// Reads Claude usage through the user's own, unmodified Claude Code CLI.
/// The app never touches Claude credentials in the Keychain, so macOS has nothing
/// to prompt for, and Claude Code keeps refreshing its own login.
@MainActor
final class ClaudeUsageController {
    enum Source: Sendable { case live, lastLive, desktopCache }
    enum Failure: Error, Sendable {
        case cliMissing
        case notLoggedIn
        case noUsageWindows
        case timedOut
        case launchFailed
    }
    enum Result: Sendable {
        case snapshot(QuotaSnapshot, source: Source, stale: Bool, liveFailure: Failure?)
        case unavailable(Failure)
    }

    private static let staleAfter: TimeInterval = 30 * 60
    private var lastLive: QuotaSnapshot?

    /// Callers must not start a second check before the completion runs.
    func check(completion: @escaping @MainActor (Result) -> Void) {
        Task { @MainActor in
            let live = await Task.detached(priority: .utility) { ClaudeCLIUsageClient.fetch() }.value
            let now = Date()
            switch live {
            case .success(let snapshot):
                lastLive = snapshot
                completion(.snapshot(snapshot, source: .live, stale: false, liveFailure: nil))
            case .failure(let failure):
                if case .notLoggedIn = failure { lastLive = nil }
                if let previous = lastLive, Self.cacheIsCurrent(previous, at: now) {
                    completion(.snapshot(previous, source: .lastLive,
                                         stale: Self.isStale(previous.observedAt, at: now), liveFailure: failure))
                    return
                }
                let cached = await Task.detached(priority: .utility) {
                    ClaudeDesktopUsageStore.latestSnapshot()
                }.value
                if let cached {
                    completion(.snapshot(cached, source: .desktopCache,
                                         stale: Self.isStale(cached.observedAt, at: now), liveFailure: failure))
                } else {
                    completion(.unavailable(failure))
                }
            }
        }
    }

    private static func isStale(_ observedAt: Date, at now: Date) -> Bool {
        let age = now.timeIntervalSince(observedAt)
        return age < 0 || age > staleAfter
    }

    private static func cacheIsCurrent(_ snapshot: QuotaSnapshot, at now: Date) -> Bool {
        let resetDates = [snapshot.resetsAt, snapshot.secondaryWindow?.resetsAt]
            .compactMap { $0 }
        if resetDates.contains(where: { $0 <= now }) { return false }
        if resetDates.isEmpty { return !isStale(snapshot.observedAt, at: now) }
        return true
    }
}

private enum ClaudeDesktopUsageStore {
    static func latestSnapshot() -> QuotaSnapshot? {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
        guard
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true,
            let size = values.fileSize,
            size > 0 && size <= 2 * 1_024 * 1_024,
            let data = try? Data(contentsOf: file)
        else { return nil }
        return ClaudeUsageParser.desktopHistorySnapshot(from: data)
    }
}

/// Runs `claude auth status` and `claude -p "/usage"` from an Anthropic-signed install.
private enum ClaudeCLIUsageClient {
    /// Anthropic PBC Developer ID. Unsigned npm shims or other signers are never run.
    private static let requirement = """
        anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] \
        and certificate leaf[subject.OU] = "Q6L2SF6YDW"
        """

    private struct Output: Sendable {
        let status: Int32
        let data: Data
    }

    static func fetch() -> Swift.Result<QuotaSnapshot, ClaudeUsageController.Failure> {
        guard let cli = locate() else { return .failure(.cliMissing) }
        var planName: String?
        if case .success(let output) = run(cli, ["auth", "status"], timeout: 10),
           let status = ClaudeUsageParser.cliAuthStatus(from: output.data) {
            guard status.loggedIn else { return .failure(.notLoggedIn) }
            planName = status.planName
        }
        switch run(cli, ["-p", "/usage", "--no-session-persistence"], timeout: 30) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let output):
            // Never log this output: it can include account and local session details.
            let text = String(decoding: output.data, as: UTF8.self)
            if let snapshot = ClaudeUsageParser.cliUsageSnapshot(from: text, now: Date(), planName: planName) {
                return .success(snapshot)
            }
            let lowered = text.lowercased()
            if lowered.contains("/login") || lowered.contains("not logged in") {
                return .failure(.notLoggedIn)
            }
            return .failure(.noUsageWindows)
        }
    }

    private static func locate() -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var candidates = [
            home.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude")
        ]
        // Claude Desktop keeps its own signed copy in a versioned folder.
        let bundled = home.appendingPathComponent("Library/Application Support/Claude/claude-code")
        let versions = ((try? fileManager.contentsOfDirectory(atPath: bundled.path)) ?? [])
            .compactMap { name in SemanticVersion(name).map { (version: $0, name: name) } }
            .sorted { $0.version > $1.version }
        candidates += versions.map {
            bundled.appendingPathComponent("\($0.name)/claude.app/Contents/MacOS/claude")
        }
        return candidates.lazy
            .map { $0.resolvingSymlinksInPath() }
            .first { fileManager.isExecutableFile(atPath: $0.path) && isTrusted($0) }
    }

    private static func isTrusted(_ url: URL) -> Bool {
        var code: SecStaticCode?
        var trusted: SecRequirement?
        guard
            SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
            let code,
            SecRequirementCreateWithString(requirement as CFString, [], &trusted) == errSecSuccess,
            let trusted
        else { return false }
        return SecStaticCodeCheckValidity(code, [], trusted) == errSecSuccess
    }

    private static func run(
        _ executable: URL,
        _ arguments: [String],
        timeout: TimeInterval
    ) -> Swift.Result<Output, ClaudeUsageController.Failure> {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment()
        process.currentDirectoryURL = workingDirectory()
        // A closed stdin avoids the CLI's three-second wait for piped input.
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        do { try process.run() } catch { return .failure(.launchFailed) }

        let collector = OutputCollector(limit: 256 * 1_024)
        let finished = DispatchSemaphore(value: 0)
        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                collector.append(chunk)
            }
            finished.signal()
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            return .failure(.timedOut)
        }
        process.waitUntilExit()
        return .success(Output(status: process.terminationStatus, data: collector.data))
    }

    /// Only what the CLI needs to find the user's own login. Tokens or API keys
    /// inherited from a terminal or another agent are deliberately not passed on.
    private static func environment() -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        var environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "en_US.UTF-8",
            "DISABLE_AUTOUPDATER": "1"
        ]
        for key in ["HOME", "USER", "LOGNAME", "TMPDIR"] { environment[key] = inherited[key] }
        environment["HOME"] = environment["HOME"] ?? NSHomeDirectory()
        return environment
    }

    /// A fixed folder keeps Claude Code's per-folder project record in one place.
    private static func workingDirectory() -> URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexQuota/ClaudeUsage", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let limit: Int

    init(limit: Int) { self.limit = limit }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(chunk.prefix(max(0, limit - buffer.count)))
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
