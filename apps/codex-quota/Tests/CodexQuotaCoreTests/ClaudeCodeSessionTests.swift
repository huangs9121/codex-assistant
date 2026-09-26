import CodexQuotaCore
import Foundation

enum ClaudeCodeSessionTests {
    static var all: [(String, () -> Bool)] { [
        ("Claude desktop session reads title, folder and completed state", desktopCompleted),
        ("Claude desktop session is running while its transcript is written", desktopRunning),
        ("Claude desktop session waits for pending tool permissions", desktopWaiting),
        ("Claude desktop session skips archived, malformed and foreign ids", desktopRejects),
        ("Claude desktop session opens with Claude's own continue link", openLink),
        ("Claude terminal sessions come only from interactive CLIs", terminalProcesses),
        ("Claude sessions keep active ones first and hide cleared completed ones", visibleOrder)
    ] }

    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private static func data(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private static func session(_ extra: [String: Any] = [:]) -> [String: Any] {
        [
            "sessionId": "local_00000000-0000-4000-8000-000000000001",
            "cliSessionId": "00000000-0000-4000-8000-0000000000aa",
            "cwd": "/Users/me/Projects/worktree",
            "originCwd": "/Users/me/Projects/codex助手",
            "title": "Review Claude quota",
            "isArchived": false,
            "createdAt": (now.timeIntervalSince1970 - 7_200) * 1_000,
            "lastActivityAt": (now.timeIntervalSince1970 - 600) * 1_000
        ].merging(extra) { $1 }
    }

    private static func desktopCompleted() -> Bool {
        let parsed = ClaudeCodeSessionParser.desktopSession(from: data(session()), now: now) { _ in
            now.addingTimeInterval(-600)
        }
        let untitled = ClaudeCodeSessionParser.desktopSession(from: data(session(["title": " "])), now: now)
        return parsed?.title == "Review Claude quota"
            && parsed?.folderName == "codex助手"
            && parsed?.status == .completed
            && parsed?.lastActiveAt == now.addingTimeInterval(-600)
            && parsed?.origin == .desktop(sessionID: "local_00000000-0000-4000-8000-000000000001")
            && untitled?.title == "codex助手"
    }

    private static func desktopRunning() -> Bool {
        var asked: String?
        let parsed = ClaudeCodeSessionParser.desktopSession(from: data(session()), now: now) { id in
            asked = id
            return now.addingTimeInterval(-20)
        }
        return asked == "00000000-0000-4000-8000-0000000000aa"
            && parsed?.status == .running
            && parsed?.lastActiveAt == now.addingTimeInterval(-20)
    }

    private static func desktopWaiting() -> Bool {
        let parsed = ClaudeCodeSessionParser.desktopSession(
            from: data(session(["pendingToolPermissions": [["tool": "Bash"]]])), now: now) { _ in
            now.addingTimeInterval(-5)
        }
        let empty = ClaudeCodeSessionParser.desktopSession(
            from: data(session(["pendingToolPermissions": []])), now: now)
        return parsed?.status == .waiting && empty?.status == .completed
    }

    private static func desktopRejects() -> Bool {
        ClaudeCodeSessionParser.desktopSession(from: data(session(["isArchived": true])), now: now) == nil
            && ClaudeCodeSessionParser.desktopSession(from: data(session(["sessionId": "cse_remote"])), now: now) == nil
            && ClaudeCodeSessionParser.desktopSession(from: data(session(["sessionId": "local_../x"])), now: now) == nil
            && ClaudeCodeSessionParser.desktopSession(
                from: data(session(["lastActivityAt": NSNull(), "createdAt": NSNull()])), now: now) == nil
            && ClaudeCodeSessionParser.desktopSession(from: Data("[]".utf8), now: now) == nil
    }

    private static func openLink() -> Bool {
        ClaudeCodeSessionParser.openURL(forDesktopSession: "local_00000000-0000-4000-8000-000000000002")?.absoluteString
            == "claude://code/continue?session=local_00000000-0000-4000-8000-000000000002"
            && ClaudeCodeSessionParser.openURL(forDesktopSession: "local_") == nil
            && ClaudeCodeSessionParser.openURL(forDesktopSession: "local_a&b=c") == nil
            && ClaudeCodeSessionParser.openURL(forDesktopSession: "session_x") == nil
    }

    private static func terminalProcesses() -> Bool {
        let ps = """
          501 ttys003  claude --resume
          502 ttys004  node /opt/homebrew/bin/claude
          503 ??       /Users/me/Library/Application Support/Claude/claude-code/2.1.281/claude.app/Contents/MacOS/claude --output-format stream-json
          504 ttys005  /usr/local/bin/codex
          505 ttys006  claude-helper --run
          506 ??       claude
        """
        let found = ClaudeCodeSessionParser.terminalProcesses(processList: ps)
        let session = ClaudeCodeSessionParser.terminalSession(process: found[0], cwd: "/Users/me/Projects/aihot", now: now)
        return found == [CodexCLIProcess(pid: 501, tty: "ttys003"), CodexCLIProcess(pid: 502, tty: "ttys004")]
            && session.title == "claude · aihot" && session.status == .running
            && session.origin == .terminal(CodexCLIProcess(pid: 501, tty: "ttys003"))
    }

    private static func visibleOrder() -> Bool {
        func make(_ id: String, _ status: ClaudeCodeSession.Status, _ minutesAgo: Double) -> ClaudeCodeSession {
            ClaudeCodeSession(id: id, title: id, folderName: nil, lastActiveAt: now.addingTimeInterval(-minutesAgo * 60),
                              status: status, origin: .desktop(sessionID: id))
        }
        let sessions = [make("done-new", .completed, 1), make("running-old", .running, 30),
                        make("waiting", .waiting, 5), make("done-old", .completed, 90),
                        make("hidden-done", .completed, 2), make("hidden-running", .running, 3)]
        let visible = ClaudeCodeSessionParser.visible(
            sessions, hiddenIDs: ["hidden-done", "hidden-running"], limit: 4).map(\.id)
        let terminal = ClaudeCodeSessionParser.terminalSession(
            process: CodexCLIProcess(pid: 7, tty: "ttys001"), cwd: nil, now: now)
        let mixed = ClaudeCodeSessionParser.visible(sessions + [terminal], hiddenIDs: [], limit: 10).map(\.id)
        return visible == ["hidden-running", "waiting", "running-old", "done-new"]
            && mixed == ["hidden-running", "waiting", "running-old", "terminal:7",
                         "done-new", "hidden-done", "done-old"]
    }
}
