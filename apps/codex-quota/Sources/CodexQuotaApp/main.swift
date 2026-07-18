import AppKit
import CodexQuotaCore
import CodexQuotaUI
import UserNotifications

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
    private let updateTimeLabel = NSTextField(labelWithString: "")
    private let resetTimeLabel = NSTextField(labelWithString: "")
    private let planNameLabel = NSTextField(labelWithString: "")
    private let resetSignalLabel = NSTextField(labelWithString: "")
    private let expectedResetLabel = NSTextField(labelWithString: "")
    private let resetSignalButton = NSButton()
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
    private var updateMenuItem: NSMenuItem?
    private var currentSnapshot: QuotaSnapshot?
    private var refreshTimer: Timer?
    private var updatePolicyTimer: Timer?
    private var resetMonitorTimer: Timer?
    private var availableRelease: GitHubRelease?
    private var currentResetSignal: TiboResetSignal?
    private var isRefreshing = false
    private var isUpdateCheckInFlight = false
    private var isResetMonitorInFlight = false
    private let updateController = GitHubUpdateController()
    private let resetMonitorController = TiboResetMonitorController()
    private let launchAtLoginController = LaunchAtLoginController()
    private let rateLimitController = CodexRateLimitController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        currentResetSignal = preferences.latestResetSignal
        updateHeaderLabels()
        configureStatusItem()
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
        updateController.invalidate()
        resetMonitorController.invalidate()
        rateLimitController.invalidate()
    }

    private func configureStatusItem() {
        updateStatusPresentation()

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(makeHeaderItem())
        menu.addItem(.separator())

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
        menu.addItem(styleItem)

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
        menu.addItem(identityItem)

        menu.addItem(.separator())

        let resetItem = makeChoiceItem(
            title: text.showResetTime,
            tag: 0,
            action: #selector(toggleResetCountdown(_:))
        )
        resetToggleItem = resetItem
        menu.addItem(resetItem)

        let loginItem = makeChoiceItem(
            title: text.launchAtLogin,
            tag: 0,
            action: #selector(toggleLaunchAtLogin(_:))
        )
        launchAtLoginItem = loginItem
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let moveHintItem = NSMenuItem(
            title: text.moveHint,
            action: nil,
            keyEquivalent: ""
        )
        moveHintItem.isEnabled = false
        menu.addItem(moveHintItem)

        let updateItem = NSMenuItem(
            title: text.checkForUpdates,
            action: #selector(checkForUpdatesManually),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateMenuItem = updateItem
        menu.addItem(updateItem)

        let quitItem = NSMenuItem(
            title: text.quit,
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        syncMenuState()
        statusItem.menu = menu
    }

    private func makeHeaderItem() -> NSMenuItem {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 112))
        let labels = [
            updateTimeLabel,
            resetTimeLabel,
            planNameLabel,
            resetSignalLabel,
            expectedResetLabel
        ]
        for label in labels {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .menuFont(ofSize: 13)
            label.lineBreakMode = .byClipping
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            row.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -12)
            ])
        }
        NSLayoutConstraint.activate([
            updateTimeLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            resetTimeLabel.topAnchor.constraint(equalTo: updateTimeLabel.bottomAnchor, constant: 3),
            planNameLabel.topAnchor.constraint(equalTo: resetTimeLabel.bottomAnchor, constant: 3),
            resetSignalLabel.topAnchor.constraint(equalTo: planNameLabel.bottomAnchor, constant: 7),
            expectedResetLabel.topAnchor.constraint(equalTo: resetSignalLabel.bottomAnchor, constant: 3)
        ])

        resetSignalButton.translatesAutoresizingMaskIntoConstraints = false
        resetSignalButton.title = ""
        resetSignalButton.isBordered = false
        resetSignalButton.focusRingType = .none
        resetSignalButton.target = self
        resetSignalButton.action = #selector(openCurrentResetAnnouncement)
        resetSignalButton.toolTip = text.resetAnnouncementTooltip
        resetSignalButton.setAccessibilityLabel(text.resetAnnouncementAccessibility)
        resetSignalButton.isHidden = true
        row.addSubview(resetSignalButton)
        NSLayoutConstraint.activate([
            resetSignalButton.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            resetSignalButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            resetSignalButton.topAnchor.constraint(equalTo: resetSignalLabel.topAnchor, constant: -2),
            resetSignalButton.bottomAnchor.constraint(equalTo: expectedResetLabel.bottomAnchor, constant: 2)
        ])

        let item = NSMenuItem()
        item.view = row
        return item
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

        if let version = availableRelease?.eligibleVersion {
            updateMenuItem?.title = text.newVersionAvailable(canonicalVersion(version))
        } else {
            updateMenuItem?.title = text.checkForUpdates
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
        statusItem.menu?.cancelTracking()
    }

    @objc private func refreshFromTimer() {
        refresh()
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
        statusItem.menu?.cancelTracking()
        activateApp()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = text.foundNewVersion(canonicalVersion(version))
        alert.informativeText = releaseNotes(release.body)
        alert.addButton(withTitle: text.goToUpdate)
        alert.addButton(withTitle: text.later)
        if alert.runModal() == .alertFirstButtonReturn {
            if !NSWorkspace.shared.open(release.htmlURL) {
                showAlert(message: text.cannotOpenUpdate)
            }
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

    private func apply(_ snapshot: QuotaSnapshot?) {
        if let snapshot {
            handleQuotaResetNotification(snapshot)
        }
        currentSnapshot = snapshot
        updateHeaderLabels()
        updateStatusPresentation()
    }

    private func handleQuotaResetNotification(_ snapshot: QuotaSnapshot) {
        guard let currentCycleStart = snapshot.windowStartedAt else {
            return
        }
        guard let previousCycleStart = preferences.lastNotifiedQuotaCycleStart else {
            preferences.lastNotifiedQuotaCycleStart = currentCycleStart
            return
        }
        guard let newCycleStart = QuotaResetDetector.newCycleStart(
            in: snapshot,
            after: previousCycleStart
        ) else {
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
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard error == nil else {
                return
            }
            Task { @MainActor [weak self] in
                self?.preferences.lastNotifiedQuotaCycleStart = cycleStart
            }
        }
    }

    private func updateHeaderLabels(now: Date = Date()) {
        updateResetSignalLabels(now: now)
        guard let snapshot = currentSnapshot else {
            updateTimeLabel.stringValue = text.updatedPlaceholder
            resetTimeLabel.stringValue = text.nextResetPlaceholder
            planNameLabel.stringValue = text.planPlaceholder
            return
        }
        updateTimeLabel.stringValue = UpdateTimeFormatter.label(
            lastRefreshAt: now,
            language: language
        )
        resetTimeLabel.stringValue = text.nextReset(
            ResetCountdownFormatter.string(
                resetsAt: snapshot.resetDate(at: now),
                now: now,
                language: language
            )
        )
        planNameLabel.stringValue = text.plan(snapshot.planName ?? "--")
    }

    private func updateResetSignalLabels(now: Date) {
        guard
            let signal = currentResetSignal,
            signal.shouldDisplay(at: now, quotaSnapshot: currentSnapshot)
        else {
            resetSignalLabel.stringValue = text.resetForecastNone
            expectedResetLabel.stringValue = text.expectedTimePlaceholder
            resetSignalLabel.textColor = .labelColor
            resetSignalButton.isHidden = true
            return
        }
        let isClickableAnnouncement = signal.kind == .announced
        resetSignalLabel.stringValue = text.resetForecast(
            signal.kind.statusText(language: language),
            linked: isClickableAnnouncement
        )
        expectedResetLabel.stringValue = text.expectedTime(
            signal.expectedTimeText(now: now, language: language)
        )
        resetSignalLabel.textColor = isClickableAnnouncement ? .linkColor : .labelColor
        resetSignalButton.isHidden = !isClickableAnnouncement
    }

    @objc private func openCurrentResetAnnouncement() {
        let now = Date()
        guard
            let signal = currentResetSignal,
            signal.kind == .announced,
            signal.shouldDisplay(at: now, quotaSnapshot: currentSnapshot)
        else {
            return
        }
        statusItem.menu?.cancelTracking()
        NSWorkspace.shared.open(signal.url)
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
                updateResetSignalLabels(now: Date())
                if
                    let signal,
                    signal.shouldDisplay(
                        at: Date(),
                        quotaSnapshot: currentSnapshot
                    ),
                    signal.id != preferences.lastNotifiedResetSignalID
                {
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
        content.body = text.expectedTime(
            signal.expectedTimeText(language: language)
        )
        content.sound = .default
        content.userInfo = ["url": signal.url.absoluteString]

        let request = UNNotificationRequest(
            identifier: "tibo-reset-\(signal.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard error == nil else {
                return
            }
            Task { @MainActor [weak self] in
                self?.preferences.lastNotifiedResetSignalID = signal.id
            }
        }
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
        updateHeaderLabels()
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
