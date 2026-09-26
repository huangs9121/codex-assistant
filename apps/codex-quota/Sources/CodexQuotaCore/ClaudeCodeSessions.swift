import Foundation

/// A Claude Code session listed when Claude is the selected quota source. Built from
/// Claude Desktop's local session metadata or a running terminal CLI; conversation
/// content is never read.
public struct ClaudeCodeSession: Equatable, Sendable, Identifiable {
    public enum Status: Equatable, Sendable {
        case running
        case waiting
        case completed
    }

    public enum Origin: Equatable, Sendable {
        case desktop(sessionID: String)
        case terminal(CodexCLIProcess)
    }

    public let id: String
    public let title: String
    public let folderName: String?
    public let lastActiveAt: Date
    public let status: Status
    public let origin: Origin

    public init(
        id: String,
        title: String,
        folderName: String?,
        lastActiveAt: Date,
        status: Status,
        origin: Origin
    ) {
        self.id = id
        self.title = title
        self.folderName = folderName
        self.lastActiveAt = lastActiveAt
        self.status = status
        self.origin = origin
    }
}

public enum ClaudeCodeSessionParser {
    /// Claude Code appends to the transcript while a turn runs, so a recent write means
    /// the session is working.
    public static let runningWindow: TimeInterval = 60

    /// Parses one `claude-code-sessions/<account>/<org>/local_*.json` file written by Claude
    /// Desktop. Archived or malformed sessions return nil. `transcriptModifiedAt` receives the
    /// Claude Code session id and returns when its transcript was last written, if known.
    public static func desktopSession(
        from data: Data,
        now: Date,
        transcriptModifiedAt: (String) -> Date? = { _ in nil }
    ) -> ClaudeCodeSession? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = root["sessionId"] as? String,
            openURL(forDesktopSession: id) != nil,
            root["isArchived"] as? Bool != true
        else { return nil }
        let cwd = [root["originCwd"], root["cwd"]].compactMap { $0 as? String }.first { !$0.isEmpty }
        let folder = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
        let transcript = (root["cliSessionId"] as? String).flatMap(transcriptModifiedAt)
        guard let recorded = date(root["lastActivityAt"]) ?? date(root["createdAt"]) ?? transcript else {
            return nil
        }
        // Same rule Claude Desktop uses for "Sessions Waiting for You".
        let waiting = (root["pendingToolPermissions"] as? [Any])?.isEmpty == false
        let writing = transcript.map { now.timeIntervalSince($0) <= runningWindow } ?? false
        let title = (root["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ClaudeCodeSession(
            id: id,
            title: title.isEmpty ? (folder ?? "Claude Code") : title,
            folderName: folder,
            lastActiveAt: max(recorded, transcript ?? recorded),
            status: waiting ? .waiting : (writing ? .running : .completed),
            origin: .desktop(sessionID: id)
        )
    }

    /// `claude://code/continue?session=<id>`, the link Claude Desktop itself uses for its Dock
    /// menu and Spotlight entries. Only Claude Desktop's own `local_` ids are accepted.
    public static func openURL(forDesktopSession id: String) -> URL? {
        guard id.range(of: #"^local_[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/continue"
        components.queryItems = [URLQueryItem(name: "session", value: id)]
        return components.url
    }

    /// Interactive Claude Code CLIs attached to a terminal, from `ps -o pid=,tty=,args=`.
    /// Sessions hosted by Claude Desktop have no terminal and use stream-json, so they are skipped.
    public static func terminalProcesses(processList: String) -> [CodexCLIProcess] {
        processList.split(separator: "\n").compactMap { line in
            let parts = line.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 3, let pid = Int(parts[0]), parts[1] != "??",
                  !parts[2].contains("--output-format") else { return nil }
            let launcher = parts[2].split(separator: " ").prefix(2)
            guard launcher.contains(where: { URL(fileURLWithPath: String($0)).lastPathComponent == "claude" }) else {
                return nil
            }
            return CodexCLIProcess(pid: pid, tty: String(parts[1]))
        }
    }

    public static func terminalSession(process: CodexCLIProcess, cwd: String?, now: Date) -> ClaudeCodeSession {
        let folder = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
        return ClaudeCodeSession(
            id: "terminal:\(process.pid)",
            title: "claude" + (folder.map { " · \($0)" } ?? ""),
            folderName: folder,
            lastActiveAt: now,
            status: .running,
            origin: .terminal(process)
        )
    }

    /// Active Claude Desktop sessions first, then terminal CLIs (as Codex CLI rows sit after
    /// desktop threads), then completed sessions; newest first within each group. A session
    /// the user cleared stays hidden only while it is completed, so new activity brings it back.
    public static func visible(
        _ sessions: [ClaudeCodeSession],
        hiddenIDs: Set<String>,
        limit: Int
    ) -> [ClaudeCodeSession] {
        func rank(_ session: ClaudeCodeSession) -> Int {
            if session.status == .completed { return 2 }
            if case .terminal = session.origin { return 1 }
            return 0
        }
        return Array(sessions
            .filter { $0.status != .completed || !hiddenIDs.contains($0.id) }
            .sorted { rank($0) == rank($1) ? $0.lastActiveAt > $1.lastActiveAt : rank($0) < rank($1) }
            .prefix(limit))
    }

    private static func date(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue > 0 else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue / 1_000)
    }
}
