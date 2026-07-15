import AppKit
import CodexQuotaCore
import CodexQuotaUI

@MainActor
private final class MenuChoiceRow: NSView {
    private let checkmarkLabel = NSTextField(labelWithString: "✓")
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

        let titleLabel = NSTextField(labelWithString: title)
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
        actionButton.setAccessibilityLabel(title)
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
        isSelected = false
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
    private let sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)
    private let refreshQueue = DispatchQueue(
        label: "CodexQuota.refresh",
        qos: .utility
    )
    private var styleItems: [BatteryStyle: NSMenuItem] = [:]
    private var labelToggleItem: NSMenuItem?
    private var currentSnapshot: QuotaSnapshot?
    private var refreshTimer: Timer?
    private var isRefreshing = false

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
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    private func configureStatusItem() {
        updateStatusPresentation()

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(makeUpdateRowItem())
        menu.addItem(.separator())

        for style in BatteryStyle.allCases {
            let item = makeStyleItem(style)
            styleItems[style] = item
            menu.addItem(item)
        }

        let labelItem = makeLabelToggleItem()
        labelToggleItem = labelItem
        menu.addItem(labelItem)

        menu.addItem(.separator())

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

    private func makeUpdateRowItem() -> NSMenuItem {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 52))

        updateTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        updateTimeLabel.lineBreakMode = .byClipping
        updateTimeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        resetTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        resetTimeLabel.lineBreakMode = .byClipping
        resetTimeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        row.addSubview(updateTimeLabel)
        row.addSubview(resetTimeLabel)
        NSLayoutConstraint.activate([
            updateTimeLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            updateTimeLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            updateTimeLabel.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -12),
            resetTimeLabel.leadingAnchor.constraint(equalTo: updateTimeLabel.leadingAnchor),
            resetTimeLabel.topAnchor.constraint(equalTo: updateTimeLabel.bottomAnchor, constant: 3),
            resetTimeLabel.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -12)
        ])

        let item = NSMenuItem()
        item.view = row
        return item
    }

    private func makeStyleItem(_ style: BatteryStyle) -> NSMenuItem {
        let preview = renderer.presentation(
            style: style,
            remainingPercent: 60,
            showsCodexLabel: false
        ).image
        preview.isTemplate = true
        let row = MenuChoiceRow(
            title: style.menuTitle,
            previewImage: preview,
            tag: BatteryStyle.allCases.firstIndex(of: style) ?? 0,
            target: self,
            action: #selector(selectBatteryStyle(_:))
        )
        let item = NSMenuItem()
        item.view = row
        return item
    }

    private func makeLabelToggleItem() -> NSMenuItem {
        let row = MenuChoiceRow(
            title: "显示 Codex 文字",
            tag: 0,
            target: self,
            action: #selector(toggleCodexLabel(_:))
        )
        let item = NSMenuItem()
        item.view = row
        return item
    }

    private func syncMenuState() {
        let selectedStyle = preferences.batteryStyle
        for (style, item) in styleItems {
            item.state = style == selectedStyle ? .on : .off
            (item.view as? MenuChoiceRow)?.isSelected = style == selectedStyle
        }
        labelToggleItem?.state = preferences.showsCodexLabel ? .on : .off
        (labelToggleItem?.view as? MenuChoiceRow)?.isSelected = preferences.showsCodexLabel
    }

    private func updateStatusPresentation() {
        let presentation = renderer.presentation(
            style: preferences.batteryStyle,
            remainingPercent: currentSnapshot?.remainingPercent,
            showsCodexLabel: preferences.showsCodexLabel
        )
        statusItem.button?.image = presentation.image
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly
        let labelState = preferences.showsCodexLabel ? "显示 Codex 文字" : "隐藏 Codex 文字"
        statusItem.button?.setAccessibilityLabel(
            "\(presentation.accessibilityLabel)，\(preferences.batteryStyle.menuTitle)，\(labelState)"
        )
    }

    @objc private func selectBatteryStyle(_ sender: NSButton) {
        guard BatteryStyle.allCases.indices.contains(sender.tag) else {
            return
        }
        let style = BatteryStyle.allCases[sender.tag]
        preferences.batteryStyle = style
        syncMenuState()
        updateStatusPresentation()
    }

    @objc private func toggleCodexLabel(_ sender: NSButton) {
        preferences.showsCodexLabel.toggle()
        syncMenuState()
        updateStatusPresentation()
    }

    @objc private func refreshFromTimer() {
        refresh()
    }

    private func refresh() {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true

        let sessionsRoot = sessionsRoot
        refreshQueue.async { [weak self] in
            let snapshot = QuotaStore().latestSnapshot(in: sessionsRoot)
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.isRefreshing = false
                self.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: QuotaSnapshot?) {
        currentSnapshot = snapshot
        updateHeaderLabels()
        updateStatusPresentation()
    }

    private func updateHeaderLabels(now: Date = Date()) {
        guard let snapshot = currentSnapshot else {
            updateTimeLabel.stringValue = "更新时间：--:--:--"
            resetTimeLabel.stringValue = "下次重置：--"
            return
        }
        updateTimeLabel.stringValue = "更新时间：\(UpdateTimeFormatter.string(observedAt: snapshot.observedAt))"
        resetTimeLabel.stringValue = "下次重置：\(ResetCountdownFormatter.string(resetsAt: snapshot.resetsAt, now: now))"
    }

    private func showAutoRefreshNoticeIfNeeded() {
        guard !preferences.hasShownAutoRefreshNotice else {
            return
        }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
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
