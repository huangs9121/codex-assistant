import CodexQuotaCore
import AppKit
import Foundation

@MainActor
final class TaskStatusController {
    struct Result {
        let tasks: [TaskStatusSnapshot]
        let desktopThreads: [CodexDesktopThreadSnapshot]
        let desktopThreadGroups: [CodexDesktopThreadGroup]
        let cliProcesses: [String: CodexCLIProcess]
        let hasRunningTasks: Bool
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
    private var pendingClear: (@MainActor (Result) -> Void)?
    private var isChecking = false {
        didSet {
            guard !isChecking, let pending = pendingClear else { return }
            pendingClear = nil
            DispatchQueue.main.async { [weak self] in
                self?.clearEndedDesktopThreads(completion: pending)
            }
        }
    }
    private var invalidated = false
    private var parentSnapshotsByID: [String: CodexDesktopThreadSnapshot] = [:]
    private var missingParentSnapshotIDs = Set<String>()

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

    /// 应用「清理已完成」隐藏集合；被隐藏的线程若重新活跃则从集合移除（恢复显示）。
    private func restoreActiveThreads(
        _ snapshots: [CodexDesktopThreadSnapshot]
    ) {
        var hidden = store.hiddenDesktopThreadIDs
        let runningHidden = snapshots
            .filter { $0.isRunning && hidden.contains($0.id) }
            .map(\.id)
        if !runningHidden.isEmpty {
            hidden.subtract(runningHidden)
            store.hiddenDesktopThreadIDs = hidden
        }
    }

    private func desktopThreadGroups(
        _ snapshots: [CodexDesktopThreadSnapshot]
    ) -> [CodexDesktopThreadGroup] {
        restoreActiveThreads(snapshots)
        let resolved = resolvingParentSnapshots(for: snapshots)
        return CodexDesktopThreadTree.groups(
            candidates: resolved,
            hiddenIDs: store.hiddenDesktopThreadIDs
        )
    }

    private func resolvingParentSnapshots(
        for snapshots: [CodexDesktopThreadSnapshot]
    ) -> [CodexDesktopThreadSnapshot] {
        var result = CodexDesktopSessionScanner.deduplicatedSnapshots(snapshots)
        var known = Set(result.map(\.id))
        var pending = result.compactMap(\.parentThreadID)
        while let parentID = pending.popLast() {
            guard !known.contains(parentID) else { continue }
            known.insert(parentID)
            guard !missingParentSnapshotIDs.contains(parentID) else { continue }
            guard let parent = parentSnapshotsByID[parentID] ?? desktopSessionScanner.snapshot(forID: parentID) else {
                missingParentSnapshotIDs.insert(parentID)
                continue
            }
            parentSnapshotsByID[parentID] = parent
            result.append(parent)
            if let grandparentID = parent.parentThreadID { pending.append(grandparentID) }
        }
        return result
    }

    func clearEndedDesktopThreads(
        completion: @escaping @MainActor (Result) -> Void
    ) {
        guard !invalidated else { return }
        guard !isChecking else {
            pendingClear = completion
            return
        }
        isChecking = true
        let desktopSessionScanner = desktopSessionScanner
        queue.async { [weak self] in
            let ownership = Self.sessionOwnership()
            let snapshots = desktopSessionScanner.candidateSnapshots(since: .distantPast).map {
                $0.reconcilingOwner(isOwned: ownership.owned.contains($0.id))
            }
            let cliProcesses = ownership.cli
            DispatchQueue.main.async { [weak self] in
                guard let self, !invalidated else {
                    return
                }
                restoreActiveThreads(snapshots)
                let hiddenIDs = CodexDesktopThreadTree.clearableThreadIDs(
                    in: resolvingParentSnapshots(for: snapshots),
                    hiddenIDs: store.hiddenDesktopThreadIDs
                )
                store.hiddenDesktopThreadIDs = store.hiddenDesktopThreadIDs.union(hiddenIDs)
                isChecking = false
                let tasks = TaskStatusSnapshotMerger.merge(
                    parsers.map { $0.snapshots() }
                )
                let detection = TaskCompletionDetector.evaluate(
                    tasks,
                    state: store.notificationState
                )
                store.notificationState = detection.state
                completion(
                    Result(
                        tasks: Array(tasks.prefix(5)),
                        desktopThreads: snapshots,
                        desktopThreadGroups: desktopThreadGroups(snapshots),
                        cliProcesses: cliProcesses,
                        hasRunningTasks: TaskSleepActivity.hasRunningTasks(
                            cliTasks: tasks,
                            desktopThreads: snapshots.filter { cliProcesses[$0.id] == nil },
                            codexDesktopLaunchDate:
                                Self.codexDesktopLaunchDate()
                        ),
                        hasCompletedTasks: tasks.contains {
                            $0.status.isClearable
                        },
                        completedTasks: detection.completedTasks
                    )
                )
            }
        }
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
            let ownership = Self.sessionOwnership()
            let desktopSnapshots = desktopSessionScanner.candidateSnapshots(since: .distantPast).map {
                $0.reconcilingOwner(isOwned: ownership.owned.contains($0.id))
            }
            let cliProcesses = ownership.cli
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
                        desktopThreads: desktopSnapshots,
                        desktopThreadGroups: desktopThreadGroups(desktopSnapshots),
                        cliProcesses: cliProcesses,
                        hasRunningTasks: TaskSleepActivity.hasRunningTasks(
                            cliTasks: tasks,
                            desktopThreads: desktopSnapshots.filter { cliProcesses[$0.id] == nil },
                            codexDesktopLaunchDate:
                                Self.codexDesktopLaunchDate()
                        ),
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
            let ownership = Self.sessionOwnership()
            let desktopSnapshots = desktopSessionScanner.candidateSnapshots(since: .distantPast).map {
                $0.reconcilingOwner(isOwned: ownership.owned.contains($0.id))
            }
            let cliProcesses = ownership.cli
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
                        desktopThreads: desktopSnapshots,
                        desktopThreadGroups: desktopThreadGroups(desktopSnapshots),
                        cliProcesses: cliProcesses,
                        hasRunningTasks: TaskSleepActivity.hasRunningTasks(
                            cliTasks: tasks,
                            desktopThreads: desktopSnapshots.filter { cliProcesses[$0.id] == nil },
                            codexDesktopLaunchDate:
                                Self.codexDesktopLaunchDate()
                        ),
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
            let ownership = Self.sessionOwnership()
            let desktopSnapshots = desktopSessionScanner.candidateSnapshots(since: .distantPast).map {
                $0.reconcilingOwner(isOwned: ownership.owned.contains($0.id))
            }
            let cliProcesses = ownership.cli
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
                        desktopThreads: desktopSnapshots,
                        desktopThreadGroups: desktopThreadGroups(desktopSnapshots),
                        cliProcesses: cliProcesses,
                        hasRunningTasks: TaskSleepActivity.hasRunningTasks(
                            cliTasks: tasks,
                            desktopThreads: desktopSnapshots.filter { cliProcesses[$0.id] == nil },
                            codexDesktopLaunchDate:
                                Self.codexDesktopLaunchDate()
                        ),
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
        pendingClear = nil
    }

    nonisolated static func cliProcesses() -> [String: CodexCLIProcess] {
        sessionOwnership().cli
    }

    nonisolated private static func sessionOwnership() -> (cli: [String: CodexCLIProcess], owned: Set<String>) {
        let locks = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/thread-writer-locks", isDirectory: true)
        let lockURLs = ((try? FileManager.default.contentsOfDirectory(at: locks, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "lock" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
        guard !lockURLs.isEmpty,
              let lsof = processOutput("/usr/sbin/lsof", ["-Fpn"] + lockURLs.map(\.path), allowPartial: true)
        else { return ([:], []) }
        var pid = 0
        var owners: [String: Int] = [:]
        for line in lsof.split(separator: "\n") {
            if line.first == "p" { pid = Int(line.dropFirst()) ?? 0 }
            if line.first == "n", pid > 0 {
                let path = String(line.dropFirst())
                let id = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                if UUID(uuidString: id) != nil { owners[id] = pid }
            }
        }
        let pids = Array(Set(owners.values))
        guard !pids.isEmpty,
              let ps = processOutput("/bin/ps", ["-o", "pid=,tty=,comm=,args=", "-p", pids.map(String.init).joined(separator: ",")])
        else { return ([:], []) }
        let cli = CodexCLIProcess.sessions(owners: owners, processList: ps)
        return (cli, Set(owners.keys))
    }

    nonisolated private static func processOutput(_ executable: String, _ arguments: [String], allowPartial: Bool = false) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 || allowPartial else { return nil }
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        } catch { return nil }
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

    private static func codexDesktopLaunchDate() -> Date? {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == "com.openai.codex" }
            .compactMap(\.launchDate)
            .max()
    }

    private static func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}
