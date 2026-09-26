import CodexQuotaCore
import Foundation

/// Lists Claude Code sessions from Claude Desktop's local session metadata and from
/// Claude Code CLIs running in a terminal. Only metadata and file dates are read;
/// transcripts are never opened.
enum ClaudeSessionScanner {
    /// Newest session files considered per scan; the panel shows at most 10 rows.
    private static let fileLimit = 40

    static func scan(now: Date = Date()) -> [ClaudeCodeSession] {
        desktopSessions(now: now) + terminalSessions(now: now)
    }

    private static func desktopSessions(now: Date) -> [ClaudeCodeSession] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let root = home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        // Layout: <account>/<organization>/local_<id>.json
        let files = children(of: root).flatMap(children).flatMap { folder in
            ((try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json" }
        }
        let projects = children(of: home.appendingPathComponent(".claude/projects", isDirectory: true))
        func transcriptModifiedAt(_ id: String) -> Date? {
            guard UUID(uuidString: id) != nil else { return nil }
            return projects.lazy.compactMap { modificationDate($0.appendingPathComponent("\(id).jsonl")) }.first
        }
        return files
            .sorted { (modificationDate($0) ?? .distantPast) > (modificationDate($1) ?? .distantPast) }
            .prefix(fileLimit)
            .compactMap { file in
                guard
                    let values = try? file.resourceValues(forKeys: Set(keys)),
                    values.isRegularFile == true,
                    let size = values.fileSize, size <= 2 * 1_024 * 1_024,
                    let data = try? Data(contentsOf: file)
                else { return nil }
                return ClaudeCodeSessionParser.desktopSession(
                    from: data, now: now, transcriptModifiedAt: transcriptModifiedAt)
            }
    }

    private static func terminalSessions(now: Date) -> [ClaudeCodeSession] {
        guard let list = TaskStatusController.processOutput("/bin/ps", ["-axo", "pid=,tty=,args="]) else { return [] }
        return ClaudeCodeSessionParser.terminalProcesses(processList: list).map { process in
            ClaudeCodeSessionParser.terminalSession(process: process, cwd: workingDirectory(of: process.pid), now: now)
        }
    }

    private static func workingDirectory(of pid: Int) -> String? {
        TaskStatusController.processOutput("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"])?
            .split(separator: "\n")
            .first { $0.hasPrefix("n") }
            .map { String($0.dropFirst()) }
    }

    private static func children(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ))?.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } ?? []
    }

    private static func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
