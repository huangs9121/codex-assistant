import Foundation

public enum CodexDesktopThreadSource: Equatable, Sendable {
    case user
    case subagent
}

public enum CodexDesktopThreadStatus: Equatable, Sendable {
    case running
    case ended
}

public struct CodexDesktopThreadSnapshot: Equatable, Sendable {
    public let id: String
    public let title: String
    public let source: CodexDesktopThreadSource
    public let startedAt: Date
    public let lastActiveAt: Date
    public let status: CodexDesktopThreadStatus

    public init(
        id: String,
        title: String,
        source: CodexDesktopThreadSource,
        startedAt: Date,
        lastActiveAt: Date,
        status: CodexDesktopThreadStatus
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.startedAt = startedAt
        self.lastActiveAt = lastActiveAt
        self.status = status
    }

    public var isRunning: Bool {
        status == .running
    }
}

public struct CodexDesktopSessionScanner: Sendable {
    public static let runningFreshness: TimeInterval = 120
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
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .isRegularFileKey
        ]
        var snapshots: [CodexDesktopThreadSnapshot] = []

        for directory in Self.sessionDirectories(
            in: sessionsDirectory,
            now: now,
            timeZone: timeZone
        ) {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in urls {
                guard
                    url.pathExtension == "jsonl",
                    url.lastPathComponent.hasPrefix("rollout-"),
                    let values = try? url.resourceValues(forKeys: keys),
                    values.isRegularFile == true,
                    let modificationDate = values.contentModificationDate,
                    let firstLine = Self.firstLine(in: url),
                    let snapshot = Self.snapshot(
                        fromSessionMetaLine: firstLine,
                        fileURL: url,
                        modificationDate: modificationDate,
                        now: now,
                        timeZone: timeZone
                    )
                else {
                    continue
                }
                snapshots.append(snapshot)
            }
        }

        return Self.visibleSnapshots(
            snapshots,
            now: now,
            timeZone: timeZone
        )
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
            payload.originator == "codex_work_desktop",
            let id = normalized(payload.id)
        else {
            return nil
        }

        let source: CodexDesktopThreadSource = payload.threadSource == "subagent"
            ? .subagent
            : .user
        let startedAt = rolloutFilenameDate(
            fileURL.lastPathComponent,
            timeZone: timeZone
        ) ?? modificationDate
        let status: CodexDesktopThreadStatus = now.timeIntervalSince(
            modificationDate
        ) < runningFreshness ? .running : .ended

        return CodexDesktopThreadSnapshot(
            id: id,
            title: displayName(
                source: source,
                cwd: payload.cwd,
                agentNickname: payload.agentNickname,
                agentPath: payload.agentPath
            ),
            source: source,
            startedAt: startedAt,
            lastActiveAt: modificationDate,
            status: status
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
        timeZone: TimeZone = .current
    ) -> [CodexDesktopThreadSnapshot] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return snapshots
            .filter {
                $0.isRunning || calendar.isDate(
                    $0.lastActiveAt,
                    inSameDayAs: now
                )
            }
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

    private struct SessionMetaEnvelope: Decodable {
        let type: String?
        let payload: Payload?

        struct Payload: Decodable {
            let originator: String?
            let threadSource: String?
            let id: String?
            let cwd: String?
            let agentNickname: String?
            let agentPath: String?

            enum CodingKeys: String, CodingKey {
                case originator
                case threadSource = "thread_source"
                case id
                case cwd
                case agentNickname = "agent_nickname"
                case agentPath = "agent_path"
            }
        }
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
