import AppKit
import CodexQuotaUI

private final class FlippedSettingsView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class QuickToolsPanelController: NSObject, NSWindowDelegate {
    enum Page: Int, CaseIterable {
        case general, scrollReversal, rightClickGesture, globalShortcut
        case sleep, quota, appearance, about

        var title: String {
            switch self {
            case .general: "通用"
            case .scrollReversal: "鼠标滚轮"
            case .rightClickGesture: "右键手势"
            case .globalShortcut: "按键映射"
            case .sleep: "防睡眠"
            case .quota: "额度"
            case .appearance: "外观"
            case .about: "关于"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .scrollReversal: "computermouse"
            case .rightClickGesture: "hand.draw"
            case .globalShortcut: "keyboard"
            case .sleep: "moon"
            case .quota: "chart.pie"
            case .appearance: "paintbrush"
            case .about: "info.circle"
            }
        }
    }

    struct SettingsState: Equatable {
        var launchAtLogin = false
        var launchAtLoginDetail = "登录 Mac 后自动在菜单栏运行趁手。"
        var displayModeIndex = 0
        var islandDisplayOptions: [IslandDisplayOption] = []
        var islandDisplayID: String?
        var islandDisplayDetail = "选择灵动岛显示在哪块屏幕。"
        var islandDualIndex = 0
        var islandDualLeftIndex = 0
        var manualSleepEnabled = false
        var manualSleepDetail = "合盖后继续运行，直到手动关闭或退出趁手。"
        var quotaProviderIndex = 0
        var quotaStatus = ""
        var batteryStyleIndex = 0
        var identityStyleIndex = 0
        var showsResetCountdown = true
        var showsResetForecast = true
        var version = ""
    }

    struct SettingsActions {
        var setLaunchAtLogin: (Bool) -> Void = { _ in }
        var setDisplayMode: (Int) -> Void = { _ in }
        var setIslandDisplay: (String?) -> Void = { _ in }
        var setIslandDual: (Int) -> Void = { _ in }
        var setIslandDualLeft: (Int) -> Void = { _ in }
        var setManualSleep: (Bool) -> Void = { _ in }
        var setQuotaProvider: (Int) -> Void = { _ in }
        var setBatteryStyle: (Int) -> Void = { _ in }
        var setIdentityStyle: (Int) -> Void = { _ in }
        var setResetCountdown: (Bool) -> Void = { _ in }
        var setResetForecast: (Bool) -> Void = { _ in }
        var openNodeScores: () -> Void = {}
        var checkUpdates: () -> Void = {}
        var showOnboarding: (() -> Void)?
        var openResetCalendar: () -> Void = {}
        var openDisplaySleep: () -> Void = {}
        var refreshQuota: () -> Void = {}
        var quit: () -> Void = {}
        var onClose: () -> Void = {}
    }

    // This key belongs to the original three-tab window. Keep it for existing callers.
    static let selectedPageDefaultsKey = "quickToolsSelectedPage"
    private static let settingsSelectedPageDefaultsKey = "settingsSelectedPage"
    private let defaults: UserDefaults
    private let text: AppText
    private let mouseScrollReversalController: MouseScrollReversalController
    private let codexInvocationSettingsController: CodexInvocationSettingsPanelController
    private let mouseGestureSettingsController: MouseGestureSettingsPanelController
    private let onScrollReversalEnabledChanged: (Bool) -> Void
    private var stateProvider: () -> SettingsState = { SettingsState() }
    private var actions = SettingsActions()
    private var renderedState: SettingsState?
    private struct ScrollRuntimeState: Equatable {
        let enabled: Bool
        let trusted: Bool
        let running: Bool
    }
    private var renderedScrollState: ScrollRuntimeState?

    private let sidebar = NSView()
    private let rightPane = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let contentContainer = NSView()
    private let scrollReversalEnabledButton = HelpButton(checkboxWithTitle: "", target: nil, action: nil)
    private var sidebarButtons: [Page: NSButton] = [:]
    private var activePage: Page?
    private var activeContentView: NSView?
    private var activeScrollView: NSScrollView?
    private lazy var panel = makePanel()

    init(
        defaults: UserDefaults = .standard,
        text: AppText,
        mouseScrollReversalController: MouseScrollReversalController,
        codexInvocationSettingsController: CodexInvocationSettingsPanelController,
        mouseGestureSettingsController: MouseGestureSettingsPanelController,
        onScrollReversalEnabledChanged: @escaping (Bool) -> Void
    ) {
        self.defaults = defaults
        self.text = text
        self.mouseScrollReversalController = mouseScrollReversalController
        self.codexInvocationSettingsController = codexInvocationSettingsController
        self.mouseGestureSettingsController = mouseGestureSettingsController
        self.onScrollReversalEnabledChanged = onScrollReversalEnabledChanged
        super.init()
    }

    func configureSettings(
        stateProvider: @escaping () -> SettingsState,
        actions: SettingsActions
    ) {
        self.stateProvider = stateProvider
        self.actions = actions
        renderedState = nil
        if panel.isVisible { refreshActivePage() }
    }

    func refreshSettings() {
        if panel.isVisible { refreshActivePage() }
    }

    func show() {
        let panel = self.panel
        let page = Page(rawValue: defaults.integer(forKey: Self.settingsSelectedPageDefaultsKey)) ?? .general
        select(page: page, persistSelection: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    // 0/1/2 remain the original scroll/mapping/gesture entry points.
    func show(pageIndex: Int) {
        defaults.set(pageIndex, forKey: Self.selectedPageDefaultsKey)
        let page: Page
        switch pageIndex {
        case 0: page = .scrollReversal
        case 1: page = .globalShortcut
        case 2: page = .rightClickGesture
        default: page = .general
        }
        _ = panel
        select(page: page, persistSelection: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func show(page: Page) {
        _ = panel
        select(page: page, persistSelection: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        deactivateActivePage()
        actions.onClose()
    }

    func windowDidResignKey(_ notification: Notification) {
        codexInvocationSettingsController.hostWindowDidResignKey()
        mouseGestureSettingsController.hostWindowDidResignKey()
    }

    private func makePanel() -> NSWindow {
        let window = QuickToolsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "趁手设置"
        // The settings design is light with fixed light backgrounds; keep the whole window, its
        // controls and sheets in the light appearance so text stays readable in Dark Mode.
        window.appearance = NSAppearance(named: .aqua)
        window.contentMinSize = NSSize(width: 880, height: 620)
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(srgbRed: 0.964, green: 0.971, blue: 0.982, alpha: 1).cgColor
        window.contentView = root
        for view in [sidebar, rightPane] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor(srgbRed: 0.968, green: 0.978, blue: 0.998, alpha: 1).cgColor
        rightPane.wantsLayer = true
        rightPane.layer?.backgroundColor = NSColor(srgbRed: 0.975, green: 0.979, blue: 0.985, alpha: 1).cgColor
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 174),
            rightPane.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            rightPane.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            rightPane.topAnchor.constraint(equalTo: root.topAnchor),
            rightPane.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        buildSidebar()
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = NSColor(srgbRed: 0.15, green: 0.18, blue: 0.23, alpha: 1)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        rightPane.addSubview(titleLabel)
        rightPane.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor, constant: 28),
            titleLabel.topAnchor.constraint(equalTo: rightPane.topAnchor, constant: 26),
            contentContainer.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            contentContainer.bottomAnchor.constraint(equalTo: rightPane.bottomAnchor)
        ])
        return window
    }

    private func buildSidebar() {
        let brand = NSTextField(labelWithString: "趁手")
        brand.font = .systemFont(ofSize: 16, weight: .semibold)
        brand.translatesAutoresizingMaskIntoConstraints = false
        let iconURL = Bundle.main.url(forResource: "chenshou-icon", withExtension: "png")
        let symbol = NSImageView(image: iconURL.flatMap(NSImage.init(contentsOf:)) ?? NSImage())
        symbol.imageScaling = .scaleProportionallyUpOrDown
        symbol.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(symbol)
        sidebar.addSubview(brand)
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            symbol.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 20),
            symbol.widthAnchor.constraint(equalToConstant: 32),
            symbol.heightAnchor.constraint(equalToConstant: 32),
            brand.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 9),
            brand.centerYAnchor.constraint(equalTo: symbol.centerYAnchor)
        ])
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: symbol.bottomAnchor, constant: 22)
        ])
        for page in Page.allCases {
            if page == .scrollReversal || page == .quota {
                let section = NSTextField(labelWithString: page == .scrollReversal ? "便捷工具" : "应用设置")
                section.font = .systemFont(ofSize: 10, weight: .medium)
                section.textColor = .tertiaryLabelColor
                stack.addArrangedSubview(section)
                section.heightAnchor.constraint(equalToConstant: 25).isActive = true
            }
            let button = NSButton(title: page.title, target: self, action: #selector(changePage(_:)))
            button.tag = page.rawValue
            button.isBordered = false
            button.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.title)
            button.imagePosition = .imageLeading
            button.alignment = .left
            button.font = .systemFont(ofSize: 13)
            button.contentTintColor = NSColor(srgbRed: 0.35, green: 0.40, blue: 0.48, alpha: 1)
            // With keyboard navigation on, the first item gets focus when the window opens and the
            // ring hugs the symbol, leaving a blue blob on the gear. The row highlight shows selection.
            button.focusRingType = .none
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setAccessibilityLabel(page.title)
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: 31).isActive = true
            sidebarButtons[page] = button
        }
        let quitButton = NSButton(title: "退出趁手", target: self, action: #selector(quitFromSettings))
        quitButton.isBordered = false
        quitButton.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quitButton.imagePosition = .imageLeading
        quitButton.alignment = .left
        quitButton.font = .systemFont(ofSize: 11)
        quitButton.contentTintColor = .tertiaryLabelColor
        quitButton.focusRingType = .none
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(quitButton)
        NSLayoutConstraint.activate([
            quitButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            quitButton.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -18)
        ])
    }

    @objc private func changePage(_ sender: NSButton) {
        guard let page = Page(rawValue: sender.tag) else { return }
        select(page: page, persistSelection: true)
    }

    private func select(page: Page, persistSelection: Bool) {
        if persistSelection { defaults.set(page.rawValue, forKey: Self.settingsSelectedPageDefaultsKey) }
        titleLabel.stringValue = page.title
        for (item, button) in sidebarButtons {
            button.layer?.backgroundColor = (item == page
                ? NSColor(srgbRed: 0.89, green: 0.93, blue: 1, alpha: 1)
                : .clear).cgColor
            button.contentTintColor = item == page
                ? NSColor(srgbRed: 0.13, green: 0.40, blue: 0.78, alpha: 1)
                : NSColor(srgbRed: 0.35, green: 0.40, blue: 0.48, alpha: 1)
        }
        if activePage == page { refreshActivePage(); return }
        deactivateActivePage()
        activeContentView?.removeFromSuperview()
        activeScrollView?.removeFromSuperview()
        activeScrollView = nil
        let view: NSView
        switch page {
        case .scrollReversal: view = makeScrollReversalContentView()
        case .globalShortcut: view = codexInvocationSettingsController.contentView
        case .rightClickGesture: view = mouseGestureSettingsController.contentView
        default: view = makeSettingsPage(page)
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        if [.globalShortcut, .rightClickGesture].contains(page) {
            // Keep the editors' original contentView in its existing lifecycle.
            // The view remains the direct child; only its surface is styled.
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.white.cgColor
            view.layer?.cornerRadius = 10
            view.layer?.borderWidth = 1
            view.layer?.borderColor = NSColor(srgbRed: 0.89, green: 0.91, blue: 0.94, alpha: 1).cgColor
            contentContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 8),
                view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -8),
                view.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 2),
                view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -16)
            ])
        } else {
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.documentView = view
            contentContainer.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
                view.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
            ])
            activeScrollView = scroll
        }
        activePage = page
        activeContentView = view
        if page == .globalShortcut { codexInvocationSettingsController.didBecomeVisible() }
        if page == .rightClickGesture { mouseGestureSettingsController.didBecomeVisible() }
        refreshActivePage()
    }

    private func refreshActivePage() {
        switch activePage {
        case .scrollReversal:
            refreshScrollReversalConfiguration()
            if scrollRuntimeState() != renderedScrollState { replaceScrollPage() }
        case .globalShortcut, .rightClickGesture:
            // A periodic state refresh must not reload a rule currently being edited.
            break
        case .general, .sleep, .quota, .appearance, .about:
            guard let page = activePage else { return }
            guard stateProvider() != renderedState else { return }
            activeContentView?.removeFromSuperview()
            activeContentView = makeSettingsPage(page)
            if let scroll = activeScrollView {
                let view = activeContentView!
                view.translatesAutoresizingMaskIntoConstraints = false
                scroll.documentView = view
                view.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
            }
        case nil: break
        }
    }

    private func deactivateActivePage() {
        switch activePage {
        case .globalShortcut: codexInvocationSettingsController.didHide()
        case .rightClickGesture: mouseGestureSettingsController.didHide()
        default: break
        }
        activePage = nil
    }

    private func makeScrollReversalContentView() -> NSView {
        renderedScrollState = scrollRuntimeState()
        let view = makePageCanvas()
        let stack = makeVerticalStack()
        attach(stack, to: view)
        addGroupHeading("滚轮反转", to: stack)
        let card = makeCard()
        let button = scrollReversalEnabledButton
        button.title = "启用滚轮反转"
        button.target = self
        button.action = #selector(toggleScrollReversal)
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.allowsMixedState = false
        let row = makeRow("鼠标滚轮方向", detail: text.mouseScrollReversalHint, symbol: "computermouse", accessory: button)
        card.addArrangedSubview(row)
        stack.addArrangedSubview(card)
        addGroupHeading("所需权限", to: stack)
        let permissionCard = makeCard()
        let status: String
        let buttonTitle: String
        if !mouseScrollReversalController.isAccessibilityTrusted {
            status = "尚未授权辅助功能，滚轮监听无法运行。"
            buttonTitle = "打开设置"
        } else if mouseScrollReversalController.isEnabled && !mouseScrollReversalController.isRunning {
            status = "已授权，但滚轮监听未启动。"
            buttonTitle = "重新检查"
        } else {
            status = mouseScrollReversalController.isRunning
                ? "已授权，滚轮监听正在运行。"
                : "已授权，滚轮反转未启用。"
            buttonTitle = "检查权限"
        }
        permissionCard.addArrangedSubview(makeRow("辅助功能", detail: status, symbol: "checkmark.shield",
            accessory: makeActionButton(buttonTitle, action: #selector(checkScrollPermission))))
        stack.addArrangedSubview(permissionCard)
        addGroupHeading("试滚区域", to: stack)
        let trialCard = makeCard()
        let trialRow = NSView()
        trialRow.translatesAutoresizingMaskIntoConstraints = false
        let mouseTrial = makeScrollTrialColumn("鼠标滚轮")
        let trackpadTrial = makeScrollTrialColumn("触控板")
        trialRow.addSubview(mouseTrial)
        trialRow.addSubview(trackpadTrial)
        NSLayoutConstraint.activate([
            mouseTrial.leadingAnchor.constraint(equalTo: trialRow.leadingAnchor, constant: 14),
            mouseTrial.topAnchor.constraint(equalTo: trialRow.topAnchor, constant: 12),
            mouseTrial.bottomAnchor.constraint(equalTo: trialRow.bottomAnchor, constant: -12),
            trackpadTrial.leadingAnchor.constraint(equalTo: mouseTrial.trailingAnchor, constant: 12),
            trackpadTrial.trailingAnchor.constraint(equalTo: trialRow.trailingAnchor, constant: -14),
            trackpadTrial.topAnchor.constraint(equalTo: trialRow.topAnchor, constant: 12),
            trackpadTrial.bottomAnchor.constraint(equalTo: trialRow.bottomAnchor, constant: -12),
            mouseTrial.widthAnchor.constraint(equalTo: trackpadTrial.widthAnchor)
        ])
        trialRow.heightAnchor.constraint(equalToConstant: 170).isActive = true
        trialCard.addArrangedSubview(trialRow)
        stack.addArrangedSubview(trialCard)
        trialCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        trialRow.widthAnchor.constraint(equalTo: trialCard.widthAnchor).isActive = true
        return view
    }

    @objc private func toggleScrollReversal() {
        onScrollReversalEnabledChanged(scrollReversalEnabledButton.state == .on)
        replaceScrollPage()
    }

    private func refreshScrollReversalConfiguration() {
        scrollReversalEnabledButton.state = mouseScrollReversalController.isEnabled ? .on : .off
    }

    @objc private func checkScrollPermission() {
        if !mouseScrollReversalController.isAccessibilityTrusted {
            mouseScrollReversalController.requestAccessibilityPermission()
            mouseScrollReversalController.openAccessibilitySettings()
        } else if mouseScrollReversalController.isEnabled {
            _ = mouseScrollReversalController.startIfPermitted()
        }
        replaceScrollPage()
    }

    private func scrollRuntimeState() -> ScrollRuntimeState {
        ScrollRuntimeState(
            enabled: mouseScrollReversalController.isEnabled,
            trusted: mouseScrollReversalController.isAccessibilityTrusted,
            running: mouseScrollReversalController.isRunning
        )
    }

    private func replaceScrollPage() {
        guard activePage == .scrollReversal, let scroll = activeScrollView else { return }
        activeContentView?.removeFromSuperview()
        let view = makeScrollReversalContentView()
        view.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = view
        view.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        activeContentView = view
    }

    private func makeScrollTrialColumn(_ title: String) -> NSView {
        let column = NSView()
        column.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        let sample = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 250))
        let deviceInstructions = title == "鼠标滚轮"
            ? "使用外接鼠标向下滚动。启用反转后，内容移动方向应与未启用时相反。"
            : "用触控板双指向下滑动。趁手不会改变触控板的系统滚动方向。"
        sample.string = """
        顶部 · 起点
        先缓慢向下滚动，观察内容如何移动。
        再快速滚动一次，直到看见中部标记。

        第一段 · 设备行为
        \(deviceInstructions)
        在这里向上滚动一次，再继续向下。

        中部 · 对照
        试着停在这一段，确认滚动能准确停止。
        向上滚动回看第一段，再向下到下一段。
        两个试滚区可以分别操作，互不影响。

        第三段 · 往返
        连续向下滚动两次，然后向上滚动一次。
        对照鼠标与触控板的手感是否符合预期。

        底部 · 终点
        看到此行表示已经滚过整个试滚区。
        向上滚回顶部，可重复进行对照。
        """
        sample.isEditable = false
        sample.isSelectable = false
        sample.isVerticallyResizable = true
        sample.isHorizontallyResizable = false
        sample.autoresizingMask = [.width]
        sample.textContainer?.widthTracksTextView = true
        sample.drawsBackground = false
        sample.font = .systemFont(ofSize: 11)
        sample.textColor = .secondaryLabelColor
        sample.textContainerInset = NSSize(width: 9, height: 9)
        let scroll = NSScrollView()
        scroll.documentView = sample
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.wantsLayer = true
        scroll.layer?.backgroundColor = NSColor(srgbRed: 0.985, green: 0.99, blue: 1, alpha: 1).cgColor
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = NSColor(srgbRed: 0.91, green: 0.93, blue: 0.95, alpha: 1).cgColor
        scroll.layer?.cornerRadius = 6
        for item in [label, scroll] {
            item.translatesAutoresizingMaskIntoConstraints = false
            column.addSubview(item)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            label.topAnchor.constraint(equalTo: column.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 7),
            scroll.bottomAnchor.constraint(equalTo: column.bottomAnchor)
        ])
        return column
    }

    private func makeSettingsPage(_ page: Page) -> NSView {
        let view = makePageCanvas()
        let stack = makeVerticalStack()
        attach(stack, to: view)
        let state = stateProvider()
        renderedState = state
        switch page {
        case .general:
            addGroupHeading("启动与行为", to: stack)
            let card = makeCard()
            card.addArrangedSubview(makeRow("登录时启动", detail: state.launchAtLoginDetail, symbol: "arrow.clockwise",
                accessory: makeSwitch(state.launchAtLogin, label: "登录时启动", tag: 1, action: #selector(changeSwitch(_:)))))
            card.addArrangedSubview(makeSeparator())
            card.addArrangedSubview(makeRow("显示入口", detail: "选择趁手的主要常驻入口。", symbol: "display",
                accessory: makeSegments(["灵动岛", "菜单栏"], selected: state.displayModeIndex, tag: 1, action: #selector(changeSegment(_:)))))
            card.addArrangedSubview(makeSeparator())
            if state.displayModeIndex == 0 {
                card.addArrangedSubview(makeRow("灵动岛显示器", detail: state.islandDisplayDetail, symbol: "display",
                    accessory: makeDisplayPicker(state)))
                card.addArrangedSubview(makeSeparator())
                card.addArrangedSubview(makeRow("灵动岛内容", detail: "双持时刘海两侧各显示一个服务。", symbol: "circle.lefthalf.filled",
                    accessory: makeSegments(["单个", "双持"], selected: state.islandDualIndex, tag: 5, action: #selector(changeSegment(_:)))))
                card.addArrangedSubview(makeSeparator())
                if state.islandDualIndex == 1 {
                    card.addArrangedSubview(makeRow("双持方位", detail: "也可以右键灵动岛直接互换。", symbol: "arrow.left.arrow.right",
                        accessory: makeSegments(["Codex 在左", "Claude 在左"], selected: state.islandDualLeftIndex, tag: 6, action: #selector(changeSegment(_:)))))
                    card.addArrangedSubview(makeSeparator())
                }
            }
            card.addArrangedSubview(makeRow("节点评分", detail: "按需测试当前网络并查看本地历史排行。", symbol: "network",
                accessory: makeActionButton("打开", action: #selector(openNodeScores))))
            stack.addArrangedSubview(card)
        case .sleep:
            addGroupHeading("手动合盖防睡眠", to: stack)
            let card = makeCard()
            card.addArrangedSubview(makeRow("保持 Mac 运行", detail: state.manualSleepDetail, symbol: "moon",
                accessory: makeActionButton(state.manualSleepEnabled ? "关闭" : "开启…", action: #selector(toggleManualSleep))))
            stack.addArrangedSubview(card)
            addGroupHeading("熄屏继续工作", to: stack)
            let screen = makeCard()
            screen.addArrangedSubview(makeRow("关闭显示器", detail: "当前任务运行时防止闲置睡眠。", symbol: "display",
                accessory: makeActionButton("开始熄屏", action: #selector(openDisplaySleep))))
            stack.addArrangedSubview(screen)
        case .quota:
            addGroupHeading("额度显示", to: stack)
            let card = makeCard()
            card.addArrangedSubview(makeRow("额度来源", detail: "在同一页配置 Codex 与 Claude 额度。", symbol: "chart.pie",
                accessory: makeSegments(["Codex", "Claude"], selected: state.quotaProviderIndex, tag: 2, action: #selector(changeSegment(_:)))))
            card.addArrangedSubview(makeSeparator())
            card.addArrangedSubview(makeRow("当前状态", detail: state.quotaStatus, symbol: "arrow.clockwise",
                accessory: makeActionButton("刷新", action: #selector(refreshQuota))))
            card.addArrangedSubview(makeSeparator())
            card.addArrangedSubview(makeRow("显示重置倒计时", detail: "在菜单栏显示当前额度窗口的重置倒计时。", symbol: "calendar",
                accessory: makeSwitch(state.showsResetCountdown, label: "显示重置倒计时", tag: 2, action: #selector(changeSwitch(_:)))))
            if state.quotaProviderIndex == 0 {
                card.addArrangedSubview(makeSeparator())
                card.addArrangedSubview(makeRow("显示 Codex 重置预告", detail: "有 AIHOT 公告时，在 Codex 额度区显示重置预告。", symbol: "bell",
                    accessory: makeSwitch(state.showsResetForecast, label: "显示 Codex 重置预告", tag: 3, action: #selector(changeSwitch(_:)))))
            }
            stack.addArrangedSubview(card)
            if state.quotaProviderIndex == 0 {
                addGroupHeading("Codex 重置日历", to: stack)
                let calendar = makeCard()
                calendar.addArrangedSubview(makeRow("重置日历 · AIHOT", detail: "查看 Codex 重置公告日历。", symbol: "calendar",
                    accessory: makeActionButton("打开日历", action: #selector(openResetCalendar))))
                stack.addArrangedSubview(calendar)
            }
        case .appearance:
            addGroupHeading("状态栏外观", to: stack)
            let card = makeCard()
            card.addArrangedSubview(makeRow("额度样式", detail: "选择菜单栏额度指示器的呈现方式。", symbol: "paintbrush",
                accessory: makeSegments(["原生电池", "数字徽章", "分段电池", "纯数字"], selected: state.batteryStyleIndex, tag: 3, action: #selector(changeSegment(_:)))))
            card.addArrangedSubview(makeSeparator())
            card.addArrangedSubview(makeRow("身份标识", detail: "标识随当前额度来源变化，可显示文字、图标或隐藏。", symbol: "person.crop.circle",
                accessory: makeSegments(["文字", "图标", "不显示"], selected: state.identityStyleIndex, tag: 4, action: #selector(changeSegment(_:)))))
            stack.addArrangedSubview(card)
        case .about:
            addGroupHeading("趁手", to: stack)
            let card = makeCard()
            card.addArrangedSubview(makeRow("趁手", detail: "Mac 工具箱 · 版本 \(state.version)", symbol: "hand.raised.fill", accessory: NSView()))
            card.addArrangedSubview(makeSeparator())
            card.addArrangedSubview(makeRow("检查更新", detail: "查看当前版本与可用更新。", symbol: "arrow.clockwise",
                accessory: makeActionButton("检查更新", action: #selector(checkUpdates))))
            stack.addArrangedSubview(card)
            if actions.showOnboarding != nil {
                addGroupHeading("支持与帮助", to: stack)
                let help = makeCard()
                help.addArrangedSubview(makeRow("欢迎与使用说明", detail: "重新查看趁手的功能介绍。", symbol: "info.circle",
                    accessory: makeActionButton("查看引导", action: #selector(showOnboarding))))
                stack.addArrangedSubview(help)
            }
        default: break
        }
        return view
    }

    private func makePageCanvas() -> NSView {
        let view = FlippedSettingsView(frame: NSRect(x: 0, y: 0, width: 706, height: 500))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(srgbRed: 0.975, green: 0.979, blue: 0.985, alpha: 1).cgColor
        return view
    }

    private func makeVerticalStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func attach(_ stack: NSStackView, to canvas: NSView) {
        canvas.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: canvas.bottomAnchor, constant: -24)
        ])
    }

    private func addGroupHeading(_ title: String, to stack: NSStackView) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        label.heightAnchor.constraint(equalToConstant: 22).isActive = true
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makeCard() -> NSStackView {
        let card = NSStackView()
        card.orientation = .vertical
        card.spacing = 0
        card.alignment = .width
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(srgbRed: 0.89, green: 0.91, blue: 0.94, alpha: 1).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true
        return card
    }

    private func makeRow(_ title: String, detail: String, symbol: String, accessory: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 68).isActive = true
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = NSColor(srgbRed: 0.35, green: 0.40, blue: 0.48, alpha: 1)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        for item in [icon, titleLabel, detailLabel, accessory] {
            item.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(item)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -10),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -10),
            accessory.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            accessory.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func makeSeparator() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(srgbRed: 0.91, green: 0.92, blue: 0.94, alpha: 1).cgColor
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func makeSwitch(_ enabled: Bool, label: String, tag: Int, action: Selector) -> NSSwitch {
        let button = NSSwitch()
        button.target = self
        button.action = action
        button.tag = tag
        button.state = enabled ? .on : .off
        button.setAccessibilityLabel(label)
        return button
    }

    private func makeSegments(_ titles: [String], selected: Int, tag: Int, action: Selector) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: titles, trackingMode: .selectOne, target: self, action: action)
        control.tag = tag
        control.selectedSegment = min(max(selected, 0), titles.count - 1)
        control.segmentStyle = .rounded
        control.font = .systemFont(ofSize: 11)
        return control
    }

    private func makeActionButton(_ title: String, action: Selector) -> NSButton {
        let button = HelpButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 11)
        return button
    }

    private func makeDisplayPicker(_ state: SettingsState) -> NSPopUpButton {
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.font = .systemFont(ofSize: 11)
        picker.target = self
        picker.action = #selector(changeIslandDisplay(_:))
        picker.setAccessibilityLabel("灵动岛显示器")
        picker.menu?.autoenablesItems = false
        for option in state.islandDisplayOptions {
            picker.addItem(withTitle: option.title)
            let item = picker.lastItem!
            item.representedObject = option.id ?? ""
            item.isEnabled = option.isAvailable
            if option.id == state.islandDisplayID { picker.select(item) }
        }
        picker.widthAnchor.constraint(equalToConstant: 210).isActive = true
        return picker
    }

    @objc private func changeIslandDisplay(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem, item.isEnabled,
              let id = item.representedObject as? String else { return }
        actions.setIslandDisplay(id.isEmpty ? nil : id)
        refreshActivePage()
    }

    @objc private func changeSwitch(_ sender: NSSwitch) {
        let value = sender.state == .on
        switch sender.tag {
        case 1: actions.setLaunchAtLogin(value)
        case 2: actions.setResetCountdown(value)
        case 3: actions.setResetForecast(value)
        default: break
        }
        refreshActivePage()
    }

    @objc private func changeSegment(_ sender: NSSegmentedControl) {
        switch sender.tag {
        case 1: actions.setDisplayMode(sender.selectedSegment)
        case 2: actions.setQuotaProvider(sender.selectedSegment)
        case 3: actions.setBatteryStyle(sender.selectedSegment)
        case 4: actions.setIdentityStyle(sender.selectedSegment)
        case 5: actions.setIslandDual(sender.selectedSegment)
        case 6: actions.setIslandDualLeft(sender.selectedSegment)
        default: break
        }
        refreshActivePage()
    }

    @objc private func toggleManualSleep() {
        actions.setManualSleep(!stateProvider().manualSleepEnabled)
        refreshActivePage()
    }
    @objc private func openNodeScores() { actions.openNodeScores() }
    @objc private func openDisplaySleep() { actions.openDisplaySleep() }
    @objc private func refreshQuota() { actions.refreshQuota() }
    @objc private func openResetCalendar() { actions.openResetCalendar() }
    @objc private func checkUpdates() { actions.checkUpdates() }
    @objc private func showOnboarding() { actions.showOnboarding?() }
    @objc private func quitFromSettings() { actions.quit() }
}
