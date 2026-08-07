import CodexQuotaCore
import Foundation

@MainActor
final class TaskStatusController {
    struct Result {
        let tasks: [TaskStatusSnapshot]
        let completedTasks: [TaskStatusSnapshot]
    }

    private let parser: TaskStatusParser
    private let store: TaskStatusStore
    private let queue = DispatchQueue(
        label: "CodexQuota.taskStatus",
        qos: .utility
    )
    private var isChecking = false
    private var invalidated = false

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        defaults: UserDefaults = .standard
    ) {
        let tasksDirectory: URL
        if
            let override = environment["CODEX_QUOTA_TASKS_DIR"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty
        {
            tasksDirectory = URL(fileURLWithPath: override, isDirectory: true)
                .standardizedFileURL
        } else {
            tasksDirectory = URL(
                fileURLWithPath:
                    "/Users/openclaw/Projects/codex助手/.codex-tasks",
                isDirectory: true
            )
        }
        parser = TaskStatusParser(
            tasksDirectory: tasksDirectory,
            workingDirectory: tasksDirectory.deletingLastPathComponent(),
            codexSessionsDirectory: homeDirectory.appendingPathComponent(
                ".codex/sessions",
                isDirectory: true
            )
        )
        store = TaskStatusStore(defaults: defaults)
    }

    func check(completion: @escaping @MainActor (Result) -> Void) {
        guard !invalidated, !isChecking else {
            return
        }
        isChecking = true
        let parser = parser
        queue.async { [weak self] in
            let tasks = parser.snapshots()
            DispatchQueue.main.async { [weak self] in
                guard let self, !invalidated else {
                    return
                }
                isChecking = false
                let detection = TaskCompletionDetector.evaluate(
                    tasks,
                    state: store.notificationState
                )
                store.notificationState = detection.state
                completion(
                    Result(
                        tasks: Array(tasks.prefix(5)),
                        completedTasks: detection.completedTasks
                    )
                )
            }
        }
    }

    func invalidate() {
        invalidated = true
    }
}
