import AppKit
import CodexQuotaCore
import CoreGraphics
import UniformTypeIdentifiers

// 列宽总和按最小可视宽度（竖向滚动条占位后的窄边 743pt）设置，
// 任何滚动条样式下都不会溢出；不要在布局期动态改列宽或表格 frame——
// AppKit 的延迟 tile 会按过宽的表格重排列，把最后的「启用」列挤出可视区。

@MainActor
final class MouseGestureSettingsPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private enum Column: String {
        case gesture, filter, action, note, immediate, enabled
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
    private var manualModifierButtons: [NSButton] = []
    private let appPickerPopover = NSPopover()
    private var appPickerRow: Int?
    private var appPickerTable: NSTableView?
    private var appPickerEmptyLabel: NSTextField?
    private var appSearchText = ""
    var availableAppsForPicker: [(name: String, bundleID: String)] = []

    private var filteredAppsForPicker: [(name: String, bundleID: String)] {
        let query = appSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return availableAppsForPicker }
        return availableAppsForPicker.filter {
            $0.name.lowercased().contains(query) || $0.bundleID.lowercased().contains(query)
        }
    }

    private let tableView = NSTableView()
    private let enabledButton = HelpButton(checkboxWithTitle: "", target: nil, action: nil)
    private let exclusionsButton = HelpButton(title: "", target: nil, action: nil)
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let exclusionsTable = NSTableView()
    private let exclusionsEmptyLabel = NSTextField(labelWithString: "")
    private let removeExclusionButton = HelpButton(title: "", target: nil, action: nil)
    private var exclusionsPanel: NSPanel?
    private let permissionLabel = NSTextField(labelWithString: "")
    private let accessibilityButton = HelpButton(title: "", target: nil, action: nil)
    private lazy var embeddedContentView = makeContentView()

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

    var contentView: NSView {
        embeddedContentView
    }

    func didBecomeVisible() {
        reloadRules()
        refreshGlobalSettings()
        refreshPermissionStatus()
    }

    func didHide() {
        stopRecording()
        manualPopover.close()
        appPickerPopover.close()
        closeExclusions()
    }

    func hostWindowDidResignKey() {
        stopRecording()
    }

    private func makeContentView() -> NSView {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 430))

        enabledButton.title = text.enableRightClickShortcuts
        enabledButton.font = .systemFont(ofSize: 14, weight: .medium)
        enabledButton.target = self
        enabledButton.action = #selector(toggleEnabled)
        enabledButton.translatesAutoresizingMaskIntoConstraints = false
        exclusionsButton.target = self
        exclusionsButton.action = #selector(showExclusions)
        exclusionsButton.bezelStyle = .rounded
        exclusionsButton.translatesAutoresizingMaskIntoConstraints = false
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        configureTable()
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let addButton = HelpButton(title: "+", target: self, action: #selector(addRule))
        addButton.bezelStyle = .rounded
        addButton.font = .systemFont(ofSize: 18)
        let removeButton = HelpButton(title: "−", target: self, action: #selector(removeRule))
        removeButton.bezelStyle = .rounded
        removeButton.font = .systemFont(ofSize: 18)
        addButton.toolTip = text.addKeyMapping
        removeButton.toolTip = text.removeKeyMapping
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

        content.addSubview(enabledButton)
        content.addSubview(exclusionsButton)
        content.addSubview(hint)
        content.addSubview(scrollView)
        content.addSubview(tableActions)
        content.addSubview(permissionLabel)
        content.addSubview(accessibilityButton)
        NSLayoutConstraint.activate([
            enabledButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            enabledButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            enabledButton.trailingAnchor.constraint(lessThanOrEqualTo: exclusionsButton.leadingAnchor, constant: -16),
            exclusionsButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            exclusionsButton.centerYAnchor.constraint(equalTo: enabledButton.centerYAnchor),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            hint.topAnchor.constraint(equalTo: enabledButton.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            scrollView.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 12),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            tableActions.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            tableActions.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 10),
            permissionLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            permissionLabel.centerYAnchor.constraint(equalTo: accessibilityButton.centerYAnchor),
            accessibilityButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            accessibilityButton.topAnchor.constraint(equalTo: tableActions.bottomAnchor, constant: 14),
            accessibilityButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
        ])
        refreshGlobalSettings()
        return content
    }

    private func refreshGlobalSettings() {
        let preferences = controller.preferences
        enabledButton.state = preferences.isEnabled ? .on : .off
        hint.stringValue = preferences.isEnabled ? text.rightClickShortcutHint : text.rightClickShortcutsDisabledHint
        exclusionsButton.title = "\(text.gestureExclusions)（\(preferences.excludedApplications.count)）…"
        exclusionsButton.toolTip = preferences.excludedApplications.isEmpty
            ? text.gestureExclusions
            : preferences.excludedApplications.map(\.name).joined(separator: ", ")
        exclusionsTable.reloadData()
        exclusionsEmptyLabel.isHidden = !preferences.excludedApplications.isEmpty
        removeExclusionButton.isEnabled = preferences.excludedApplications.indices.contains(exclusionsTable.selectedRow)
    }

    private func saveGlobalSettings(_ preferences: MouseGesturePreferences) {
        preferences.save(to: defaults)
        controller.reloadRules()
        _ = controller.startIfPermitted()
        onRulesChanged()
        refreshGlobalSettings()
        refreshPermissionStatus()
    }

    @objc private func toggleEnabled() {
        var preferences = controller.preferences
        preferences.isEnabled = enabledButton.state == .on
        saveGlobalSettings(preferences)
    }

    @objc private func showExclusions() {
        guard let window = contentView.window, exclusionsPanel == nil else { return }
        stopRecording()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        panel.title = text.gestureExclusions
        panel.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
        panel.contentView = content
        let title = NSTextField(labelWithString: text.gestureExclusions)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.frame = NSRect(x: 20, y: 318, width: 440, height: 22)
        let explanation = NSTextField(wrappingLabelWithString: text.gestureExclusionsHint)
        explanation.font = .systemFont(ofSize: 13)
        explanation.textColor = .secondaryLabelColor
        explanation.frame = NSRect(x: 20, y: 266, width: 440, height: 42)
        exclusionsTable.headerView = nil
        exclusionsTable.rowHeight = 44
        exclusionsTable.delegate = self
        exclusionsTable.dataSource = self
        exclusionsTable.usesAlternatingRowBackgroundColors = true
        exclusionsTable.frame = NSRect(x: 0, y: 0, width: 420, height: 196)
        if exclusionsTable.tableColumns.isEmpty {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("excludedApp"))
            column.width = 420
            exclusionsTable.addTableColumn(column)
        }
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 62, width: 440, height: 196))
        scroll.documentView = exclusionsTable
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        exclusionsEmptyLabel.stringValue = text.gestureExclusionsEmpty
        exclusionsEmptyLabel.font = .systemFont(ofSize: 13)
        exclusionsEmptyLabel.textColor = .secondaryLabelColor
        exclusionsEmptyLabel.alignment = .center
        exclusionsEmptyLabel.frame = NSRect(x: 20, y: 145, width: 440, height: 24)
        let add = HelpButton(title: text.addExcludedApplication, target: self, action: #selector(addExclusions))
        add.frame = NSRect(x: 20, y: 18, width: 120, height: 30)
        add.bezelStyle = .rounded
        removeExclusionButton.title = text.removeExcludedApplication
        removeExclusionButton.target = self
        removeExclusionButton.action = #selector(removeExclusion)
        removeExclusionButton.frame = NSRect(x: 144, y: 18, width: 180, height: 30)
        removeExclusionButton.bezelStyle = .rounded
        let done = HelpButton(title: text.done, target: self, action: #selector(closeExclusions))
        done.frame = NSRect(x: 372, y: 18, width: 88, height: 30)
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        for view in [title, explanation, scroll, exclusionsEmptyLabel, add, removeExclusionButton, done] {
            content.addSubview(view)
        }
        exclusionsPanel = panel
        refreshGlobalSettings()
        window.beginSheet(panel)
    }

    @objc private func closeExclusions() {
        guard let panel = exclusionsPanel else { return }
        panel.sheetParent?.endSheet(panel)
        panel.orderOut(nil)
        exclusionsPanel = nil
    }

    @objc private func addExclusions() {
        guard let panel = exclusionsPanel else { return }
        let picker = NSOpenPanel()
        picker.title = text.addExcludedApplication
        picker.allowedContentTypes = [.applicationBundle]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = true
        picker.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        picker.beginSheetModal(for: panel) { [weak self] response in
            guard let self, response == .OK else { return }
            var preferences = self.controller.preferences
            var invalidNames: [String] = []
            for url in picker.urls {
                guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier, !identifier.isEmpty else {
                    invalidNames.append(url.lastPathComponent)
                    continue
                }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                preferences.exclude(MouseGestureExcludedApplication(bundleIdentifier: identifier, name: name))
            }
            self.saveGlobalSettings(preferences)
            if !invalidNames.isEmpty {
                let alert = NSAlert()
                alert.messageText = self.text.invalidExcludedApplication
                alert.informativeText = invalidNames.joined(separator: "\n")
                alert.beginSheetModal(for: panel)
            }
        }
    }

    @objc private func removeExclusion() {
        var preferences = controller.preferences
        guard preferences.excludedApplications.indices.contains(exclusionsTable.selectedRow) else { return }
        preferences.removeExclusion(bundleIdentifier: preferences.excludedApplications[exclusionsTable.selectedRow].bundleIdentifier)
        saveGlobalSettings(preferences)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as? NSTableView === exclusionsTable else { return }
        removeExclusionButton.isEnabled = controller.preferences.excludedApplications.indices.contains(exclusionsTable.selectedRow)
    }

    private func configureTable() {
        tableView.frame = NSRect(x: 0, y: 0, width: 650, height: 230)
        tableView.delegate = self
        tableView.dataSource = self
        QuickToolsTableStyle.configure(tableView)
        // 列宽总和 650：系统新表格样式会按列累加约 11-17pt 装饰宽度，
        // 膨胀后约 720-752pt，仍小于最窄可视区（竖向滚动条占位后的 743pt）。
        for (column, width) in [
            (Column.gesture, 127.0), (Column.filter, 158.0), (Column.action, 144.0),
            (Column.note, 143.0), (Column.immediate, 36.0), (Column.enabled, 42.0)
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
        case .immediate: "⚡️"
        case .enabled: text.enabled
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === exclusionsTable { return controller.preferences.excludedApplications.count }
        return tableView === appPickerTable ? filteredAppsForPicker.count : rules.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        if tableView === exclusionsTable {
            guard controller.preferences.excludedApplications.indices.contains(row) else { return nil }
            let application = controller.preferences.excludedApplications[row]
            let name = NSTextField(labelWithString: application.name)
            name.font = .systemFont(ofSize: 14, weight: .medium)
            name.lineBreakMode = .byTruncatingTail
            let identifier = NSTextField(labelWithString: application.bundleIdentifier)
            identifier.font = .systemFont(ofSize: 12)
            identifier.textColor = .secondaryLabelColor
            identifier.lineBreakMode = .byTruncatingMiddle
            let stack = NSStackView(views: [name, identifier])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 2
            stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
            return stack
        }
        if tableView === appPickerTable {
            return appPickerRowView(row: row)
        }
        guard let tableColumn,
              let column = Column(rawValue: tableColumn.identifier.rawValue),
              rules.indices.contains(row) else { return nil }
        switch column {
        case .gesture:
            return gestureControls(row: row)
        case .filter:
            let field = SingleClickTextField(string: rules[row].appFilter)
            field.tag = row
            field.identifier = tableColumn.identifier
            field.delegate = self
            field.font = .systemFont(ofSize: 14)
            field.isEditable = true
            field.isSelectable = true
            field.isBordered = false
            field.drawsBackground = false
            field.setContentHuggingPriority(.init(1), for: .horizontal)
            let picker = HelpButton(
                image: NSImage(
                    systemSymbolName: "macwindow.on.rectangle",
                    accessibilityDescription: text.appPickerButton
                ) ?? NSImage(),
                target: self,
                action: #selector(showAppPicker(_:))
            )
            picker.tag = row
            picker.bezelStyle = .rounded
            picker.toolTip = text.appPickerTooltip
            picker.setContentCompressionResistancePriority(.required, for: .horizontal)
            let stack = NSStackView(views: [field, picker])
            stack.orientation = .horizontal
            stack.spacing = 4
            return stack
        case .note:
            let field = SingleClickTextField(string: rules[row].note)
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
            let button = HelpButton(title: actionTitle(for: row), target: self, action: #selector(recordShortcut(_:)))
            button.tag = row
            button.bezelStyle = .rounded
            button.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            button.toolTip = recordingRow == row ? text.recordingShortcut : text.recordShortcut
            let manual = HelpButton(image: NSImage(systemSymbolName: "keyboard", accessibilityDescription: text.action) ?? NSImage(), target: self, action: #selector(showManualShortcut(_:)))
            manual.tag = row
            manual.bezelStyle = .rounded
            manual.toolTip = text.configureShortcut
            return NSStackView(views: [button, manual])
        case .immediate:
            let button = HelpButton(checkboxWithTitle: "", target: self, action: #selector(toggleImmediateRule(_:)))
            button.tag = row
            button.state = rules[row].firesImmediately ? .on : .off
            button.setAccessibilityLabel(text.immediateTrigger)
            button.toolTip = text.immediateTrigger
            return button
        case .enabled:
            let button = HelpButton(checkboxWithTitle: "", target: self, action: #selector(toggleRule(_:)))
            button.tag = row
            button.state = rules[row].isEnabled ? .on : .off
            button.setAccessibilityLabel(text.enabled)
            button.toolTip = text.enabled
            return button
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field.identifier?.rawValue == "appPickerSearch" else { return }
        appSearchText = field.stringValue
        refreshAppPickerResults()
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

    @objc private func toggleImmediateRule(_ sender: NSButton) {
        guard rules.indices.contains(sender.tag) else { return }
        rules[sender.tag].firesImmediately = sender.state == .on
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
            guard
                let self,
                self.contentView.window?.isKeyWindow == true,
                let row = self.recordingRow
            else {
                return event
            }
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
        let first = HelpPopUpButton(frame: .zero, pullsDown: false)
        let second = HelpPopUpButton(frame: .zero, pullsDown: false)
        for direction in MouseGestureDirection.allCases {
            first.addItem(withTitle: direction.symbol)
            second.addItem(withTitle: direction.symbol)
        }
        second.insertItem(withTitle: text.none, at: 0)
        first.selectItem(withTitle: rules[row].gesture.first?.symbol ?? MouseGestureDirection.down.symbol)
        second.selectItem(withTitle: rules[row].gesture.dropFirst().first?.symbol ?? text.none)
        first.tag = row * 2
        second.tag = row * 2 + 1
        first.toolTip = text.language == .simplifiedChinese
            ? "选择手势的第一个方向"
            : "Choose the first gesture direction"
        second.toolTip = text.language == .simplifiedChinese
            ? "选择手势的第二个方向"
            : "Choose the second gesture direction"
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

    // MARK: - 应用选择器（过滤列）

    @objc private func showAppPicker(_ sender: NSButton) {
        guard rules.indices.contains(sender.tag) else { return }
        stopRecording()
        appPickerRow = sender.tag
        appSearchText = ""
        availableAppsForPicker = Self.runningApps()
        appPickerPopover.contentViewController = NSViewController()
        appPickerPopover.contentViewController?.view = makeAppPickerView()
        appPickerPopover.behavior = .transient
        appPickerPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    static func runningApps() -> [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (name: String, bundleID: String)? in
                guard let name = app.localizedName,
                      let bundleID = app.bundleIdentifier,
                      !bundleID.isEmpty else { return nil }
                return (name: name, bundleID: bundleID)
            }
            .reduce(into: [(name: String, bundleID: String)]()) { result, item in
                guard !result.contains(where: { $0.bundleID == item.bundleID }) else { return }
                result.append(item)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func makeAppPickerView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 340))

        let search = NSTextField(string: "")
        search.identifier = NSUserInterfaceItemIdentifier("appPickerSearch")
        search.placeholderString = text.appPickerSearchPlaceholder
        search.delegate = self
        search.frame = NSRect(x: 12, y: 302, width: 276, height: 26)
        view.addSubview(search)

        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = 36
        table.delegate = self
        table.dataSource = self
        table.frame = NSRect(x: 0, y: 0, width: 276, height: 282)
        table.autoresizingMask = [.width]
        table.target = self
        table.action = #selector(pickAppFromList(_:))
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app")))
        appPickerTable = table

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.frame = NSRect(x: 12, y: 12, width: 276, height: 282)
        scrollView.autoresizingMask = [.width, .height]
        view.addSubview(scrollView)

        let emptyLabel = NSTextField(labelWithString: text.appPickerEmptyHint)
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.frame = NSRect(x: 12, y: 143, width: 276, height: 20)
        emptyLabel.autoresizingMask = [.width]
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
        appPickerEmptyLabel = emptyLabel

        refreshAppPickerResults()
        return view
    }

    private func appPickerRowView(row: Int) -> NSView? {
        guard filteredAppsForPicker.indices.contains(row) else { return nil }
        let app = filteredAppsForPicker[row]
        let nameLabel = NSTextField(labelWithString: app.name)
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        let bundleLabel = NSTextField(labelWithString: app.bundleID)
        bundleLabel.font = .systemFont(ofSize: 11)
        bundleLabel.textColor = .secondaryLabelColor
        bundleLabel.lineBreakMode = .byTruncatingMiddle
        let stack = NSStackView(views: [nameLabel, bundleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func refreshAppPickerResults() {
        appPickerTable?.reloadData()
        appPickerEmptyLabel?.isHidden = !filteredAppsForPicker.isEmpty
    }

    @objc private func pickAppFromList(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard filteredAppsForPicker.indices.contains(row),
              let target = appPickerRow,
              rules.indices.contains(target) else { return }
        let bundleID = filteredAppsForPicker[row].bundleID
        let trimmed = rules[target].appFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "*" {
            rules[target].appFilter = bundleID
        } else {
            var patterns = trimmed.split(separator: "|", omittingEmptySubsequences: true).map(String.init)
            if !patterns.contains(bundleID) {
                patterns.append(bundleID)
            }
            rules[target].appFilter = patterns.joined(separator: "|")
        }
        saveRules()
        appPickerPopover.close()
        tableView.reloadData(
            forRowIndexes: IndexSet(integer: target),
            columnIndexes: IndexSet(integer: 1)
        )
    }

    private func makeManualShortcutView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        manualPreview.stringValue = shortcutDisplayString(keyCode: manualKeyCode, flags: manualFlags)
        manualPreview.alignment = .center; manualPreview.font = .monospacedSystemFont(ofSize: 20, weight: .medium); manualPreview.frame = NSRect(x: 20, y: 320, width: 480, height: 28)
        view.addSubview(manualPreview)
        let modifiers: [(String, UInt64)] = [("⌃ Control", KeyboardShortcut.controlFlag), ("⌥ Option", KeyboardShortcut.optionFlag), ("⇧ Shift", KeyboardShortcut.shiftFlag), ("⌘ Command", KeyboardShortcut.commandFlag)]
        manualModifierButtons = []
        for (index, item) in modifiers.enumerated() {
            let button = HelpButton(checkboxWithTitle: item.0, target: self, action: #selector(toggleManualModifier(_:)))
            button.tag = index; button.state = manualFlags & item.1 != 0 ? .on : .off; button.frame = NSRect(x: 20, y: 275 - index * 34, width: 130, height: 26); view.addSubview(button)
            manualModifierButtons.append(button)
        }
        let keys = manualKeys()
        for (index, key) in keys.enumerated() {
            let button = HelpButton(title: key.0, target: self, action: #selector(selectManualKey(_:)))
            button.tag = Int(key.1); button.frame = NSRect(x: 170 + (index % 8) * 41, y: 275 - (index / 8) * 36, width: 37, height: 28); view.addSubview(button)
        }
        let systemActions = NSTextField(labelWithString: text.systemActions)
        systemActions.font = .systemFont(ofSize: 12)
        systemActions.textColor = .secondaryLabelColor
        systemActions.frame = NSRect(x: 20, y: 136, width: 130, height: 18)
        view.addSubview(systemActions)
        for (index, action) in SystemGestureAction.all.enumerated() {
            let button = HelpButton(
                title: action.localizedName(language: text.language),
                target: self,
                action: #selector(selectSystemAction(_:))
            )
            button.tag = Int(action.keyCode)
            button.frame = NSRect(x: 20, y: 104 - index * 32, width: 130, height: 28)
            view.addSubview(button)
        }
        let save = HelpButton(title: text.save, target: self, action: #selector(saveManualShortcut)); save.bezelStyle = .rounded; save.frame = NSRect(x: 420, y: 16, width: 80, height: 28); view.addSubview(save)
        return view
    }

    @objc private func toggleManualModifier(_ sender: NSButton) {
        clearSystemActionIfNeeded()
        let flags = [KeyboardShortcut.controlFlag, KeyboardShortcut.optionFlag, KeyboardShortcut.shiftFlag, KeyboardShortcut.commandFlag]
        manualFlags ^= flags[sender.tag]
        refreshManualPreview()
    }

    @objc private func selectManualKey(_ sender: NSButton) {
        clearSystemActionIfNeeded()
        manualKeyCode = UInt16(sender.tag)
        refreshManualPreview()
    }

    @objc private func selectSystemAction(_ sender: NSButton) {
        guard let action = SystemGestureAction.action(
            keyCode: UInt16(sender.tag),
            modifierFlags: 0
        ) else { return }
        manualKeyCode = action.keyCode
        manualFlags = 0
        manualModifierButtons.forEach { $0.state = .off }
        refreshManualPreview()
    }

    @objc private func saveManualShortcut() { guard let row = manualRow else { return }; rules[row].keyCode = manualKeyCode; rules[row].modifierFlags = manualFlags; saveRules(); manualPopover.close(); tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 2)) }
    private func refreshManualPreview() { manualPreview.stringValue = shortcutDisplayString(keyCode: manualKeyCode, flags: manualFlags) }

    private func shortcutDisplayString(keyCode: UInt16, flags: UInt64) -> String {
        if let action = SystemGestureAction.action(keyCode: keyCode, modifierFlags: flags) {
            return action.localizedName(language: text.language)
        }
        return KeyboardShortcut.displayString(keyCode: keyCode, flags: flags)
    }

    private func clearSystemActionIfNeeded() {
        guard SystemGestureAction.action(keyCode: manualKeyCode, modifierFlags: manualFlags) != nil else {
            return
        }
        manualKeyCode = 0
        manualFlags = 0
    }
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
            ? shortcutDisplayString(keyCode: rule.keyCode, flags: rule.modifierFlags)
            : text.recordShortcut
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
