import CryptoKit
import Foundation

public enum TaskDispatchMode: String, Codable, Equatable, Sendable {
    case sync
    case resume
    case status
}

public enum TaskExecutionStatus: String, Codable, Equatable, Sendable {
    case running
    case done
    case failed
    case interrupted

    public var isTerminal: Bool {
        self != .running
    }

    public var isClearable: Bool {
        self == .done || self == .interrupted
    }

    public var shouldNotifyCompletion: Bool {
        self == .done || self == .failed
    }
}

public struct TaskSessionEntry: Equatable, Sendable {
    public let startedAt: Date
    public let sessionUUID: String
    public let mode: TaskDispatchMode
    public let briefPath: String

    public init(
        startedAt: Date,
        sessionUUID: String,
        mode: TaskDispatchMode,
        briefPath: String
    ) {
        self.startedAt = startedAt
        self.sessionUUID = sessionUUID
        self.mode = mode
        self.briefPath = briefPath
    }
}

public struct TaskStatusSnapshot: Equatable, Sendable {
    public let id: String
    public let startedAt: Date
    public let sessionUUID: String?
    public let mode: TaskDispatchMode?
    public let taskName: String?
    public let isBackgroundTask: Bool
    public let status: TaskExecutionStatus
    public let exitCode: Int?
    public let lastMessage: String?
    public let endedAt: Date?

    public init(
        id: String,
        startedAt: Date,
        sessionUUID: String?,
        mode: TaskDispatchMode?,
        taskName: String?,
        isBackgroundTask: Bool,
        status: TaskExecutionStatus,
        exitCode: Int?,
        lastMessage: String?,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.sessionUUID = sessionUUID
        self.mode = mode
        self.taskName = taskName
        self.isBackgroundTask = isBackgroundTask
        self.status = status
        self.exitCode = exitCode
        self.lastMessage = lastMessage
        self.endedAt = endedAt
    }

    public var duration: TimeInterval? {
        guard let endedAt else {
            return nil
        }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }
}

public struct TaskStatusParser: Sendable {
    private static let archiveLimit = 50
    private static let tailByteLimit = 64 * 1024
    private static let rolloutMatchTolerance: TimeInterval = 10 * 60
    private static let interruptionThreshold: TimeInterval = 10 * 60

    public let tasksDirectory: URL
    public let workingDirectory: URL
    public let codexSessionsDirectory: URL
    public let timeZone: TimeZone

    private let tmuxStatusProvider: @Sendable (String) -> Bool

    public init(
        tasksDirectory: URL,
        workingDirectory: URL,
        codexSessionsDirectory: URL,
        timeZone: TimeZone = .current,
        tmuxStatusProvider: (@Sendable (String) -> Bool)? = nil
    ) {
        self.tasksDirectory = tasksDirectory
        self.workingDirectory = workingDirectory
        self.codexSessionsDirectory = codexSessionsDirectory
        self.timeZone = timeZone
        self.tmuxStatusProvider = tmuxStatusProvider
            ?? Self.tmuxSessionIsRunning(named:)
    }

    public func snapshots(now: Date = Date()) -> [TaskStatusSnapshot] {
        let sessionEntries = Self.sessionEntries(
            from: Self.readTail(
                tasksDirectory.appendingPathComponent("sessions.log")
            ) ?? "",
            timeZone: timeZone
        )
        let currentSessionUUID = Self.normalizedUUID(
            readText(
                tasksDirectory.appendingPathComponent("current-session")
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        var archives = archiveRecords()
        guard !archives.isEmpty || !sessionEntries.isEmpty else {
            return []
        }

        archives.sort { $0.startedAt > $1.startedAt }
        if archives.count > Self.archiveLimit {
            archives.removeSubrange(Self.archiveLimit...)
        }

        let unfinishedEventID = archives.first {
            $0.eventsURL != nil && $0.exitCode == nil
        }?.id
        let tmuxSessionName = Self.tmuxSessionName(
            forWorkingDirectoryPath: workingDirectory.path
        )
        let needsTmuxCheck = archives.contains {
            $0.exitCode == nil && $0.lastLogActivityAt != nil
        }
            || sessionEntries.contains { $0.mode == .status }
        let tmuxIsRunning = needsTmuxCheck
            && tmuxStatusProvider(tmuxSessionName)
        let rolloutFiles = rolloutCandidates(
            for: archives.compactMap(\.eventsModificationDate)
        )

        var unusedEntryIndices = Set(sessionEntries.indices)
        var results: [TaskStatusSnapshot] = []
        for archive in archives {
            let entryIndex = matchingSessionEntryIndex(
                for: archive.startedAt,
                entries: sessionEntries,
                unusedIndices: unusedEntryIndices
            )
            let entry = entryIndex.map { sessionEntries[$0] }
            if let entryIndex {
                unusedEntryIndices.remove(entryIndex)
            }

            var sessionUUID = entry?.sessionUUID
            if sessionUUID == nil, let modificationDate = archive.eventsModificationDate {
                sessionUUID = closestRolloutUUID(
                    to: modificationDate,
                    archiveStartedAt: archive.startedAt,
                    candidates: rolloutFiles
                )
            }
            if
                sessionUUID == nil,
                archive.id == archives.first?.id
            {
                sessionUUID = currentSessionUUID
            }

            let exitCode = archive.exitCode
            let status: TaskExecutionStatus
            if let exitCode {
                status = exitCode == 0 ? .done : .failed
            } else if
                (!tmuxIsRunning || archive.eventsURL == nil),
                let lastLogActivityAt = archive.lastLogActivityAt,
                now.timeIntervalSince(lastLogActivityAt)
                    > Self.interruptionThreshold
            {
                status = .interrupted
            } else if archive.eventsURL != nil {
                status = archive.id == unfinishedEventID && tmuxIsRunning
                    ? .running
                    : .failed
            } else {
                status = .running
            }

            let isBackground = entry?.mode == .status
                || (entry == nil && archive.eventsURL != nil)
            results.append(
                TaskStatusSnapshot(
                    id: archive.id,
                    startedAt: archive.startedAt,
                    sessionUUID: sessionUUID,
                    mode: entry?.mode,
                    taskName: archive.briefURL
                        .flatMap(readText)
                        .flatMap(Self.taskName(forBriefPath:))
                        ?? entry.flatMap(Self.taskName),
                    isBackgroundTask: isBackground,
                    status: status,
                    exitCode: exitCode,
                    lastMessage: archive.lastMessageURL.flatMap(readText),
                    endedAt: status == .interrupted
                        ? archive.lastLogActivityAt
                        : (status.isTerminal ? archive.completionDate : nil)
                )
            )
        }

        for index in unusedEntryIndices {
            let entry = sessionEntries[index]
            guard entry.mode != .status else {
                continue
            }
            let isLatestEntry = entry == sessionEntries.max {
                $0.startedAt < $1.startedAt
            }
            let status: TaskExecutionStatus = isLatestEntry
                && entry.mode == .status
                && tmuxIsRunning ? .running : .failed
            results.append(
                TaskStatusSnapshot(
                    id: "session-\(Int(entry.startedAt.timeIntervalSince1970))-\(index)",
                    startedAt: entry.startedAt,
                    sessionUUID: entry.sessionUUID,
                    mode: entry.mode,
                    taskName: Self.taskName(for: entry),
                    isBackgroundTask: entry.mode == .status,
                    status: status,
                    exitCode: nil,
                    lastMessage: nil
                )
            )
        }

        return results.sorted {
            if $0.status == .running, $1.status != .running {
                return true
            }
            if $0.status != .running, $1.status == .running {
                return false
            }
            if $0.startedAt != $1.startedAt {
                return $0.startedAt > $1.startedAt
            }
            return $0.id < $1.id
        }
    }

    public static func sessionEntries(
        from contents: String,
        timeZone: TimeZone = .current
    ) -> [TaskSessionEntry] {
        let formatter = sessionDateFormatter(timeZone: timeZone)
        return contents
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let fields = line.split(
                    separator: " ",
                    maxSplits: 4,
                    omittingEmptySubsequences: true
                )
                guard
                    fields.count == 5,
                    let startedAt = formatter.date(
                        from: "\(fields[0]) \(fields[1])"
                    ),
                    let sessionUUID = normalizedUUID(String(fields[2])),
                    let mode = TaskDispatchMode(rawValue: String(fields[3]))
                else {
                    return nil
                }
                return TaskSessionEntry(
                    startedAt: startedAt,
                    sessionUUID: sessionUUID,
                    mode: mode,
                    briefPath: String(fields[4])
                )
            }
    }

    public static func exitCode(fromEventsContents contents: String) -> Int? {
        contents
            .split(whereSeparator: \.isNewline)
            .reversed()
            .lazy
            .compactMap { line -> Int? in
                let value = line.trimmingCharacters(in: .whitespaces)
                guard value.hasPrefix("EXIT_CODE=") else {
                    return nil
                }
                return Int(value.dropFirst("EXIT_CODE=".count))
            }
            .first
    }

    public static func exitCode(fromRunLogContents contents: String) -> Int? {
        let pattern = #"(?i)exit\s+code:\s*(-?\d+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(contents.startIndex..., in: contents)
        return expression
            .matches(in: contents, range: range)
            .reversed()
            .compactMap { match -> Int? in
                guard
                    match.numberOfRanges == 2,
                    let valueRange = Range(match.range(at: 1), in: contents)
                else {
                    return nil
                }
                return Int(contents[valueRange])
            }
            .first
    }

    public static func sessionUUID(fromRolloutFilename filename: String) -> String? {
        let name = URL(fileURLWithPath: filename)
            .deletingPathExtension()
            .lastPathComponent
        guard name.hasPrefix("rollout-"), name.count >= 36 else {
            return nil
        }
        return normalizedUUID(String(name.suffix(36)))
    }

    public static func tmuxSessionName(
        forWorkingDirectoryPath path: String
    ) -> String {
        let normalizedPath = URL(fileURLWithPath: path)
            .standardizedFileURL
            .path
        let digest = Insecure.SHA1.hash(
            data: Data((normalizedPath + "\n").utf8)
        )
        let prefix = digest.prefix(4).map {
            String(format: "%02x", $0)
        }.joined()
        return "codex-task-\(prefix)"
    }

    private struct ArchiveRecord {
        let id: String
        let startedAt: Date
        var eventsURL: URL?
        var eventsModificationDate: Date?
        var runLogURL: URL?
        var runLogModificationDate: Date?
        var lastMessageURL: URL?
        var briefURL: URL?

        var exitCode: Int? {
            if
                let eventsURL,
                let contents = TaskStatusParser.readTail(eventsURL),
                let exitCode = TaskStatusParser.exitCode(
                    fromEventsContents: contents
                )
            {
                return exitCode
            }
            if
                let runLogURL,
                let contents = TaskStatusParser.readTail(runLogURL)
            {
                return TaskStatusParser.exitCode(
                    fromRunLogContents: contents
                )
            }
            return nil
        }

        var completionDate: Date? {
            if
                let eventsURL,
                let contents = TaskStatusParser.readTail(eventsURL),
                TaskStatusParser.exitCode(fromEventsContents: contents) != nil
            {
                return eventsModificationDate
            }
            if
                let runLogURL,
                let contents = TaskStatusParser.readTail(runLogURL),
                TaskStatusParser.exitCode(fromRunLogContents: contents) != nil
            {
                return runLogModificationDate
            }
            return nil
        }

        var lastLogActivityAt: Date? {
            [eventsModificationDate, runLogModificationDate]
                .compactMap { $0 }
                .max()
        }
    }

    private struct RolloutCandidate {
        let url: URL
        let modificationDate: Date
        let filenameDate: Date?
        let sessionUUID: String
    }

    private func archiveRecords() -> [ArchiveRecord] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey
        ]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: tasksDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let formatter = Self.archiveDateFormatter(timeZone: timeZone)
        var records: [String: ArchiveRecord] = [:]
        for url in urls {
            let filename = url.lastPathComponent
            guard
                filename.count > 15,
                filename[filename.index(filename.startIndex, offsetBy: 8)] == "-",
                let startedAt = formatter.date(from: String(filename.prefix(15))),
                let values = try? url.resourceValues(forKeys: keys),
                values.isRegularFile == true
            else {
                continue
            }
            let id = String(filename.prefix(15))
            var record = records[id] ?? ArchiveRecord(
                id: id,
                startedAt: startedAt,
                eventsURL: nil,
                eventsModificationDate: nil,
                runLogURL: nil,
                runLogModificationDate: nil,
                lastMessageURL: nil,
                briefURL: nil
            )
            if filename.hasSuffix("-events.jsonl") {
                record.eventsURL = url
                record.eventsModificationDate = values.contentModificationDate
            } else if filename.hasSuffix("-run.log") {
                record.runLogURL = url
                record.runLogModificationDate = values.contentModificationDate
            } else if filename.hasSuffix("-last-message.md") {
                record.lastMessageURL = url
            } else if filename.hasSuffix("-events.brief") {
                record.briefURL = url
            } else {
                continue
            }
            records[id] = record
        }
        return Array(records.values)
    }

    private func matchingSessionEntryIndex(
        for startedAt: Date,
        entries: [TaskSessionEntry],
        unusedIndices: Set<Int>
    ) -> Int? {
        unusedIndices.min { lhs, rhs in
            let leftDistance = abs(
                entries[lhs].startedAt.timeIntervalSince(startedAt)
            )
            let rightDistance = abs(
                entries[rhs].startedAt.timeIntervalSince(startedAt)
            )
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }
            return lhs < rhs
        }.flatMap { index in
            abs(entries[index].startedAt.timeIntervalSince(startedAt))
                <= Self.rolloutMatchTolerance ? index : nil
        }
    }

    private func rolloutCandidates(
        for eventModificationDates: [Date]
    ) -> [RolloutCandidate] {
        guard !eventModificationDates.isEmpty else {
            return []
        }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: codexSessionsDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [RolloutCandidate] = []
        for case let url as URL in enumerator {
            guard
                url.pathExtension == "jsonl",
                url.lastPathComponent.hasPrefix("rollout-"),
                let sessionUUID = Self.sessionUUID(
                    fromRolloutFilename: url.lastPathComponent
                ),
                let values = try? url.resourceValues(forKeys: keys),
                values.isRegularFile == true,
                let modificationDate = values.contentModificationDate,
                eventModificationDates.contains(where: {
                    abs($0.timeIntervalSince(modificationDate))
                        <= Self.rolloutMatchTolerance
                })
            else {
                continue
            }
            candidates.append(
                RolloutCandidate(
                    url: url,
                    modificationDate: modificationDate,
                    filenameDate: Self.rolloutFilenameDate(
                        url.lastPathComponent,
                        timeZone: timeZone
                    ),
                    sessionUUID: sessionUUID
                )
            )
        }
        return candidates
    }

    private func closestRolloutUUID(
        to modificationDate: Date,
        archiveStartedAt: Date,
        candidates: [RolloutCandidate]
    ) -> String? {
        candidates.min {
            let leftModificationDistance = abs(
                $0.modificationDate.timeIntervalSince(modificationDate)
            )
            let rightModificationDistance = abs(
                $1.modificationDate.timeIntervalSince(modificationDate)
            )
            if leftModificationDistance != rightModificationDistance {
                return leftModificationDistance < rightModificationDistance
            }
            let leftFilenameDistance = $0.filenameDate.map {
                abs($0.timeIntervalSince(archiveStartedAt))
            } ?? .greatestFiniteMagnitude
            let rightFilenameDistance = $1.filenameDate.map {
                abs($0.timeIntervalSince(archiveStartedAt))
            } ?? .greatestFiniteMagnitude
            if leftFilenameDistance != rightFilenameDistance {
                return leftFilenameDistance < rightFilenameDistance
            }
            return $0.url.path < $1.url.path
        }.flatMap { candidate in
            abs(candidate.modificationDate.timeIntervalSince(modificationDate))
                <= Self.rolloutMatchTolerance ? candidate.sessionUUID : nil
        }
    }

    private static func taskName(for entry: TaskSessionEntry) -> String? {
        guard entry.mode != .status, entry.briefPath != "status" else {
            return nil
        }
        return taskName(forBriefPath: entry.briefPath)
    }

    private static func taskName(forBriefPath briefPath: String) -> String? {
        let filename = URL(
            fileURLWithPath: briefPath.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = filename.replacingOccurrences(
            of: #"^(?:\d{4}-\d{2}-\d{2}|\d{8})-"#,
            with: "",
            options: .regularExpression
        )
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func normalizedUUID(_ value: String?) -> String? {
        guard let value, let uuid = UUID(uuidString: value) else {
            return nil
        }
        return uuid.uuidString.lowercased()
    }

    private static func sessionDateFormatter(
        timeZone: TimeZone
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    private static func archiveDateFormatter(
        timeZone: TimeZone
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
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
        let value = String(name[start..<end])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.date(from: value)
    }

    private static func readTail(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        do {
            let size = try handle.seekToEnd()
            let byteCount = min(UInt64(tailByteLimit), size)
            try handle.seek(toOffset: size - byteCount)
            guard let data = try handle.read(upToCount: Int(byteCount)) else {
                return nil
            }
            return String(decoding: data, as: UTF8.self)
        } catch {
            return nil
        }
    }

    private func readText(_ url: URL) -> String? {
        Self.readText(url)
    }

    private static func readText(_ url: URL) -> String? {
        guard
            let handle = try? FileHandle(forReadingFrom: url),
            let data = try? handle.read(upToCount: tailByteLimit)
        else {
            return nil
        }
        try? handle.close()
        return String(decoding: data, as: UTF8.self)
    }

    private static func tmuxSessionIsRunning(named sessionName: String) -> Bool {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux"
        ]
        guard
            let executablePath = candidates.first(where: {
                FileManager.default.isExecutableFile(atPath: $0)
            })
        else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["has-session", "-t", sessionName]
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
