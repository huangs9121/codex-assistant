import CodexQuotaCore
import Foundation

@MainActor
final class TaskStatusController {
    struct Result {
        let tasks: [TaskStatusSnapshot]
        let hasCompletedTasks: Bool
        let completedTasks: [TaskStatusSnapshot]
    }

    private let parsers: [TaskStatusParser]
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
        let tasksDirectories: [URL]
        if
            let override = environment["CODEX_QUOTA_TASKS_DIR"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty
        {
            tasksDirectories = [
                URL(fileURLWithPath: override, isDirectory: true)
                    .standardizedFileURL
            ]
        } else {
            let workspaceDirectory = URL(
                fileURLWithPath:
                    "/Users/openclaw/Projects/codex助手",
                isDirectory: true
            )
            let appsDirectory = workspaceDirectory.appendingPathComponent(
                "apps",
                isDirectory: true
            )
            let appTasksDirectories = (try? FileManager.default
                .contentsOfDirectory(
                    at: appsDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ))?
                .filter {
                    (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?
                        .isDirectory == true
                }
                .map {
                    $0.appendingPathComponent(
                        ".codex-tasks",
                        isDirectory: true
                    )
                }
                .filter { Self.directoryExists(at: $0) }
                ?? []
            tasksDirectories = [
                workspaceDirectory.appendingPathComponent(
                    ".codex-tasks",
                    isDirectory: true
                )
            ].filter(Self.directoryExists(at:)) + appTasksDirectories
        }
        parsers = tasksDirectories.map { tasksDirectory in
            TaskStatusParser(
                tasksDirectory: tasksDirectory,
                workingDirectory: tasksDirectory.deletingLastPathComponent(),
                codexSessionsDirectory: homeDirectory.appendingPathComponent(
                    ".codex/sessions",
                    isDirectory: true
                )
            )
        }
        store = TaskStatusStore(defaults: defaults)
    }

    func check(completion: @escaping @MainActor (Result) -> Void) {
        guard !invalidated, !isChecking else {
            return
        }
        isChecking = true
        let parsers = parsers
        queue.async { [weak self] in
            let tasks = TaskStatusSnapshotMerger.merge(
                parsers.map { $0.snapshots() }
            )
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
                        hasCompletedTasks: tasks.contains { $0.status == .done },
                        completedTasks: detection.completedTasks
                    )
                )
            }
        }
    }

    func archiveCompletedTasks(
        completion: @escaping @MainActor (Result) -> Void
    ) {
        guard !invalidated, !isChecking else {
            return
        }
        isChecking = true
        let parsers = parsers
        queue.async { [weak self] in
            for parser in parsers {
                TaskArchive.archiveCompletedRecords(
                    in: parser.tasksDirectory,
                    snapshots: parser.snapshots()
                )
            }
            let tasks = TaskStatusSnapshotMerger.merge(
                parsers.map { $0.snapshots() }
            )
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
                        hasCompletedTasks: tasks.contains { $0.status == .done },
                        completedTasks: detection.completedTasks
                    )
                )
            }
        }
    }

    func invalidate() {
        invalidated = true
    }

    private static func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}
