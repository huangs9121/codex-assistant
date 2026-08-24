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
        fileManager: FileManager = .default
    ) -> Set<String> {
        let completedIDs = snapshots
            .filter { $0.status == .done }
            .map(\.id)
            .filter { $0.count == 15 }
        guard !completedIDs.isEmpty else {
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
        for id in completedIDs {
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
