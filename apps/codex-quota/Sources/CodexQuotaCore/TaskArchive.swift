import Foundation

public enum TaskArchive {
    private static let recordSuffixes = [
        "-events.jsonl",
        "-events.brief",
        "-last-message.md",
        "-run.log"
    ]

    @discardableResult
    public static func archiveCompletedRecords(
        in tasksDirectory: URL,
        snapshots: [TaskStatusSnapshot],
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) -> Set<String> {
        let completedIDs = Set(snapshots
            .filter { $0.status == .done }
            .map(\.id)
            .filter { $0.count == 15 })

        let archivedIDs = archiveRecords(
            withIDs: completedIDs,
            in: tasksDirectory,
            fileManager: fileManager
        )

        for snapshot in snapshots where
            snapshot.id.hasPrefix("session-") && snapshot.status.isTerminal
        {
            guard let sessionUUID = snapshot.sessionUUID else {
                continue
            }
            _ = removeSessionEntry(
                sessionUUID: sessionUUID,
                startedAt: snapshot.startedAt,
                in: tasksDirectory,
                timeZone: timeZone,
                fileManager: fileManager
            )
        }

        return archivedIDs
    }

    @discardableResult
    public static func archiveRecord(
        id: String,
        in tasksDirectory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        archiveRecords(
            withIDs: [id],
            in: tasksDirectory,
            fileManager: fileManager
        ).contains(id)
    }

    @discardableResult
    public static func removeSessionEntry(
        sessionUUID: String,
        startedAt: Date,
        in tasksDirectory: URL,
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) -> Bool {
        let sessionsURL = tasksDirectory.appendingPathComponent("sessions.log")
        guard
            let contents = try? Data(contentsOf: sessionsURL),
            !contents.isEmpty
        else {
            return false
        }

        let remainingLines = contents.split(
            separator: 0x0A,
            omittingEmptySubsequences: false
        )
        var removed = false
        var rewritten = Data()
        for (index, line) in remainingLines.enumerated() {
            let lineText = String(decoding: line, as: UTF8.self)
            let entry = TaskStatusParser.sessionEntries(
                from: lineText,
                timeZone: timeZone
            ).first
            let isMatch = entry?.startedAt == startedAt
                && entry?.sessionUUID.caseInsensitiveCompare(sessionUUID)
                    == .orderedSame
            if isMatch {
                removed = true
            } else {
                rewritten.append(contentsOf: line)
                if index < remainingLines.count - 1 {
                    rewritten.append(0x0A)
                }
            }
        }

        guard removed else {
            return false
        }
        do {
            try rewritten.write(to: sessionsURL)
            return true
        } catch {
            return false
        }
    }

    private static func archiveRecords(
        withIDs ids: Set<String>,
        in tasksDirectory: URL,
        fileManager: FileManager
    ) -> Set<String> {
        let recordIDs = ids.filter { $0.count == 15 }
        guard !recordIDs.isEmpty else {
            return []
        }

        let archivedDirectory = tasksDirectory.appendingPathComponent(
            "archived",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: archivedDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return []
        }

        var archivedIDs = Set<String>()
        for id in recordIDs {
            var movedRecord = false
            for suffix in recordSuffixes {
                let source = tasksDirectory.appendingPathComponent(id + suffix)
                guard fileManager.fileExists(atPath: source.path) else {
                    continue
                }
                let destination = archivedDirectory.appendingPathComponent(
                    source.lastPathComponent
                )
                guard !fileManager.fileExists(atPath: destination.path) else {
                    continue
                }
                do {
                    try fileManager.moveItem(at: source, to: destination)
                    movedRecord = true
                } catch {
                    continue
                }
            }
            if movedRecord {
                archivedIDs.insert(id)
            }
        }
        return archivedIDs
    }
}
