import Foundation

public enum TaskStatusSnapshotMerger {
    public static let archiveLimit = 50

    public static func merge(
        _ snapshotGroups: [[TaskStatusSnapshot]],
        limit: Int = archiveLimit
    ) -> [TaskStatusSnapshot] {
        var snapshotsByID: [String: TaskStatusSnapshot] = [:]
        for snapshot in snapshotGroups.joined() {
            guard let existing = snapshotsByID[snapshot.id] else {
                snapshotsByID[snapshot.id] = snapshot
                continue
            }
            if snapshot.startedAt > existing.startedAt {
                snapshotsByID[snapshot.id] = snapshot
            }
        }

        return snapshotsByID.values
            .sorted {
                if $0.startedAt != $1.startedAt {
                    return $0.startedAt > $1.startedAt
                }
                return $0.id < $1.id
            }
            .prefix(max(0, limit))
            .map { $0 }
    }
}
