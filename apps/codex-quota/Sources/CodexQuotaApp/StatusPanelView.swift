import AppKit
import CodexQuotaCore
import CodexQuotaUI
import SwiftUI

struct StatusPanelView: View {
    @ObservedObject var model: StatusPanelModel
    @FocusState private var isClearFinishedThreadsFocused: Bool

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

    private var quotaData: StatusPanelQuotaData {
        StatusPanelQuotaData(snapshot: model.snapshot, now: model.now)
    }

    private var resetForecast: StatusPanelResetForecast {
        StatusPanelResetForecast(
            signal: model.currentResetSignal,
            quotaSnapshot: model.snapshot,
            now: model.now
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            quotaSection
            resetForecastSection
            if !model.tasks.isEmpty {
                Divider()
                taskSection
            }
            if !model.desktopThreadGroups.isEmpty {
                Divider()
                codexDesktopSection
            }
            if !model.cliProcesses.isEmpty {
                Divider()
                cliSection
            }
            Divider()
            toolbar
        }
        .frame(width: StatusPanelController.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(text.quotaTitle)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Text(quotaData.planName ?? "--")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Color(nsColor: .separatorColor).opacity(0.22),
                        in: Capsule()
                    )
            }

            if let primaryWindow = quotaData.primaryWindow {
                primaryQuotaRow(primaryWindow)
                    .padding(.top, 9)
            }

            if let secondaryWindow = quotaData.secondaryWindow {
                secondaryQuotaRow(secondaryWindow)
                    .padding(.top, 10)
            }

            if
                quotaData.primaryWindow == nil,
                quotaData.secondaryWindow == nil
            {
                Text(text.waitingForData)
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 13)
    }

    private func primaryQuotaRow(
        _ window: StatusPanelQuotaWindow
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(window.remainingPercent)%")
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
                Text(windowLabel(for: window.windowDuration))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            QuotaProgressBar(
                percent: window.remainingPercent,
                height: 5
            )
            Text(primaryResetLabel(for: window))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private func secondaryQuotaRow(
        _ window: StatusPanelQuotaWindow
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(window.remainingPercent)%")
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                Text(windowLabel(for: window.windowDuration))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            QuotaProgressBar(percent: window.remainingPercent, height: 4)
            Text(secondaryResetLabel(for: window))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private var resetForecastSection: some View {
        ResetForecastRow(
            forecast: resetForecast,
            now: model.now,
            text: text,
            action: onOpenResetAnnouncement
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 13)
    }

    private var taskSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text(text.scheduledTasks)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Button(text.clearCompletedTasks) {
                    onClearCompletedTasks()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!model.hasCompletedTasks)
                .buttonHelp(text.clearCompletedTasks)
                let runningCount = TaskStatusPresentationFormatter.runningCount(
                    in: model.tasks
                )
                if runningCount > 0 {
                    Circle()
                        .fill(Color(nsColor: .controlAccentColor))
                        .frame(width: 6, height: 6)
                    Text(text.runningTaskCount(runningCount))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 5)

            let tasks = Array(model.tasks.prefix(5))
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                TaskStatusRow(
                    task: task,
                    now: model.now,
                    text: text,
                    canResumeTaskSessions: canResumeTaskSessions,
                    onResumeSession: onResumeSession,
                    onArchiveTask: onArchiveTask
                )
                if index < tasks.count - 1 {
                    Divider()
                        .padding(.leading, 40)
                }
            }
        }
        .padding(.bottom, 5)
    }

    private var codexDesktopSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text(text.codexClientThreads)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                clearFinishedThreadsButton
                let runningCount = model.desktopThreadGroups.reduce(0) { $0 + $1.runningCount }
                if runningCount > 0 {
                    Circle()
                        .fill(Color(nsColor: .controlAccentColor))
                        .frame(width: 6, height: 6)
                    Text(text.runningTaskCount(runningCount))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 5)

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(model.desktopThreadGroups) { group in
                        CodexDesktopThreadGroupView(
                            group: group,
                            isCollapsed: !model.expandedDesktopThreadGroupIDs.contains(group.id),
                            now: model.now,
                            text: text,
                            onToggle: { model.toggleDesktopThreadGroup(group.id) },
                            onOpenCodexThread: onOpenCodexThread
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(.bottom, 5)
    }

    private var cliSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text(text.codexCLIProcesses).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                let count = model.cliProcesses.count
                if count > 0 {
                    Circle().fill(Color(nsColor: .controlAccentColor)).frame(width: 6, height: 6)
                    Text(text.cliOccupiedCount(count)).font(.system(size: 12)).foregroundStyle(Color(nsColor: .controlAccentColor)).monospacedDigit()
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 5)
            ForEach(model.cliProcesses.keys.sorted(), id: \.self) { id in
                if let process = model.cliProcesses[id] {
                    CodexCLIProcessRow(id: id, title: model.desktopThreads.first(where: { $0.id == id })?.title ?? text.codexCLIProcesses, process: process, text: text, onOpen: onOpenCLIProcess)
                }
            }
        }
        .padding(.bottom, 5)
    }

    @ViewBuilder
    private var clearFinishedThreadsButton: some View {
        let button = Button {
            onClearFinishedThreads()
        } label: {
            Image(systemName: "eraser")
                .font(.system(size: 12))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(nsColor: .controlAccentColor))
        .buttonHelp(text.clearFinishedThreads)
        .accessibilityLabel(text.clearFinishedThreads)
        .focused($isClearFinishedThreadsFocused)
        .overlay(alignment: .bottom) {
            Color(nsColor: .controlAccentColor)
                .frame(height: 1)
                .opacity(isClearFinishedThreadsFocused ? 0.7 : 0)
        }
        .disabled(!model.canClearCompletedSessions)

        if #available(macOS 14.0, *) {
            button.focusEffectDisabled()
        } else {
            button
        }
    }


    private var toolbar: some View {
        HStack(spacing: 8) {
            SettingsMenuButton(
                accessibilityLabel: text.settings,
                action: onSettingsMenu
            )
            .frame(width: 24, height: 24)
            QuickToolsButton(
                accessibilityLabel: text.quickTools,
                action: onQuickTools
            )
            .frame(width: 24, height: 24)
            manualSleepButton
            Button(action: onNodeScores) {
                Image(systemName: "network").frame(width: 24, height: 24)
            }.buttonStyle(.plain).buttonHelp("节点评分与本地排行榜").accessibilityLabel("节点评分")
            Button(action: onDisplaySleep) {
                Image(systemName: "display")
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .offset(x: 3, y: -3)
                    }
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .buttonHelp(text.language == .simplifiedChinese
                ? "熄屏继续工作：临时防休眠，亮屏后自动结束。请插电、勿合盖。"
                : "Turn display off and keep working until it wakes. Keep plugged in and lid open.")
            .accessibilityLabel(text.language == .simplifiedChinese ? "熄屏继续工作" : "Turn display off and keep working")
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(
                    text.updatedAt(
                        UpdateTimeFormatter.string(
                            observedAt: quotaData.observedAt
                        )
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                Text(text.moveHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
    }

    private var manualSleepButton: some View {
        Button(action: onToggleSleep) {
            Group {
                switch model.sleepState {
                case .off:
                    Image(systemName: "moon.zzz")
                        .foregroundStyle(.secondary)
                case .on:
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(.orange)
                        .frame(width: 24, height: 24)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                case .pending:
                    ProgressView()
                        .controlSize(.small)
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.system(size: 15, weight: .medium))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.sleepState == .pending)
        .buttonHelp(manualSleepStatusText)
        .accessibilityLabel(manualSleepStatusText)
    }

    private var manualSleepStatusText: String {
        let stateText: String
        switch model.sleepState {
        case .off:
            stateText = text.language == .simplifiedChinese
                ? "手动防睡眠已关"
                : "Manual keep-awake is off"
        case .on:
            stateText = text.language == .simplifiedChinese
                ? "手动防睡眠已开"
                : "Manual keep-awake is on"
        case .pending:
            stateText = text.language == .simplifiedChinese
                ? "手动防睡眠处理中"
                : "Manual keep-awake is processing"
        case .failed:
            stateText = text.language == .simplifiedChinese
                ? "手动防睡眠错误"
                : "Manual keep-awake error"
        }
        return stateText
    }

    private func windowLabel(for duration: TimeInterval?) -> String {
        switch StatusPanelQuotaWindowKind(windowDuration: duration) {
        case .fiveHour:
            return text.fiveHourWindow
        case .weekly:
            return text.weeklyWindow
        case .generic:
            return text.quotaWindow
        }
    }

    private func primaryResetLabel(
        for window: StatusPanelQuotaWindow
    ) -> String {
        guard let value = ResetCountdownFormatter.panelCountdownValue(
            resetsAt: window.resetsAt,
            now: model.now,
            language: text.language
        ) else {
            return "--"
        }
        return text.resetsIn(value)
    }

    private func secondaryResetLabel(
        for window: StatusPanelQuotaWindow
    ) -> String {
        if StatusPanelQuotaWindowKind(
            windowDuration: window.windowDuration
        ) == .weekly {
            guard let value = ResetCountdownFormatter.weeklyResetValue(
                resetsAt: window.resetsAt,
                language: text.language
            ) else {
                return "--"
            }
            return text.weeklyReset(value)
        }
        guard let value = ResetCountdownFormatter.panelCountdownValue(
            resetsAt: window.resetsAt,
            now: model.now,
            language: text.language
        ) else {
            return "--"
        }
        return text.resetsIn(value)
    }

}

private struct ResetForecastRow: View {
    let forecast: StatusPanelResetForecast
    let now: Date
    let text: AppText
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        if let signal = forecast.signal {
            Button(action: action) {
                signalContent(signal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .buttonHelp(text.resetAnnouncementTooltip)
            .accessibilityLabel(text.resetAnnouncementAccessibility)
            .onHover { isHovered = $0 }
        } else {
            HStack(spacing: 7) {
                Image(systemName: "dot.radiowaves.left.and.right")
                Text(text.resetForecastNone)
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func signalContent(_ signal: TiboResetSignal) -> some View {
        switch forecast.state {
        case .quiet:
            EmptyView()
        case .proposal:
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(.yellow)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        text.resetProposalTitle(
                            signal.expectedTimeText(
                                now: now,
                                language: text.language
                            )
                        )
                    )
                    .font(.system(size: 13))
                    Text(text.resetMonitoringSource)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        case .announced:
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        text.resetAnnouncedTitle(
                            signal.expectedTimeText(
                                now: now,
                                language: text.language
                            )
                        )
                    )
                    .font(.system(size: 13))
                    if let expectedAt = signal.expectedAt {
                        Text(
                            ResetForecastCountdownFormatter.string(
                                until: expectedAt,
                                now: now,
                                text: text.resetCountdownText
                            )
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    }
                }
                Spacer(minLength: 6)
                Text(text.resetAnnouncedBadge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Color.accentColor.opacity(isHovered ? 0.14 : 0.10),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        case .completed:
            HStack(spacing: 8) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                Text(text.resetCompletedTitle)
                    .font(.system(size: 13))
            }
        }
    }
}

private struct QuotaProgressBar: View {
    let percent: Int?
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .separatorColor).opacity(0.32))
                Capsule()
                    .fill(Color(nsColor: .controlAccentColor))
                    .frame(
                        width: proxy.size.width
                            * CGFloat(min(max(percent ?? 0, 0), 100)) / 100
                    )
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(percent.map { "\($0)%" } ?? "--")
    }
}

private struct CodexCLIProcessRow: View {
    let id: String
    let title: String
    let process: CodexCLIProcess
    let text: AppText
    let onOpen: (String, CodexCLIProcess) -> CodexCLIProcessOpenActionResult

    var body: some View {
        Button { _ = onOpen(id, process) } label: {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12)).foregroundStyle(Color(nsColor: .controlAccentColor))
                    .frame(width: 16, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.tertiary).monospacedDigit().lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 20, height: 20)
            }
            .padding(.horizontal, 16).padding(.vertical, 7).contentShape(Rectangle())
        }
        .buttonStyle(.plain).buttonHelp(text.openCLIProcessHelp).accessibilityLabel(text.codexCLIProcesses)
    }

    private var subtitle: String {
        text.cliOccupied(process.pid, tty: process.tty)
    }
}

private struct TaskStatusRow: View {
    let task: TaskStatusSnapshot
    let now: Date
    let text: AppText
    let canResumeTaskSessions: Bool
    let onResumeSession: (String, Bool) -> TaskResumeActionResult
    let onArchiveTask: (TaskStatusSnapshot) -> Void

    @State private var isHovered = false
    @State private var isCopied = false
    @State private var showsResumeFallback = false
    @FocusState private var isRowFocused: Bool
    @FocusState private var isContinueFocused: Bool
    @FocusState private var isDeleteFocused: Bool

    private var sessionUUID: String? {
        guard let value = task.sessionUUID?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !value.isEmpty else {
            return nil
        }
        return value
    }

    private var canContinue: Bool {
        sessionUUID != nil && canResumeTaskSessions
    }

    private var canDelete: Bool {
        task.status.isTerminal
    }

    private var showsActionButtons: Bool {
        isHovered
            || isRowFocused
            || isContinueFocused
            || isDeleteFocused
            || isCopied
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TaskStatusIcon(status: task.status)
                .frame(width: 16, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(taskSubtitle)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Button {
                guard let sessionUUID else {
                    return
                }
                let copyOnly = NSApp.currentEvent?
                    .modifierFlags.contains(.option) == true
                let result = onResumeSession(sessionUUID, copyOnly)
                if result == .copied || result == .copiedAfterLaunchFailure {
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        isCopied = false
                    }
                }
                if result == .copiedAfterLaunchFailure {
                    showsResumeFallback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showsResumeFallback = false
                    }
                }
            } label: {
                Image(systemName: isCopied ? "checkmark" : "play.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(!canContinue)
            .focused($isContinueFocused)
            .opacity(showsActionButtons ? (canContinue ? 1 : 0.35) : 0)
            .allowsHitTesting(showsActionButtons)
            .buttonHelp(text.continueTask)
            .accessibilityLabel(text.continueTask)

            Button {
                onArchiveTask(task)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(!canDelete)
            .focused($isDeleteFocused)
            .opacity(showsActionButtons ? (canDelete ? 1 : 0.35) : 0)
            .allowsHitTesting(showsActionButtons)
            .buttonHelp(text.deleteTask)
            .accessibilityLabel(text.deleteTask)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .focusable(true)
        .focused($isRowFocused)
        .onHover { isHovered = $0 }
    }

    private var displayName: String {
        task.taskName
            ?? (task.isBackgroundTask ? text.backgroundTask : text.unknownTask)
    }

    private var taskSubtitle: String {
        if showsResumeFallback {
            return text.resumeCommandCopiedFallback
        }
        return TaskStatusPresentationFormatter.subtitle(
            for: task,
            now: now,
            language: text.language,
            text: text.taskStatusPresentationText
        )
    }
}

private struct CodexDesktopThreadGroupView: View {
    let group: CodexDesktopThreadGroup
    let isCollapsed: Bool
    let now: Date
    let text: AppText
    let onToggle: () -> Void
    let onOpenCodexThread: (CodexDesktopThreadSnapshot) -> CodexThreadOpenActionResult

    var body: some View {
        VStack(spacing: 0) {
            if let root = group.root {
                CodexDesktopThreadOpenButton(thread: root.thread, text: text, onOpenCodexThread: onOpenCodexThread) {
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 18, height: 24)
                        CodexDesktopThreadSummary(thread: root.thread, now: now, text: text, childCount: group.descendantCount, showsMainTaskLabel: root.thread.source == .user, statusIcon: aggregateStatus)
                        Spacer(minLength: 4)
                        CodexDesktopThreadOpenChevron()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                }
                .overlay(alignment: .leading) {
                    disclosureButton.padding(.leading, 16)
                }
            } else {
                HStack(spacing: 8) {
                    disclosureButton
                    Text("所属聊天不可用")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
            }
            if !isCollapsed {
                CodexDesktopThreadChildren(nodes: childNodes, depth: group.root == nil ? 0 : 1, now: now, text: text, onOpenCodexThread: onOpenCodexThread)
                    .padding(.vertical, 4)
                    .background(
                        Color(nsColor: .separatorColor).opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
        .background(
            Color(nsColor: .separatorColor).opacity(0.10),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    @ViewBuilder
    private var disclosureButton: some View {
        if group.descendantCount > 0 {
            Button(action: onToggle) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .buttonHelp(isCollapsed ? "展开子任务" : "折叠子任务")
        }
    }

    private var childNodes: [CodexDesktopThreadNode] {
        group.root?.children ?? group.orphanNodes
    }

    private var aggregateStatus: CodexDesktopThreadStatus {
        let nodes = group.root.map { [$0] } ?? group.orphanNodes
        let statuses = nodes.flatMap(allStatuses)
        if statuses.contains(.running) { return .running }
        if statuses.contains(.unknown) { return .unknown }
        return .ended
    }

    private func allStatuses(_ node: CodexDesktopThreadNode) -> [CodexDesktopThreadStatus] {
        [node.thread.status] + node.children.flatMap(allStatuses)
    }
}

private struct CodexDesktopThreadChildren: View {
    let nodes: [CodexDesktopThreadNode]
    let depth: Int
    let now: Date
    let text: AppText
    let onOpenCodexThread: (CodexDesktopThreadSnapshot) -> CodexThreadOpenActionResult

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                CodexDesktopThreadOpenButton(thread: node.thread, text: text, onOpenCodexThread: onOpenCodexThread) {
                    HStack(spacing: 8) {
                        DesktopThreadStatusIcon(status: node.thread.status)
                            .frame(width: 16, height: 18)
                        CodexDesktopThreadSummary(thread: node.thread, now: now, text: text)
                        Spacer(minLength: 4)
                        CodexDesktopThreadOpenChevron()
                    }
                    .padding(.leading, CGFloat(34 + depth * 18))
                    .padding(.trailing, 16)
                    .padding(.vertical, 5)
                }
                if !node.children.isEmpty {
                    CodexDesktopThreadChildren(nodes: node.children, depth: depth + 1, now: now, text: text, onOpenCodexThread: onOpenCodexThread)
                }
                if index < nodes.count - 1 {
                    Divider().padding(.leading, CGFloat(34 + depth * 18))
                }
            }
        }
    }
}

private struct CodexDesktopThreadSummary: View {
    let thread: CodexDesktopThreadSnapshot
    let now: Date
    let text: AppText
    var childCount = 0
    var showsMainTaskLabel = false
    var statusIcon: CodexDesktopThreadStatus? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(thread.title)
                    .font(.system(size: 13, weight: childCount > 0 ? .semibold : .regular))
                    .foregroundStyle(thread.isRunning ? .primary : .secondary)
                    .lineLimit(1)
                if showsMainTaskLabel {
                    Text("主任务")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
                if let statusIcon {
                    DesktopThreadStatusIcon(status: statusIcon)
                }
            }
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        let base: String
        if thread.isRunning {
            base = text.codexClientRunning(TaskStatusPresentationFormatter.durationString(max(0, now.timeIntervalSince(thread.startedAt)), language: text.language))
        } else {
            let formatter = DateFormatter()
            formatter.locale = text.language.locale
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            base = text.codexClientLastActive(formatter.string(from: thread.lastActiveAt))
        }
        let origin = thread.createdByCLI ? text.createdByCLI : text.createdByDesktop
        let summary = "\(origin) · \(base)"
        guard childCount > 0 else { return summary }
        return "\(summary) · \(childCount) 子 Agent"
    }
}

private struct DesktopThreadStatusIcon: View {
    let status: CodexDesktopThreadStatus

    var body: some View {
        switch status {
        case .running:
            Circle().fill(Color(nsColor: .controlAccentColor)).frame(width: 8, height: 8)
                .accessibilityLabel("运行中")
                .buttonHelp("任务运行中")
        case .ended:
            Circle().fill(Color.secondary.opacity(0.55)).frame(width: 8, height: 8)
                .accessibilityLabel("已结束")
                .buttonHelp("已收到明确的完成事件")
        case .unknown:
            Image(systemName: "questionmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .buttonHelp("状态未知，尚未收到明确的完成事件")
                .accessibilityLabel("状态未知")
        }
    }
}

private struct CodexDesktopThreadOpenChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(width: 20, height: 20)
    }
}

private struct CodexDesktopThreadOpenButton<Label: View>: View {
    let thread: CodexDesktopThreadSnapshot
    let text: AppText
    let onOpenCodexThread: (CodexDesktopThreadSnapshot) -> CodexThreadOpenActionResult
    @ViewBuilder let label: () -> Label

    private var canOpen: Bool {
        let id = thread.source == .subagent ? thread.parentThreadID : thread.id
        return id.flatMap(UUID.init(uuidString:)) != nil
    }

    var body: some View {
        Button { if canOpen { _ = onOpenCodexThread(thread) } } label: {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
        .buttonHelp(thread.source == .subagent ? text.openParentCodexThreadHelp : text.openCodexThreadHelp)
    }
}

private struct CodexDesktopThreadRow: View {
    let thread: CodexDesktopThreadSnapshot
    let now: Date
    let text: AppText
    let onOpenCodexThread: (CodexDesktopThreadSnapshot) -> CodexThreadOpenActionResult

    private var targetThreadID: String? {
        switch thread.source {
        case .user:
            return thread.id
        case .subagent:
            return thread.parentThreadID
        }
    }

    private var canOpenThread: Bool {
        guard let targetThreadID else {
            return false
        }
        return UUID(uuidString: targetThreadID) != nil
    }

    var body: some View {
        Button {
            guard canOpenThread else {
                return
            }
            _ = onOpenCodexThread(thread)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                TaskStatusIcon(
                    status: thread.isRunning ? .running : .interrupted
                )
                .frame(width: 16, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.title)
                        .font(.system(size: 13))
                        .foregroundStyle(
                            thread.isRunning ? .primary : .secondary
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canOpenThread)
        .buttonHelp(threadHelp)
        .accessibilityLabel(thread.title)
    }

    private var threadHelp: String {
        guard canOpenThread else {
            return text.subagentThreadUnavailableHelp
        }
        return thread.source == .subagent
            ? text.openParentCodexThreadHelp
            : text.openCodexThreadHelp
    }

    private var subtitle: String {
        if thread.isRunning {
            return text.codexClientRunning(
                TaskStatusPresentationFormatter.durationString(
                    max(0, now.timeIntervalSince(thread.startedAt)),
                    language: text.language
                )
            )
        }
        let formatter = DateFormatter()
        formatter.locale = text.language.locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return text.codexClientLastActive(
            formatter.string(from: thread.lastActiveAt)
        )
    }
}

private struct TaskStatusIcon: View {
    let status: TaskExecutionStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Group {
            switch status {
            case .running:
                ZStack {
                    Circle()
                        .stroke(
                            Color(nsColor: .controlAccentColor).opacity(
                                reduceMotion ? 0.32 : (pulse ? 0 : 0.5)
                            ),
                            lineWidth: 1
                        )
                        .frame(width: 10, height: 10)
                        .scaleEffect(reduceMotion ? 1.2 : (pulse ? 1.9 : 0.8))
                    Circle()
                        .fill(Color(nsColor: .controlAccentColor))
                        .frame(width: 7, height: 7)
                }
                .onAppear(perform: startPulseIfNeeded)
                .onChange(of: reduceMotion) { _ in
                    startPulseIfNeeded()
                }
            case .done:
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Color(nsColor: .systemGreen))
            case .failed:
                Image(systemName: "xmark.circle")
                    .foregroundStyle(Color(nsColor: .systemRed))
            case .interrupted:
                Image(systemName: "minus.circle")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 12))
        .accessibilityHidden(true)
    }

    private func startPulseIfNeeded() {
        guard !reduceMotion else {
            pulse = false
            return
        }
        pulse = false
        withAnimation(
            .easeOut(duration: 1.25)
                .repeatForever(autoreverses: false)
        ) {
            pulse = true
        }
    }
}

private struct SettingsMenuButton: NSViewRepresentable {
    let accessibilityLabel: String
    let action: (NSView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = HelpButton()
        button.title = ""
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.focusRingType = .exterior
        button.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: accessibilityLabel
        )
        button.image?.isTemplate = true
        button.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 15,
            weight: .regular
        )
        button.contentTintColor = .secondaryLabelColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction(_:))
        button.setAccessibilityLabel(accessibilityLabel)
        button.toolTip = accessibilityLabel
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.setAccessibilityLabel(accessibilityLabel)
        button.toolTip = accessibilityLabel
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: (NSView) -> Void

        init(action: @escaping (NSView) -> Void) {
            self.action = action
        }

        @objc func performAction(_ sender: NSButton) {
            action(sender)
        }
    }
}

private final class HoverButton: HelpButton {
    private var isPointerInside = false

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        needsDisplay = true
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        needsDisplay = true
        super.mouseExited(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isPointerInside {
            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: 1, dy: 1),
                xRadius: 6,
                yRadius: 6
            ).fill()
        }
        super.draw(dirtyRect)
    }
}

private struct QuickToolsButton: NSViewRepresentable {
    let accessibilityLabel: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = HoverButton()
        button.title = ""
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.focusRingType = .exterior
        button.image = NSImage(
            systemSymbolName: "briefcase",
            accessibilityDescription: accessibilityLabel
        )
        button.image?.isTemplate = true
        button.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 15,
            weight: .regular
        )
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = accessibilityLabel
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction(_:))
        button.setAccessibilityLabel(accessibilityLabel)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction(_ sender: NSButton) {
            action()
        }
    }
}
