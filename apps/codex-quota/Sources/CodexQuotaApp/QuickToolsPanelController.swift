import AppKit

@MainActor
final class QuickToolsPanelController: NSObject, NSWindowDelegate {
    private enum Page: Int {
        case scrollReversal
        case globalShortcut
        case rightClickGesture
    }

    static let selectedPageDefaultsKey = "quickToolsSelectedPage"

    private let defaults: UserDefaults
    private let text: AppText
    private let mouseScrollReversalController: MouseScrollReversalController
    private let codexInvocationSettingsController: CodexInvocationSettingsPanelController
    private let mouseGestureSettingsController: MouseGestureSettingsPanelController
    private let onScrollReversalEnabledChanged: (Bool) -> Void

    private let pageControl = NSSegmentedControl()
    private let contentContainer = NSView()
    private let scrollReversalEnabledButton = NSButton(
        checkboxWithTitle: "",
        target: nil,
        action: nil
    )
    private var activePage: Page?
    private var activeContentView: NSView?
    private lazy var scrollReversalContentView = makeScrollReversalContentView()
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

    func show() {
        let panel = self.panel
        let selectedPage = Page(
            rawValue: defaults.integer(forKey: Self.selectedPageDefaultsKey)
        ) ?? .scrollReversal
        select(page: selectedPage, persistSelection: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        deactivateActivePage()
    }

    func windowDidResignKey(_ notification: Notification) {
        codexInvocationSettingsController.hostWindowDidResignKey()
        mouseGestureSettingsController.hostWindowDidResignKey()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 540),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = text.quickTools
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let content = NSView(frame: panel.contentView?.bounds ?? .zero)
        panel.contentView = content

        configurePageControl()
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(pageControl)
        content.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            pageControl.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            pageControl.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            contentContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            contentContainer.topAnchor.constraint(
                equalTo: pageControl.bottomAnchor,
                constant: 14
            ),
            contentContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        return panel
    }

    private func configurePageControl() {
        pageControl.segmentCount = 3
        pageControl.segmentStyle = .texturedRounded
        pageControl.trackingMode = .selectOne
        pageControl.target = self
        pageControl.action = #selector(changePage(_:))
        pageControl.setLabel(
            text.mouseScrollReversal,
            forSegment: Page.scrollReversal.rawValue
        )
        pageControl.setLabel(
            text.globalShortcutSettings,
            forSegment: Page.globalShortcut.rawValue
        )
        pageControl.setLabel(
            text.rightClickShortcutOperations,
            forSegment: Page.rightClickGesture.rawValue
        )
        pageControl.setToolTip(
            text.mouseScrollReversal,
            forSegment: Page.scrollReversal.rawValue
        )
        pageControl.setToolTip(
            text.globalShortcutSettings,
            forSegment: Page.globalShortcut.rawValue
        )
        pageControl.setToolTip(
            text.rightClickShortcutOperations,
            forSegment: Page.rightClickGesture.rawValue
        )
        pageControl.setAccessibilityLabel(text.quickTools)
    }

    @objc private func changePage(_ sender: NSSegmentedControl) {
        guard let page = Page(rawValue: sender.selectedSegment) else {
            return
        }
        select(page: page, persistSelection: true)
    }

    private func select(page: Page, persistSelection: Bool) {
        if persistSelection {
            defaults.set(page.rawValue, forKey: Self.selectedPageDefaultsKey)
        }
        pageControl.selectedSegment = page.rawValue
        guard activePage != page else {
            refreshActivePage()
            return
        }

        deactivateActivePage()
        activeContentView?.removeFromSuperview()

        let contentView: NSView
        switch page {
        case .scrollReversal:
            contentView = scrollReversalContentView
        case .globalShortcut:
            contentView = codexInvocationSettingsController.contentView
        case .rightClickGesture:
            contentView = mouseGestureSettingsController.contentView
        }
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(
                equalTo: contentContainer.leadingAnchor
            ),
            contentView.trailingAnchor.constraint(
                equalTo: contentContainer.trailingAnchor
            ),
            contentView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            contentView.bottomAnchor.constraint(
                equalTo: contentContainer.bottomAnchor
            )
        ])
        activePage = page
        activeContentView = contentView
        refreshActivePage()
    }

    private func refreshActivePage() {
        switch activePage {
        case .scrollReversal:
            refreshScrollReversalConfiguration()
        case .globalShortcut:
            codexInvocationSettingsController.didBecomeVisible()
        case .rightClickGesture:
            mouseGestureSettingsController.didBecomeVisible()
        case nil:
            break
        }
    }

    private func deactivateActivePage() {
        switch activePage {
        case .globalShortcut:
            codexInvocationSettingsController.didHide()
        case .rightClickGesture:
            mouseGestureSettingsController.didHide()
        case .scrollReversal, nil:
            break
        }
        activePage = nil
    }

    private func makeScrollReversalContentView() -> NSView {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))
        scrollReversalEnabledButton.title = text.mouseScrollReversal
        scrollReversalEnabledButton.target = self
        scrollReversalEnabledButton.action = #selector(toggleScrollReversal)
        scrollReversalEnabledButton.allowsMixedState = false
        scrollReversalEnabledButton.font = .systemFont(
            ofSize: 14,
            weight: .medium
        )

        let hint = NSTextField(
            wrappingLabelWithString: text.mouseScrollReversalHint
        )
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor

        let root = NSStackView(views: [scrollReversalEnabledButton, hint])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            hint.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
        return content
    }

    @objc private func toggleScrollReversal() {
        onScrollReversalEnabledChanged(
            scrollReversalEnabledButton.state == .on
        )
        refreshScrollReversalConfiguration()
    }

    private func refreshScrollReversalConfiguration() {
        scrollReversalEnabledButton.state = mouseScrollReversalController.isEnabled
            ? .on
            : .off
    }
}
