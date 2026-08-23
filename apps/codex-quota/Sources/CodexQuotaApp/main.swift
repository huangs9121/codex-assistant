import AppKit
import CodexQuotaCore
import CodexQuotaUI
import UserNotifications

private extension DisplayPreferences {
    var lastNotifiedResetSignalKey: TiboResetNotificationKey? {
        get {
            UserDefaults.standard.string(
                forKey: TiboResetNotificationKey.defaultsKey
            ).flatMap(TiboResetNotificationKey.init(storageValue:))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(
                    newValue.storageValue,
                    forKey: TiboResetNotificationKey.defaultsKey
                )
            } else {
                UserDefaults.standard.removeObject(
                    forKey: TiboResetNotificationKey.defaultsKey
                )
            }
        }
    }
}

@MainActor
private final class MenuChoiceRow: NSView {
    private let checkmarkLabel = NSTextField(labelWithString: "✓")
    private let titleLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton()
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

        let preview = NSImageView(image: previewImage ?? NSImage())
        preview.translatesAutoresizingMaskIntoConstraints = false
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
            preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            preview.centerYAnchor.constraint(equalTo: centerYAnchor),
            preview.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
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
    private var resetToggleItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var mouseScrollReversalItem: NSMenuItem?
    private var doubleCommandTapItem: NSMenuItem?
    private var modifierTapGestureItem: NSMenuItem?
    private var mouseScrollPermissionItem: NSMenuItem?
    private var doubleCommandTapPermissionStatusItem: NSMenuItem?
    private var inputMonitoringSettingsItem: NSMenuItem?
    private var doubleCommandAccessibilitySettingsItem: NSMenuItem?
    private var updateMenuItem: NSMenuItem?
    private var currentSnapshot: QuotaSnapshot?
    private var refreshTimer: Timer?
    private var updatePolicyTimer: Timer?
    private var resetMonitorTimer: Timer?
    private var accessibilityPermissionTimer: Timer?
    private var availableRelease: GitHubRelease?
    private var currentResetSignal: TiboResetSignal?
    private var isRefreshing = false
    private var isUpdateCheckInFlight = false
    private var isUpdateInstallInFlight = false
    private var isResetMonitorInFlight = false
    private let updateController = GitHubUpdateController()
    private let automaticUpdateInstaller = AutomaticUpdateInstaller()
    private let resetMonitorController = TiboResetMonitorController()
    private let launchAtLoginController = LaunchAtLoginController()
    private let mouseScrollReversalController = MouseScrollReversalController()
    private let doubleCommandTapController = DoubleCommandTapController()
    private lazy var doubleCommandTapShortcutPanelController = DoubleCommandTapShortcutPanelController(text: text)
    private lazy var modifierTapGesturePanelController = ModifierTapGesturePanelController(text: text) { [weak self] in
        self?.doubleCommandTapController.reloadGesture()
        self?.syncMenuState()
    }
    private let rateLimitController = CodexRateLimitController()
    private let taskStatusController = TaskStatusController()
    private lazy var panelController = StatusPanelController(
        model: panelModel,
        text: text,
        onSettingsMenu: { [weak self] view in
            self?.showSettingsMenu(relativeTo: view)
        },
        onOpenResetAnnouncement: { [weak self] in
            self?.openCurrentResetAnnouncement()
        },
        onResumeSession: { [weak self] sessionUUID, copyOnly in
            self?.resumeTaskSession(
                sessionUUID: sessionUUID,
                copyOnly: copyOnly
            ) ?? .copiedAfterLaunchFailure
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        currentResetSignal = preferences.latestResetSignal
        panelModel.update(resetSignal: currentResetSignal)
        configureStatusItem()
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
        showAutoRefreshNoticeIfNeeded()
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
        checkTiboResetSignals()
        let resetTimer = Timer(
            timeInterval: 300,
            target: self,
            selector: #selector(checkTiboResetSignalsFromTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(resetTimer, forMode: .common)
        resetMonitorTimer = resetTimer
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        doubleCommandTapController.stop()
    }

    private func configureStatusItem() {
        updateStatusPresentation()
        configureSettingsMenu()
        guard let button = statusItem.button else {
            return
        }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureSettingsMenu() {
        settingsMenu.removeAllItems()
        settingsMenu.delegate = self
        styleItems.removeAll()
        identityItems.removeAll()

        let moveHintItem = NSMenuItem(
            title: text.moveHint,
            action: nil,
            keyEquivalent: ""
        )
        moveHintItem.isEnabled = false
        settingsMenu.addItem(moveHintItem)
        settingsMenu.addItem(.separator())

        let styleItem = NSMenuItem(
            title: text.displayStyle,
            action: nil,
            keyEquivalent: ""
        )
        let styleMenu = NSMenu(title: text.displayStyle)
        for style in BatteryStyle.allCases {
            let item = makeStyleItem(style)
            styleItems[style] = item
            styleMenu.addItem(item)
        }
        styleItem.submenu = styleMenu
        settingsMenu.addItem(styleItem)

        let identityItem = NSMenuItem(
            title: text.identityStyle,
            action: nil,
            keyEquivalent: ""
        )
        let identityMenu = NSMenu(title: text.identityStyle)
        for mode in StatusIdentityMode.allCases {
            let item = makeIdentityItem(mode)
            identityItems[mode] = item
            identityMenu.addItem(item)
        }
        identityItem.submenu = identityMenu
        settingsMenu.addItem(identityItem)

        settingsMenu.addItem(.separator())

        let resetItem = makeChoiceItem(
            title: text.showResetTime,
            tag: 0,
            action: #selector(toggleResetCountdown(_:))
        )
        resetToggleItem = resetItem
        settingsMenu.addItem(resetItem)

        let loginItem = makeChoiceItem(
            title: text.launchAtLogin,
            tag: 0,
            action: #selector(toggleLaunchAtLogin(_:))
        )
        launchAtLoginItem = loginItem
        settingsMenu.addItem(loginItem)

        settingsMenu.addItem(.separator())

        let mouseScrollItem = makeChoiceItem(
            title: text.mouseScrollReversal,
            tag: 0,
            action: #selector(toggleMouseScrollReversal(_:))
        )
        mouseScrollReversalItem = mouseScrollItem
        settingsMenu.addItem(mouseScrollItem)

        let doubleCommandTapItem = makeChoiceItem(
            title: text.doubleCommandTap,
            tag: 0,
            action: #selector(toggleDoubleCommandTap(_:))
        )
        self.doubleCommandTapItem = doubleCommandTapItem
        settingsMenu.addItem(doubleCommandTapItem)

        let testCodexShortcutItem = NSMenuItem(
            title: text.testCodexShortcut,
            action: #selector(testCodexShortcut),
            keyEquivalent: ""
        )
        testCodexShortcutItem.target = self
        settingsMenu.addItem(testCodexShortcutItem)

        let setDoubleCommandTapShortcutItem = NSMenuItem(
            title: text.setCodexShortcut,
            action: #selector(showDoubleCommandTapShortcutPanel),
            keyEquivalent: ""
        )
        setDoubleCommandTapShortcutItem.target = self
        settingsMenu.addItem(setDoubleCommandTapShortcutItem)

        let recordModifierTapGestureItem = NSMenuItem(
            title: text.recordTriggerGesture,
            action: #selector(showModifierTapGesturePanel),
            keyEquivalent: ""
        )
        recordModifierTapGestureItem.target = self
        settingsMenu.addItem(recordModifierTapGestureItem)

        let modifierTapGestureItem = NSMenuItem(
            title: text.triggerGesture(
                ModifierTapGesture(defaults: .standard).displayString(text: text)
            ),
            action: nil,
            keyEquivalent: ""
        )
        modifierTapGestureItem.isEnabled = false
        self.modifierTapGestureItem = modifierTapGestureItem
        settingsMenu.addItem(modifierTapGestureItem)

        let mouseScrollDetailItem = NSMenuItem(
            title: text.mouseScrollReversalDetail,
            action: nil,
            keyEquivalent: ""
        )
        mouseScrollDetailItem.isEnabled = false
        settingsMenu.addItem(mouseScrollDetailItem)

        let mouseScrollConflictItem = NSMenuItem(
            title: text.mouseScrollReversalConflictHint,
            action: nil,
            keyEquivalent: ""
        )
        mouseScrollConflictItem.isEnabled = false
        settingsMenu.addItem(mouseScrollConflictItem)

        let doubleCommandTapDetailItem = NSMenuItem(
            title: text.doubleCommandTapDetail,
            action: nil,
            keyEquivalent: ""
        )
        doubleCommandTapDetailItem.isEnabled = false
        settingsMenu.addItem(doubleCommandTapDetailItem)

        let doubleCommandTapPermissionStatusItem = NSMenuItem(
            title: text.doubleCommandTapRunning,
            action: nil,
            keyEquivalent: ""
        )
        doubleCommandTapPermissionStatusItem.isEnabled = false
        self.doubleCommandTapPermissionStatusItem = doubleCommandTapPermissionStatusItem
        settingsMenu.addItem(doubleCommandTapPermissionStatusItem)

        let inputMonitoringSettingsItem = NSMenuItem(
            title: text.openInputMonitoringSettings,
            action: #selector(openInputMonitoringSettings),
            keyEquivalent: ""
        )
        inputMonitoringSettingsItem.target = self
        self.inputMonitoringSettingsItem = inputMonitoringSettingsItem
        settingsMenu.addItem(inputMonitoringSettingsItem)

        let doubleCommandAccessibilitySettingsItem = NSMenuItem(
            title: text.openAccessibilitySettings,
            action: #selector(openDoubleCommandAccessibilitySettings),
            keyEquivalent: ""
        )
        doubleCommandAccessibilitySettingsItem.target = self
        self.doubleCommandAccessibilitySettingsItem = doubleCommandAccessibilitySettingsItem
        settingsMenu.addItem(doubleCommandAccessibilitySettingsItem)

        let mouseScrollPermissionItem = NSMenuItem(
            title: text.openAccessibilitySettings,
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        mouseScrollPermissionItem.target = self
        self.mouseScrollPermissionItem = mouseScrollPermissionItem
        settingsMenu.addItem(mouseScrollPermissionItem)

        settingsMenu.addItem(.separator())

        let updateItem = NSMenuItem(
            title: text.checkForUpdates,
            action: #selector(checkForUpdatesManually),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateMenuItem = updateItem
        settingsMenu.addItem(updateItem)

        let quitItem = NSMenuItem(
            title: text.quit,
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitItem.target = self
        settingsMenu.addItem(quitItem)

        syncMenuState()
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
        syncMenuState()
        settingsMenu.popUp(
            positioning: nil,
            at: NSPoint(x: view.bounds.minX, y: view.bounds.maxY + 4),
            in: view
        )
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

        let mouseScrollEnabled = mouseScrollReversalController.isEnabled
        mouseScrollReversalItem?.state = mouseScrollEnabled ? .on : .off
        (mouseScrollReversalItem?.view as? MenuChoiceRow)?.isSelected = mouseScrollEnabled
        let doubleCommandTapEnabled = doubleCommandTapController.isEnabled
        doubleCommandTapItem?.state = doubleCommandTapEnabled ? .on : .off
        (doubleCommandTapItem?.view as? MenuChoiceRow)?.isSelected = doubleCommandTapEnabled
        modifierTapGestureItem?.title = text.triggerGesture(
            ModifierTapGesture(defaults: .standard).displayString(text: text)
        )
        mouseScrollPermissionItem?.title = accessibilityPermissionTitle()
        syncDoubleCommandTapPermissionItems()

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
        let effectiveReset = currentSnapshot?.resetDate(at: now)
        let compactReset = preferences.showsResetCountdownInStatusBar
            ? ResetCountdownFormatter.compactString(
                resetsAt: effectiveReset,
                now: now,
                language: language
            )
            : nil
        let presentation = renderer.presentation(
            style: preferences.batteryStyle,
            remainingPercent: currentSnapshot?.remainingPercent(at: now),
            identityMode: preferences.identityMode,
            compactReset: compactReset,
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

    @objc private func toggleMouseScrollReversal(_ sender: NSButton) {
        mouseScrollReversalController.isEnabled.toggle()
        if mouseScrollReversalController.isEnabled,
           !mouseScrollReversalController.startIfPermitted() {
            mouseScrollReversalController.requestAccessibilityPermission()
        } else if !mouseScrollReversalController.isEnabled {
            mouseScrollReversalController.stop()
        }
        syncMenuState()
    }

    @objc private func toggleDoubleCommandTap(_ sender: NSButton) {
        doubleCommandTapController.isEnabled.toggle()
        if doubleCommandTapController.isEnabled,
           !doubleCommandTapController.startIfPermitted() {
            doubleCommandTapController.requestInputMonitoringPermission()
            doubleCommandTapController.requestAccessibilityPermission()
        } else if !doubleCommandTapController.isEnabled {
            doubleCommandTapController.stop()
        }
        syncMenuState()
    }

    @objc private func showDoubleCommandTapShortcutPanel() {
        doubleCommandTapShortcutPanelController.show()
    }

    @objc private func showModifierTapGesturePanel() {
        modifierTapGesturePanelController.show()
    }

    @objc private func testCodexShortcut() {
        doubleCommandTapController.testTriggerCodexShortcut()
    }

    @objc private func openAccessibilitySettings() {
        mouseScrollReversalController.openAccessibilitySettings()
    }

    @objc private func openInputMonitoringSettings() {
        doubleCommandTapController.openInputMonitoringSettings()
    }

    @objc private func openDoubleCommandAccessibilitySettings() {
        doubleCommandTapController.openAccessibilitySettings()
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
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func closeMenuForLaunchAtLoginInteraction() {
        settingsMenu.cancelTracking()
        panelController.close()
    }

    private func refreshAccessibilityControllers() {
        doubleCommandTapController.observePermissionStatus()
        if mouseScrollReversalController.isEnabled,
           !mouseScrollReversalController.isRunning {
            _ = mouseScrollReversalController.startIfPermitted()
        }
        if doubleCommandTapController.isEnabled,
           !doubleCommandTapController.isRunning {
            _ = doubleCommandTapController.startIfPermitted()
        }
    }

    private func accessibilityPermissionTitle() -> String {
        guard AXIsProcessTrusted() else {
            return text.openAccessibilitySettings + "（" + text.accessibilityPermissionRequired + "）"
        }
        let hasEnabledController = mouseScrollReversalController.isEnabled
        let hasFailedController = mouseScrollReversalController.isEnabled
            && !mouseScrollReversalController.isRunning
        if hasFailedController {
            return text.accessibilityEnableFailed
        }
        return hasEnabledController ? text.accessibilityPermissionRunning : text.accessibilityPermissionGranted
    }

    private func syncDoubleCommandTapPermissionItems() {
        let isEnabled = doubleCommandTapController.isEnabled
        let status = doubleCommandTapController.permissionStatus
        doubleCommandTapPermissionStatusItem?.isHidden = !isEnabled
        inputMonitoringSettingsItem?.isHidden = !isEnabled || status == .running || status == .accessibilityRequired
        doubleCommandAccessibilitySettingsItem?.isHidden = !isEnabled || status == .running || status == .inputMonitoringRequired
        switch status {
        case .running:
            doubleCommandTapPermissionStatusItem?.title = text.doubleCommandTapRunning
        case .inputMonitoringRequired:
            doubleCommandTapPermissionStatusItem?.title = text.inputMonitoringPermissionRequired
        case .accessibilityRequired:
            doubleCommandTapPermissionStatusItem?.title = text.accessibilityPermissionRequired
        case .inputMonitoringAndAccessibilityRequired:
            doubleCommandTapPermissionStatusItem?.title = text.doubleCommandTapPermissionsRequired
        }
    }

    @objc private func refreshFromTimer() {
        refresh()
    }

    @objc private func refreshAccessibilityPermissionFromTimer() {
        refreshAccessibilityControllers()
        syncMenuState()
    }

    @objc private func checkForUpdatesFromTimer() {
        checkForUpdatesAutomatically()
    }

    @objc private func checkTiboResetSignalsFromTimer() {
        checkTiboResetSignals()
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
        if alert.runModal() == .alertFirstButtonReturn {
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
        if alert.runModal() == .alertFirstButtonReturn,
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
        panelModel.tick()
        refreshTaskStatuses()
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
                        self.apply(snapshot)
                    case .failure:
                        self.apply(fallbackSnapshot)
                    }
                }
            }
        }
    }

    private func refreshTaskStatuses() {
        taskStatusController.check { [weak self] result in
            guard let self else {
                return
            }
            panelModel.update(tasks: result.tasks)
            for task in result.completedTasks {
                sendTaskCompletionNotification(for: task)
            }
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
        let now = Date()
        guard
            let signal = currentResetSignal,
            signal.shouldDisplay(at: now, quotaSnapshot: currentSnapshot)
        else {
            return
        }
        settingsMenu.cancelTracking()
        panelController.close()
        NSWorkspace.shared.open(signal.url)
    }

    private func resumeTaskSession(
        sessionUUID: String,
        copyOnly: Bool
    ) -> TaskResumeActionResult {
        guard !copyOnly else {
            copyTaskResumeCommand(sessionUUID: sessionUUID)
            return .copied
        }
        let source = """
        tell application "Terminal"
            activate
            do script "codex resume \(sessionUUID)"
        end tell
        """
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            _ = script.executeAndReturnError(&error)
            if error == nil {
                return .openedTerminal
            }
        }
        copyTaskResumeCommand(sessionUUID: sessionUUID)
        return .copiedAfterLaunchFailure
    }

    private func copyTaskResumeCommand(sessionUUID: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            "codex resume \(sessionUUID)",
            forType: .string
        )
    }

    private func configureResetNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.checkTiboResetSignals()
            }
        }
    }

    private func checkTiboResetSignals() {
        guard !isResetMonitorInFlight else {
            return
        }
        isResetMonitorInFlight = true
        resetMonitorController.check { [weak self] result in
            guard let self else {
                return
            }
            isResetMonitorInFlight = false
            switch result {
            case let .signal(signal):
                currentResetSignal = signal
                preferences.latestResetSignal = signal
                panelModel.update(resetSignal: signal)
                if
                    let signal,
                    signal.shouldDisplay(
                        at: Date(),
                        quotaSnapshot: currentSnapshot
                    ),
                    TiboResetNotificationKey(signal: signal).shouldNotify(
                        after: preferences.lastNotifiedResetSignalKey
                    )
                {
                    preferences.lastNotifiedResetSignalKey = TiboResetNotificationKey(
                        signal: signal
                    )
                    sendResetNotification(for: signal)
                }
            case .failure:
                break
            }
        }
    }

    private func sendResetNotification(for signal: TiboResetSignal) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard
                settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
            else {
                return
            }
            Task { @MainActor [weak self] in
                self?.deliverResetNotification(for: signal)
            }
        }
    }

    private func deliverResetNotification(for signal: TiboResetSignal) {
        let content = UNMutableNotificationContent()
        content.title = text.resetNotificationTitle(kind: signal.kind)
        content.body = text.resetNotificationBody(for: signal)
        content.sound = .default
        content.userInfo = ["url": signal.url.absoluteString]

        let request = UNNotificationRequest(
            identifier: "tibo-reset-\(signal.id)-\(signal.kind.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
        alert.runModal()
    }

    private func showAutoRefreshNoticeIfNeeded() {
        guard !preferences.hasShownAutoRefreshNotice else {
            return
        }
        activateApp()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = text.launched
        alert.informativeText = text.launchNotice
        alert.addButton(withTitle: text.dismiss)
        alert.runModal()
        preferences.hasShownAutoRefreshNotice = true
    }

    func menuWillOpen(_ menu: NSMenu) {
        syncMenuState()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
