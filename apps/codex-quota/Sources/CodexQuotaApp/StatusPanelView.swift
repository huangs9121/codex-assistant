import AppKit
import CodexQuotaCore
import CodexQuotaUI
import SwiftUI

struct StatusPanelView: View {
    @ObservedObject var model: StatusPanelModel

    let text: AppText
    let onSettingsMenu: (NSView) -> Void
    let onOpenResetAnnouncement: () -> Void
    let canResumeTaskSessions: Bool
    let onResumeSession: (String, Bool) -> TaskResumeActionResult
    let onArchiveTask: (TaskStatusSnapshot) -> Void
    let onClearCompletedTasks: () -> Void

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
            Divider()
            taskSection
            if !model.desktopThreads.isEmpty {
                Divider()
                codexDesktopSection
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
            .padding(.bottom, model.tasks.isEmpty ? 0 : 5)

            if model.tasks.isEmpty {
                emptyTasks
            } else {
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
        }
        .padding(.bottom, model.tasks.isEmpty ? 14 : 5)
    }

    private var emptyTasks: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(text.noScheduledTasks)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(text.scheduledTasksEmptyDetail)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.top, 15)
    }

    private var codexDesktopSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text(text.codexClientThreads)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                let runningCount = model.desktopThreads.count {
                    $0.isRunning
                }
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

            ForEach(
                Array(model.desktopThreads.enumerated()),
                id: \.element.id
            ) { index, thread in
                CodexDesktopThreadRow(
                    thread: thread,
                    now: model.now,
                    text: text,
                    canResumeTaskSessions: canResumeTaskSessions,
                    onCopyResumeCommand: { id in
                        onResumeSession(id, true)
                    }
                )
                if index < model.desktopThreads.count - 1 {
                    Divider()
                        .padding(.leading, 40)
                }
            }
        }
        .padding(.bottom, 5)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            SettingsMenuButton(
                accessibilityLabel: text.settings,
                action: onSettingsMenu
            )
            .frame(width: 24, height: 24)
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
            .help(text.resetAnnouncementTooltip)
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
            .help(text.continueTask)
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
            .help(text.deleteTask)
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

private struct CodexDesktopThreadRow: View {
    let thread: CodexDesktopThreadSnapshot
    let now: Date
    let text: AppText
    let canResumeTaskSessions: Bool
    let onCopyResumeCommand: (String) -> TaskResumeActionResult

    @State private var isCopied = false

    private var canCopyResumeCommand: Bool {
        !thread.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && canResumeTaskSessions
    }

    var body: some View {
        Button {
            guard canCopyResumeCommand else {
                return
            }
            let result = onCopyResumeCommand(thread.id)
            if result == .copied || result == .copiedAfterLaunchFailure {
                isCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    isCopied = false
                }
            }
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

                Image(systemName: isCopied ? "checkmark" : "play.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canCopyResumeCommand)
        .help(text.copyResumeCommandHelp)
        .accessibilityLabel(thread.title)
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
        let button = NSButton()
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
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.setAccessibilityLabel(accessibilityLabel)
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
