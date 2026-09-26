import AppKit
import CodexQuotaCore
import CodexQuotaUI
import SwiftUI

struct StatusPanelView: View {
    @ObservedObject var model: StatusPanelModel

    let text: AppText
    let onSettingsMenu: (NSView) -> Void
    let onQuickTools: () -> Void
    let onNodeScores: () -> Void
    var onDisplaySleep: () -> Void = {}
    let onOpenResetAnnouncement: () -> Void
    let canResumeTaskSessions: Bool
    let onResumeSession: (String, Bool) -> TaskResumeActionResult
    let onOpenCodexThread: (CodexDesktopThreadSnapshot) -> CodexThreadOpenActionResult
    let onOpenCLIProcess: (String, CodexCLIProcess) -> CodexCLIProcessOpenActionResult
    let onArchiveTask: (TaskStatusSnapshot) -> Void
    let onClearCompletedTasks: () -> Void
    let onClearFinishedThreads: () -> Void
    let onToggleSleep: () -> Void
    let onDisplayMode: (PanelDisplayMode) -> Void
    var onOpenClaudeSession: (ClaudeCodeSession) -> Void = { _ in }

    var body: some View {
        DailyPanelContent(model: model, text: text, actions: NotchActions(
            settings: onSettingsMenu, quickTools: onQuickTools,
            openTasks: {
                let bundleID = model.selectedQuotaProvider == .claude ? "com.anthropic.claudefordesktop" : "com.openai.codex"
                if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
                }
            }, scroll: onQuickTools, gestures: onQuickTools, mappings: onQuickTools,
            sleep: onToggleSleep, reset: onOpenResetAnnouncement, mode: onDisplayMode,
            resume: onResumeSession, thread: onOpenCodexThread, cli: onOpenCLIProcess,
            archive: onArchiveTask, clear: { onClearCompletedTasks(); onClearFinishedThreads() },
            claude: onOpenClaudeSession
        )).frame(width: StatusPanelController.panelWidth)
            .fixedSize(horizontal: false, vertical: true)
    }

}
