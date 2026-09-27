import AppKit
import CodexQuotaCore
import CodexQuotaUI
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
    @Published private(set) var selectedQuotaProvider: QuotaProvider
    @Published private(set) var codexQuotaStatus = "正在读取额度…"
    @Published private(set) var codexQuotaDetail = ""
    @Published private(set) var claudeQuotaStatus = "正在读取额度…"
    @Published private(set) var claudeQuotaDetail = ""
    @Published private(set) var claudeQuotaStale = false
    @Published private(set) var codexSnapshot: QuotaSnapshot?
    @Published private(set) var claudeSnapshot: QuotaSnapshot?
    /// Island only: both providers beside the notch, one per side.
    @Published private(set) var islandDual: Bool
    @Published private(set) var islandDualLeft: QuotaProvider
    var onIslandLayoutChange: (() -> Void)?
    private let defaults: UserDefaults
    var onQuotaProviderChange: (() -> Void)?
    var onRefreshQuota: (() -> Void)?
    /// Short line shown in the panel.
    var quotaStatus: String { selectedQuotaProvider == .codex ? codexQuotaStatus : claudeQuotaStatus }
    /// Full explanation for settings and the panel line's help.
    var quotaDetail: String {
        let detail = selectedQuotaProvider == .codex ? codexQuotaDetail : claudeQuotaDetail
        return detail.isEmpty ? quotaStatus : detail
    }
    var quotaStale: Bool { selectedQuotaProvider == .claude && claudeQuotaStale }
    @Published private(set) var tasks: [TaskStatusSnapshot] = []
    @Published private(set) var desktopThreads: [CodexDesktopThreadSnapshot] = []
    @Published private(set) var desktopThreadGroups: [CodexDesktopThreadGroup] = []
    @Published private(set) var cliProcesses: [String: CodexCLIProcess] = [:]
    /// Claude Code sessions shown instead of Codex tasks while Claude is selected.
    @Published private(set) var claudeSessions: [ClaudeCodeSession] = []
    private var scannedClaudeSessions: [ClaudeCodeSession] = []
    private var hiddenClaudeSessionIDs: Set<String>
    @Published private(set) var expandedDesktopThreadGroupIDs: Set<String>
    @Published private(set) var hasCompletedTasks = false
    @Published private(set) var showsResetForecast = false
    @Published private(set) var resetCalendar: CodexResetCache?
    @Published private(set) var resetSyncFailed = false
    @Published private(set) var now = Date()
    @Published private(set) var sleepState: ManualSleepState = .off
    @Published private(set) var sleepDetail = ""
    @Published var displayMode: PanelDisplayMode = .menuBar
    @Published private(set) var scrollEnabled = false
    @Published private(set) var gesturesEnabled = false
    @Published private(set) var keyMappingCount = 0
    @Published private(set) var keyMappingEnabled = false

    var canClearCompletedSessions: Bool {
        !CodexDesktopThreadTree.clearableThreadIDs(
            in: desktopThreads, hiddenIDs: store.hiddenDesktopThreadIDs
        ).isEmpty
    }

    var onContentChange: (() -> Void)?
    var onIslandContentChange: (() -> Void)?

    func updateQuickTools(scroll: Bool, gestures: Bool, mappingCount: Int, mappingEnabled: Bool) {
        scrollEnabled = scroll
        gesturesEnabled = gestures
        keyMappingCount = mappingCount
        keyMappingEnabled = mappingEnabled
        notifyContentChange()
    }

    private let store: TaskStatusStore

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedQuotaProvider = QuotaProvider(rawValue: defaults.string(forKey: "selectedQuotaProvider") ?? "") ?? .codex
        islandDual = defaults.bool(forKey: Self.islandDualKey)
        islandDualLeft = QuotaProvider(rawValue: defaults.string(forKey: Self.islandDualLeftKey) ?? "") ?? .codex
        store = TaskStatusStore(defaults: defaults)
        expandedDesktopThreadGroupIDs = store.expandedDesktopThreadGroupIDs
        hiddenClaudeSessionIDs = Set(defaults.stringArray(forKey: Self.hiddenClaudeSessionsKey) ?? [])
    }

    private static let hiddenClaudeSessionsKey = "hiddenClaudeSessionIDs"
    private static let islandDualKey = "islandDualProviders"
    private static let islandDualLeftKey = "islandDualLeftProvider"

    func quotaSnapshot(for provider: QuotaProvider) -> QuotaSnapshot? {
        provider == .codex ? codexSnapshot : claudeSnapshot
    }

    func setIslandDual(_ value: Bool) {
        islandDual = value
        defaults.set(value, forKey: Self.islandDualKey)
        onIslandLayoutChange?()
    }

    func setIslandDualLeft(_ provider: QuotaProvider) {
        islandDualLeft = provider
        defaults.set(provider.rawValue, forKey: Self.islandDualLeftKey)
        onIslandLayoutChange?()
    }

    func swapIslandDualSides() { setIslandDualLeft(islandDualLeft == .codex ? .claude : .codex) }

    var canClearClaudeSessions: Bool { claudeSessions.contains { $0.status == .completed } }

    func updateClaudeSessions(_ sessions: [ClaudeCodeSession]) {
        scannedClaudeSessions = sessions
        // Forget hidden ids that no longer exist so the list cannot grow without bound.
        let known = hiddenClaudeSessionIDs.intersection(sessions.map(\.id))
        if known != hiddenClaudeSessionIDs { setHiddenClaudeSessionIDs(known) }
        applyClaudeSessions()
    }

    /// Hides completed sessions from this list only; Claude itself keeps them.
    func hideCompletedClaudeSessions() {
        setHiddenClaudeSessionIDs(hiddenClaudeSessionIDs.union(claudeSessions.filter { $0.status == .completed }.map(\.id)))
        applyClaudeSessions()
    }

    private func setHiddenClaudeSessionIDs(_ ids: Set<String>) {
        hiddenClaudeSessionIDs = ids
        defaults.set(ids.sorted(), forKey: Self.hiddenClaudeSessionsKey)
    }

    private func applyClaudeSessions() {
        claudeSessions = ClaudeCodeSessionParser.visible(scannedClaudeSessions, hiddenIDs: hiddenClaudeSessionIDs, limit: 10)
        notifyContentChange()
    }

    func update(snapshot: QuotaSnapshot?) {
        codexSnapshot = snapshot
        if selectedQuotaProvider == .codex { self.snapshot = snapshot }
        notifyContentChange()
    }

    func updateClaude(snapshot: QuotaSnapshot?, status: String, detail: String = "", stale: Bool = false) {
        claudeSnapshot = snapshot
        claudeQuotaStatus = status
        claudeQuotaDetail = detail
        claudeQuotaStale = stale
        if selectedQuotaProvider == .claude { self.snapshot = snapshot }
        notifyContentChange()
    }

    func updateCodexStatus(_ status: String, detail: String = "") {
        codexQuotaStatus = status
        codexQuotaDetail = detail
    }

    func selectQuotaProvider(_ provider: QuotaProvider) {
        selectedQuotaProvider = provider
        defaults.set(provider.rawValue, forKey: "selectedQuotaProvider")
        snapshot = provider == .codex ? codexSnapshot : claudeSnapshot
        notifyContentChange()
        onQuotaProviderChange?()
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

    func update(showsResetForecast: Bool) {
        self.showsResetForecast = showsResetForecast
        notifyContentChange()
    }

    func update(resetCalendar: CodexResetCache?, syncFailed: Bool = false) {
        self.resetCalendar = resetCalendar
        resetSyncFailed = syncFailed
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
            self?.onIslandContentChange?()
        }
    }
}

@MainActor
final class StatusPanelController: NSObject, NSPopoverDelegate {
    /// The menu bar keeps the compact 1.4.5 panel; the island has its own wide layout.
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
        onNodeScores: @escaping () -> Void,
        onDisplaySleep: @escaping () -> Void,
        onOpenResetAnnouncement: @escaping () -> Void,
        canResumeTaskSessions: Bool,
        onResumeSession: @escaping (String, Bool) -> TaskResumeActionResult,
        onOpenCodexThread: @escaping (CodexDesktopThreadSnapshot) -> CodexThreadOpenActionResult,
        onOpenCLIProcess: @escaping (String, CodexCLIProcess) -> CodexCLIProcessOpenActionResult,
        onArchiveTask: @escaping (TaskStatusSnapshot) -> Void,
        onClearCompletedTasks: @escaping () -> Void,
        onClearFinishedThreads: @escaping () -> Void,
        onToggleSleep: @escaping () -> Void,
        onOpenClaudeSession: @escaping (ClaudeCodeSession) -> Void
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
                onNodeScores: {
                    panelPopover.performClose(nil)
                    onNodeScores()
                },
                onDisplaySleep: {
                    panelPopover.performClose(nil)
                    onDisplaySleep()
                },
                onOpenResetAnnouncement: onOpenResetAnnouncement,
                canResumeTaskSessions: canResumeTaskSessions,
                onResumeSession: onResumeSession,
                onOpenCodexThread: onOpenCodexThread,
                onOpenCLIProcess: onOpenCLIProcess,
                onArchiveTask: onArchiveTask,
                onClearCompletedTasks: onClearCompletedTasks,
                onClearFinishedThreads: onClearFinishedThreads,
                onToggleSleep: onToggleSleep,
                onOpenClaudeSession: { session in
                    panelPopover.performClose(nil)
                    onOpenClaudeSession(session)
                }
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
