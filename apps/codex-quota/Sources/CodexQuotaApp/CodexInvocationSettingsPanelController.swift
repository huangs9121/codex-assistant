import AppKit
import CodexQuotaCore
import CoreGraphics

@MainActor
final class CodexInvocationSettingsPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private enum Column: String { case source, target, note, enabled }
    private let defaults: UserDefaults
    private let text: AppText
    private let controller: DoubleCommandTapController
    private let onEnabledChanged: (Bool) -> Void
    private let onGestureSaved: () -> Void
    private let onPermissionRefresh: () -> Void
    private var rules: [KeyMappingRule] = []
    private let table = NSTableView()
    private let enabledButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let permissionLabel = NSTextField(labelWithString: "")
    private var permissionTimer: Timer?
    private var recording: (row: Int, source: Bool)?
    private var monitor: Any?
    private var recordingTimer: Timer?
    private var tapKey: UInt16?
    private var tapCount = 0
    private var pressedModifiers: Set<UInt16> = []
    private var candidateShortcut: KeyMappingShortcut?
    private var manualPanel: NSPanel?
    private var manualRow = 0
    private var manualSource = true
    private let manualType = NSPopUpButton()
    private let manualKey = NSPopUpButton()
    private let manualModifierKey = NSPopUpButton()
    private var modifierButtons: [NSButton] = []
    private let modifiers: [(String, UInt64)] = [("⌃ Control", KeyboardShortcut.controlFlag), ("⌥ Option", KeyboardShortcut.optionFlag), ("⇧ Shift", KeyboardShortcut.shiftFlag), ("⌘ Command", KeyboardShortcut.commandFlag)]
    private let gestureKeys: [UInt16] = [55, 54, 58, 61, 56, 60, 59, 62, 63]
    private var keyboardCodes: [UInt16] { (0...126).filter { ($0 == 63 || !KeyMappingShortcut.modifierKeyCodes.contains($0)) && !KeyboardShortcut.displayString(keyCode: $0, flags: 0).hasPrefix("Key ") } }
    private lazy var embeddedContentView = makeContentView()

    init(defaults: UserDefaults = .standard, text: AppText,
         doubleCommandTapController: DoubleCommandTapController,
         onEnabledChanged: @escaping (Bool) -> Void, onGestureSaved: @escaping () -> Void,
         onPermissionRefresh: @escaping () -> Void) {
        self.defaults = defaults; self.text = text; controller = doubleCommandTapController
        self.onEnabledChanged = onEnabledChanged; self.onGestureSaved = onGestureSaved
        self.onPermissionRefresh = onPermissionRefresh
        super.init()
    }
    var contentView: NSView { embeddedContentView }
    func didBecomeVisible() {
        rules = DoubleCommandTapController.loadRules(from: defaults)
        table.reloadData(); refreshPermissionStatus()
        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: 2, target: self, selector: #selector(refreshPermissionStatus), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common); permissionTimer = timer
    }
    func didHide() { stopRecording(); closeManual(); permissionTimer?.invalidate(); permissionTimer = nil }
    func hostWindowDidResignKey() { if manualPanel == nil { stopRecording() } }

    private func makeContentView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))
        enabledButton.title = text.enableKeyMappings
        enabledButton.font = .systemFont(ofSize: 14, weight: .medium)
        enabledButton.target = self; enabledButton.action = #selector(toggleEnabled)
        let hint = NSTextField(wrappingLabelWithString: text.keyMappingHint)
        hint.font = .systemFont(ofSize: 13); hint.textColor = .secondaryLabelColor
        table.delegate = self; table.dataSource = self
        table.frame = NSRect(x: 0, y: 0, width: 650, height: 230)
        QuickToolsTableStyle.configure(table)
        for (column, title, width) in [(Column.source, text.originalShortcut, 230.0), (.target, text.mappedShortcut, 230.0), (.note, text.description, 148.0), (.enabled, text.enabled, 42.0)] {
            let item = NSTableColumn(identifier: .init(column.rawValue))
            item.title = title; item.width = width; item.minWidth = width
            table.addTableColumn(item)
        }
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true; scroll.borderType = .bezelBorder
        let add = NSButton(title: "+", target: self, action: #selector(addRule))
        let remove = NSButton(title: "−", target: self, action: #selector(removeRule))
        for button in [add, remove] { button.bezelStyle = .rounded; button.font = .systemFont(ofSize: 18) }
        add.setAccessibilityLabel(text.addKeyMapping); remove.setAccessibilityLabel(text.removeKeyMapping)
        let actions = NSStackView(views: [add, remove]); actions.spacing = 6
        permissionLabel.font = .systemFont(ofSize: 12)
        let settings = NSButton(title: text.openSettings, target: self, action: #selector(openPermissions(_:)))
        settings.bezelStyle = .rounded
        for child in [enabledButton, hint, scroll, actions, permissionLabel, settings] {
            child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            enabledButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            enabledButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            hint.topAnchor.constraint(equalTo: enabledButton.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 12),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            actions.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            actions.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            settings.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            settings.topAnchor.constraint(equalTo: actions.bottomAnchor, constant: 14),
            settings.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
            permissionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            permissionLabel.centerYAnchor.constraint(equalTo: settings.centerYAnchor),
            permissionLabel.trailingAnchor.constraint(lessThanOrEqualTo: settings.leadingAnchor, constant: -12)
        ])
        return view
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rules.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rules.indices.contains(row), let column = tableColumn.flatMap({ Column(rawValue: $0.identifier.rawValue) }) else { return nil }
        switch column {
        case .source, .target:
            let source = column == .source
            let isRecording = recording?.row == row && recording?.source == source
            let title = isRecording ? text.recordingShortcut : (source ? display(rules[row].trigger) : rules[row].target?.displayString ?? text.noShortcut)
            let record = NSButton(title: title, target: self, action: #selector(startRecording(_:)))
            record.tag = row * 2 + (source ? 0 : 1); record.bezelStyle = .rounded
            record.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            record.toolTip = source ? text.recordOriginalShortcut : text.recordMappedShortcut
            let manual = NSButton(image: NSImage(systemSymbolName: "keyboard", accessibilityDescription: text.configureShortcut) ?? NSImage(), target: self, action: #selector(showManual(_:)))
            manual.tag = record.tag; manual.bezelStyle = .rounded
            manual.toolTip = text.configureShortcut
            let stack = NSStackView(views: [record, manual]); stack.spacing = 8
            return stack
        case .note:
            let field = SingleClickTextField(string: rules[row].note)
            field.tag = row; field.delegate = self; field.font = .systemFont(ofSize: 14)
            field.isBordered = false; field.drawsBackground = false
            return field
        case .enabled:
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRule(_:)))
            button.tag = row; button.state = rules[row].isEnabled ? .on : .off
            button.setAccessibilityLabel(text.enabled)
            return button
        }
    }
    private func display(_ trigger: KeyMappingTrigger?) -> String {
        switch trigger {
        case .shortcut(let shortcut): return shortcut.displayString
        case let .modifierTap(keys, count): return ModifierTapGesture(keyCodes: keys, tapCount: count).displayString(text: text)
        case nil: return text.noShortcut
        }
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, rules.indices.contains(field.tag) else { return }
        rules[field.tag].note = field.stringValue; save()
    }
    @objc private func addRule() {
        stopRecording(); rules.append(KeyMappingRule()); save(); table.reloadData()
        table.selectRowIndexes(IndexSet(integer: rules.count - 1), byExtendingSelection: false)
        table.scrollRowToVisible(rules.count - 1)
    }
    @objc private func removeRule() {
        let row = table.selectedRow
        guard rules.indices.contains(row) else { return }
        stopRecording(); rules.remove(at: row); save(); table.reloadData()
    }
    @objc private func toggleEnabled() { onEnabledChanged(enabledButton.state == .on); refreshPermissionStatus() }
    @objc private func toggleRule(_ button: NSButton) {
        guard rules.indices.contains(button.tag) else { return }
        var candidate = rules[button.tag]; candidate.isEnabled = button.state == .on
        _ = commit(candidate, row: button.tag)
        table.reloadData()
    }
    @discardableResult private func commit(_ rule: KeyMappingRule, row: Int) -> Bool {
        guard rules.indices.contains(row) else { return false }
        if let conflict = KeyMappingRule.conflictingRule(for: rule, in: rules) {
            let alert = NSAlert(); alert.messageText = text.keyMappingConflict
            alert.informativeText = "\(display(conflict.trigger)) — \(conflict.note.isEmpty ? text.originalShortcut : conflict.note)\n\(text.keyMappingConflictHint)"
            if let window = contentView.window { alert.beginSheetModal(for: window) }
            return false
        }
        rules[row] = rule; save(); table.reloadData(); return true
    }
    private func save() {
        DoubleCommandTapController.saveRules(rules, to: defaults)
        controller.reloadGesture(); onGestureSaved(); onPermissionRefresh()
    }
    @objc private func refreshPermissionStatus() {
        onPermissionRefresh()
        enabledButton.state = controller.isEnabled ? .on : .off
        permissionLabel.stringValue = text.inputMonitoringPermissionStatus(isAuthorized: controller.isInputMonitoringTrusted)
            + "   ·   " + text.accessibilityPermissionStatus(isAuthorized: controller.isAccessibilityTrusted)
        permissionLabel.textColor = controller.permissionStatus == .running ? .secondaryLabelColor : .systemOrange
    }
    @objc private func openPermissions(_ sender: NSButton) {
        let menu = NSMenu()
        for (title, action) in [(text.inputMonitoringSettings, #selector(openInputMonitoring)), (text.accessibilitySettings, #selector(openAccessibility))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
    }
    @objc private func openInputMonitoring() { controller.openInputMonitoringSettings() }
    @objc private func openAccessibility() { controller.openAccessibilitySettings() }

    // During recording all global mappings are suspended, including the existing modifier gesture.
    @objc private func startRecording(_ button: NSButton) {
        let row = button.tag / 2; let source = button.tag % 2 == 0
        guard rules.indices.contains(row) else { return }
        if recording?.row == row && recording?.source == source { stopRecording(); return }
        stopRecording(); recording = (row, source); controller.setRecording(true); table.reloadData()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self, self.recording != nil, self.contentView.window?.isKeyWindow == true else { return event }
            return self.record(event)
        }
    }
    private func record(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown, event.keyCode == 53 { stopRecording(); return nil }
        let flags = UInt64(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
        if recording?.source == false, event.type == .flagsChanged, event.keyCode == 63 {
            if event.modifierFlags.contains(.function) { pressedModifiers.insert(63) }
            else if pressedModifiers.remove(63) != nil {
                let fn = KeyMappingShortcut(keyCode: 63, flags: 0)
                finish(trigger: .modifierTap(keyCodes: [63], tapCount: 1), target: fn)
            }
            return nil
        }
        if event.type == .keyDown {
            guard !event.isARepeat, candidateShortcut == nil else { return nil }
            recordingTimer?.invalidate(); tapKey = nil; tapCount = 0
            let shortcut = KeyMappingShortcut(keyCode: event.keyCode, flags: flags)
            if shortcut.isValid { candidateShortcut = shortcut }
            return nil
        }
        if let candidate = candidateShortcut {
            if event.type == .keyUp && event.keyCode == candidate.keyCode {
                finish(trigger: .shortcut(candidate), target: candidate)
            }
            return event.type == .flagsChanged ? event : nil
        }
        guard recording?.source == true, event.type == .flagsChanged,
              ModifierTapGesture.isSupported(keyCode: event.keyCode),
              let modifierFlag = ModifierTapGesture.modifierFlag(for: event.keyCode) else { return event }
        let isUp = pressedModifiers.remove(event.keyCode) != nil
        if !isUp { pressedModifiers.insert(event.keyCode) }
        let otherFlags = KeyMappingShortcut.modifierMask & ~modifierFlag.rawValue
        guard pressedModifiers.count <= 1, flags & otherFlags == 0 else {
            recordingTimer?.invalidate(); tapKey = nil; tapCount = 0; return event
        }
        guard isUp else { return event }
        if tapKey != event.keyCode { tapKey = event.keyCode; tapCount = 0 }
        tapCount += 1
        if tapCount == 2 { finish(trigger: .modifierTap(keyCodes: [event.keyCode], tapCount: 2), target: nil) }
        else {
            recordingTimer?.invalidate()
            let timer = Timer(timeInterval: ModifierTapSequence.maximumInterval, target: self, selector: #selector(confirmSingleTap), userInfo: nil, repeats: false)
            RunLoop.main.add(timer, forMode: .common); recordingTimer = timer
        }
        return event
    }
    @objc private func confirmSingleTap() {
        guard let key = tapKey, pressedModifiers.isEmpty else { return }
        finish(trigger: .modifierTap(keyCodes: [key], tapCount: 1), target: nil)
    }
    private func finish(trigger: KeyMappingTrigger, target: KeyMappingShortcut?) {
        guard let recording, rules.indices.contains(recording.row) else { stopRecording(); return }
        var candidate = rules[recording.row]
        if recording.source { candidate.trigger = trigger } else { candidate.target = target }
        stopRecording()
        _ = commit(candidate, row: recording.row)
    }
    private func stopRecording() {
        let wasRecording = recording != nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; recording = nil; recordingTimer?.invalidate(); recordingTimer = nil
        tapKey = nil; tapCount = 0; pressedModifiers.removeAll(); candidateShortcut = nil
        if wasRecording { controller.setRecording(false); table.reloadData() }
    }

    @objc private func showManual(_ button: NSButton) {
        guard let window = contentView.window, manualPanel == nil, rules.indices.contains(button.tag / 2) else { return }
        stopRecording(); manualRow = button.tag / 2; manualSource = button.tag % 2 == 0
        controller.setRecording(true)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 280), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = manualSource ? text.originalShortcut : text.mappedShortcut
        panel.isReleasedWhenClosed = false
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 280)); panel.contentView = view
        manualType.removeAllItems(); manualType.addItems(withTitles: [text.keyCombination, text.modifierSingleTap, text.modifierDoubleTap])
        manualType.isEnabled = manualSource; manualType.target = self; manualType.action = #selector(changeManualType)
        manualType.frame = NSRect(x: 20, y: 222, width: 220, height: 28)
        manualKey.removeAllItems(); manualKey.addItems(withTitles: keyboardCodes.map { KeyboardShortcut.displayString(keyCode: $0, flags: 0) })
        manualKey.frame = NSRect(x: 20, y: 178, width: 220, height: 28)
        manualKey.target = self; manualKey.action = #selector(changeManualType)
        manualModifierKey.removeAllItems()
        manualModifierKey.addItems(withTitles: gestureKeys.map { ModifierTapGesture(keyCodes: [$0], tapCount: 1).displayString(text: text) })
        manualModifierKey.frame = manualKey.frame
        let shortcut = manualSource ? rules[manualRow].trigger.flatMap { if case .shortcut(let key) = $0 { return key }; return nil } : rules[manualRow].target
        if let code = shortcut?.keyCode, let index = keyboardCodes.firstIndex(of: code) { manualKey.selectItem(at: index) }
        if manualSource, case let .modifierTap(keys, count) = rules[manualRow].trigger {
            manualType.selectItem(at: count)
            if let index = gestureKeys.firstIndex(where: { keys.contains($0) }) { manualModifierKey.selectItem(at: index) }
        } else { manualType.selectItem(at: 0) }
        modifierButtons = modifiers.enumerated().map { index, item in
            let button = NSButton(checkboxWithTitle: item.0, target: nil, action: nil)
            button.state = (shortcut?.flags ?? 0) & item.1 != 0 ? .on : .off
            button.frame = NSRect(x: 20 + (index % 2) * 240, y: 128 - (index / 2) * 34, width: 220, height: 24)
            return button
        }
        let cancel = NSButton(title: text.cancel, target: self, action: #selector(closeManual))
        cancel.frame = NSRect(x: 290, y: 16, width: 88, height: 28); cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: text.save, target: self, action: #selector(saveManual))
        save.frame = NSRect(x: 388, y: 16, width: 88, height: 28); save.bezelStyle = .rounded; save.keyEquivalent = "\r"
        for child in [manualType, manualKey, manualModifierKey, cancel, save] + modifierButtons { view.addSubview(child) }
        manualPanel = panel; changeManualType(); window.beginSheet(panel)
    }
    @objc private func changeManualType() {
        let gesture = manualType.indexOfSelectedItem > 0
        manualKey.isHidden = gesture; manualModifierKey.isHidden = !gesture
        let fn = manualKey.indexOfSelectedItem >= 0 && keyboardCodes[manualKey.indexOfSelectedItem] == 63
        for button in modifierButtons { button.isHidden = gesture || fn }
    }
    @objc private func saveManual() {
        guard rules.indices.contains(manualRow) else { closeManual(); return }
        var candidate = rules[manualRow]
        let flags = zip(modifierButtons, modifiers).reduce(UInt64(0)) { $0 | ($1.0.state == .on ? $1.1.1 : 0) }
        let code = keyboardCodes[manualKey.indexOfSelectedItem]
        let shortcut = KeyMappingShortcut(keyCode: code, flags: code == 63 ? 0 : flags)
        if manualSource {
            candidate.trigger = manualType.indexOfSelectedItem == 0 ? (shortcut.isFunctionKey ? .modifierTap(keyCodes: [63], tapCount: 1) : .shortcut(shortcut))
                : .modifierTap(keyCodes: [gestureKeys[manualModifierKey.indexOfSelectedItem]], tapCount: manualType.indexOfSelectedItem)
        } else { candidate.target = shortcut }
        let row = manualRow
        closeManual()
        _ = commit(candidate, row: row)
    }
    @objc private func closeManual() {
        guard let panel = manualPanel else { return }
        panel.sheetParent?.endSheet(panel); panel.orderOut(nil); manualPanel = nil
        controller.setRecording(false)
    }
}
