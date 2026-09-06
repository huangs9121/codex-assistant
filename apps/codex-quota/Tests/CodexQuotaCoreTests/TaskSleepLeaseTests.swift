import CodexQuotaCore
import Foundation

enum TaskSleepLeaseTests {
    static let all: [TaskStatusParserTestCase] = [
        TaskStatusParserTestCase(name: "task sleep lease round trips strict numeric fields", run: roundTrip),
        TaskStatusParserTestCase(name: "task sleep lease rejects commands malformed fields and stale lifetimes", run: rejectsUnsafeInput),
        TaskStatusParserTestCase(name: "task sleep policy leaves the default system setting alone", run: defaultDoesNotWrite),
        TaskStatusParserTestCase(name: "task sleep policy takes over idle monitoring as ordinary sleep", run: idleLeaseRestoresOrdinarySleep),
        TaskStatusParserTestCase(name: "task sleep policy prevents sleep for any active lease", run: activeLeaseWins),
        TaskStatusParserTestCase(name: "task sleep policy restores after expiration or task end", run: journalRecovery)
    ]

    private static func roundTrip() -> Bool {
        let lease = TaskSleepLease(uid: 502, ownerPID: 1234, scannedAt: 1_000, expiresAt: 1_060, hasRunningTasks: true, restoreSleepDisabled: false)
        return TaskSleepLease.decode(lease.encoded()) == lease && lease.isValid(at: 1_030)
    }

    private static func rejectsUnsafeInput() -> Bool {
        let command = Data("1\n502\n1234\n1000\n1060\n1\n0\n/bin/sh\n".utf8)
        let oversizedLifetime = TaskSleepLease(uid: 502, ownerPID: 1234, scannedAt: 1_000, expiresAt: 1_061, hasRunningTasks: false, restoreSleepDisabled: false)
        let invalidOwner = TaskSleepLease(uid: 0, ownerPID: 1, scannedAt: 1_000, expiresAt: 1_010, hasRunningTasks: false, restoreSleepDisabled: false)
        return TaskSleepLease.decode(command) == nil
            && TaskSleepLease.decode(Data("1\n502\n1234\n1000\n1060\n1\n1\n".utf8)) == nil
            && !oversizedLifetime.isValid(at: 1_030)
            && !invalidOwner.isValid(at: 1_005)
    }

    private static func defaultDoesNotWrite() -> Bool {
        TaskSleepLeasePolicy.decision(validLeases: [], hasJournal: false) == .noChange
    }

    private static func idleLeaseRestoresOrdinarySleep() -> Bool {
        TaskSleepLeasePolicy.decision(validLeases: [idleLease], hasJournal: false) == .setSleepDisabled(false)
    }

    private static func activeLeaseWins() -> Bool {
        let active = TaskSleepLease(uid: 503, ownerPID: 2234, scannedAt: 1_000, expiresAt: 1_060, hasRunningTasks: true, restoreSleepDisabled: false)
        return TaskSleepLeasePolicy.decision(validLeases: [active], hasJournal: true) == .setSleepDisabled(true)
            && TaskSleepLeasePolicy.decision(validLeases: [idleLease, active], hasJournal: true) == .setSleepDisabled(true)
    }

    private static func journalRecovery() -> Bool {
        let expired = TaskSleepLease(uid: 502, ownerPID: 1234, scannedAt: 1_000, expiresAt: 1_060, hasRunningTasks: true, restoreSleepDisabled: false)
        let deadOwner = TaskSleepLease(uid: 502, ownerPID: 9999, scannedAt: 1_000, expiresAt: 1_060, hasRunningTasks: true, restoreSleepDisabled: false)
        let filteredExpired = TaskSleepLeasePolicy.validatedLeases([expired], now: 1_061) { _ in true }
        let filteredDeadOwner = TaskSleepLeasePolicy.validatedLeases([deadOwner], now: 1_030) { $0.ownerPID != 9999 }
        return filteredExpired.isEmpty
            && filteredDeadOwner.isEmpty
            && TaskSleepLeasePolicy.decision(validLeases: filteredExpired, hasJournal: true) == .setSleepDisabled(false)
            && TaskSleepLeasePolicy.decision(validLeases: filteredDeadOwner, hasJournal: true) == .setSleepDisabled(false)
            && TaskSleepLeasePolicy.decision(validLeases: [idleLease], hasJournal: true) == .setSleepDisabled(false)
    }

    private static let idleLease = TaskSleepLease(uid: 502, ownerPID: 1234, scannedAt: 1_000, expiresAt: 1_060, hasRunningTasks: false, restoreSleepDisabled: false)
}
