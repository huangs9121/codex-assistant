import Foundation

public enum CodexDesktopThreadSource: Equatable, Sendable {
    case user
    case subagent
}

public struct CodexCLIProcess: Equatable, Sendable {
    public let pid: Int
    public let tty: String?
    public init(pid: Int, tty: String?) { self.pid = pid; self.tty = tty }

    public static func sessions(owners: [String: Int], processList: String) -> [String: Self] {
        var live: [Int: CodexCLIProcess] = [:]
        for line in processList.split(separator: "\n") {
            let parts = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 4, let currentPID = Int(parts[0]) else { continue }
            let description = "\(parts[2]) \(parts[3])"
            guard URL(fileURLWithPath: String(parts[2])).lastPathComponent == "codex",
                  !description.contains("app-server"), parts[1] != "??" else { continue }
            let tty = String(parts[1])
            live[currentPID] = CodexCLIProcess(pid: currentPID, tty: tty)
        }
        let cli = owners.reduce(into: [String: CodexCLIProcess]()) { result, item in
            if let process = live[item.value] { result[item.key] = process }
        }
        return cli
    }
}

public enum CodexDesktopThreadStatus: Equatable, Sendable {
    case running
    case ended
    case unknown
}

public struct CodexDesktopThreadSnapshot: Equatable, Sendable {
    public let id: String
    public let parentThreadID: String?
    public let title: String
    public let source: CodexDesktopThreadSource
    public let startedAt: Date
    public let lastActiveAt: Date
    public let status: CodexDesktopThreadStatus
    public let createdByCLI: Bool

    public init(
        id: String,
        parentThreadID: String? = nil,
        title: String,
        source: CodexDesktopThreadSource,
        startedAt: Date,
        lastActiveAt: Date,
        status: CodexDesktopThreadStatus,
        createdByCLI: Bool = false
    ) {
        self.id = id
        self.parentThreadID = parentThreadID
        self.title = title
        self.source = source
        self.startedAt = startedAt
        self.lastActiveAt = lastActiveAt
        self.status = status
        self.createdByCLI = createdByCLI
    }

    public func reconcilingOwner(isOwned: Bool) -> Self {
        guard status == .running, !isOwned else { return self }
        return Self(id: id, parentThreadID: parentThreadID, title: title,
                    source: source, startedAt: startedAt, lastActiveAt: lastActiveAt,
                    status: .unknown, createdByCLI: createdByCLI)
    }

    public var isRunning: Bool {
        status == .running
    }
}

public final class CodexDesktopSessionScanner: @unchecked Sendable {
    private let cacheLock = NSLock()
    private var snapshotCache: [URL: (modified: Date, snapshot: CodexDesktopThreadSnapshot)] = [:]
    public static let displayLimit = 8

    public let sessionsDirectory: URL
    public let timeZone: TimeZone

    public init(
        sessionsDirectory: URL,
        timeZone: TimeZone = .current
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.timeZone = timeZone
    }

    public func snapshots(now: Date = Date()) -> [CodexDesktopThreadSnapshot] {
        Self.visibleSnapshots(candidateSnapshots(now: now), now: now, timeZone: timeZone)
    }

    /// 未按展示规则截断的近期候选。树投影必须基于这组数据建关系。
    public func candidateSnapshots(
        now: Date = Date(),
        since: Date? = nil
    ) -> [CodexDesktopThreadSnapshot] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .isRegularFileKey
        ]
        var snapshots: [CodexDesktopThreadSnapshot] = []
        let titles = Self.sessionTitles(
            in: sessionsDirectory.deletingLastPathComponent()
        )

        let urls: [URL]
        if let since {
            urls = Self.sessionFiles(
                in: sessionsDirectory,
                since: since,
                resourceKeys: keys
            )
        } else {
            urls = Self.sessionDirectories(
                in: sessionsDirectory,
                now: now,
                timeZone: timeZone
            ).flatMap { directory in
                (try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles]
                )) ?? []
            }
        }

        for url in urls {
            guard
                url.pathExtension == "jsonl",
                url.lastPathComponent.hasPrefix("rollout-"),
                let values = try? url.resourceValues(forKeys: keys),
                values.isRegularFile == true,
                let modificationDate = values.contentModificationDate,
                since.map({ modificationDate >= $0 }) ?? true,
                let snapshot = cachedSnapshot(at: url, modified: modificationDate, now: now)
            else {
                continue
            }
            if snapshot.source == .user, let title = titles[snapshot.id] {
                snapshots.append(CodexDesktopThreadSnapshot(
                    id: snapshot.id, parentThreadID: snapshot.parentThreadID,
                    title: title, source: snapshot.source, startedAt: snapshot.startedAt,
                    lastActiveAt: snapshot.lastActiveAt, status: snapshot.status,
                    createdByCLI: snapshot.createdByCLI
                ))
            } else { snapshots.append(snapshot) }
        }

        return Self.deduplicatedSnapshots(snapshots)
    }

    // Called under cacheLock. Titles and live ownership are applied after this cache.
    private func cachedSnapshot(at url: URL, modified: Date, now: Date) -> CodexDesktopThreadSnapshot? {
        if let cached = snapshotCache[url], cached.modified == modified { return cached.snapshot }
        guard let line = Self.firstLine(in: url),
              let snapshot = Self.snapshot(fromSessionMetaLine: line, fileURL: url,
                    modificationDate: modified, now: now, timeZone: timeZone) else { return nil }
        snapshotCache[url] = (modified, snapshot)
        return snapshot
    }

    /// 为跨日期父任务精确查找会话头；只按 ID 匹配，不从显示名称推断。
    public func snapshot(forID id: String, now: Date = Date()) -> CodexDesktopThreadSnapshot? {
        if let recent = candidateSnapshots(now: now).first(where: { $0.id == id }) {
            return recent
        }
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            guard
                url.pathExtension == "jsonl",
                url.lastPathComponent.hasPrefix("rollout-"),
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                values.isRegularFile == true,
                let modificationDate = values.contentModificationDate,
                let line = Self.firstLine(in: url),
                let snapshot = Self.snapshot(fromSessionMetaLine: line, fileURL: url, modificationDate: modificationDate, now: now, timeZone: timeZone),
                snapshot.id == id
            else { continue }
            return snapshot
        }
        return nil
    }

    public static func sessionDirectories(
        in sessionsDirectory: URL,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> [URL] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(
            byAdding: .day,
            value: -1,
            to: today
        ) ?? today

        return [today, yesterday].map { date in
            let components = calendar.dateComponents(
                [.year, .month, .day],
                from: date
            )
            return sessionsDirectory
                .appendingPathComponent(
                    String(format: "%04d", components.year ?? 0),
                    isDirectory: true
                )
                .appendingPathComponent(
                    String(format: "%02d", components.month ?? 0),
                    isDirectory: true
                )
                .appendingPathComponent(
                    String(format: "%02d", components.day ?? 0),
                    isDirectory: true
                )
        }
    }

    private static func sessionFiles(
        in sessionsDirectory: URL,
        since: Date,
        resourceKeys: Set<URLResourceKey>
    ) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { url in
            guard
                url.pathExtension == "jsonl",
                url.lastPathComponent.hasPrefix("rollout-"),
                let values = try? url.resourceValues(forKeys: resourceKeys),
                values.isRegularFile == true,
                let modificationDate = values.contentModificationDate
            else {
                return false
            }
            return modificationDate >= since
        }
    }

    private static func sessionTitles(in codexDirectory: URL) -> [String: String] {
        let url = codexDirectory.appendingPathComponent("session_index.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        struct Entry: Decodable { let id: String?; let threadName: String?; enum CodingKeys: String, CodingKey { case id; case threadName = "thread_name" } }
        return text.split(separator: "\n").reduce(into: [String: String]()) { result, line in
            guard let item = try? JSONDecoder().decode(Entry.self, from: Data(line.utf8)), let id = item.id, let title = item.threadName?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
            result[id] = title
        }
    }

    public static func snapshot(
        fromSessionMetaLine line: String,
        fileURL: URL,
        modificationDate: Date,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> CodexDesktopThreadSnapshot? {
        guard
            let data = line.data(using: .utf8),
            let envelope = try? JSONDecoder().decode(
                SessionMetaEnvelope.self,
                from: data
            ),
            envelope.type == "session_meta",
            let payload = envelope.payload,
            (payload.originator == "codex_work_desktop" || (payload.originator == "codex-tui" && payload.source == "cli")),
            let id = normalized(payload.id)
        else {
            return nil
        }

        let source: CodexDesktopThreadSource = payload.threadSource == "subagent"
            ? .subagent
            : .user
        let filenameStartedAt = rolloutFilenameDate(
            fileURL.lastPathComponent,
            timeZone: timeZone
        ) ?? modificationDate
        let activity = activitySummary(in: fileURL, modificationDate: modificationDate)
        let status: CodexDesktopThreadStatus
        if activity.latestTurnIsActive {
            status = .running
        } else if activity.hasExplicitCompletion {
            status = .ended
        } else {
            status = .unknown
        }
        let startedAt = activity.latestTurnStartedAt ?? filenameStartedAt

        return CodexDesktopThreadSnapshot(
            id: id,
            parentThreadID: normalized(payload.parentThreadID),
            title: displayName(
                source: source,
                cwd: payload.cwd,
                agentNickname: payload.agentNickname,
                agentPath: payload.agentPath
            ),
            source: source,
            startedAt: startedAt,
            lastActiveAt: activity.lastActiveAt ?? modificationDate,
            status: status,
            createdByCLI: payload.originator == "codex-tui" && payload.source == "cli"
        )
    }

    public static func displayName(
        source: CodexDesktopThreadSource,
        cwd: String?,
        agentNickname: String?,
        agentPath: String?
    ) -> String {
        let workspaceName = pathComponent(cwd)
        switch source {
        case .user:
            return workspaceName ?? "Codex"
        case .subagent:
            let parts = [
                normalized(agentNickname),
                pathComponent(agentPath)
            ].compactMap { $0 }
            return parts.isEmpty
                ? (workspaceName ?? "Codex")
                : parts.joined(separator: " · ")
        }
    }

    public static func visibleSnapshots(
        _ snapshots: [CodexDesktopThreadSnapshot],
        now: Date = Date(),
        timeZone: TimeZone = .current,
        hiddenIDs: Set<String> = []
    ) -> [CodexDesktopThreadSnapshot] {
        return deduplicatedSnapshots(snapshots)
            .filter { $0.isRunning || !hiddenIDs.contains($0.id) }
            .sorted {
                if $0.isRunning != $1.isRunning {
                    return $0.isRunning
                }
                if $0.lastActiveAt != $1.lastActiveAt {
                    return $0.lastActiveAt > $1.lastActiveAt
                }
                return $0.id < $1.id
            }
            .prefix(displayLimit)
            .map { $0 }
    }

    public static func deduplicatedSnapshots(
        _ snapshots: [CodexDesktopThreadSnapshot]
    ) -> [CodexDesktopThreadSnapshot] {
        Array(snapshots.reduce(into: [String: CodexDesktopThreadSnapshot]()) { result, snapshot in
            guard let existing = result[snapshot.id], existing.lastActiveAt >= snapshot.lastActiveAt else {
                result[snapshot.id] = snapshot
                return
            }
        }.values)
    }

    private struct SessionMetaEnvelope: Decodable {
        let type: String?
        let payload: Payload?

        struct Payload: Decodable {
            let originator: String?
            let threadSource: String?
            let id: String?
            let parentThreadID: String?
            let cwd: String?
            let agentNickname: String?
            let agentPath: String?
            let source: String?

            enum CodingKeys: String, CodingKey {
                case originator
                case threadSource = "thread_source"
                case id
                case parentThreadID = "parent_thread_id"
                case cwd
                case agentNickname = "agent_nickname"
                case agentPath = "agent_path"
                case source
            }
        }
    }

    private struct ActivityEnvelope: Decodable {
        let timestamp: String?
        let payload: Payload?

        struct Payload: Decodable {
            let type: String?
            let turnID: String?
            let startedAt: Double?

            enum CodingKeys: String, CodingKey {
                case type
                case turnID = "turn_id"
                case startedAt = "started_at"
            }
        }
    }

    private struct ActivitySummary {
        var latestTurnID: String? = nil
        var latestTurnStartedAt: Date? = nil
        var latestTurnIsActive = false
        var hasExplicitCompletion = false
        var lastActiveAt: Date? = nil
    }

    private static func activitySummary(
        in url: URL,
        modificationDate: Date
    ) -> ActivitySummary {
        guard
            let handle = try? FileHandle(forReadingFrom: url),
            let fileSize = try? handle.seekToEnd()
        else {
            return ActivitySummary(lastActiveAt: modificationDate)
        }
        defer { try? handle.close() }

        let chunkSize: UInt64 = 512 * 1024
        var offset = fileSize > chunkSize ? fileSize - chunkSize : 0
        try? handle.seek(toOffset: offset)
        guard var data = try? handle.readToEnd(), !data.isEmpty else {
            return ActivitySummary(lastActiveAt: modificationDate)
        }

        // A verbose tool can push the latest task_started event out of the
        // initial tail. Expand only until that start is available, then parse
        // the retained segment in chronological order to match its completion.
        while !containsTaskStarted(in: data, skippingFirstLine: offset > 0), offset > 0 {
            let length = min(UInt64(data.count), offset)
            offset -= length
            try? handle.seek(toOffset: offset)
            guard let prefix = try? handle.read(upToCount: Int(length)), !prefix.isEmpty else {
                break
            }
            data = prefix + data
        }

        var summary = ActivitySummary()
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.dropFirst(offset > 0 ? 1 : 0) {
            guard
                let event = try? JSONDecoder().decode(
                    ActivityEnvelope.self,
                    from: Data(line.utf8)
                ),
                let payload = event.payload,
                let type = payload.type,
                ["task_started", "task_complete", "turn_aborted"].contains(type)
            else {
                continue
            }
            let eventDate: Date
            if type == "task_started", let startedAt = payload.startedAt {
                eventDate = Date(timeIntervalSince1970: startedAt)
            } else {
                eventDate = event.timestamp.flatMap(isoDate) ?? modificationDate
            }
            if summary.lastActiveAt == nil || eventDate > summary.lastActiveAt! {
                summary.lastActiveAt = eventDate
            }
            switch type {
            case "task_started":
                guard let turnID = payload.turnID else { continue }
                summary.latestTurnID = turnID
                summary.latestTurnStartedAt = eventDate
                summary.latestTurnIsActive = true
            case "task_complete", "turn_aborted":
                guard
                    payload.turnID == nil
                        || payload.turnID == summary.latestTurnID
                else {
                    continue
                }
                summary.latestTurnIsActive = false
                summary.hasExplicitCompletion = true
            default:
                break
            }
        }
        summary.lastActiveAt = summary.lastActiveAt ?? modificationDate
        return summary
    }

    private static func containsTaskStarted(
        in data: Data,
        skippingFirstLine: Bool
    ) -> Bool {
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
        return lines.dropFirst(skippingFirstLine ? 1 : 0).contains { line in
            guard
                let event = try? JSONDecoder().decode(
                    ActivityEnvelope.self,
                    from: Data(line.utf8)
                ),
                let payload = event.payload,
                payload.type == "task_started",
                normalized(payload.turnID) != nil
            else {
                return false
            }
            return true
        }
    }

    private static func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
    }

    private static func firstLine(in url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        var line = Data()
        while line.count < 64 * 1024 {
            guard
                let chunk = try? handle.read(upToCount: 4 * 1024),
                !chunk.isEmpty
            else {
                break
            }
            if let newlineIndex = chunk.firstIndex(of: 0x0A) {
                line.append(chunk.prefix(upTo: newlineIndex))
                break
            }
            line.append(chunk)
        }
        guard !line.isEmpty else {
            return nil
        }
        return String(decoding: line, as: UTF8.self)
            .trimmingCharacters(in: .newlines)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func pathComponent(_ value: String?) -> String? {
        guard let value = normalized(value) else {
            return nil
        }
        let component = URL(fileURLWithPath: value)
            .standardizedFileURL
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return component.isEmpty || component == "/" ? nil : component
    }

    private static func rolloutFilenameDate(
        _ filename: String,
        timeZone: TimeZone
    ) -> Date? {
        let name = URL(fileURLWithPath: filename)
            .deletingPathExtension()
            .lastPathComponent
        guard name.hasPrefix("rollout-"), name.count >= 27 else {
            return nil
        }
        let start = name.index(name.startIndex, offsetBy: 8)
        let end = name.index(start, offsetBy: 19)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.date(from: String(name[start..<end]))
    }
}
