import Foundation

/// The root helper accepts only this fixed, numeric lease format. Keeping it
/// line-oriented avoids passing commands, paths, or user supplied text across
/// the privilege boundary.
public struct TaskSleepLease: Equatable, Sendable {
    public static let version = 1
    public static let maximumLifetime: TimeInterval = 60

    public let uid: UInt32
    public let ownerPID: Int32
    public let scannedAt: Int64
    public let expiresAt: Int64
    public let hasRunningTasks: Bool
    public let restoreSleepDisabled: Bool

    public init(
        uid: UInt32,
        ownerPID: Int32,
        scannedAt: Int64,
        expiresAt: Int64,
        hasRunningTasks: Bool,
        restoreSleepDisabled: Bool
    ) {
        self.uid = uid
        self.ownerPID = ownerPID
        self.scannedAt = scannedAt
        self.expiresAt = expiresAt
        self.hasRunningTasks = hasRunningTasks
        self.restoreSleepDisabled = restoreSleepDisabled
    }

    public func isValid(at now: Int64) -> Bool {
        uid > 0
            && ownerPID > 1
            && !restoreSleepDisabled
            && scannedAt <= now
            && expiresAt >= now
            && expiresAt - scannedAt <= Int64(Self.maximumLifetime)
    }

    public func encoded() -> Data {
        Data("\(Self.version)\n\(uid)\n\(ownerPID)\n\(scannedAt)\n\(expiresAt)\n\(hasRunningTasks ? 1 : 0)\n\(restoreSleepDisabled ? 1 : 0)\n".utf8)
    }

    public static func decode(_ data: Data) -> TaskSleepLease? {
        guard data.count <= 160, let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard rows.count == 8, rows.last == "", rows.dropLast().allSatisfy({
            !$0.isEmpty && $0.allSatisfy(\.isNumber)
        }) else {
            return nil
        }
        guard
            rows[0] == "1",
            let uid = UInt32(rows[1]),
            let pid = Int32(rows[2]),
            let scannedAt = Int64(rows[3]),
            let expiresAt = Int64(rows[4]),
            let active = Int(rows[5]),
            let restore = Int(rows[6]),
            active == 0 || active == 1,
            restore == 0
        else {
            return nil
        }
        return TaskSleepLease(
            uid: uid,
            ownerPID: pid,
            scannedAt: scannedAt,
            expiresAt: expiresAt,
            hasRunningTasks: active == 1,
            restoreSleepDisabled: restore == 1
        )
    }
}

public enum TaskSleepLeaseDecision: Equatable, Sendable {
    case noChange
    case setSleepDisabled(Bool)
}

/// Pure policy used by the privileged helper after it has already validated
/// file ownership, PID ownership, and lease freshness.
public enum TaskSleepLeasePolicy {
    public static func validatedLeases(
        _ leases: [TaskSleepLease],
        now: Int64,
        ownerIsAlive: (TaskSleepLease) -> Bool
    ) -> [TaskSleepLease] {
        leases.filter { $0.isValid(at: now) && ownerIsAlive($0) }
    }

    public static func decision(
        validLeases: [TaskSleepLease],
        hasJournal: Bool
    ) -> TaskSleepLeaseDecision {
        guard !validLeases.isEmpty else {
            return hasJournal ? .setSleepDisabled(false) : .noChange
        }
        return .setSleepDisabled(validLeases.contains(where: \.hasRunningTasks))
    }
}
