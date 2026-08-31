import Foundation

public struct TaskNotificationState: Codable, Equatable, Sendable {
    public let lastScannedAt: Date
    public let unfinishedSessionUUIDs: Set<String>
    public let notifiedSessionUUIDs: Set<String>

    public init(
        lastScannedAt: Date,
        unfinishedSessionUUIDs: Set<String>,
        notifiedSessionUUIDs: Set<String>
    ) {
        self.lastScannedAt = lastScannedAt
        self.unfinishedSessionUUIDs = unfinishedSessionUUIDs
        self.notifiedSessionUUIDs = notifiedSessionUUIDs
    }
}

public struct TaskCompletionDetection: Equatable, Sendable {
    public let state: TaskNotificationState
    public let completedTasks: [TaskStatusSnapshot]

    public init(
        state: TaskNotificationState,
        completedTasks: [TaskStatusSnapshot]
    ) {
        self.state = state
        self.completedTasks = completedTasks
    }
}

public enum TaskCompletionDetector {
    public static func evaluate(
        _ tasks: [TaskStatusSnapshot],
        state previousState: TaskNotificationState?,
        now: Date = Date()
    ) -> TaskCompletionDetection {
        let unfinished = Set(
            tasks.compactMap {
                $0.status == .running ? $0.sessionUUID : nil
            }
        )
        let terminalBySession = tasks
            .filter {
                $0.status.shouldNotifyCompletion && $0.sessionUUID != nil
            }
            .reduce(into: [String: TaskStatusSnapshot]()) { result, task in
                guard let sessionUUID = task.sessionUUID else {
                    return
                }
                if
                    let existing = result[sessionUUID],
                    existing.startedAt >= task.startedAt
                {
                    return
                }
                result[sessionUUID] = task
            }

        guard let previousState else {
            return TaskCompletionDetection(
                state: TaskNotificationState(
                    lastScannedAt: now,
                    unfinishedSessionUUIDs: unfinished,
                    notifiedSessionUUIDs: Set(terminalBySession.keys)
                ),
                completedTasks: []
            )
        }

        let completedTasks = terminalBySession.values
            .filter { task in
                guard
                    let sessionUUID = task.sessionUUID,
                    !previousState.notifiedSessionUUIDs.contains(sessionUUID)
                else {
                    return false
                }
                return previousState.unfinishedSessionUUIDs.contains(sessionUUID)
                    || task.startedAt > previousState.lastScannedAt
            }
            .sorted { $0.startedAt < $1.startedAt }
        let notified = previousState.notifiedSessionUUIDs.union(
            completedTasks.compactMap(\.sessionUUID)
        )
        return TaskCompletionDetection(
            state: TaskNotificationState(
                lastScannedAt: now,
                unfinishedSessionUUIDs: unfinished,
                notifiedSessionUUIDs: notified
            ),
            completedTasks: completedTasks
        )
    }
}

public struct TaskStatusStore {
    public static let notificationStateKey = "taskStatusNotificationState"
    public static let hiddenDesktopThreadIDsKey = "desktopHiddenThreadIDs"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 被用户「清理已完成」隐藏的 Codex 客户端线程 ID。
    /// 只影响展示，不删除会话文件；线程重新活跃（运行中）时恢复显示。
    public var hiddenDesktopThreadIDs: Set<String> {
        get {
            Set(defaults.stringArray(forKey: Self.hiddenDesktopThreadIDsKey) ?? [])
        }
        nonmutating set {
            let sorted = newValue.sorted()
            if sorted.isEmpty {
                defaults.removeObject(forKey: Self.hiddenDesktopThreadIDsKey)
            } else {
                defaults.set(sorted, forKey: Self.hiddenDesktopThreadIDsKey)
            }
        }
    }

    public var notificationState: TaskNotificationState? {
        get {
            guard
                let data = defaults.data(forKey: Self.notificationStateKey),
                let state = try? JSONDecoder().decode(
                    TaskNotificationState.self,
                    from: data
                )
            else {
                return nil
            }
            return state
        }
        nonmutating set {
            guard
                let newValue,
                let data = try? JSONEncoder().encode(newValue)
            else {
                defaults.removeObject(forKey: Self.notificationStateKey)
                return
            }
            defaults.set(data, forKey: Self.notificationStateKey)
        }
    }
}
