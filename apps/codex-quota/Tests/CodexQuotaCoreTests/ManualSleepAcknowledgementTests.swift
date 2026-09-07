import CodexQuotaCore

enum ManualSleepAcknowledgementTests {
    static let all: [TaskStatusParserTestCase] = [
        .init(name: "manual sleep acknowledgement rejects an older helper status", run: rejectsOlderStatus),
        .init(name: "manual sleep acknowledgement requires matching active state", run: requiresMatchingState),
        .init(name: "manual sleep acknowledgement accepts the matching helper status", run: acceptsMatchingStatus),
        .init(name: "manual sleep rejects a stale operation completion", run: rejectsStaleCompletion)
    ]

    private static func rejectsOlderStatus() -> Bool {
        ManualSleepAcknowledgement(
            scannedAt: 100,
            active: true,
            sleepDisabled: true,
            success: true
        ).confirms(scannedAtOrAfter: 101, active: true) == false
    }

    private static func requiresMatchingState() -> Bool {
        !ManualSleepAcknowledgement(
            scannedAt: 101,
            active: false,
            sleepDisabled: false,
            success: true
        ).confirms(scannedAtOrAfter: 101, active: true)
    }

    private static func acceptsMatchingStatus() -> Bool {
        ManualSleepAcknowledgement(
            scannedAt: 101,
            active: false,
            sleepDisabled: false,
            success: true
        ).confirms(scannedAtOrAfter: 101, active: false)
    }

    private static func rejectsStaleCompletion() -> Bool {
        !ManualSleepOperation.acceptsCompletion(requestGeneration: 4, currentGeneration: 5)
            && ManualSleepOperation.acceptsCompletion(requestGeneration: 5, currentGeneration: 5)
    }
}
