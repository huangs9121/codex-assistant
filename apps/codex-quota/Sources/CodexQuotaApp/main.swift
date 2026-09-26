import AppKit
import CodexQuotaCore
import CodexQuotaUI
import UserNotifications

@MainActor
private final class MenuChoiceRow: NSView {
    private let checkmarkLabel = NSTextField(labelWithString: "✓")
    private let titleLabel = NSTextField(labelWithString: "")
    private let preview = NSImageView()
    private let actionButton = HelpButton()
    private let selectedAccessibilityValue: String
    private let notSelectedAccessibilityValue: String

    var isSelected = false {
        didSet {
            checkmarkLabel.isHidden = !isSelected
            actionButton.setAccessibilityValue(
                isSelected ? selectedAccessibilityValue : notSelectedAccessibilityValue
            )
        }
    }

    init(
        title: String,
        previewImage: NSImage? = nil,
        tag: Int,
        target: AnyObject,
        action: Selector,
        selectedAccessibilityValue: String,
        notSelectedAccessibilityValue: String,
        width: CGFloat
    ) {
        self.selectedAccessibilityValue = selectedAccessibilityValue
        self.notSelectedAccessibilityValue = notSelectedAccessibilityValue
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 32))

        checkmarkLabel.translatesAutoresizingMaskIntoConstraints = false
        checkmarkLabel.font = .menuFont(ofSize: 13)
        checkmarkLabel.alignment = .center

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .menuFont(ofSize: 13)

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.image = previewImage
        preview.imageScaling = .scaleNone
        preview.setAccessibilityElement(false)

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.title = ""
        actionButton.isBordered = false
        actionButton.bezelStyle = .shadowlessSquare
        actionButton.focusRingType = .exterior
        actionButton.tag = tag
        actionButton.target = target
        actionButton.action = action
        actionButton.setAccessibilityRole(.button)

        addSubview(checkmarkLabel)
        addSubview(titleLabel)
        addSubview(preview)
        addSubview(actionButton)
        NSLayoutConstraint.activate([
            checkmarkLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            checkmarkLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmarkLabel.widthAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: checkmarkLabel.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            preview.centerYAnchor.constraint(equalTo: centerYAnchor),
            preview.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            actionButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionButton.topAnchor.constraint(equalTo: topAnchor),
            actionButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateTitle(title)
        isSelected = false
    }

    func updateTitle(_ title: String) {
        titleLabel.stringValue = title
        actionButton.setAccessibilityLabel(title)
        actionButton.toolTip = title
    }

    func setWarning(_ showsWarning: Bool) {
        preview.image = showsWarning ? NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        ) : nil
        preview.contentTintColor = showsWarning ? .systemOrange : nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate,
    @preconcurrency UNUserNotificationCenterDelegate
{
    private let language = AppLanguage.current
    private lazy var text = AppText(language: language)
    private var menuWidth: CGFloat {
        language == .simplifiedChinese ? 260 : 340
    }
    private let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
    )
    private var preferences = DisplayPreferences(defaults: .standard)
    private let renderer = BatteryStatusRenderer()
    private let settingsMenu = NSMenu()
    private let panelModel = StatusPanelModel()
    private let sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)
    private let refreshQueue = DispatchQueue(
        label: "CodexQuota.refresh",
        qos: .utility
    )
    private var styleItems: [BatteryStyle: NSMenuItem] = [:]
    private var identityItems: [StatusIdentityMode: NSMenuItem] = [:]
    private var panelModeItems: [PanelDisplayMode: NSMenuItem] = [:]
    private var resetForecastToggleItem: NSMenuItem?
    private var resetToggleItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var isChangingTaskSleep = false
    private var updateMenuItem: NSMenuItem?
    private var currentSnapshot: QuotaSnapshot?
    private var refreshTimer: Timer?
    private var updatePolicyTimer: Timer?
    private var resetMonitorTimer: Timer?
    private var accessibilityPermissionTimer: Timer?
    private var availableRelease: GitHubRelease?
    private var currentResetCalendar: CodexResetCache?
    private var resetNotificationsInFlight: Set<String> = []
    private var isRefreshing = false
    private var isUpdateCheckInFlight = false
    private var isUpdateInstallInFlight = false
    private var isResetMonitorInFlight = false
    private let updateController = GitHubUpdateController()
    private let automaticUpdateInstaller = AutomaticUpdateInstaller()
    private let resetMonitorController = CodexResetMonitorController()
    private let launchAtLoginController = LaunchAtLoginController()
    private let displaySleepController = DisplaySleepController()
    private lazy var taskSleepController = TaskSleepController(language: language)
    private let mouseScrollReversalController = MouseScrollReversalController()
    private let mouseGestureController = MouseGestureController()
    private let doubleCommandTapController = DoubleCommandTapController()
    private lazy var codexInvocationSettingsPanelController = CodexInvocationSettingsPanelController(
        text: text,
        doubleCommandTapController: doubleCommandTapController,
        onEnabledChanged: { [weak self] isEnabled in
            self?.setDoubleCommandTapEnabled(isEnabled)
        },
        onGestureSaved: { [weak self] in
            self?.doubleCommandTapController.reloadGesture()
            self?.syncMenuState()
        },
        onPermissionRefresh: { [weak self] in
            self?.refreshAccessibilityControllers()
        }
    )
    private lazy var mouseGestureSettingsPanelController = MouseGestureSettingsPanelController(
        text: text,
        controller: mouseGestureController,
        onRulesChanged: { [weak self] in
            self?.refreshAccessibilityControllers()
            self?.syncMenuState()
        }
    )
    private lazy var quickToolsPanelController = QuickToolsPanelController(
        text: text,
        mouseScrollReversalController: mouseScrollReversalController,
        codexInvocationSettingsController: codexInvocationSettingsPanelController,
        mouseGestureSettingsController: mouseGestureSettingsPanelController,
        onScrollReversalEnabledChanged: { [weak self] isEnabled in
            self?.setMouseScrollReversalEnabled(isEnabled)
        }
    )
    private let rateLimitController = CodexRateLimitController()
    private lazy var onboardingController: OnboardingWindowController = OnboardingWindowController(
        snapshot: { [weak self] in
            guard let self else { return .init() }
            return .init(
                accessibilityTrusted: mouseScrollReversalController.isAccessibilityTrusted,
                inputMonitoringTrusted: doubleCommandTapController.isInputMonitoringTrusted,
                scrollReversal: .init(enabled: mouseScrollReversalController.isEnabled,
                                      running: mouseScrollReversalController.isRunning),
                rightClickGesture: .init(enabled: mouseGestureController.preferences.isEnabled,
                                         running: mouseGestureController.isRunning),
                keyMapping: .init(enabled: doubleCommandTapController.isEnabled,
                                  running: doubleCommandTapController.isRunning))
        },
        setFeatureEnabled: { [weak self] feature, enabled in
            self?.setOnboardingFeature(feature, enabled: enabled)
        },
        openSettings: { [weak self] feature in
            guard let self else { return }
            let page: QuickToolsPanelController.Page
            switch feature {
            case .scrollReversal: page = .scrollReversal
            case .rightClickGesture: page = .rightClickGesture
            case .keyMapping: page = .globalShortcut
            case nil: page = .general
            }
            quickToolsPanelController.show(page: page)
        },
        requestAccessibility: { [weak self] in self?.mouseScrollReversalController.requestAccessibilityPermission() },
        requestInputMonitoring: { [weak self] in self?.doubleCommandTapController.requestInputMonitoringPermission() }
    )
    private let claudeUsageController = ClaudeUsageController()
    private var lastClaudeCheck: Date?
    private var isRefreshingClaude = false
    private var isScanningClaudeSessions = false
    private let nodeScoreWindowController = NodeScoreWindowController()
    private let taskStatusController = TaskStatusController()
    private lazy var panelController = StatusPanelController(
        model: panelModel,
        text: text,
        onSettingsMenu: { [weak self] view in
            self?.showSettingsMenu(relativeTo: view)
        },
        onQuickTools: { [weak self] in
            self?.quickToolsPanelController.show()
        },
        onNodeScores: { [weak self] in self?.nodeScoreWindowController.show() },
        onDisplaySleep: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do { try await displaySleepController.start() }
                catch { showAlert(message: "熄屏未完成", informativeText: error.localizedDescription) }
            }
        },
        onOpenResetAnnouncement: { [weak self] in
            self?.openCurrentResetAnnouncement()
        },
        canResumeTaskSessions: TaskStatusController.codexExecutableURL() != nil,
        onResumeSession: { [weak self] sessionUUID, copyOnly in
            self?.resumeTaskSession(
                sessionUUID: sessionUUID,
                copyOnly: copyOnly
            ) ?? .copiedAfterLaunchFailure
        },
        onOpenCodexThread: { [weak self] thread in
            self?.openCodexThread(thread) ?? .unavailable
        },
        onOpenCLIProcess: { [weak self] id, process in
            self?.openCLIProcess(id: id, process: process) ?? .unavailable
        },
        onArchiveTask: { [weak self] task in
            self?.archiveTask(task)
        },
        onClearCompletedTasks: { [weak self] in self?.confirmClearCompletedTasks() },
        onClearFinishedThreads: {},
        onToggleSleep: { [weak self] in
            self?.toggleTaskSleep()
        },
        onOpenClaudeSession: { [weak self] in self?.openClaudeSession($0) }
    )

    private lazy var notchController: NotchPanelController = NotchPanelController(model: panelModel, text: text, actions: NotchActions(
        settings: { [weak self] view in
            self?.showSettingsMenu(relativeTo: view)
        },
        quickTools: { [weak self] in self?.notchController.collapse(); self?.quickToolsPanelController.show() },
        openTasks: { [weak self] in self?.openTasksApplication() },
        scroll: { [weak self] in
            guard let self else { return }
            setMouseScrollReversalEnabled(!mouseScrollReversalController.isRunning)
        },
        gestures: { [weak self] in self?.notchController.collapse(); self?.quickToolsPanelController.show(pageIndex: 2) },
        mappings: { [weak self] in self?.notchController.collapse(); self?.quickToolsPanelController.show(pageIndex: 1) },
        sleep: { [weak self] in self?.toggleTaskSleep() },
        reset: { [weak self] in self?.openCurrentResetAnnouncement() },
        mode: { [weak self] in self?.setPanelDisplayMode($0) },
        resume: { [weak self] uuid, copy in self?.resumeTaskSession(sessionUUID: uuid, copyOnly: copy) ?? .unavailable },
        thread: { [weak self] in self?.openCodexThread($0) ?? .unavailable },
        cli: { [weak self] id, process in self?.openCLIProcess(id: id, process: process) ?? .unavailable },
        archive: { [weak self] in self?.archiveTask($0) },
        clear: { [weak self] in self?.confirmClearCompletedTasks() },
        claude: { [weak self] in self?.openClaudeSession($0) }
    ))

    private func setPanelDisplayMode(_ mode: PanelDisplayMode, reveal: Bool = true) {
        preferences.panelDisplayMode = mode
        panelModel.displayMode = mode
        panelController.close()
        notchController.setEnabled(mode == .island, expand: reveal && mode == .island)
        statusItem.isVisible = mode == .menuBar
        if reveal, mode == .menuBar, let button = statusItem.button {
            DispatchQueue.main.async { [weak self] in self?.panelController.toggle(relativeTo: button) }
        }
    }

    /// Verification flag: right after launch the status item has no on-screen frame yet, so a
    /// popover anchored to it would not appear. Retry for a few seconds until it is placed.
    private func showPanelWhenStatusItemIsPlaced(attempt: Int = 0) {
        guard let button = statusItem.button else { return }
        if let window = button.window, window.frame.width > 0, window.frame.height > 0 {
            panelController.toggle(relativeTo: button)
        } else if attempt < 12 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.showPanelWhenStatusItemIsPlaced(attempt: attempt + 1)
            }
        }
    }

    private func openTasksApplication() {
        notchController.collapse()
        let claude = panelModel.selectedQuotaProvider == .claude
        let bundleID = claude ? "com.anthropic.claudefordesktop" : "com.openai.codex"
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            let name = claude ? "Claude" : "Codex"
            showAlert(message: language == .simplifiedChinese ? "未找到 \(name) 应用" : "\(name) is not installed")
            return
        }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The task list shows one source at a time, so Claude sessions are scanned only while Claude is selected.
    private func refreshClaudeSessions() {
        guard panelModel.selectedQuotaProvider == .claude, !isScanningClaudeSessions else { return }
        isScanningClaudeSessions = true
        Task { @MainActor [weak self] in
            let sessions = await Task.detached(priority: .utility) { ClaudeSessionScanner.scan() }.value
            guard let self else { return }
            isScanningClaudeSessions = false
            panelModel.updateClaudeSessions(sessions)
        }
    }

    private func openClaudeSession(_ session: ClaudeCodeSession) {
        notchController.collapse()
        let cn = language == .simplifiedChinese
        switch session.origin {
        case .desktop(let id):
            // Claude Desktop's own deep link, also used by its Dock menu and Spotlight.
            if let url = ClaudeCodeSessionParser.openURL(forDesktopSession: id), NSWorkspace.shared.open(url) { return }
            showAlert(message: cn ? "未能在 Claude 中打开这个会话。" : "Could not open this session in Claude.")
        case .terminal(let process):
            if let tty = process.tty, activateTerminalTab(tty) { return }
            if activateOwningApplication(for: process) { return }
            showAlert(message: cn ? "这个 Claude Code 终端会话已结束，或不在“终端”中。" : "This Claude Code terminal session has ended or is not in Terminal.")
        }
    }

    private func confirmClearCompletedClaudeSessions() {
        guard confirmClear(
            title: "清理已完成的 Claude 会话？",
            detail: "只从趁手的列表中隐藏，不会归档或删除 Claude 里的会话；运行中的会话仍会显示。",
            skipKey: "skipClearClaudeSessionsConfirmation"
        ) else { return }
        panelModel.hideCompletedClaudeSessions()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        taskSleepController.onChange = { [weak self] in
            guard let self else { return }
            syncMenuState()
            panelModel.updateSleep(
                state: taskSleepController.manualState,
                detail: taskSleepController.statusDescription
            )
        }
        taskSleepController.resetOnLaunch()
        panelModel.update(showsResetForecast: preferences.showsResetForecast)
        currentResetCalendar = preferences.resetCalendarCache
        panelModel.update(resetCalendar: currentResetCalendar)
        configureStatusItem()
        configureUnifiedSettings()
        setPanelDisplayMode(CommandLine.arguments.contains("--show-island") ? .island : preferences.panelDisplayMode,
                            reveal: CommandLine.arguments.contains("--show-island"))
        refreshAccessibilityControllers()
        refresh()
        let timer = Timer(
            timeInterval: 15,
            target: self,
            selector: #selector(refreshFromTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        let accessibilityTimer = Timer(
            timeInterval: 2,
            target: self,
            selector: #selector(refreshAccessibilityPermissionFromTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(accessibilityTimer, forMode: .common)
        accessibilityPermissionTimer = accessibilityTimer
        preferences.hasShownAutoRefreshNotice = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if CommandLine.arguments.contains("--show-onboarding") { onboardingController.show() }
            else { onboardingController.showIfNeeded() }
        }
        checkForUpdatesAutomatically()
        let updateTimer = Timer(
            timeInterval: 3_600,
            target: self,
            selector: #selector(checkForUpdatesFromTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(updateTimer, forMode: .common)
        updatePolicyTimer = updateTimer

        configureResetNotifications()
        checkResetCalendar()
        let resetTimer = Timer(
            timeInterval: CodexResetFeed.pollInterval,
            target: self,
            selector: #selector(checkResetCalendarFromTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(resetTimer, forMode: .common)
        resetMonitorTimer = resetTimer
        if CommandLine.arguments.contains("--show-quick-tools") {
            DispatchQueue.main.async { [weak self] in self?.quickToolsPanelController.show() }
        }
        if CommandLine.arguments.contains("--show-panel") {
            setPanelDisplayMode(.menuBar, reveal: false)
            showPanelWhenStatusItemIsPlaced()
        }
        if CommandLine.arguments.contains("--show-node-scores") {
            DispatchQueue.main.async { [weak self] in self?.nodeScoreWindowController.show() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchController.setEnabled(false)
        displaySleepController.stop()
        taskSleepController.stop()
        refreshTimer?.invalidate()
        updatePolicyTimer?.invalidate()
        resetMonitorTimer?.invalidate()
        accessibilityPermissionTimer?.invalidate()
        updateController.invalidate()
        automaticUpdateInstaller.invalidate()
        resetMonitorController.invalidate()
        rateLimitController.invalidate()
        taskStatusController.invalidate()
        mouseScrollReversalController.stop()
        mouseGestureController.stop()
        doubleCommandTapController.stop()
    }

    private func configureStatusItem() {
        updateStatusPresentation()
        configureSettingsMenu()
        guard let button = statusItem.button else {
            return
        }
        button.installButtonHelp(language == .simplifiedChinese ? "查看额度与 Codex 任务" : "View quotas and Codex tasks")
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureSettingsMenu() {
        settingsMenu.removeAllItems()
        settingsMenu.delegate = self
        let settings = NSMenuItem(title: "设置…", action: #selector(openUnifiedSettings), keyEquivalent: ",")
        settings.target = self
        settingsMenu.addItem(settings)
        settingsMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出趁手", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        settingsMenu.addItem(quitItem)
    }

    private func configureUnifiedSettings() {
        var actions = QuickToolsPanelController.SettingsActions()
        actions.setLaunchAtLogin = { [weak self] in self?.setLaunchAtLogin($0) }
        actions.setDisplayMode = { [weak self] in self?.setPanelDisplayMode($0 == 0 ? .island : .menuBar, reveal: false) }
        actions.setManualSleep = { [weak self] desired in
            guard let self, desired != taskSleepController.isEnabled else { return }
            toggleTaskSleep()
        }
        actions.setQuotaProvider = { [weak self] in self?.panelModel.selectQuotaProvider($0 == 0 ? .codex : .claude) }
        actions.setBatteryStyle = { [weak self] index in
            guard let self, BatteryStyle.allCases.indices.contains(index) else { return }
            preferences.batteryStyle = BatteryStyle.allCases[index]; updateStatusPresentation()
        }
        actions.setIdentityStyle = { [weak self] index in
            guard let self, StatusIdentityMode.allCases.indices.contains(index) else { return }
            preferences.identityMode = StatusIdentityMode.allCases[index]; updateStatusPresentation()
        }
        actions.setResetCountdown = { [weak self] enabled in
            self?.preferences.showsResetCountdownInStatusBar = enabled; self?.updateStatusPresentation()
        }
        actions.setResetForecast = { [weak self] enabled in
            self?.preferences.showsResetForecast = enabled; self?.panelModel.update(showsResetForecast: enabled)
        }
        actions.openNodeScores = { [weak self] in self?.nodeScoreWindowController.show() }
        actions.openResetCalendar = { [weak self] in self?.openResetCalendar() }
        actions.openDisplaySleep = { [weak self] in self?.startDisplaySleep() }
        actions.refreshQuota = { [weak self] in self?.refreshQuotaManually() }
        actions.quit = { NSApp.terminate(nil) }
        actions.checkUpdates = { [weak self] in self?.checkForUpdatesManually() }
        actions.showOnboarding = { [weak self] in self?.onboardingController.show() }
        actions.onClose = { [weak self] in self?.onboardingController.resumeAfterSettings() }
        quickToolsPanelController.configureSettings(stateProvider: { [weak self] in
            guard let self else { return .init() }
            var state = QuickToolsPanelController.SettingsState()
            state.launchAtLogin = launchAtLoginController.state == .enabled
            state.displayModeIndex = preferences.panelDisplayMode == .island ? 0 : 1
            state.manualSleepEnabled = taskSleepController.isEnabled
            state.quotaProviderIndex = panelModel.selectedQuotaProvider == .codex ? 0 : 1
            state.batteryStyleIndex = BatteryStyle.allCases.firstIndex(of: preferences.batteryStyle) ?? 0
            state.identityStyleIndex = StatusIdentityMode.allCases.firstIndex(of: preferences.identityMode) ?? 0
            state.showsResetCountdown = preferences.showsResetCountdownInStatusBar
            state.showsResetForecast = preferences.showsResetForecast
            state.manualSleepDetail = taskSleepController.statusDescription
            state.quotaStatus = panelModel.quotaDetail.isEmpty
                ? "\(panelModel.selectedQuotaProvider.title) 额度已同步。" : panelModel.quotaDetail
            state.launchAtLoginDetail = launchAtLoginController.state == .requiresApproval ? "请在系统登录项中允许趁手启动。" : "登录 Mac 后自动运行趁手。"
            state.version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.4.5"
            return state
        }, actions: actions)
        panelModel.onQuotaProviderChange = { [weak self] in
            self?.updateStatusPresentation()
            self?.quickToolsPanelController.refreshSettings()
            self?.refreshClaudeSessions()
        }
        panelModel.onRefreshQuota = { [weak self] in self?.refreshQuotaManually() }
        let appMenu = NSMenu()
        let root = NSMenuItem(); appMenu.addItem(root)
        root.submenu = settingsMenu
        NSApp.mainMenu = appMenu
    }

    @objc private func openUnifiedSettings() {
        notchController.collapse(); panelController.close(); quickToolsPanelController.show()
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            panelController.close()
            syncMenuState()
            if let event = NSApp.currentEvent {
                NSMenu.popUpContextMenu(
                    settingsMenu,
                    with: event,
                    for: sender
                )
            }
            return
        }
        panelController.toggle(relativeTo: sender)
    }

    private func showSettingsMenu(relativeTo view: NSView) {
        openUnifiedSettings()
    }

    @objc private func selectPanelMode(_ sender: NSMenuItem) {
        guard PanelDisplayMode.allCases.indices.contains(sender.tag) else { return }
        settingsMenu.cancelTracking()
        setPanelDisplayMode(PanelDisplayMode.allCases[sender.tag])
    }
    @objc private func openResetCalendar() { NSWorkspace.shared.open(CodexResetFeed.calendarURL) }
    @objc private func openResetSource() { NSWorkspace.shared.open(URL(string: "https://x.com/thsottiaux")!) }
    @objc private func openNodeScores() { notchController.collapse(); panelController.close(); nodeScoreWindowController.show() }
    @objc private func startDisplaySleep() {
        notchController.collapse(); panelController.close()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await displaySleepController.start() }
            catch { showAlert(message: "熄屏未完成", informativeText: error.localizedDescription) }
        }
    }

    private func makeStyleItem(_ style: BatteryStyle) -> NSMenuItem {
        let preview = renderer.presentation(
            style: style,
            remainingPercent: 60,
            identityMode: .hidden,
            compactReset: nil,
            language: language
        ).image
        preview.isTemplate = true
        return makeChoiceItem(
            title: style.menuTitle(language: language),
            previewImage: preview,
            tag: BatteryStyle.allCases.firstIndex(of: style) ?? 0,
            action: #selector(selectBatteryStyle(_:))
        )
    }

    private func taskDisplayName(_ task: TaskStatusSnapshot) -> String {
        task.taskName
            ?? (task.isBackgroundTask ? text.backgroundTask : text.unknownTask)
    }

    private func taskTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func makeIdentityItem(_ mode: StatusIdentityMode) -> NSMenuItem {
        let preview: NSImage?
        switch mode {
        case .text:
            preview = textIdentityPreview()
        case .logo:
            preview = OpenAILogoRenderer.image()
        case .hidden:
            preview = nil
        }
        return makeChoiceItem(
            title: mode.menuTitle(language: language),
            previewImage: preview,
            tag: StatusIdentityMode.allCases.firstIndex(of: mode) ?? 0,
            action: #selector(selectIdentityMode(_:))
        )
    }

    private func makeChoiceItem(
        title: String,
        previewImage: NSImage? = nil,
        tag: Int,
        action: Selector
    ) -> NSMenuItem {
        let row = MenuChoiceRow(
            title: title,
            previewImage: previewImage,
            tag: tag,
            target: self,
            action: action,
            selectedAccessibilityValue: text.selected,
            notSelectedAccessibilityValue: text.notSelected,
            width: menuWidth
        )
        let item = NSMenuItem()
        item.view = row
        return item
    }

    private func textIdentityPreview() -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor
        ]
        let text = NSAttributedString(string: "Codex", attributes: attributes)
        let size = text.size()
        let image = NSImage(size: NSSize(width: ceil(size.width), height: 18), flipped: false) { _ in
            text.draw(at: NSPoint(x: 0, y: floor((18 - size.height) / 2)))
            return true
        }
        image.isTemplate = true
        return image
    }

    private func syncMenuState() {
        quickToolsPanelController.refreshSettings()
        for (mode, item) in panelModeItems { item.state = mode == preferences.panelDisplayMode ? .on : .off }
        panelModel.updateQuickTools(scroll: mouseScrollReversalController.isRunning,
            gestures: mouseGestureController.isRunning,
            mappingCount: doubleCommandTapController.rules.filter { $0.isEnabled && $0.isComplete }.count,
            mappingEnabled: doubleCommandTapController.isEnabled)
        let selectedStyle = preferences.batteryStyle
        for (style, item) in styleItems {
            let selected = style == selectedStyle
            item.state = selected ? .on : .off
            (item.view as? MenuChoiceRow)?.isSelected = selected
        }

        let selectedIdentity = preferences.identityMode
        for (mode, item) in identityItems {
            let selected = mode == selectedIdentity
            item.state = selected ? .on : .off
            (item.view as? MenuChoiceRow)?.isSelected = selected
        }

        let showsReset = preferences.showsResetCountdownInStatusBar
        resetToggleItem?.state = showsReset ? .on : .off
        (resetToggleItem?.view as? MenuChoiceRow)?.isSelected = showsReset

        let showsForecast = preferences.showsResetForecast
        resetForecastToggleItem?.state = showsForecast ? .on : .off
        (resetForecastToggleItem?.view as? MenuChoiceRow)?.isSelected = showsForecast

        let launchState = launchAtLoginController.state
        let launchTitle: String
        let launchSelected: Bool
        switch launchState {
        case .enabled:
            launchTitle = text.launchAtLogin
            launchSelected = true
        case .disabled:
            launchTitle = text.launchAtLogin
            launchSelected = false
        case .requiresApproval:
            launchTitle = text.launchAtLoginApproval
            launchSelected = false
        case .unavailable:
            launchTitle = text.launchAtLoginUnavailable
            launchSelected = false
        }
        launchAtLoginItem?.state = launchSelected ? .on : .off
        (launchAtLoginItem?.view as? MenuChoiceRow)?.isSelected = launchSelected
        (launchAtLoginItem?.view as? MenuChoiceRow)?.updateTitle(launchTitle)

        if isUpdateInstallInFlight {
            updateMenuItem?.title = text.downloadingUpdate
            updateMenuItem?.isEnabled = false
        } else if let version = availableRelease?.eligibleVersion {
            updateMenuItem?.title = text.newVersionAvailable(canonicalVersion(version))
            updateMenuItem?.isEnabled = true
        } else {
            updateMenuItem?.title = text.checkForUpdates
            updateMenuItem?.isEnabled = true
        }
    }

    private func updateStatusPresentation() {
        let now = Date()
        let selectedSnapshot = panelModel.snapshot
        let effectiveReset = selectedSnapshot?.resetDate(at: now)
        let compactReset = preferences.showsResetCountdownInStatusBar
            ? ResetCountdownFormatter.compactString(
                resetsAt: effectiveReset,
                now: now,
                language: language
            )
            : nil
        let presentation = renderer.presentation(
            style: preferences.batteryStyle,
            remainingPercent: selectedSnapshot?.remainingPercent(at: now),
            identityMode: preferences.identityMode,
            compactReset: compactReset,
            provider: panelModel.selectedQuotaProvider,
            language: language
        )
        statusItem.button?.image = presentation.image
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.setAccessibilityLabel(
            presentation.accessibilityLabel
                + text.accessibilityStyle(
                    preferences.batteryStyle.menuTitle(language: language)
                )
        )
    }

    @objc private func selectBatteryStyle(_ sender: NSButton) {
        guard BatteryStyle.allCases.indices.contains(sender.tag) else {
            return
        }
        preferences.batteryStyle = BatteryStyle.allCases[sender.tag]
        syncMenuState()
        updateStatusPresentation()
    }

    @objc private func selectIdentityMode(_ sender: NSButton) {
        guard StatusIdentityMode.allCases.indices.contains(sender.tag) else {
            return
        }
        preferences.identityMode = StatusIdentityMode.allCases[sender.tag]
        syncMenuState()
        updateStatusPresentation()
    }

    @objc private func toggleResetCountdown(_ sender: NSButton) {
        preferences.showsResetCountdownInStatusBar.toggle()
        syncMenuState()
        updateStatusPresentation()
    }

    @objc private func toggleResetForecast(_ sender: NSButton) {
        preferences.showsResetForecast.toggle()
        panelModel.update(showsResetForecast: preferences.showsResetForecast)
        syncMenuState()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        switch launchAtLoginController.state {
        case .enabled:
            setLaunchAtLogin(false)
        case .disabled:
            guard confirmLaunchOutsideApplicationsIfNeeded() else {
                syncMenuState()
                return
            }
            setLaunchAtLogin(true)
        case .requiresApproval:
            closeMenuForLaunchAtLoginInteraction()
            launchAtLoginController.openSystemSettings()
            syncMenuState()
        case .unavailable:
            closeMenuForLaunchAtLoginInteraction()
            showAlert(
                message: text.launchUnavailableMessage,
                informativeText: text.unavailableRetry
            )
            syncMenuState()
        }
    }

    private func toggleTaskSleep() {
        guard !isChangingTaskSleep else { return }
        settingsMenu.cancelTracking()
        let enable = !taskSleepController.isEnabled
        if enable {
            let alert = NSAlert()
            alert.messageText = text.taskSleepConfirm
            alert.informativeText = text.taskSleepExplanation
            alert.addButton(withTitle: text.enabled)
            alert.addButton(withTitle: language == .simplifiedChinese ? "取消" : "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runWithButtonHelp() == .alertFirstButtonReturn else { return }
        }
        isChangingTaskSleep = true
        Task { [weak self] in
            guard let self else { return }
            defer {
                isChangingTaskSleep = false
                syncMenuState()
            }
            do {
                try await taskSleepController.setEnabled(enable)
                refreshTaskStatuses()
            } catch {
                showAlert(message: text.taskSleepFailed, informativeText: error.localizedDescription)
            }
        }
    }

    private func setMouseScrollReversalEnabled(_ isEnabled: Bool) {
        mouseScrollReversalController.isEnabled = isEnabled
        if isEnabled,
           !mouseScrollReversalController.startIfPermitted() {
            mouseScrollReversalController.requestAccessibilityPermission()
        } else if !isEnabled {
            mouseScrollReversalController.stop()
        }
        syncMenuState()
    }

    // Choosing first-use preferences does not itself request system permissions.
    private func setOnboardingFeature(_ feature: OnboardingWindowController.Feature, enabled: Bool) {
        switch feature {
        case .scrollReversal:
            mouseScrollReversalController.isEnabled = enabled
            if enabled { _ = mouseScrollReversalController.startIfPermitted() }
            else { mouseScrollReversalController.stop() }
        case .rightClickGesture:
            var settings = mouseGestureController.preferences
            settings.isEnabled = enabled
            settings.save(to: .standard)
            mouseGestureController.reloadRules()
            if enabled { _ = mouseGestureController.startIfPermitted() }
            else { mouseGestureController.stop() }
        case .keyMapping:
            doubleCommandTapController.isEnabled = enabled
            if enabled { _ = doubleCommandTapController.startIfPermitted() }
            else { doubleCommandTapController.stop() }
        }
        syncMenuState()
    }

    private func setDoubleCommandTapEnabled(_ isEnabled: Bool) {
        doubleCommandTapController.isEnabled = isEnabled
        if isEnabled,
           !doubleCommandTapController.startIfPermitted() {
            doubleCommandTapController.requestInputMonitoringPermission()
            doubleCommandTapController.requestAccessibilityPermission()
        } else if !isEnabled {
            doubleCommandTapController.stop()
        }
        syncMenuState()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
            syncMenuState()
            if enabled, launchAtLoginController.state == .requiresApproval {
                closeMenuForLaunchAtLoginInteraction()
                launchAtLoginController.openSystemSettings()
            }
        } catch {
            closeMenuForLaunchAtLoginInteraction()
            showAlert(
                message: enabled ? text.cannotEnableLaunch : text.cannotDisableLaunch,
                informativeText: text.checkLoginItems
            )
            syncMenuState()
        }
    }

    private func confirmLaunchOutsideApplicationsIfNeeded() -> Bool {
        guard !Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            return true
        }
        closeMenuForLaunchAtLoginInteraction()
        activateApp()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = text.moveToApplications
        alert.addButton(withTitle: text.enableAnyway)
        alert.addButton(withTitle: text.cancel)
        return alert.runWithButtonHelp() == .alertFirstButtonReturn
    }

    private func closeMenuForLaunchAtLoginInteraction() {
        settingsMenu.cancelTracking()
        panelController.close()
    }

    private func refreshAccessibilityControllers() {
        if mouseScrollReversalController.isEnabled,
           !mouseScrollReversalController.isRunning {
            _ = mouseScrollReversalController.startIfPermitted()
        }
        if doubleCommandTapController.isEnabled,
           !doubleCommandTapController.isRunning {
            _ = doubleCommandTapController.startIfPermitted()
        }
        if mouseGestureController.preferences.isEnabled,
           mouseGestureController.hasEnabledRules,
           !mouseGestureController.isRunning {
            _ = mouseGestureController.startIfPermitted()
        }
    }

    @objc private func refreshFromTimer() {
        refresh()
    }

    @objc private func refreshAccessibilityPermissionFromTimer() {
        refreshAccessibilityControllers()
        // Fast completion detection is needed only while holding a sleep assertion.
        // Otherwise, task scans retain the normal 15-second refresh cadence.
        if displaySleepController.isActive {
            refreshTaskStatuses()
        }
        syncMenuState()
    }

    @objc private func checkForUpdatesFromTimer() {
        checkForUpdatesAutomatically()
    }

    @objc private func checkResetCalendarFromTimer() {
        checkResetCalendar()
    }

    private func checkForUpdatesAutomatically() {
        guard let currentVersion = currentAppVersion() else {
            return
        }
        performUpdateCheck(currentVersion: currentVersion, manual: false)
    }

    @objc private func checkForUpdatesManually() {
        guard !isUpdateInstallInFlight else {
            showAlert(message: text.downloadingUpdate)
            return
        }
        guard !isUpdateCheckInFlight else {
            showAlert(message: text.checkingUpdates)
            return
        }
        if let availableRelease {
            showUpdateAlert(for: availableRelease)
            return
        }
        guard let currentVersion = currentAppVersion() else {
            showAlert(
                message: text.cannotCheckUpdates,
                informativeText: text.invalidVersion
            )
            return
        }
        performUpdateCheck(currentVersion: currentVersion, manual: true)
    }

    private func performUpdateCheck(currentVersion: SemanticVersion, manual: Bool) {
        guard !isUpdateCheckInFlight else {
            if manual {
                showAlert(message: text.checkingUpdates)
            }
            return
        }
        if !manual, !UpdatePolicy.shouldAutomaticallyCheck(
            lastSuccess: preferences.lastUpdateCheckSuccess,
            lastFailure: preferences.lastUpdateCheckFailure,
            now: Date()
        ) {
            return
        }
        isUpdateCheckInFlight = true
        updateController.check(currentVersion: currentVersion, manual: manual) { [weak self] result in
            self?.isUpdateCheckInFlight = false
            self?.handleUpdateResult(result, manual: manual)
        }
    }

    private func handleUpdateResult(_ result: GitHubUpdateController.Result, manual: Bool) {
        switch result {
        case let .update(release):
            availableRelease = release
            syncMenuState()
            guard let version = release.eligibleVersion else {
                if manual {
                    showAlert(
                        message: text.cannotCheckUpdates,
                        informativeText: text.updateFailed
                    )
                }
                return
            }
            if manual || UpdatePolicy.shouldPrompt(
                version: version,
                lastPromptedVersion: preferences.lastPromptedVersion
            ) {
                preferences.lastPromptedVersion = canonicalVersion(version)
                showUpdateAlert(for: release)
            }
        case .current:
            if manual {
                showAlert(message: text.upToDate)
            }
        case .failure:
            if manual {
                showAlert(message: text.updateFailed)
            }
        }
    }

    private func showUpdateAlert(for release: GitHubRelease) {
        guard let version = release.eligibleVersion else {
            return
        }
        preferences.lastPromptedVersion = canonicalVersion(version)
        settingsMenu.cancelTracking()
        panelController.close()
        activateApp()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = text.foundNewVersion(canonicalVersion(version))
        alert.informativeText = releaseNotes(release.body)
        let canInstallAutomatically = release.eligibleUpdateAsset != nil
        alert.addButton(
            withTitle: canInstallAutomatically ? text.installUpdate : text.goToUpdate
        )
        alert.addButton(withTitle: text.later)
        if alert.runWithButtonHelp() == .alertFirstButtonReturn {
            if canInstallAutomatically {
                beginAutomaticUpdate(release)
            } else if !NSWorkspace.shared.open(release.htmlURL) {
                showAlert(message: text.cannotOpenUpdate)
            }
        }
    }

    private func beginAutomaticUpdate(_ release: GitHubRelease) {
        guard
            !isUpdateInstallInFlight,
            let currentVersion = currentAppVersion(),
            release.eligibleUpdateAsset != nil
        else {
            showAutomaticUpdateFailure(for: release)
            return
        }
        isUpdateInstallInFlight = true
        syncMenuState()
        automaticUpdateInstaller.install(
            release: release,
            currentVersion: currentVersion,
            currentAppURL: Bundle.main.bundleURL
        ) { [weak self] result in
            guard let self else {
                return
            }
            isUpdateInstallInFlight = false
            syncMenuState()
            switch result {
            case .restarting:
                NSApp.terminate(nil)
            case .failure:
                showAutomaticUpdateFailure(for: release)
            }
        }
    }

    private func showAutomaticUpdateFailure(for release: GitHubRelease) {
        settingsMenu.cancelTracking()
        panelController.close()
        activateApp()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text.automaticUpdateFailed
        alert.informativeText = text.automaticUpdateFailedDetail
        alert.addButton(withTitle: text.openDownloadPage)
        alert.addButton(withTitle: text.later)
        if alert.runWithButtonHelp() == .alertFirstButtonReturn,
           !NSWorkspace.shared.open(release.htmlURL) {
            showAlert(message: text.cannotOpenUpdate)
        }
    }

    private func releaseNotes(_ body: String?) -> String {
        guard language == .simplifiedChinese else {
            return text.githubReleaseNotes
        }
        let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return text.githubReleaseNotes
        }
        let prefix = String(trimmed.prefix(600))
        return trimmed.count > 600 ? prefix + "…" : prefix
    }

    private func currentAppVersion() -> SemanticVersion? {
        guard let versionString = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else {
            return nil
        }
        return SemanticVersion(versionString)
    }

    private func canonicalVersion(_ version: SemanticVersion) -> String {
        "\(version.major).\(version.minor).\(version.patch)"
    }

    private func refresh() {
        refreshClaudeQuota()
        panelModel.tick()
        refreshTaskStatuses()
        refreshClaudeSessions()
        guard !isRefreshing else {
            return
        }
        isRefreshing = true

        let sessionsRoot = sessionsRoot
        refreshQueue.async { [weak self] in
            let fallbackSnapshot = QuotaStore().latestSnapshot(in: sessionsRoot)
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.rateLimitController.check { [weak self] result in
                    guard let self else {
                        return
                    }
                    self.isRefreshing = false
                    switch result {
                    case let .snapshot(snapshot):
                        self.panelModel.updateCodexStatus("")
                        self.apply(snapshot)
                    case .failure:
                        self.panelModel.updateCodexStatus(fallbackSnapshot == nil ? "暂未读取到 Codex 额度" : "实时读取失败，显示本地记录")
                        self.apply(fallbackSnapshot)
                    }
                }
            }
        }
    }

    private func refreshQuotaManually() {
        if panelModel.selectedQuotaProvider == .claude {
            refreshClaudeQuota(manual: true)
        } else { refresh() }
    }

    private func refreshClaudeQuota(manual: Bool = false) {
        guard !isRefreshingClaude else { return }
        // Each check starts the official Claude Code CLI, so keep background checks sparse:
        // every 5 minutes while Claude is shown, otherwise every 15 minutes for reset notices.
        let interval: TimeInterval = panelModel.selectedQuotaProvider == .claude ? 300 : 900
        if !manual, let lastClaudeCheck, Date().timeIntervalSince(lastClaudeCheck) < interval { return }
        isRefreshingClaude = true
        lastClaudeCheck = Date()
        claudeUsageController.check { [weak self] result in
            guard let self else { return }
            isRefreshingClaude = false
            switch result {
            case let .snapshot(snapshot, source, stale, failure):
                let reason = failure.map { " " + claudeFailureMessage($0) } ?? ""
                switch source {
                case .live:
                    handleClaudeResetNotification(snapshot)
                    panelModel.updateClaude(snapshot: snapshot, status: "")
                case .lastLive:
                    let status = "实时更新失败，显示上次读取的数据"
                    panelModel.updateClaude(snapshot: snapshot, status: status, detail: status + "。" + reason, stale: stale)
                case .desktopCache:
                    let status = stale ? "数据来自 Claude 桌面记录（较旧）" : "数据来自 Claude 桌面记录"
                    let detail = "数据来自 Claude 桌面记录" + (stale ? "，已超过 30 分钟未更新" : "") + "，尚未获取重置时间。"
                    panelModel.updateClaude(snapshot: snapshot, status: status, detail: detail + reason, stale: stale)
                }
            case let .unavailable(failure):
                panelModel.updateClaude(snapshot: nil, status: claudeFailureMessage(failure))
            }
            updateStatusPresentation()
            quickToolsPanelController.refreshSettings()
        }
    }

    private func claudeFailureMessage(_ failure: ClaudeUsageController.Failure) -> String {
        switch failure {
        case .cliMissing: "未找到可用的 Claude Code，请安装 Claude Code 或 Claude 桌面版。"
        case .notLoggedIn: "Claude Code 未登录，请在 Claude Code 中登录后刷新。"
        case .noUsageWindows: "Claude Code 未返回额度窗口，请确认使用 Pro 或 Max 账户登录。"
        case .timedOut: "Claude Code 响应超时，稍后自动重试。"
        case .launchFailed: "无法启动 Claude Code，稍后自动重试。"
        }
    }

    private func handleClaudeResetNotification(_ snapshot: QuotaSnapshot) {
        let key = "claudeQuotaResetNotificationState"
        let old = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(QuotaResetNotificationState.self, from: $0) }
        let detection = QuotaResetDetector.evaluate(snapshot, state: old)
        if let data = try? JSONEncoder().encode(detection.state) { UserDefaults.standard.set(data, forKey: key) }
        guard let start = detection.cycleStartToNotify else { return }
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Claude 额度已重置"
            content.body = "新的额度周期已开始，可继续使用 Claude。"
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: "claude-quota-reset-\(Int(start.timeIntervalSince1970))", content: content, trigger: nil))
        }
    }

    private func refreshTaskStatuses() {
        taskStatusController.check { [weak self] result in
            guard let self else {
                return
            }
            displaySleepController.update(hasRunningTasks: result.hasRunningTasks)
            // Task scans have no authoritative liveness signal. Manual intent
            // alone controls renewal, so scanner results must not change it.
            // taskSleepController.update(hasRunningTasks: result.hasRunningTasks)
            panelModel.update(
                tasks: result.tasks,
                desktopThreads: result.desktopThreads,
                desktopThreadGroups: result.desktopThreadGroups,
                cliProcesses: result.cliProcesses,
                hasCompletedTasks: result.hasCompletedTasks
            )
            for task in result.completedTasks {
                sendTaskCompletionNotification(for: task)
            }
        }
    }

    private func confirmClearCompletedTasks() {
        if panelModel.selectedQuotaProvider == .claude {
            confirmClearCompletedClaudeSessions()
            return
        }
        guard confirmClear(
            title: "清理已完成的任务？",
            detail: "从列表中移除已完成项，保留运行中、状态未知和终端占用的任务。不会删除项目源码或工作区。",
            skipKey: "skipClearCompletedTasksConfirmation"
        ) else { return }
        archiveCompletedTasks()
        clearFinishedDesktopThreads()
    }

    /// Clearing only removes finished items from the list, so the user may turn the prompt off.
    /// The choice is saved only when the user goes ahead with the clearing.
    private func confirmClear(title: String, detail: String, skipKey: String) -> Bool {
        if UserDefaults.standard.bool(forKey: skipKey) { return true }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "清理完成项")
        alert.addButton(withTitle: "取消")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "不再提醒"
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runWithButtonHelp() == .alertFirstButtonReturn else { return false }
        if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: skipKey) }
        return true
    }

    private func clearFinishedDesktopThreads() {
        taskStatusController.clearEndedDesktopThreads { [weak self] result in
            self?.panelModel.update(
                tasks: result.tasks,
                desktopThreads: result.desktopThreads,
                desktopThreadGroups: result.desktopThreadGroups,
                cliProcesses: result.cliProcesses,
                hasCompletedTasks: result.hasCompletedTasks
            )
        }
    }

    private func archiveCompletedTasks() {
        taskStatusController.archiveCompletedTasks { [weak self] result in
            self?.panelModel.update(
                tasks: result.tasks,
                desktopThreads: result.desktopThreads,
                desktopThreadGroups: result.desktopThreadGroups,
                cliProcesses: result.cliProcesses,
                hasCompletedTasks: result.hasCompletedTasks
            )
        }
    }

    private func archiveTask(_ task: TaskStatusSnapshot) {
        taskStatusController.archiveTask(task) { [weak self] result in
            self?.panelModel.update(
                tasks: result.tasks,
                desktopThreads: result.desktopThreads,
                desktopThreadGroups: result.desktopThreadGroups,
                cliProcesses: result.cliProcesses,
                hasCompletedTasks: result.hasCompletedTasks
            )
        }
    }

    private func apply(_ snapshot: QuotaSnapshot?) {
        if let snapshot {
            handleQuotaResetNotification(snapshot)
        }
        currentSnapshot = snapshot
        panelModel.update(snapshot: snapshot)
        updateStatusPresentation()
    }

    private func handleQuotaResetNotification(_ snapshot: QuotaSnapshot) {
        let detection = QuotaResetDetector.evaluate(
            snapshot,
            state: preferences.quotaResetNotificationState
        )
        preferences.quotaResetNotificationState = detection.state
        guard let newCycleStart = detection.cycleStartToNotify else {
            return
        }
        sendQuotaResetNotification(cycleStart: newCycleStart)
    }

    private func sendQuotaResetNotification(cycleStart: Date) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard
                settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
            else {
                return
            }
            Task { @MainActor [weak self] in
                self?.deliverQuotaResetNotification(cycleStart: cycleStart)
            }
        }
    }

    private func deliverQuotaResetNotification(cycleStart: Date) {
        let content = UNMutableNotificationContent()
        content.title = text.quotaResetNotificationTitle
        content.body = text.quotaResetNotificationBody
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "quota-reset-\(Int(cycleStart.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func sendTaskCompletionNotification(
        for task: TaskStatusSnapshot
    ) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard
                settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
            else {
                return
            }
            Task { @MainActor [weak self] in
                self?.deliverTaskCompletionNotification(for: task)
            }
        }
    }

    private func deliverTaskCompletionNotification(
        for task: TaskStatusSnapshot
    ) {
        guard let sessionUUID = task.sessionUUID else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = task.status == .done
            ? text.taskCompletedNotificationTitle
            : text.taskFailedNotificationTitle
        content.body = text.taskNotificationBody(
            name: taskDisplayName(task),
            time: taskTime(task.startedAt)
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "task-completion-\(sessionUUID)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    @objc private func openCurrentResetAnnouncement() {
        guard let url = currentResetCalendar?.feed.upcomingAnnouncement()?.sourceURL else { return }
        settingsMenu.cancelTracking()
        panelController.close()
        NSWorkspace.shared.open(url)
    }

    private func resumeTaskSession(
        sessionUUID: String,
        copyOnly: Bool
    ) -> TaskResumeActionResult {
        guard
            UUID(uuidString: sessionUUID) != nil,
            let executable = TaskStatusController.codexExecutableURL()
        else {
            return .unavailable
        }
        let command = "\(shellQuoted(executable.path)) resume \(shellQuoted(sessionUUID))"
        guard !copyOnly else {
            copyTaskResumeCommand(command)
            return .copied
        }
        let source = """
        tell application "Terminal"
            activate
            do script "\(appleScriptEscaped(command))"
        end tell
        """
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            _ = script.executeAndReturnError(&error)
            if error == nil {
                return .openedTerminal
            }
        }
        copyTaskResumeCommand(command)
        return .copiedAfterLaunchFailure
    }

    private func openCLIProcess(id: String, process: CodexCLIProcess) -> CodexCLIProcessOpenActionResult {
        guard TaskStatusController.cliProcesses()[id] == process else { return .unavailable }
        if let tty = process.tty, activateTerminalTab(tty) { return .opened }
        if activateOwningApplication(for: process) {
            showAlert(message: text.cliOwningAppOpened)
            return .unavailable
        }
        showAlert(message: text.cliOccupiedElsewhere)
        return .unavailable
    }

    private func activateTerminalTab(_ tty: String) -> Bool {
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == "com.apple.Terminal"
        }) else { return false }
        let escapedTTY = appleScriptEscaped(tty)
        let source = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if (tty of t as text) ends with "\(escapedTTY)" then
                        set selected tab of w to t
                        set index of w to 1
                        return "opened"
                    end if
                end repeat
            end repeat
        end tell
        return "missing"
        """
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return error == nil && result.stringValue == "opened"
    }

    private func activateOwningApplication(for process: CodexCLIProcess) -> Bool {
        var currentPID = process.pid
        for _ in 0..<4 {
            guard let output = processOutput("/bin/ps", ["-o", "ppid=", "-p", String(currentPID)]), let parent = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)), parent > 1 else { return false }
            currentPID = parent
            if let application = NSRunningApplication(processIdentifier: pid_t(currentPID)) {
                return application.activate(options: [.activateIgnoringOtherApps])
            }
        }
        return false
    }

    private func processOutput(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private func openCodexThread(
        _ thread: CodexDesktopThreadSnapshot
    ) -> CodexThreadOpenActionResult {
        let threadID: String?
        switch thread.source {
        case .user:
            threadID = thread.id
        case .subagent:
            threadID = thread.parentThreadID
        }
        guard
            let threadID,
            UUID(uuidString: threadID) != nil,
            let url = URL(string: "codex://threads/\(threadID)"),
            let application = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.openai.codex"
            )
        else {
            return .unavailable
        }

        NSWorkspace.shared.open(
            [url],
            withApplicationAt: application,
            configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                let alert = NSAlert()
                alert.messageText = self.text.codexThreadOpenFailedTitle
                alert.informativeText = error.localizedDescription
                alert.runWithButtonHelp()
            }
        }
        return .openRequested
    }

    private func copyTaskResumeCommand(_ command: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func configureResetNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.checkResetCalendar()
            }
        }
    }

    private func checkResetCalendar() {
        guard !isResetMonitorInFlight else { return }
        isResetMonitorInFlight = true
        resetMonitorController.check(cache: currentResetCalendar) { [weak self] result in
            guard let self else { return }
            isResetMonitorInFlight = false
            switch result {
            case var .snapshot(cache):
                // Delivery may finish while this request is in flight.
                cache.seenNoticeKeys.formUnion(currentResetCalendar?.seenNoticeKeys ?? [])
                currentResetCalendar = cache
                preferences.resetCalendarCache = cache
                panelModel.update(resetCalendar: cache)
                guard !cache.feed.isVerificationDelayed() else { return }
                for event in cache.feed.notificationCandidates(seen: cache.seenNoticeKeys) {
                    sendResetNotification(for: event)
                }
            case .failure:
                panelModel.update(resetCalendar: currentResetCalendar, syncFailed: true)
            }
        }
    }

    private func sendResetNotification(for event: CodexResetEvent) {
        let key = event.noticeKey
        guard !resetNotificationsInFlight.contains(key), let url = event.sourceURL else { return }
        resetNotificationsInFlight.insert(key)
        Task { [weak self] in
            guard let self else { return }
            defer { resetNotificationsInFlight.remove(key) }
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                markResetNoticeSeen(key)
                return
            }
            let content = UNMutableNotificationContent()
            content.title = event.kindText(language: text.language) + " · " + event.statusText(language: text.language)
            content.body = event.detailText(language: text.language)
            content.sound = .default
            content.userInfo = ["url": url.absoluteString]
            let request = UNNotificationRequest(identifier: "aihot-reset-" + key, content: content, trigger: nil)
            do {
                try await center.add(request)
                markResetNoticeSeen(key)
            } catch {
                // Leave this key pending so the next successful sync can retry delivery.
            }
        }
    }

    private func markResetNoticeSeen(_ key: String) {
        currentResetCalendar?.seenNoticeKeys.insert(key)
        preferences.resetCalendarCache = currentResetCalendar
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer {
            completionHandler()
        }
        guard
            let value = response.notification.request.content.userInfo["url"] as? String,
            let url = URL(string: value),
            url.scheme == "https",
            ["x.com", "twitter.com"].contains(url.host?.lowercased())
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showAlert(message: String, informativeText: String = "") {
        activateApp()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.informativeText = informativeText
        alert.addButton(withTitle: text.dismiss)
        alert.runWithButtonHelp()
    }

    func menuWillOpen(_ menu: NSMenu) {
        syncMenuState()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
if CommandLine.arguments.contains("--notch-preview") {
    let args = CommandLine.arguments
    let state = args.firstIndex(of: "--state").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "tasks"
    let preview = NotchPreview(state: state)
    application.setActivationPolicy(.accessory)
    if let index = args.firstIndex(of: "--animation-dir"), args.count > index + 1 {
        preview.recordAnimation(to: args[index + 1])
    } else if args.contains("--demo-cycle") { preview.demoCycle() } else { preview.show() }
    if let index = args.firstIndex(of: "--snapshot"), args.count > index + 1 {
        let path = args[index + 1]
        Task { @MainActor in
            // claude-real waits for one real Claude Code CLI check.
            try? await Task.sleep(for: .milliseconds(state == "claude-real" ? 15_000 : 700))
            do {
                if args.contains("--status-panel") { try preview.snapshotStatusPanel(to: path) } else { try preview.snapshot(to: path) }
            } catch { print(error) }
            application.terminate(nil)
        }
    }
    application.run()
    exit(0)
}
if CommandLine.arguments.contains("--node-scores-preview") {
    let preview = NodeScoreWindowController()
    application.setActivationPolicy(.regular)
    preview.show()
    if let index = CommandLine.arguments.firstIndex(of:"--snapshot"), CommandLine.arguments.count > index + 1 {
        let destination = CommandLine.arguments[index + 1]
        Task { @MainActor in
            try? await Task.sleep(for:.milliseconds(500))
            do { try preview.snapshot(to:destination) } catch { print(error) }
            application.terminate(nil)
        }
    }
    application.run()
    exit(0)
}
let delegate = AppDelegate()
application.delegate = delegate
application.run()
