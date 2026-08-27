import CodexQuotaCore
import Foundation

@MainActor
final class TaskStatusController {
    struct Result {
        let tasks: [TaskStatusSnapshot]
        let desktopThreads: [CodexDesktopThreadSnapshot]
        let hasCompletedTasks: Bool
        let completedTasks: [TaskStatusSnapshot]
    }

    private let parsers: [TaskStatusParser]
    private let desktopSessionScanner: CodexDesktopSessionScanner
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
        desktopSessionScanner = CodexDesktopSessionScanner(
            sessionsDirectory: homeDirectory.appendingPathComponent(
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
        let parsers = parsers
        let desktopSessionScanner = desktopSessionScanner
        queue.async { [weak self] in
            let tasks = TaskStatusSnapshotMerger.merge(
                parsers.map { $0.snapshots() }
            )
            let desktopThreads = desktopSessionScanner.snapshots()
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
                        desktopThreads: desktopThreads,
                        hasCompletedTasks: tasks.contains {
                            $0.status.isClearable
                        },
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
        let desktopSessionScanner = desktopSessionScanner
        queue.async { [weak self] in
            for parser in parsers {
                TaskArchive.archiveCompletedRecords(
                    in: parser.tasksDirectory,
                    snapshots: parser.snapshots(),
                    timeZone: parser.timeZone
                )
            }
            let tasks = TaskStatusSnapshotMerger.merge(
                parsers.map { $0.snapshots() }
            )
            let desktopThreads = desktopSessionScanner.snapshots()
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
                        desktopThreads: desktopThreads,
                        hasCompletedTasks: tasks.contains {
                            $0.status.isClearable
                        },
                        completedTasks: detection.completedTasks
                    )
                )
            }
        }
    }

    func archiveTask(
        _ task: TaskStatusSnapshot,
        completion: @escaping @MainActor (Result) -> Void
    ) {
        guard !invalidated, !isChecking, task.status.isTerminal else {
            return
        }
        isChecking = true
        let parsers = parsers
        let desktopSessionScanner = desktopSessionScanner
        queue.async { [weak self] in
            for parser in parsers {
                guard
                    let currentTask = parser.snapshots().first(
                        where: { $0.id == task.id }
                    ),
                    currentTask.status.isTerminal
                else {
                    continue
                }
                let archived = TaskArchive.archiveRecord(
                    id: task.id,
                    in: parser.tasksDirectory
                )
                if
                    !archived,
                    task.id.hasPrefix("session-"),
                    let sessionUUID = currentTask.sessionUUID,
                    sessionUUID == task.sessionUUID,
                    currentTask.startedAt == task.startedAt
                {
                    _ = TaskArchive.removeSessionEntry(
                        sessionUUID: sessionUUID,
                        startedAt: currentTask.startedAt,
                        in: parser.tasksDirectory,
                        timeZone: parser.timeZone
                    )
                }
            }
            let tasks = TaskStatusSnapshotMerger.merge(
                parsers.map { $0.snapshots() }
            )
            let desktopThreads = desktopSessionScanner.snapshots()
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
                        desktopThreads: desktopThreads,
                        hasCompletedTasks: tasks.contains {
                            $0.status.isClearable
                        },
                        completedTasks: detection.completedTasks
                    )
                )
            }
        }
    }

    func invalidate() {
        invalidated = true
    }

    nonisolated static func codexExecutableURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        let homeDirectory: URL
        if let home = environment["HOME"], !home.isEmpty {
            homeDirectory = URL(fileURLWithPath: home, isDirectory: true)
        } else {
            homeDirectory = fileManager.homeDirectoryForCurrentUser
        }

        var candidates: [URL] = []
        if let override = environment["CODEX_PATH"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }
        candidates += [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
            homeDirectory.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]
        if let path = environment["PATH"] {
            candidates += path.split(
                separator: ":",
                omittingEmptySubsequences: false
            ).map { directory in
                URL(
                    fileURLWithPath: directory.isEmpty ? "." : String(directory),
                    isDirectory: true
                ).appendingPathComponent("codex")
            }
        }
        return candidates.first {
            fileManager.isExecutableFile(atPath: $0.path)
        }
    }

    private static func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}
