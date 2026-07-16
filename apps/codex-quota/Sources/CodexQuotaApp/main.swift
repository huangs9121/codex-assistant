import AppKit
import CodexQuotaCore
import CodexQuotaUI

@MainActor
private final class MenuChoiceRow: NSView {
    private let checkmarkLabel = NSTextField(labelWithString: "✓")
    private let titleLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton()

    var isSelected = false {
        didSet {
            checkmarkLabel.isHidden = !isSelected
            actionButton.setAccessibilityValue(isSelected ? "已选择" : "未选择")
        }
    }

    init(
        title: String,
        previewImage: NSImage? = nil,
        tag: Int,
        target: AnyObject,
        action: Selector
    ) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 32))

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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
    )
    private var preferences = DisplayPreferences(defaults: .standard)
    private let renderer = BatteryStatusRenderer()
    private let updateTimeLabel = NSTextField(labelWithString: "更新时间：--:--:--")
    private let resetTimeLabel = NSTextField(labelWithString: "下次重置：--")
    private let planNameLabel = NSTextField(labelWithString: "当前套餐：--")
    private let expiryLabel = NSTextField(labelWithString: "套餐到期：--")
    private let sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)
    private let authURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/auth.json")
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
    private var currentSubscriptionExpiry: Date?
    private var refreshTimer: Timer?
    private var updatePolicyTimer: Timer?
    private var availableRelease: GitHubRelease?
    private var isRefreshing = false
    private var isUpdateCheckInFlight = false
    private let updateController = GitHubUpdateController()
    private let launchAtLoginController = LaunchAtLoginController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        updatePolicyTimer?.invalidate()
        updateController.invalidate()
    }

    private func configureStatusItem() {
        updateStatusPresentation()

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(makeHeaderItem())
        menu.addItem(.separator())

        for style in BatteryStyle.allCases {
            let item = makeStyleItem(style)
            styleItems[style] = item
            menu.addItem(item)
        }

        for mode in StatusIdentityMode.allCases {
            let item = makeIdentityItem(mode)
            identityItems[mode] = item
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let resetItem = makeChoiceItem(
            title: "显示重置时间",
            tag: 0,
            action: #selector(toggleResetCountdown(_:))
        )
        resetToggleItem = resetItem
        menu.addItem(resetItem)

        let loginItem = makeChoiceItem(
            title: "开机自动启动",
            tag: 0,
            action: #selector(toggleLaunchAtLogin(_:))
        )
        launchAtLoginItem = loginItem
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let updateItem = NSMenuItem(
            title: "检查更新…",
            action: #selector(checkForUpdatesManually),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateMenuItem = updateItem
        menu.addItem(updateItem)

        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        syncMenuState()
        statusItem.menu = menu
    }

    private func makeHeaderItem() -> NSMenuItem {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 92))
        let labels = [updateTimeLabel, resetTimeLabel, planNameLabel, expiryLabel]
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
            expiryLabel.topAnchor.constraint(equalTo: planNameLabel.bottomAnchor, constant: 3)
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
            compactReset: nil
        ).image
        preview.isTemplate = true
        return makeChoiceItem(
            title: style.menuTitle,
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
            title: mode.menuTitle,
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
            action: action
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
            launchTitle = "开机自动启动"
            launchSelected = true
        case .disabled:
            launchTitle = "开机自动启动"
            launchSelected = false
        case .requiresApproval:
            launchTitle = "开机自动启动（需系统确认）"
            launchSelected = false
        case .unavailable:
            launchTitle = "开机自动启动（不可用）"
            launchSelected = false
        }
        launchAtLoginItem?.state = launchSelected ? .on : .off
        (launchAtLoginItem?.view as? MenuChoiceRow)?.isSelected = launchSelected
        (launchAtLoginItem?.view as? MenuChoiceRow)?.updateTitle(launchTitle)

        if let version = availableRelease?.eligibleVersion {
            updateMenuItem?.title = "新版本 \(canonicalVersion(version)) 可用…"
        } else {
            updateMenuItem?.title = "检查更新…"
        }
    }

    private func updateStatusPresentation() {
        let compactReset = preferences.showsResetCountdownInStatusBar
            ? ResetCountdownFormatter.compactString(resetsAt: currentSnapshot?.resetsAt)
            : nil
        let presentation = renderer.presentation(
            style: preferences.batteryStyle,
            remainingPercent: currentSnapshot?.remainingPercent,
            identityMode: preferences.identityMode,
            compactReset: compactReset
        )
        statusItem.button?.image = presentation.image
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.setAccessibilityLabel(
            "\(presentation.accessibilityLabel)，\(preferences.batteryStyle.menuTitle)"
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
                message: "开机自动启动不可用",
                informativeText: "当前系统无法使用此功能，请稍后重试。"
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
                message: enabled ? "无法开启开机自动启动" : "无法关闭开机自动启动",
                informativeText: "请在“系统设置”中的“登录项”里检查后重试。"
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
        alert.messageText = "建议先将 Codex Quota 移到“应用程序”文件夹，开机启动会更稳定。"
        alert.addButton(withTitle: "仍然开启")
        alert.addButton(withTitle: "取消")
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

    private func checkForUpdatesAutomatically() {
        guard let currentVersion = currentAppVersion() else {
            return
        }
        performUpdateCheck(currentVersion: currentVersion, manual: false)
    }

    @objc private func checkForUpdatesManually() {
        guard !isUpdateCheckInFlight else {
            showAlert(message: "正在检查更新，请稍候。")
            return
        }
        if let availableRelease {
            showUpdateAlert(for: availableRelease)
            return
        }
        guard let currentVersion = currentAppVersion() else {
            showAlert(
                message: "无法检查更新",
                informativeText: "当前版本信息无效，请重新安装 Codex Quota。"
            )
            return
        }
        performUpdateCheck(currentVersion: currentVersion, manual: true)
    }

    private func performUpdateCheck(currentVersion: SemanticVersion, manual: Bool) {
        guard !isUpdateCheckInFlight else {
            if manual {
                showAlert(message: "正在检查更新，请稍候。")
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
                        message: "无法检查更新",
                        informativeText: "检查更新失败，请稍后重试。"
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
                showAlert(message: "当前已是最新版本")
            }
        case let .failure(message):
            if manual {
                showAlert(message: message)
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
        alert.messageText = "发现新版本 \(canonicalVersion(version))"
        alert.informativeText = releaseNotes(release.body)
        alert.addButton(withTitle: "前往更新")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            if !NSWorkspace.shared.open(release.htmlURL) {
                showAlert(message: "无法打开更新页面，请稍后重试。")
            }
        }
    }

    private func releaseNotes(_ body: String?) -> String {
        let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return "前往 GitHub 查看更新说明。"
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
        let authURL = authURL
        refreshQueue.async { [weak self] in
            let snapshot = QuotaStore().latestSnapshot(in: sessionsRoot)
            let expiry: Date?
            if
                let planName = snapshot?.planName,
                let authData = try? Data(contentsOf: authURL)
            {
                expiry = PlanInfo.subscriptionExpiry(
                    authData: authData,
                    currentPlan: planName,
                    now: Date()
                )
            } else {
                expiry = nil
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.isRefreshing = false
                self.apply(snapshot, expiry: expiry)
            }
        }
    }

    private func apply(_ snapshot: QuotaSnapshot?, expiry: Date?) {
        currentSnapshot = snapshot
        currentSubscriptionExpiry = expiry
        updateHeaderLabels()
        updateStatusPresentation()
    }

    private func updateHeaderLabels(now: Date = Date()) {
        guard let snapshot = currentSnapshot else {
            updateTimeLabel.stringValue = "更新时间：--:--:--"
            resetTimeLabel.stringValue = "下次重置：--"
            planNameLabel.stringValue = "当前套餐：--"
            expiryLabel.stringValue = "套餐到期：--"
            return
        }
        updateTimeLabel.stringValue = UpdateTimeFormatter.label(lastRefreshAt: now)
        resetTimeLabel.stringValue = "下次重置：\(ResetCountdownFormatter.string(resetsAt: snapshot.resetsAt, now: now))"
        planNameLabel.stringValue = "当前套餐：\(snapshot.planName ?? "--")"
        expiryLabel.stringValue = "套餐到期：\(expiryString(currentSubscriptionExpiry))"
    }

    private func expiryString(_ date: Date?) -> String {
        guard let date else {
            return "--"
        }
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.calendar = .current
        formatter.locale = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func showAutoRefreshNoticeIfNeeded() {
        guard !preferences.hasShownAutoRefreshNotice else {
            return
        }
        activateApp()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Codex Quota 已启动"
        alert.informativeText = "额度每 15 秒自动更新一次，无需手动刷新。"
        alert.addButton(withTitle: "知道了")
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
