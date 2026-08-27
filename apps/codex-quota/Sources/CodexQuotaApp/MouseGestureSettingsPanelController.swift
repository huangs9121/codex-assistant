import AppKit
import CodexQuotaCore
import CoreGraphics

private final class SingleClickTextField: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

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
    private let manualPopover = NSPopover()
    private var manualRow: Int?
    private var manualKeyCode: UInt16 = 0
    private var manualFlags: UInt64 = 0
    private let manualPreview = NSTextField(labelWithString: "")

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
            (Column.gesture, 130.0), (Column.filter, 145.0), (Column.action, 155.0),
            (Column.note, 170.0), (Column.enabled, 60.0)
        ] {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = columnTitle(column)
            tableColumn.width = width
            tableColumn.minWidth = width
            tableView.addTableColumn(tableColumn)
        }
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
        case .gesture:
            return gestureControls(row: row)
        case .filter, .note:
            let field = SingleClickTextField(string: value(for: column, rule: rules[row]))
            field.tag = row
            field.identifier = tableColumn.identifier
            field.delegate = self
            field.font = .systemFont(ofSize: 14)
            field.isEditable = true
            field.isSelectable = true
            field.isBordered = false
            field.drawsBackground = false
            return field
        case .action:
            let button = NSButton(title: actionTitle(for: row), target: self, action: #selector(recordShortcut(_:)))
            button.tag = row
            button.bezelStyle = .rounded
            button.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            let manual = NSButton(image: NSImage(systemSymbolName: "keyboard", accessibilityDescription: text.action) ?? NSImage(), target: self, action: #selector(showManualShortcut(_:)))
            manual.tag = row
            manual.bezelStyle = .rounded
            return NSStackView(views: [button, manual])
        case .enabled:
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRule(_:)))
            button.tag = row
            button.state = rules[row].isEnabled ? .on : .off
            button.setAccessibilityLabel(text.enabled)
            return button
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              rules.indices.contains(field.tag),
              let column = field.identifier.flatMap({ Column(rawValue: $0.rawValue) }) else { return }
        switch column {
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
        rules.append(MouseGestureRule(gesture: [.down]))
        saveRules()
        tableView.reloadData()
        let row = rules.count - 1
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.editColumn(1, row: row, with: nil, select: true)
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

    private func gestureControls(row: Int) -> NSView {
        let first = NSPopUpButton(frame: .zero, pullsDown: false)
        let second = NSPopUpButton(frame: .zero, pullsDown: false)
        for direction in MouseGestureDirection.allCases {
            first.addItem(withTitle: direction.symbol)
            second.addItem(withTitle: direction.symbol)
        }
        second.insertItem(withTitle: text.none, at: 0)
        first.selectItem(withTitle: rules[row].gesture.first?.symbol ?? MouseGestureDirection.down.symbol)
        second.selectItem(withTitle: rules[row].gesture.dropFirst().first?.symbol ?? text.none)
        first.tag = row * 2
        second.tag = row * 2 + 1
        first.target = self; second.target = self
        first.action = #selector(changeGesture(_:)); second.action = #selector(changeGesture(_:))
        return NSStackView(views: [first, second])
    }

    @objc private func changeGesture(_ sender: NSPopUpButton) {
        let row = sender.tag / 2
        guard rules.indices.contains(row) else { return }
        let segment = sender.tag % 2
        let selected = sender.titleOfSelectedItem.flatMap { title in MouseGestureDirection.allCases.first { $0.symbol == title } }
        if segment == 0 {
            rules[row].gesture = selected.map { [$0] } ?? [.down]
        } else if let selected {
            let first = rules[row].gesture.first ?? .down
            rules[row].gesture = [first, selected]
        } else {
            rules[row].gesture = Array(rules[row].gesture.prefix(1))
        }
        saveRules()
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
    }

    @objc private func openAccessibilitySettings() {
        controller.openAccessibilitySettings()
    }

    @objc private func showManualShortcut(_ sender: NSButton) {
        manualRow = sender.tag
        manualKeyCode = rules[sender.tag].keyCode
        manualFlags = rules[sender.tag].modifierFlags
        manualPopover.contentViewController = NSViewController()
        manualPopover.contentViewController?.view = makeManualShortcutView()
        manualPopover.behavior = .transient
        manualPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    private func makeManualShortcutView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        manualPreview.stringValue = KeyboardShortcut.displayString(keyCode: manualKeyCode, flags: manualFlags)
        manualPreview.alignment = .center; manualPreview.font = .monospacedSystemFont(ofSize: 20, weight: .medium); manualPreview.frame = NSRect(x: 20, y: 320, width: 480, height: 28)
        view.addSubview(manualPreview)
        let modifiers: [(String, UInt64)] = [("⌃ Control", KeyboardShortcut.controlFlag), ("⌥ Option", KeyboardShortcut.optionFlag), ("⇧ Shift", KeyboardShortcut.shiftFlag), ("⌘ Command", KeyboardShortcut.commandFlag)]
        for (index, item) in modifiers.enumerated() {
            let button = NSButton(checkboxWithTitle: item.0, target: self, action: #selector(toggleManualModifier(_:)))
            button.tag = index; button.state = manualFlags & item.1 != 0 ? .on : .off; button.frame = NSRect(x: 20, y: 275 - index * 34, width: 130, height: 26); view.addSubview(button)
        }
        let keys = manualKeys()
        for (index, key) in keys.enumerated() {
            let button = NSButton(title: key.0, target: self, action: #selector(selectManualKey(_:)))
            button.tag = Int(key.1); button.frame = NSRect(x: 170 + (index % 8) * 41, y: 275 - (index / 8) * 36, width: 37, height: 28); view.addSubview(button)
        }
        let save = NSButton(title: text.save, target: self, action: #selector(saveManualShortcut)); save.bezelStyle = .rounded; save.frame = NSRect(x: 420, y: 16, width: 80, height: 28); view.addSubview(save)
        return view
    }

    @objc private func toggleManualModifier(_ sender: NSButton) { let flags = [KeyboardShortcut.controlFlag, KeyboardShortcut.optionFlag, KeyboardShortcut.shiftFlag, KeyboardShortcut.commandFlag]; manualFlags ^= flags[sender.tag]; refreshManualPreview() }
    @objc private func selectManualKey(_ sender: NSButton) { manualKeyCode = UInt16(sender.tag); refreshManualPreview() }
    @objc private func saveManualShortcut() { guard let row = manualRow else { return }; rules[row].keyCode = manualKeyCode; rules[row].modifierFlags = manualFlags; saveRules(); manualPopover.close(); tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 2)) }
    private func refreshManualPreview() { manualPreview.stringValue = KeyboardShortcut.displayString(keyCode: manualKeyCode, flags: manualFlags) }
    private func manualKeys() -> [(String, UInt16)] {
        var keys: [(String, UInt16)] = [("Esc",53),("Space",49),("Tab",48),("Return",36),("Delete",51),("←",123),("↑",126),("→",124),("↓",125)]
        keys += (0...25).map { (String(UnicodeScalar(65 + $0)!), ansiKeyCode(for: $0)) }
        keys += (0...9).map { (String($0), digitKeyCode(for: $0)) }
        keys += [("F1",122),("F2",120),("F3",99),("F4",118),("F5",96),("F6",97),("F7",98),("F8",100),("F9",101),("F10",109),("F11",103),("F12",111)]
        return keys
    }
    private func ansiKeyCode(for index: Int) -> UInt16 { [0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6][index] }
    private func digitKeyCode(for digit: Int) -> UInt16 { [29,18,19,20,21,23,22,26,28,25][digit] }

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
        case .gesture: rule.displayGesture
        case .filter: rule.appFilter
        case .note: rule.note
        default: ""
        }
    }

    private func reloadRules() {
        stopRecording()
        rules = MouseGestureController.loadRules(from: defaults)
        let needsDefaultGesture = rules.indices.filter { rules[$0].gesture.isEmpty }
        for index in needsDefaultGesture {
            rules[index].gesture = [.down]
        }
        if !needsDefaultGesture.isEmpty {
            MouseGestureController.saveRules(rules, to: defaults)
            controller.reloadRules()
            _ = controller.startIfPermitted()
            onRulesChanged()
        }
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
