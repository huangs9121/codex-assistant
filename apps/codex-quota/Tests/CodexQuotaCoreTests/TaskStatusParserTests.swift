import CodexQuotaCore
import Foundation

struct TaskStatusParserTestCase: Sendable {
    let name: String
    let run: @Sendable () -> Bool
}

enum TaskStatusParserTests {
    static let all: [TaskStatusParserTestCase] = [
        TaskStatusParserTestCase(
            name: "task sessions log parses paths and status mode",
            run: testSessionsLogParsing
        ),
        TaskStatusParserTestCase(
            name: "task events log extracts EXIT_CODE",
            run: testEventsExitCode
        ),
        TaskStatusParserTestCase(
            name: "task events log without EXIT_CODE stays unfinished",
            run: testEventsWithoutExitCode
        ),
        TaskStatusParserTestCase(
            name: "task run log extracts the final exit code",
            run: testRunLogExitCode
        ),
        TaskStatusParserTestCase(
            name: "task rollout filename restores UUID",
            run: testRolloutFilenameUUID
        ),
        TaskStatusParserTestCase(
            name: "task tmux name hashes workdir with newline",
            run: testTmuxSessionName
        ),
        TaskStatusParserTestCase(
            name: "task archive snapshot joins session and last message",
            run: testArchiveSnapshot
        ),
        TaskStatusParserTestCase(
            name: "task sidecar name takes priority and cleans dashed date",
            run: testSidecarNameWithDashedDate
        ),
        TaskStatusParserTestCase(
            name: "task sidecar name cleans compact date and keeps Chinese",
            run: testSidecarNameWithCompactDateAndChinese
        ),
        TaskStatusParserTestCase(
            name: "task name falls back from sidecar to session then nil",
            run: testTaskNameFallbackChain
        ),
        TaskStatusParserTestCase(
            name: "task unmatched status session does not create snapshot",
            run: testUnmatchedStatusEntryIsHidden
        ),
        TaskStatusParserTestCase(
            name: "task unfinished events require the matching tmux session",
            run: testRunningTmuxSession
        ),
        TaskStatusParserTestCase(
            name: "task orphan events recover nearest rollout UUID",
            run: testRolloutRecovery
        ),
        TaskStatusParserTestCase(
            name: "task completion notifications baseline and deduplicate",
            run: testCompletionDetection
        ),
        TaskStatusParserTestCase(
            name: "task notification state persists",
            run: testNotificationStatePersistence
        ),
        TaskStatusParserTestCase(
            name: "task snapshots merge by newest start time and limit archives",
            run: testSnapshotMerge
        ),
        TaskStatusParserTestCase(
            name: "task snapshots merge archives from multiple task directories",
            run: testMultiDirectorySnapshots
        ),
        TaskStatusParserTestCase(
            name: "task archive moves only completed records and parser skips archived",
            run: testArchiveCompletedRecords
        ),
        TaskStatusParserTestCase(
            name: "task archive moves one selected record and keeps peer records",
            run: testArchiveSingleRecord
        )
    ]

    private static let shanghai = TimeZone(secondsFromGMT: 8 * 60 * 60)!
    private static let sessionUUID =
        "019fb5f6-40d1-7383-ac0d-48b797170e07"

    private static func testSessionsLogParsing() -> Bool {
        let contents = """
        2026-07-31 10:17:47 \(sessionUUID) sync /tmp/My Brief.md
        invalid line
        2026-07-31 10:18:00 019fb5f6-40d1-7383-ac0d-48b797170e08 status status
        """
        let entries = TaskStatusParser.sessionEntries(
            from: contents,
            timeZone: shanghai
        )
        return entries.count == 2
            && entries[0].sessionUUID == sessionUUID
            && entries[0].mode == .sync
            && entries[0].briefPath == "/tmp/My Brief.md"
            && entries[1].mode == .status
            && entries[1].briefPath == "status"
    }

    private static func testEventsExitCode() -> Bool {
        let contents = """
        {"type":"turn.started"}
        EXIT_CODE=7
        """
        return TaskStatusParser.exitCode(
            fromEventsContents: contents
        ) == 7
    }

    private static func testEventsWithoutExitCode() -> Bool {
        let contents = """
        {"type":"turn.started"}
        {"type":"item.completed","exit_code":0}
        """
        return TaskStatusParser.exitCode(
            fromEventsContents: contents
        ) == nil
    }

    private static func testRunLogExitCode() -> Bool {
        let contents = """
        exit code: 9
        more output
        exit code: -2
        """
        return TaskStatusParser.exitCode(
            fromRunLogContents: contents
        ) == -2
    }

    private static func testRolloutFilenameUUID() -> Bool {
        let filename =
            "rollout-2026-07-31T10-17-47-\(sessionUUID).jsonl"
        return TaskStatusParser.sessionUUID(
            fromRolloutFilename: filename
        ) == sessionUUID
            && TaskStatusParser.sessionUUID(
                fromRolloutFilename: "not-a-rollout.jsonl"
            ) == nil
    }

    private static func testTmuxSessionName() -> Bool {
        TaskStatusParser.tmuxSessionName(
            forWorkingDirectoryPath:
                "/Users/openclaw/Projects/codex助手"
        ) == "codex-task-cc6493e5"
    }

    private static func testArchiveSnapshot() -> Bool {
        withTemporaryDirectories { tasks, sessions in
            let stamp = "20260731-101747"
            guard
                write(
                    "2026-07-31 10:17:47 \(sessionUUID) sync /tmp/My Brief.md\n",
                    to: tasks.appendingPathComponent("sessions.log")
                ),
                write(
                    "{\"type\":\"turn.completed\"}\nEXIT_CODE=0\n",
                    to: tasks.appendingPathComponent(
                        "\(stamp)-events.jsonl"
                    )
                ),
                write(
                    "Finished successfully.",
                    to: tasks.appendingPathComponent(
                        "\(stamp)-last-message.md"
                    )
                )
            else {
                return false
            }
            let parser = TaskStatusParser(
                tasksDirectory: tasks,
                workingDirectory: tasks.deletingLastPathComponent(),
                codexSessionsDirectory: sessions,
                timeZone: shanghai,
                tmuxStatusProvider: { _ in false }
            )
            guard let task = parser.snapshots().first else {
                return false
            }
            return task.sessionUUID == sessionUUID
                && task.taskName == "My Brief"
                && task.status == .done
                && task.exitCode == 0
                && task.endedAt != nil
                && task.lastMessage == "Finished successfully."
        }
    }

    private static func testSidecarNameWithDashedDate() -> Bool {
        sidecarTaskName(
            briefPath: "/tmp/2026-08-01-popover-panel.md",
            expected: "popover-panel"
        )
    }

    private static func testSidecarNameWithCompactDateAndChinese() -> Bool {
        sidecarTaskName(
            briefPath: "/tmp/20260731-菜单栏任务监控.md",
            expected: "菜单栏任务监控"
        )
    }

    private static func testTaskNameFallbackChain() -> Bool {
        let fallbackWorked = withTemporaryDirectories { tasks, sessions in
            let stamp = "20260731-101747"
            guard
                write(
                    "2026-07-31 10:17:47 \(sessionUUID) sync /tmp/2026-08-01-session-fallback.md\n",
                    to: tasks.appendingPathComponent("sessions.log")
                ),
                write(
                    "EXIT_CODE=0\n",
                    to: tasks.appendingPathComponent("\(stamp)-events.jsonl")
                )
            else {
                return false
            }
            return makeParser(tasks: tasks, sessions: sessions)
                .snapshots().first?.taskName == "session-fallback"
        }
        let nilFallbackWorked = withTemporaryDirectories { tasks, sessions in
            guard write(
                "EXIT_CODE=0\n",
                to: tasks.appendingPathComponent(
                    "20260731-101747-events.jsonl"
                )
            ) else {
                return false
            }
            return makeParser(tasks: tasks, sessions: sessions)
                .snapshots().first?.taskName == nil
        }
        return fallbackWorked && nilFallbackWorked
    }

    private static func testUnmatchedStatusEntryIsHidden() -> Bool {
        withTemporaryDirectories { tasks, sessions in
            guard write(
                "2026-07-31 10:18:00 \(sessionUUID) status status\n",
                to: tasks.appendingPathComponent("sessions.log")
            ) else {
                return false
            }
            let parser = TaskStatusParser(
                tasksDirectory: tasks,
                workingDirectory: tasks.deletingLastPathComponent(),
                codexSessionsDirectory: sessions,
                timeZone: shanghai,
                tmuxStatusProvider: { _ in true }
            )
            return parser.snapshots().isEmpty
        }
    }

    private static func sidecarTaskName(
        briefPath: String,
        expected: String
    ) -> Bool {
        withTemporaryDirectories { tasks, sessions in
            let stamp = "20260731-101747"
            guard
                write(
                    "2026-07-31 10:17:47 \(sessionUUID) sync /tmp/wrong-name.md\n",
                    to: tasks.appendingPathComponent("sessions.log")
                ),
                write(
                    "EXIT_CODE=0\n",
                    to: tasks.appendingPathComponent("\(stamp)-events.jsonl")
                ),
                write(
                    "\(briefPath)\n",
                    to: tasks.appendingPathComponent("\(stamp)-events.brief")
                )
            else {
                return false
            }
            return makeParser(tasks: tasks, sessions: sessions)
                .snapshots().first?.taskName == expected
        }
    }

    private static func makeParser(
        tasks: URL,
        sessions: URL
    ) -> TaskStatusParser {
        TaskStatusParser(
            tasksDirectory: tasks,
            workingDirectory: tasks.deletingLastPathComponent(),
            codexSessionsDirectory: sessions,
            timeZone: shanghai,
            tmuxStatusProvider: { _ in false }
        )
    }

    private static func testRolloutRecovery() -> Bool {
        withTemporaryDirectories { tasks, sessions in
            let stamp = "20260731-113832"
            let events = tasks.appendingPathComponent(
                "\(stamp)-events.jsonl"
            )
            let rolloutDirectory = sessions.appendingPathComponent(
                "2026/07/31",
                isDirectory: true
            )
            let rollout = rolloutDirectory.appendingPathComponent(
                "rollout-2026-07-31T11-38-32-\(sessionUUID).jsonl"
            )
            guard
                (try? FileManager.default.createDirectory(
                    at: rolloutDirectory,
                    withIntermediateDirectories: true
                )) != nil,
                write("EXIT_CODE=0\n", to: events),
                write("{}\n", to: rollout)
            else {
                return false
            }
            let modificationDate = date(
                "2026-07-31 11:39:00"
            )
            guard
                setModificationDate(modificationDate, for: events),
                setModificationDate(
                    modificationDate.addingTimeInterval(30),
                    for: rollout
                )
            else {
                return false
            }
            let parser = TaskStatusParser(
                tasksDirectory: tasks,
                workingDirectory: tasks.deletingLastPathComponent(),
                codexSessionsDirectory: sessions,
                timeZone: shanghai,
                tmuxStatusProvider: { _ in false }
            )
            return parser.snapshots().first?.sessionUUID == sessionUUID
        }
    }

    private static func testRunningTmuxSession() -> Bool {
        withTemporaryDirectories { tasks, sessions in
            guard write(
                "{\"type\":\"turn.started\"}\n",
                to: tasks.appendingPathComponent(
                    "20260731-113832-events.jsonl"
                )
            ) else {
                return false
            }
            let expectedName = TaskStatusParser.tmuxSessionName(
                forWorkingDirectoryPath:
                    tasks.deletingLastPathComponent().path
            )
            let parser = TaskStatusParser(
                tasksDirectory: tasks,
                workingDirectory: tasks.deletingLastPathComponent(),
                codexSessionsDirectory: sessions,
                timeZone: shanghai,
                tmuxStatusProvider: { $0 == expectedName }
            )
            return parser.snapshots().first?.status == .running
        }
    }

    private static func testCompletionDetection() -> Bool {
        let startedAt = date("2026-07-31 10:17:47")
        let running = snapshot(
            startedAt: startedAt,
            status: .running
        )
        let initial = TaskCompletionDetector.evaluate(
            [running],
            state: nil,
            now: startedAt.addingTimeInterval(10)
        )
        guard initial.completedTasks.isEmpty else {
            return false
        }

        let done = snapshot(startedAt: startedAt, status: .done)
        let completed = TaskCompletionDetector.evaluate(
            [done],
            state: initial.state,
            now: startedAt.addingTimeInterval(20)
        )
        let repeated = TaskCompletionDetector.evaluate(
            [done],
            state: completed.state,
            now: startedAt.addingTimeInterval(30)
        )
        let fastSessionUUID =
            "019fb5f6-40d1-7383-ac0d-48b797170e08"
        let fastTask = TaskStatusSnapshot(
            id: "fast",
            startedAt: startedAt.addingTimeInterval(35),
            sessionUUID: fastSessionUUID,
            mode: .sync,
            taskName: "Fast",
            isBackgroundTask: false,
            status: .done,
            exitCode: 0,
            lastMessage: nil
        )
        let fastCompletion = TaskCompletionDetector.evaluate(
            [fastTask],
            state: repeated.state,
            now: startedAt.addingTimeInterval(40)
        )
        return completed.completedTasks.map(\.sessionUUID) == [
            sessionUUID
        ] && repeated.completedTasks.isEmpty
            && fastCompletion.completedTasks.map(\.sessionUUID) == [
                fastSessionUUID
            ]
    }

    private static func testNotificationStatePersistence() -> Bool {
        let suiteName = "TaskStatusParserTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return false
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let expected = TaskNotificationState(
            lastScannedAt: date("2026-07-31 10:17:47"),
            unfinishedSessionUUIDs: [sessionUUID],
            notifiedSessionUUIDs: [
                "019fb5f6-40d1-7383-ac0d-48b797170e08"
            ]
        )
        let store = TaskStatusStore(defaults: defaults)
        store.notificationState = expected
        return TaskStatusStore(
            defaults: defaults
        ).notificationState == expected
    }

    private static func testSnapshotMerge() -> Bool {
        let july31 = date("2026-07-31 10:17:47")
        let august12 = date("2026-08-12 16:28:53")
        let august18 = date("2026-08-18 11:07:36")
        let snapshots = TaskStatusSnapshotMerger.merge([
            [
                snapshot(id: "20260731-101747", startedAt: july31),
                snapshot(id: "20260812-162853", startedAt: august12)
            ],
            [
                snapshot(id: "20260818-110736", startedAt: august18),
                snapshot(id: "20260812-162853", startedAt: august12),
                snapshot(id: "duplicate", startedAt: july31),
                snapshot(id: "duplicate", startedAt: august18)
            ]
        ])
        return snapshots.map(\.id) == [
            "20260818-110736",
            "duplicate",
            "20260812-162853",
            "20260731-101747"
        ] && TaskStatusSnapshotMerger.merge(
            [snapshots],
            limit: 2
        ).map(\.id) == ["20260818-110736", "duplicate"]
    }

    private static func testMultiDirectorySnapshots() -> Bool {
        withTemporaryDirectories { rootTasks, sessions in
            let appTasks = rootTasks.deletingLastPathComponent()
                .appendingPathComponent("app/.codex-tasks", isDirectory: true)
            do {
                try FileManager.default.createDirectory(
                    at: appTasks,
                    withIntermediateDirectories: true
                )
            } catch {
                return false
            }
            let archives: [(URL, String, String, String)] = [
                (rootTasks, "20260731-101747", "2026-07-31", "old-root-one"),
                (rootTasks, "20260801-003850", "2026-08-01", "old-root-two"),
                (appTasks, "20260812-162853", "2026-08-12", "reset-signal-fallback"),
                (appTasks, "20260818-110736", "2026-08-18", "countdown-ceil-days")
            ]
            guard archives.allSatisfy({ directory, id, date, name in
                write(
                    "EXIT_CODE=0\n",
                    to: directory.appendingPathComponent("\(id)-events.jsonl")
                ) && write(
                    "/tmp/\(date)-\(name).md\n",
                    to: directory.appendingPathComponent("\(id)-events.brief")
                )
            }) else {
                return false
            }

            let snapshots = TaskStatusSnapshotMerger.merge([
                TaskStatusParser(
                    tasksDirectory: rootTasks,
                    workingDirectory: rootTasks.deletingLastPathComponent(),
                    codexSessionsDirectory: sessions,
                    timeZone: shanghai,
                    tmuxStatusProvider: { _ in false }
                ).snapshots(),
                TaskStatusParser(
                    tasksDirectory: appTasks,
                    workingDirectory: appTasks.deletingLastPathComponent(),
                    codexSessionsDirectory: sessions,
                    timeZone: shanghai,
                    tmuxStatusProvider: { _ in false }
                ).snapshots()
            ])
            return snapshots.map(\.id) == [
                "20260818-110736",
                "20260812-162853",
                "20260801-003850",
                "20260731-101747"
            ] && snapshots.map(\.taskName) == [
                "countdown-ceil-days",
                "reset-signal-fallback",
                "old-root-two",
                "old-root-one"
            ]
        }
    }

    private static func testArchiveCompletedRecords() -> Bool {
        withTemporaryDirectories { tasks, sessions in
            let doneID = "20260818-110736"
            let failedID = "20260818-110737"
            let runningID = "20260818-110738"
            guard [doneID, failedID, runningID].allSatisfy({ id in
                write(
                    id == doneID ? "EXIT_CODE=0\n" : "EXIT_CODE=1\n",
                    to: tasks.appendingPathComponent("\(id)-events.jsonl")
                ) && write(
                    "/tmp/\(id).md\n",
                    to: tasks.appendingPathComponent("\(id)-events.brief")
                ) && write(
                    "message",
                    to: tasks.appendingPathComponent("\(id)-last-message.md")
                ) && write(
                    "exit code: \(id == doneID ? 0 : 1)\n",
                    to: tasks.appendingPathComponent("\(id)-run.log")
                )
            }) else {
                return false
            }

            let runningEvents = tasks.appendingPathComponent(
                "\(runningID)-events.jsonl"
            )
            guard write("{\"type\":\"turn.started\"}\n", to: runningEvents),
                  write(
                    "",
                    to: tasks.appendingPathComponent("\(runningID)-run.log")
                  )
            else {
                return false
            }
            let parser = TaskStatusParser(
                tasksDirectory: tasks,
                workingDirectory: tasks.deletingLastPathComponent(),
                codexSessionsDirectory: sessions,
                timeZone: shanghai,
                tmuxStatusProvider: { _ in true }
            )
            let snapshots = parser.snapshots()
            guard snapshots.first(where: { $0.id == doneID })?.status == .done,
                  snapshots.first(where: { $0.id == failedID })?.status == .failed,
                  snapshots.first(where: { $0.id == runningID })?.status == .running
            else {
                return false
            }

            let archived = TaskArchive.archiveCompletedRecords(
                in: tasks,
                snapshots: snapshots
            )
            let archivedDirectory = tasks.appendingPathComponent(
                "archived",
                isDirectory: true
            )
            let doneFilesArchived = [
                "-events.jsonl", "-events.brief", "-last-message.md", "-run.log"
            ].allSatisfy {
                FileManager.default.fileExists(
                    atPath: archivedDirectory.appendingPathComponent(doneID + $0).path
                )
            }
            let nonDoneFilesRemain = [failedID, runningID].allSatisfy { id in
                FileManager.default.fileExists(
                    atPath: tasks.appendingPathComponent(id + "-events.jsonl").path
                )
            }
            let remainingIDs = parser.snapshots().map(\.id)
            return archived == Set([doneID])
                && doneFilesArchived
                && nonDoneFilesRemain
                && !remainingIDs.contains(doneID)
                && Set(remainingIDs) == Set([failedID, runningID])
        }
    }

    private static func testArchiveSingleRecord() -> Bool {
        withTemporaryDirectories { tasks, _ in
            let selectedID = "20260818-110736"
            let peerID = "20260818-110737"
            let suffixes = [
                "-events.jsonl",
                "-events.brief",
                "-last-message.md",
                "-run.log"
            ]
            guard [selectedID, peerID].allSatisfy({ id in
                suffixes.allSatisfy { suffix in
                    write(
                        "\(id)\(suffix)",
                        to: tasks.appendingPathComponent(id + suffix)
                    )
                }
            }) else {
                return false
            }

            guard TaskArchive.archiveRecord(id: selectedID, in: tasks) else {
                return false
            }
            let archivedDirectory = tasks.appendingPathComponent(
                "archived",
                isDirectory: true
            )
            let selectedFilesArchived = suffixes.allSatisfy { suffix in
                FileManager.default.fileExists(
                    atPath: archivedDirectory.appendingPathComponent(
                        selectedID + suffix
                    ).path
                )
            }
            let selectedFilesRemoved = suffixes.allSatisfy { suffix in
                !FileManager.default.fileExists(
                    atPath: tasks.appendingPathComponent(selectedID + suffix).path
                )
            }
            let peerFilesRemain = suffixes.allSatisfy { suffix in
                FileManager.default.fileExists(
                    atPath: tasks.appendingPathComponent(peerID + suffix).path
                )
            }
            return selectedFilesArchived
                && selectedFilesRemoved
                && peerFilesRemain
                && !TaskArchive.archiveRecord(id: "invalid", in: tasks)
        }
    }

    private static func snapshot(
        id: String = "test",
        startedAt: Date,
        status: TaskExecutionStatus = .done
    ) -> TaskStatusSnapshot {
        TaskStatusSnapshot(
            id: id,
            startedAt: startedAt,
            sessionUUID: sessionUUID,
            mode: .sync,
            taskName: "Test",
            isBackgroundTask: false,
            status: status,
            exitCode: status == .done ? 0 : nil,
            lastMessage: nil
        )
    }

    private static func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = shanghai
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)!
    }

    private static func withTemporaryDirectories(
        _ body: (URL, URL) -> Bool
    ) -> Bool {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CodexQuotaTaskTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let tasks = root.appendingPathComponent(
            ".codex-tasks",
            isDirectory: true
        )
        let sessions = root.appendingPathComponent(
            "sessions",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: tasks,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: sessions,
                withIntermediateDirectories: true
            )
        } catch {
            return false
        }
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        return body(tasks, sessions)
    }

    private static func write(_ contents: String, to url: URL) -> Bool {
        do {
            try Data(contents.utf8).write(to: url)
            return true
        } catch {
            return false
        }
    }

    private static func setModificationDate(
        _ date: Date,
        for url: URL
    ) -> Bool {
        do {
            try FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: url.path
            )
            return true
        } catch {
            return false
        }
    }
}
