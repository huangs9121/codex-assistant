import AppKit
import CodexQuotaCore
import SwiftUI

struct NotchTaskList: View {
    @ObservedObject var model: StatusPanelModel
    let text: AppText
    let onResumeSession: (String, Bool) -> TaskResumeActionResult
    let onOpenCodexThread: (CodexDesktopThreadSnapshot) -> CodexThreadOpenActionResult
    let onOpenCLIProcess: (String, CodexCLIProcess) -> CodexCLIProcessOpenActionResult
    let onArchiveTask: (TaskStatusSnapshot) -> Void
    let onClearCompleted: () -> Void

    private static let rowHeight: CGFloat = 50
    private static let rowSpacing: CGFloat = 4
    private static let headerHeight: CGFloat = 36
    private static let bottomPadding: CGFloat = 12
    private static let visibleRowLimit = 6

    var body: some View {
        let rows = Self.rows(model: model)
        if !rows.isEmpty {
            VStack(spacing: 0) {
                header
                    .frame(height: Self.headerHeight)

                ScrollView(.vertical, showsIndicators: rows.count > Self.visibleRowLimit) {
                    LazyVStack(spacing: Self.rowSpacing) {
                        ForEach(rows) { row in
                            rowView(row)
                                .frame(height: Self.rowHeight)
                        }
                    }
                }
                .frame(height: Self.rowsHeight(rows.count))

                Color.clear.frame(height: Self.bottomPadding)
            }
        }
    }

    static func rowCount(model: StatusPanelModel) -> Int {
        rows(model: model).count
    }

    static func contentHeight(model: StatusPanelModel) -> CGFloat {
        let count = rowCount(model: model)
        guard count > 0 else { return 0 }
        return headerHeight + rowsHeight(count) + bottomPadding
    }

    static func totalCount(model: StatusPanelModel) -> Int {
        model.tasks.count
            + model.desktopThreadGroups.reduce(0) { $0 + logicalThreadCount($1) }
            + model.cliProcesses.count
    }

    static func runningCount(model: StatusPanelModel) -> Int {
        TaskStatusPresentationFormatter.runningCount(in: model.tasks)
            + model.desktopThreadGroups.reduce(0) { $0 + $1.runningCount }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(taskTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            let running = Self.runningCount(model: model)
            if running > 0 {
                Text(runningTitle(running))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: .controlAccentColor))
                    .monospacedDigit()
                    .fixedSize()
            }

            Button(action: onClearCompleted) {
                Text(clearTitle)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        Color.white.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(canClearCompleted ? 0.88 : 0.35))
            .disabled(!canClearCompleted)
            .buttonHelp(clearTitle)
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row.kind {
        case let .task(task):
            taskRow(task)
        case let .desktop(thread, depth, childCount, aggregateStatus):
            desktopRow(
                thread,
                depth: depth,
                childCount: childCount,
                aggregateStatus: aggregateStatus
            )
        case let .missingParent(group):
            missingParentRow(group)
        case let .cli(id, title, process):
            cliRow(id: id, title: title, process: process)
        }
    }

    private func taskRow(_ task: TaskStatusSnapshot) -> some View {
        let title = task.taskName
            ?? (task.isBackgroundTask ? text.backgroundTask : text.unknownTask)
        let sessionUUID = normalizedUUID(task.sessionUUID)

        return Group {
            if let sessionUUID {
                Button {
                    _ = onResumeSession(sessionUUID, false)
                } label: {
                    taskRowLabel(task, title: title)
                }
                .buttonStyle(.plain)
                .buttonHelp(resumeTitle)
            } else {
                taskRowLabel(task, title: title)
            }
        }
        .contextMenu {
            Button(resumeTitle) {
                guard let sessionUUID else { return }
                _ = onResumeSession(sessionUUID, false)
            }
            .disabled(sessionUUID == nil)

            Button(copyResumeTitle) {
                guard let sessionUUID else { return }
                _ = onResumeSession(sessionUUID, true)
            }
            .disabled(sessionUUID == nil)

            Divider()

            Button(archiveTitle) {
                onArchiveTask(task)
            }
            .disabled(!task.status.isTerminal)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title + "，" + taskStatusTitle(task.status))
        .accessibilityHint(sessionUUID == nil ? unavailableResumeTitle : resumeTitle)
    }

    private func taskRowLabel(
        _ task: TaskStatusSnapshot,
        title: String
    ) -> some View {
        HStack(spacing: 10) {
            taskStatusBadge(task.status)
            rowTitle(title, depth: 0, subtitle: relativeTime(task.startedAt))
            taskStatus(task.status)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(cardBackground)
        .contentShape(Rectangle())
    }

    private func desktopRow(
        _ thread: CodexDesktopThreadSnapshot,
        depth: Int,
        childCount: Int,
        aggregateStatus: CodexDesktopThreadStatus?
    ) -> some View {
        let canOpen = targetThreadID(thread).flatMap(UUID.init(uuidString:)) != nil
        let isRoot = depth == 0
        let status = aggregateStatus ?? thread.status

        return HStack(spacing: 10) {
            if isRoot, childCount > 0 {
                disclosureButton(thread.id, status: status)
            } else {
                desktopStatusBadge(status)
            }

            Button {
                guard canOpen else { return }
                _ = onOpenCodexThread(thread)
            } label: {
                HStack(spacing: 10) {
                    rowTitle(thread.title, depth: depth, subtitle: relativeTime(thread.lastActiveAt))
                    desktopStatus(status)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canOpen)
            .buttonHelp(canOpen ? openThreadTitle(thread) : unavailableThreadTitle)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(cardBackground)
        .accessibilityLabel(thread.title + "，" + desktopStatusTitle(aggregateStatus ?? thread.status))
        .accessibilityHint(canOpen ? openThreadTitle(thread) : unavailableThreadTitle)
    }

    private func missingParentRow(_ group: CodexDesktopThreadGroup) -> some View {
        HStack(spacing: 10) {
            if group.descendantCount > 0 {
                disclosureButton(group.id, status: .unknown)
            } else {
                desktopStatusBadge(.unknown)
            }
            rowTitle(missingParentTitle, depth: 0)
            desktopStatus(.unknown)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(cardBackground)
        .accessibilityLabel(missingParentTitle)
    }

    private func cliRow(id: String, title: String, process: CodexCLIProcess) -> some View {
        Button {
            _ = onOpenCLIProcess(id, process)
        } label: {
            HStack(spacing: 10) {
                sourceBadge(systemName: "terminal.fill", color: .orange)
                rowTitle(title, depth: 0)
                Text(cliOccupiedTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.9))
                    .fixedSize()
                    .accessibilityLabel(cliOccupiedTitle)
            }
            .padding(.horizontal, 10)
            .frame(height: Self.rowHeight)
            .background(cardBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonHelp(text.openCLIProcessHelp)
        .accessibilityLabel(title)
        .accessibilityHint(cliOccupiedTitle)
    }

    private func disclosureButton(
        _ groupID: String,
        status: CodexDesktopThreadStatus
    ) -> some View {
        let isExpanded = model.expandedDesktopThreadGroupIDs.contains(groupID)
        return Button {
            model.toggleDesktopThreadGroup(groupID)
        } label: {
            ZStack {
                Circle().fill(desktopStatusColor(status))
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .buttonHelp(isExpanded ? collapseTitle : expandTitle)
        .accessibilityValue(desktopStatusTitle(status))
    }

    private func sourceBadge(systemName: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.95))
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
        .help(text.openCLIProcessHelp)
    }

    private func taskStatusBadge(_ status: TaskExecutionStatus) -> some View {
        ZStack {
            Circle().fill(taskStatusColor(status)).frame(width: 5, height: 5)
        }
        .foregroundStyle(.white)
        .frame(width: 18, height: 18)
        .help(taskStatusTitle(status))
        .accessibilityHidden(true)
    }

    private func desktopStatusBadge(_ status: CodexDesktopThreadStatus) -> some View {
        ZStack {
            Circle().fill(desktopStatusColor(status)).frame(width: 5, height: 5)
            switch status {
            case .running:
                Circle().fill(.white).frame(width: 6, height: 6)
            case .ended:
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
            case .unknown:
                Image(systemName: "questionmark").font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 18, height: 18)
        .help(desktopStatusTitle(status))
        .accessibilityHidden(true)
    }

    private func rowTitle(_ title: String, depth: Int, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12)).foregroundStyle(.white).lineLimit(1).truncationMode(.tail).help(title)
            if let subtitle { Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.48)).lineLimit(1) }
        }.padding(.leading, CGFloat(depth) * 12).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = text.language.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: model.now)
    }

    private func taskStatus(_ status: TaskExecutionStatus) -> some View {
        Text(taskStatusTitle(status))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(taskStatusColor(status))
            .fixedSize()
    }

    private func desktopStatus(_ status: CodexDesktopThreadStatus) -> some View {
        Text(desktopStatusTitle(status))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(desktopStatusColor(status))
            .fixedSize()
    }

    private func taskStatusColor(_ status: TaskExecutionStatus) -> Color {
        switch status {
        case .running: return Color(nsColor: .controlAccentColor)
        case .done: return .green
        case .failed: return .orange
        case .interrupted: return .gray
        }
    }

    private func desktopStatusColor(_ status: CodexDesktopThreadStatus) -> Color {
        switch status {
        case .running: return Color(nsColor: .controlAccentColor)
        case .ended: return .green
        case .unknown: return .orange
        }
    }

    private var cardBackground: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var canClearCompleted: Bool {
        model.hasCompletedTasks || model.canClearCompletedSessions
    }

    private var taskTitle: String {
        let count = Self.totalCount(model: model)
        return text.language == .simplifiedChinese
            ? "Codex 任务 (\(count))"
            : "Codex Tasks (\(count))"
    }

    private func runningTitle(_ count: Int) -> String {
        text.language == .simplifiedChinese ? "\(count)运行中" : "\(count) running"
    }

    private var clearTitle: String {
        text.language == .simplifiedChinese ? "清理已完成" : "Clear completed"
    }

    private var resumeTitle: String {
        text.language == .simplifiedChinese ? "恢复任务" : "Resume task"
    }

    private var copyResumeTitle: String {
        text.language == .simplifiedChinese ? "复制恢复命令" : "Copy resume command"
    }

    private var archiveTitle: String {
        text.language == .simplifiedChinese ? "归档" : "Archive"
    }

    private var unavailableResumeTitle: String {
        text.language == .simplifiedChinese ? "没有可用的恢复会话" : "No resumable session"
    }

    private var unavailableThreadTitle: String {
        text.language == .simplifiedChinese ? "没有可打开的所属聊天" : "No conversation is available"
    }

    private var missingParentTitle: String {
        text.language == .simplifiedChinese ? "所属聊天不可用" : "Parent conversation unavailable"
    }

    private var expandTitle: String {
        text.language == .simplifiedChinese ? "展开子任务" : "Expand subtasks"
    }

    private var collapseTitle: String {
        text.language == .simplifiedChinese ? "折叠子任务" : "Collapse subtasks"
    }

    private var cliOccupiedTitle: String {
        text.language == .simplifiedChinese ? "CLI 终端占用中" : "CLI terminal occupied"
    }

    private func openThreadTitle(_ thread: CodexDesktopThreadSnapshot) -> String {
        thread.source == .subagent ? text.openParentCodexThreadHelp : text.openCodexThreadHelp
    }

    private func taskStatusTitle(_ status: TaskExecutionStatus) -> String {
        switch status {
        case .running:
            return text.language == .simplifiedChinese ? "运行中" : "Running"
        case .done:
            return text.language == .simplifiedChinese ? "已完成" : "Completed"
        case .failed:
            return text.language == .simplifiedChinese ? "失败" : "Failed"
        case .interrupted:
            return text.language == .simplifiedChinese ? "已中断" : "Interrupted"
        }
    }

    private func desktopStatusTitle(_ status: CodexDesktopThreadStatus) -> String {
        switch status {
        case .running:
            return text.language == .simplifiedChinese ? "运行中" : "Running"
        case .ended:
            return text.language == .simplifiedChinese ? "已完成" : "Completed"
        case .unknown:
            return text.language == .simplifiedChinese ? "状态未知" : "Status unknown"
        }
    }

    private func targetThreadID(_ thread: CodexDesktopThreadSnapshot) -> String? {
        switch thread.source {
        case .user: return thread.id
        case .subagent: return thread.parentThreadID
        }
    }

    private func normalizedUUID(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, UUID(uuidString: value) != nil else {
            return nil
        }
        return value
    }

    private static func rowsHeight(_ count: Int) -> CGFloat {
        let visible = min(count, visibleRowLimit)
        guard visible > 0 else { return 0 }
        return CGFloat(visible) * (rowHeight + rowSpacing) - rowSpacing
    }

    private static func logicalThreadCount(_ group: CodexDesktopThreadGroup) -> Int {
        let nodes = group.root.map { [$0] } ?? group.orphanNodes
        return nodes.reduce(0) { $0 + flattenedCount($1) }
    }

    private static func flattenedCount(_ node: CodexDesktopThreadNode) -> Int {
        1 + node.children.reduce(0) { $0 + flattenedCount($1) }
    }

    private static func rows(model: StatusPanelModel) -> [Row] {
        var rows = model.tasks.map { task in
            Row(id: "task:\(task.id)", kind: .task(task))
        }

        for group in model.desktopThreadGroups {
            let isExpanded = model.expandedDesktopThreadGroupIDs.contains(group.id)
            if let root = group.root {
                rows.append(Row(
                    id: "desktop:\(root.id)",
                    kind: .desktop(
                        root.thread,
                        depth: 0,
                        childCount: group.descendantCount,
                        aggregateStatus: aggregateStatus(in: [root])
                    )
                ))
                if isExpanded {
                    appendChildren(root.children, depth: 1, to: &rows)
                }
            } else {
                rows.append(Row(id: "missing:\(group.id)", kind: .missingParent(group)))
                if isExpanded {
                    appendChildren(group.orphanNodes, depth: 0, to: &rows)
                }
            }
        }

        for id in model.cliProcesses.keys.sorted() {
            guard let process = model.cliProcesses[id] else { continue }
            let title = model.desktopThreads.first(where: { $0.id == id })?.title
                ?? (model.cliProcesses.count == 1 ? "CLI" : "CLI \(process.pid)")
            rows.append(Row(id: "cli:\(id)", kind: .cli(id, title, process)))
        }
        return rows
    }

    private static func appendChildren(
        _ nodes: [CodexDesktopThreadNode],
        depth: Int,
        to rows: inout [Row]
    ) {
        for node in nodes {
            rows.append(Row(
                id: "desktop:\(node.id)",
                kind: .desktop(
                    node.thread,
                    depth: depth,
                    childCount: node.descendantCount,
                    aggregateStatus: nil
                )
            ))
            appendChildren(node.children, depth: depth + 1, to: &rows)
        }
    }

    private static func aggregateStatus(
        in nodes: [CodexDesktopThreadNode]
    ) -> CodexDesktopThreadStatus {
        let statuses = nodes.flatMap(allStatuses)
        if statuses.contains(.running) { return .running }
        if statuses.contains(.unknown) { return .unknown }
        return .ended
    }

    private static func allStatuses(
        _ node: CodexDesktopThreadNode
    ) -> [CodexDesktopThreadStatus] {
        [node.thread.status] + node.children.flatMap(allStatuses)
    }

    private struct Row: Identifiable {
        let id: String
        let kind: Kind

        enum Kind {
            case task(TaskStatusSnapshot)
            case desktop(
                CodexDesktopThreadSnapshot,
                depth: Int,
                childCount: Int,
                aggregateStatus: CodexDesktopThreadStatus?
            )
            case missingParent(CodexDesktopThreadGroup)
            case cli(String, String, CodexCLIProcess)
        }
    }
}
