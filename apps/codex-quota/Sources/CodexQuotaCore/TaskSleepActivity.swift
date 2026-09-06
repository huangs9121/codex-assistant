import Foundation

/// A conservative signal for temporarily preventing system sleep while a task
/// is actively executing.
public enum TaskSleepActivity {
    /// CLI tasks are authoritative when their recorded status is `running`.
    /// Desktop session logs additionally require the Codex client to be alive
    /// and to have started no later than the task. This excludes a persisted
    /// `task_started` event from a client process that has since restarted.
    public static func hasRunningTasks(
        cliTasks: [TaskStatusSnapshot],
        desktopThreads: [CodexDesktopThreadSnapshot],
        codexDesktopLaunchDate: Date?
    ) -> Bool {
        if cliTasks.contains(where: { $0.status == .running }) {
            return true
        }

        guard let codexDesktopLaunchDate else {
            return false
        }

        return desktopThreads.contains {
            $0.status == .running
                && $0.startedAt >= codexDesktopLaunchDate
        }
    }
}
