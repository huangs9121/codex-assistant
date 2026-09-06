import CodexQuotaCore
import Foundation

enum TaskSleepActivityTests {
    static let all: [TaskStatusParserTestCase] = [
        TaskStatusParserTestCase(
            name: "sleep activity accepts only running CLI tasks",
            run: testRunningCLITasks
        ),
        TaskStatusParserTestCase(
            name: "sleep activity requires a live client for running desktop tasks",
            run: testDesktopClientRequirement
        ),
        TaskStatusParserTestCase(
            name: "sleep activity rejects desktop tasks before client restart",
            run: testDesktopTaskBeforeClientLaunch
        ),
        TaskStatusParserTestCase(
            name: "sleep activity ignores ended and unknown desktop threads",
            run: testTerminalAndUnknownDesktopThreads
        )
    ]

    private static func testRunningCLITasks() -> Bool {
        TaskSleepActivity.hasRunningTasks(
            cliTasks: [task(status: .running)],
            desktopThreads: [],
            codexDesktopLaunchDate: nil
        ) && !TaskSleepActivity.hasRunningTasks(
            cliTasks: [task(status: .done), task(status: .interrupted)],
            desktopThreads: [],
            codexDesktopLaunchDate: Date()
        )
    }

    private static func testDesktopClientRequirement() -> Bool {
        let desktop = desktopThread(status: .running)
        return !TaskSleepActivity.hasRunningTasks(
            cliTasks: [],
            desktopThreads: [desktop],
            codexDesktopLaunchDate: nil
        ) && TaskSleepActivity.hasRunningTasks(
            cliTasks: [],
            desktopThreads: [desktop],
            codexDesktopLaunchDate: desktop.startedAt.addingTimeInterval(-1)
        )
    }

    private static func testTerminalAndUnknownDesktopThreads() -> Bool {
        TaskSleepActivity.hasRunningTasks(
            cliTasks: [],
            desktopThreads: [
                desktopThread(status: .ended),
                desktopThread(status: .unknown)
            ],
            codexDesktopLaunchDate: Date()
        ) == false
    }

    private static func testDesktopTaskBeforeClientLaunch() -> Bool {
        let desktop = desktopThread(status: .running)
        return !TaskSleepActivity.hasRunningTasks(
            cliTasks: [],
            desktopThreads: [desktop],
            codexDesktopLaunchDate: desktop.startedAt.addingTimeInterval(1)
        )
    }

    private static func task(status: TaskExecutionStatus) -> TaskStatusSnapshot {
        TaskStatusSnapshot(
            id: UUID().uuidString,
            startedAt: Date(),
            sessionUUID: nil,
            mode: .sync,
            taskName: nil,
            isBackgroundTask: false,
            status: status,
            exitCode: nil,
            lastMessage: nil
        )
    }

    private static func desktopThread(
        status: CodexDesktopThreadStatus
    ) -> CodexDesktopThreadSnapshot {
        CodexDesktopThreadSnapshot(
            id: UUID().uuidString,
            title: "Codex",
            source: .user,
            startedAt: Date(),
            lastActiveAt: Date(),
            status: status
        )
    }
}
