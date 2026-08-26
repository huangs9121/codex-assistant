import AppKit
import CodexQuotaCore
import CoreGraphics

@MainActor
final class MouseGestureSettingsPanelController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private enum Column: String {
        case gesture, filter, action, note, enabled
    }

    private let defaults: UserDefaults
    private let text: AppText
    private let controller: MouseGestureController
    private let onRulesChanged: () -> Void
    private var rules: [MouseGestureRule] = []
    private var shortcutMonitor: Any?
    private var recordingRow: Int?

    private let tableView = NSTableView()
    private let permissionLabel = NSTextField(labelWithString: "")
    private let accessibilityButton = NSButton(title: "", target: nil, action: nil)
    private lazy var panel = makePanel()

    init(
        defaults: UserDefaults = .standard,
        text: AppText,
        controller: MouseGestureController,
        onRulesChanged: @escaping () -> Void
    ) {
        self.defaults = defaults
        self.text = text
        self.controller = controller
        self.onRulesChanged = onRulesChanged
        super.init()
    }

    func show() {
        reloadRules()
        refreshPermissionStatus()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }

    func windowDidResignKey(_ notification: Notification) {
        stopRecording()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 430),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = text.rightClickShortcutOperations
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let content = NSView(frame: panel.contentView?.bounds ?? .zero)
        panel.contentView = content

        let hint = NSTextField(wrappingLabelWithString: text.rightClickShortcutHint)
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        configureTable()
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let addButton = NSButton(title: "+", target: self, action: #selector(addRule))
        addButton.bezelStyle = .rounded
        addButton.font = .systemFont(ofSize: 18)
        let removeButton = NSButton(title: "−", target: self, action: #selector(removeRule))
        removeButton.bezelStyle = .rounded
        removeButton.font = .systemFont(ofSize: 18)
        let tableActions = NSStackView(views: [addButton, removeButton])
        tableActions.orientation = .horizontal
        tableActions.spacing = 6
        tableActions.translatesAutoresizingMaskIntoConstraints = false

        permissionLabel.font = .systemFont(ofSize: 12)
        permissionLabel.translatesAutoresizingMaskIntoConstraints = false
        accessibilityButton.title = text.openSettings
        accessibilityButton.target = self
        accessibilityButton.action = #selector(openAccessibilitySettings)
        accessibilityButton.bezelStyle = .rounded
        accessibilityButton.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(hint)
        content.addSubview(scrollView)
        content.addSubview(tableActions)
        content.addSubview(permissionLabel)
        content.addSubview(accessibilityButton)
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            hint.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            scrollView.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 12),
            scrollView.heightAnchor.constraint(equalToConstant: 230),
            tableActions.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            tableActions.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 10),
            permissionLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            permissionLabel.centerYAnchor.constraint(equalTo: accessibilityButton.centerYAnchor),
            accessibilityButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            accessibilityButton.topAnchor.constraint(equalTo: tableActions.bottomAnchor, constant: 14),
            accessibilityButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
        ])
        return panel
    }

    private func configureTable() {
        tableView.frame = NSRect(x: 0, y: 0, width: 720, height: 230)
        tableView.autoresizingMask = [.width]
        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 34
        tableView.usesAlternatingRowBackgroundColors = true
        for (column, width) in [
            (Column.gesture, 90.0), (Column.filter, 185.0), (Column.action, 140.0),
            (Column.note, 220.0), (Column.enabled, 70.0)
        ] {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = columnTitle(column)
            tableColumn.width = width
            tableColumn.minWidth = width
            tableView.addTableColumn(tableColumn)
        }
        tableView.sizeLastColumnToFit()
    }

    private func columnTitle(_ column: Column) -> String {
        switch column {
        case .gesture: text.gesture
        case .filter: text.filter
        case .action: text.action
        case .note: text.description
        case .enabled: text.enabled
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rules.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn,
              let column = Column(rawValue: tableColumn.identifier.rawValue),
              rules.indices.contains(row) else { return nil }
        switch column {
        case .gesture, .filter, .note:
            let field = NSTextField(string: value(for: column, rule: rules[row]))
            field.tag = row
            field.identifier = tableColumn.identifier
            field.delegate = self
            field.font = .systemFont(ofSize: 14)
            field.isBordered = false
            field.drawsBackground = false
            return field
        case .action:
            let button = NSButton(title: actionTitle(for: row), target: self, action: #selector(recordShortcut(_:)))
            button.tag = row
            button.bezelStyle = .rounded
            button.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            return button
        case .enabled:
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRule(_:)))
            button.tag = row
            button.state = rules[row].isEnabled ? .on : .off
            button.setAccessibilityLabel(text.enabled)
            return button
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field.identifier?.rawValue == Column.gesture.rawValue else { return }
        let normalized = MouseGestureRule.normalizedGesture(field.stringValue)
        if field.stringValue != normalized {
            field.stringValue = normalized
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              rules.indices.contains(field.tag),
              let column = field.identifier.flatMap({ Column(rawValue: $0.rawValue) }) else { return }
        switch column {
        case .gesture:
            rules[field.tag].gesture = MouseGestureRule.normalizedGesture(field.stringValue)
        case .filter:
            rules[field.tag].appFilter = field.stringValue
        case .note:
            rules[field.tag].note = field.stringValue
        default:
            return
        }
        saveRules()
    }

    @objc private func addRule() {
        stopRecording()
        rules.append(MouseGestureRule())
        saveRules()
        tableView.reloadData()
        let row = rules.count - 1
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.editColumn(0, row: row, with: nil, select: true)
    }

    @objc private func removeRule() {
        let row = tableView.selectedRow
        guard rules.indices.contains(row) else { return }
        stopRecording()
        rules.remove(at: row)
        saveRules()
        tableView.reloadData()
    }

    @objc private func toggleRule(_ sender: NSButton) {
        guard rules.indices.contains(sender.tag) else { return }
        rules[sender.tag].isEnabled = sender.state == .on
        saveRules()
    }

    @objc private func recordShortcut(_ sender: NSButton) {
        if recordingRow == sender.tag {
            stopRecording()
            tableView.reloadData(forRowIndexes: IndexSet(integer: sender.tag), columnIndexes: IndexSet(integer: 2))
            return
        }
        stopRecording()
        recordingRow = sender.tag
        tableView.reloadData(forRowIndexes: IndexSet(integer: sender.tag), columnIndexes: IndexSet(integer: 2))
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow, let row = self.recordingRow else { return event }
            if event.keyCode == 53 {
                self.stopRecording()
                self.tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 2))
                return nil
            }
            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue))
            guard KeyboardShortcut.isValid(keyCode: event.keyCode, flags: flags.rawValue) else { return nil }
            self.rules[row].keyCode = event.keyCode
            self.rules[row].modifierFlags = flags.rawValue
            self.saveRules()
            self.stopRecording()
            self.tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 2))
            return nil
        }
    }

    @objc private func openAccessibilitySettings() {
        controller.openAccessibilitySettings()
    }

    private func actionTitle(for row: Int) -> String {
        guard rules.indices.contains(row) else { return text.noShortcut }
        if recordingRow == row { return text.recordingShortcut }
        let rule = rules[row]
        return rule.hasValidShortcut
            ? KeyboardShortcut.displayString(keyCode: rule.keyCode, flags: rule.modifierFlags)
            : text.recordShortcut
    }

    private func value(for column: Column, rule: MouseGestureRule) -> String {
        switch column {
        case .gesture: rule.gesture
        case .filter: rule.appFilter
        case .note: rule.note
        default: ""
        }
    }

    private func reloadRules() {
        stopRecording()
        rules = MouseGestureController.loadRules(from: defaults)
        tableView.reloadData()
    }

    private func saveRules() {
        MouseGestureController.saveRules(rules, to: defaults)
        controller.reloadRules()
        _ = controller.startIfPermitted()
        onRulesChanged()
        refreshPermissionStatus()
    }

    private func refreshPermissionStatus() {
        let trusted = controller.isAccessibilityTrusted
        permissionLabel.stringValue = trusted
            ? text.rightClickShortcutPermissionGranted
            : text.rightClickShortcutPermissionRequired
        permissionLabel.textColor = trusted ? .secondaryLabelColor : .systemOrange
    }

    private func stopRecording() {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        recordingRow = nil
    }
}
