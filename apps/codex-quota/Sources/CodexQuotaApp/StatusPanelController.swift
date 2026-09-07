import AppKit
import CodexQuotaCore
import SwiftUI

enum TaskResumeActionResult: Equatable {
    case openedTerminal
    case copied
    case copiedAfterLaunchFailure
    case unavailable
}

enum CodexThreadOpenActionResult: Equatable {
    case openRequested
    case unavailable
}

enum CodexCLIProcessOpenActionResult: Equatable { case opened, unavailable }

@MainActor
final class StatusPanelModel: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var tasks: [TaskStatusSnapshot] = []
    @Published private(set) var desktopThreads: [CodexDesktopThreadSnapshot] = []
    @Published private(set) var desktopThreadGroups: [CodexDesktopThreadGroup] = []
    @Published private(set) var cliProcesses: [String: CodexCLIProcess] = [:]
    @Published private(set) var expandedDesktopThreadGroupIDs: Set<String>
    @Published private(set) var hasCompletedTasks = false
    @Published private(set) var currentResetSignal: TiboResetSignal?
    @Published private(set) var now = Date()
    @Published private(set) var sleepState: ManualSleepState = .off
    @Published private(set) var sleepDetail = ""

    var canClearCompletedSessions: Bool {
        !CodexDesktopThreadTree.clearableThreadIDs(
            in: desktopThreads, hiddenIDs: store.hiddenDesktopThreadIDs
        ).isEmpty
    }

    var onContentChange: (() -> Void)?

    private let store = TaskStatusStore()

    init() {
        expandedDesktopThreadGroupIDs = store.expandedDesktopThreadGroupIDs
    }

    func update(snapshot: QuotaSnapshot?) {
        self.snapshot = snapshot
        notifyContentChange()
    }

    func update(
        tasks: [TaskStatusSnapshot],
        desktopThreads: [CodexDesktopThreadSnapshot],
        desktopThreadGroups: [CodexDesktopThreadGroup],
        cliProcesses: [String: CodexCLIProcess],
        hasCompletedTasks: Bool
    ) {
        self.tasks = tasks
        self.desktopThreads = desktopThreads
        self.desktopThreadGroups = desktopThreadGroups
        self.cliProcesses = cliProcesses
        self.hasCompletedTasks = hasCompletedTasks
        notifyContentChange()
    }

    func toggleDesktopThreadGroup(_ id: String) {
        if expandedDesktopThreadGroupIDs.contains(id) {
            expandedDesktopThreadGroupIDs.remove(id)
        } else {
            expandedDesktopThreadGroupIDs.insert(id)
        }
        store.expandedDesktopThreadGroupIDs = expandedDesktopThreadGroupIDs
        notifyContentChange()
    }

    func update(resetSignal: TiboResetSignal?) {
        currentResetSignal = resetSignal
        notifyContentChange()
    }

    func updateSleep(state: ManualSleepState, detail: String) {
        sleepState = state
        sleepDetail = detail
        notifyContentChange()
    }

    func tick(at date: Date = Date()) {
        now = date
        notifyContentChange()
    }

    private func notifyContentChange() {
        DispatchQueue.main.async { [weak self] in
            self?.onContentChange?()
        }
    }
}

@MainActor
final class StatusPanelController: NSObject, NSPopoverDelegate {
    static let panelWidth: CGFloat = 320

    private let popover = NSPopover()
    private let hostingController: NSHostingController<StatusPanelView>
    private let model: StatusPanelModel
    private weak var statusButton: NSStatusBarButton?
    private var countdownTimer: Timer?

    init(
        model: StatusPanelModel,
        text: AppText,
        onSettingsMenu: @escaping (NSView) -> Void,
        onQuickTools: @escaping () -> Void,
        onOpenResetAnnouncement: @escaping () -> Void,
        canResumeTaskSessions: Bool,
        onResumeSession: @escaping (String, Bool) -> TaskResumeActionResult,
        onOpenCodexThread: @escaping (CodexDesktopThreadSnapshot) -> CodexThreadOpenActionResult,
        onOpenCLIProcess: @escaping (String, CodexCLIProcess) -> CodexCLIProcessOpenActionResult,
        onArchiveTask: @escaping (TaskStatusSnapshot) -> Void,
        onClearCompletedTasks: @escaping () -> Void,
        onClearFinishedThreads: @escaping () -> Void,
        onToggleSleep: @escaping () -> Void
    ) {
        self.model = model
        let panelPopover = popover
        hostingController = NSHostingController(
            rootView: StatusPanelView(
                model: model,
                text: text,
                onSettingsMenu: onSettingsMenu,
                onQuickTools: {
                    panelPopover.performClose(nil)
                    onQuickTools()
                },
                onOpenResetAnnouncement: onOpenResetAnnouncement,
                canResumeTaskSessions: canResumeTaskSessions,
                onResumeSession: onResumeSession,
                onOpenCodexThread: onOpenCodexThread,
                onOpenCLIProcess: onOpenCLIProcess,
                onArchiveTask: onArchiveTask,
                onClearCompletedTasks: onClearCompletedTasks,
                onClearFinishedThreads: onClearFinishedThreads,
                onToggleSleep: onToggleSleep
            )
        )
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = hostingController
        model.onContentChange = { [weak self] in
            self?.resizeToFit()
        }
        resizeToFit()
    }

    var isShown: Bool {
        popover.isShown
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        model.tick()
        resizeToFit()
        statusButton = button
        button.highlight(true)
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        // AppKit otherwise assigns first responder to the first toolbar button.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.popover.isShown else { return }
            self.hostingController.view.window?.makeFirstResponder(nil)
        }
        DispatchQueue.main.async { [weak self] in
            self?.resizeToFit()
        }
    }

    func close() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        stopCountdownTimer()
        statusButton?.highlight(false)
        statusButton = nil
    }

    func popoverDidShow(_ notification: Notification) {
        startCountdownTimer()
    }

    private func startCountdownTimer() {
        stopCountdownTimer()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func resizeToFit() {
        hostingController.view.frame.size.width = Self.panelWidth
        hostingController.view.layoutSubtreeIfNeeded()
        let height = ceil(hostingController.view.fittingSize.height)
        guard height.isFinite, height > 0 else {
            return
        }
        popover.contentSize = NSSize(
            width: Self.panelWidth,
            height: height
        )
    }
}
