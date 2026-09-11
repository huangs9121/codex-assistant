import AppKit
import CodexQuotaCore

/// A single target editor shared by mouse gestures and keyboard mappings.
final class SystemActionPicker: NSView {
    private var selection: KeyMappingShortcut
    private let language: AppLanguage
    private let onSave: (KeyMappingShortcut) -> Void
    private let onCancel: () -> Void
    private let summary = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private var actionButtons: [NSButton] = []
    private var modifierButtons: [NSButton] = []
    private let key = NSPopUpButton()
    private let flags = [KeyboardShortcut.controlFlag, KeyboardShortcut.optionFlag, KeyboardShortcut.shiftFlag, KeyboardShortcut.commandFlag]
    private let codes: [UInt16] = (0...126).filter { ($0 == 63 || !KeyMappingShortcut.modifierKeyCodes.contains($0)) && !KeyboardShortcut.displayString(keyCode: $0, flags: 0).hasPrefix("Key ") }
    let scroll = NSScrollView()

    init(selection: KeyMappingShortcut, language: AppLanguage, onSave: @escaping (KeyMappingShortcut) -> Void, onCancel: @escaping () -> Void) {
        self.selection = selection; self.language = language; self.onSave = onSave; self.onCancel = onCancel
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 570))
        wantsLayer = true
        label(tr("选择动作", "Choose Action"), size: 21, weight: .semibold, rect: NSRect(x: 24, y: 516, width: 592, height: 28), centered: true)
        label(tr("右键快捷键与按键映射共用", "Shared by mouse gestures and key mappings"), size: 13, rect: NSRect(x: 24, y: 487, width: 592, height: 22), centered: true, secondary: true)
        separator(470)
        label(tr("常用系统动作", "Common System Actions"), size: 17, weight: .semibold, rect: NSRect(x: 24, y: 432, width: 570, height: 24))
        scroll.frame = NSRect(x: 24, y: 199, width: 592, height: 218)
        scroll.verticalScroller = VisibleActionScroller()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = false; scroll.scrollerStyle = .legacy
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        let actions = SystemGestureAction.all.sorted { order($0.id) < order($1.id) }
        let document = FlippedActionDocument(frame: NSRect(x: 0, y: 0, width: 573, height: CGFloat((actions.count + 1) / 2) * 80))
        for (index, action) in actions.enumerated() {
            let button = ActionTileButton(title: action.localizedName(language: language), target: self, action: #selector(selectAction(_:)))
            button.tag = Int(action.keyCode); button.setButtonType(.momentaryChange); button.isBordered = false
            button.font = .systemFont(ofSize: 16, weight: .medium)
            button.image = NSImage(systemSymbolName: symbol(action.id), accessibilityDescription: nil)
            button.image = button.image?.withSymbolConfiguration(.init(pointSize: 24, weight: .regular))
            button.imageHugsTitle = true
            button.imagePosition = .imageLeft; button.imageScaling = .scaleProportionallyDown
            button.frame = NSRect(x: (index % 2) * 290, y: (index / 2) * 80, width: 279, height: 68)
            button.wantsLayer = true
            button.setAccessibilityLabel(action.localizedName(language: language))
            document.addSubview(button); actionButtons.append(button)
        }
        scroll.documentView = document; addSubview(scroll)
        scroll.tile(); scroll.reflectScrolledClipView(scroll.contentView)
        scroll.verticalScroller?.isHidden = false
        separator(184)
        label(tr("自定义组合键", "Custom Shortcut"), size: 17, weight: .semibold, rect: NSRect(x: 24, y: 147, width: 580, height: 24))
        for (index, title) in ["Control", "Option", "Shift", "Command"].enumerated() {
            let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(selectCustom))
            button.font = .systemFont(ofSize: 14); button.frame = NSRect(x: 24 + index * 118, y: 104, width: 116, height: 28)
            modifierButtons.append(button); addSubview(button)
        }
        key.frame = NSRect(x: 506, y: 102, width: 108, height: 30)
        key.addItems(withTitles: codes.map { KeyboardShortcut.displayString(keyCode: $0, flags: 0) })
        key.target = self; key.action = #selector(selectCustom); addSubview(key)
        if let index = codes.firstIndex(of: selection.keyCode) { key.selectItem(at: index) }
        separator(85)
        summary.font = .systemFont(ofSize: 14, weight: .semibold); summary.frame = NSRect(x: 24, y: 49, width: 370, height: 24); addSubview(summary)
        detail.font = .systemFont(ofSize: 12); detail.textColor = .secondaryLabelColor; detail.frame = NSRect(x: 24, y: 24, width: 370, height: 21); addSubview(detail)
        let cancel = NSButton(title: tr("取消", "Cancel"), target: self, action: #selector(cancelSelection)); cancel.bezelStyle = .rounded; cancel.frame = NSRect(x: 414, y: 26, width: 90, height: 36); cancel.keyEquivalent = "\u{1b}"; addSubview(cancel)
        let save = PrimaryActionButton(title: tr("保存", "Save"), target: self, action: #selector(saveSelection)); save.bezelStyle = .rounded; save.frame = NSRect(x: 514, y: 26, width: 100, height: 36); save.keyEquivalent = "\r"; save.bezelColor = .controlAccentColor; addSubview(save)
        refresh()
    }
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func tr(_ zh: String, _ en: String) -> String { language == .simplifiedChinese ? zh : en }
    private func order(_ id: String) -> Int { ["captureSelection", "captureScreen", "recordScreen", "missionControl", "sleepDisplay", "screenSaver"].firstIndex(of: id) ?? 100 }
    private func symbol(_ id: String) -> String {
        ["captureSelection": "viewfinder", "captureScreen": "display", "recordScreen": "record.circle", "missionControl": "rectangle.3.group", "sleepDisplay": "display", "screenSaver": "moon"] [id] ?? "keyboard"
    }
    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, rect: NSRect, centered: Bool = false, secondary: Bool = false) {
        let field = NSTextField(labelWithString: text); field.font = .systemFont(ofSize: size, weight: weight); field.frame = rect
        if centered { field.alignment = .center }; if secondary { field.textColor = .secondaryLabelColor }; addSubview(field)
    }
    private func separator(_ y: CGFloat) { let line = NSBox(frame: NSRect(x: 24, y: y, width: 592, height: 1)); line.boxType = .separator; addSubview(line) }
    @objc private func selectAction(_ sender: NSButton) { selection = .init(keyCode: UInt16(sender.tag), flags: 0); refresh() }
    @objc private func selectCustom() {
        let code = codes[key.indexOfSelectedItem]
        selection = .init(keyCode: code, flags: code == 63 ? 0 : zip(modifierButtons, flags).reduce(UInt64(0)) { $0 | ($1.0.state == .on ? $1.1 : 0) }); refresh()
    }
    private func refresh() {
        let action = SystemGestureAction.action(keyCode: selection.keyCode, modifierFlags: selection.flags)
        for button in actionButtons {
            let selected = action?.keyCode == UInt16(button.tag)
            (button as? ActionTileButton)?.selected = selected
            button.contentTintColor = selected ? .controlAccentColor : .labelColor
            button.setAccessibilityValue(selected ? "selected" : "")
        }
        for (button, flag) in zip(modifierButtons, flags) { button.state = action == nil && selection.flags & flag != 0 ? .on : .off; button.isEnabled = action != nil || !selection.isFunctionKey }
        summary.stringValue = tr("当前选择：", "Selected: ") + (action?.localizedName(language: language) ?? selection.displayString)
        switch action?.id {
        case "captureSelection": detail.stringValue = tr("⌃⌘⇧4 · 选取后复制到剪贴板", "⌃⌘⇧4 · Select and copy to clipboard")
        case "captureScreen": detail.stringValue = tr("⌃⌘⇧3 · 全屏复制到剪贴板", "⌃⌘⇧3 · Copy screen to clipboard")
        case "recordScreen": detail.stringValue = tr("打开系统工具栏，选择范围并开始录制", "Open capture toolbar to start recording")
        default: detail.stringValue = selection.isFunctionKey
            ? tr("Fn 单独触发；选其它按键后可勾选修饰键", "Fn works alone; choose another key to add modifiers")
            : tr("保存后通过已配置的快捷操作触发", "Save, then use the configured trigger")
        }
    }
    @objc private func saveSelection() { onSave(selection) }
    @objc private func cancelSelection() { onCancel() }
}
private final class FlippedActionDocument: NSView { override var isFlipped: Bool { true } }

private final class ActionTileButton: NSButton {
    // The custom tile does not use NSButtonCell's image/title layout.
    // Its focus mask must follow the whole tile, not the default cell contents.
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9).fill()
    }

    private func drawIcon(_ icon: NSImage?, color: NSColor, rect: NSRect) {
        guard let icon else { return }
        let tinted = NSImage(size: rect.size, flipped: false) { bounds in
            icon.draw(in: bounds); color.setFill(); bounds.fill(using: .sourceAtop); return true
        }
        tinted.draw(in: rect)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    var selected = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        // Resolve dynamic colors during drawing, in this view's current appearance.
        // CGColor values cached before attachment retain the old light/dark theme.
        let tile = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        tile.fill()
        (selected ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        tile.lineWidth = 1; tile.stroke()
        let color: NSColor = selected ? .controlAccentColor : .labelColor
        drawIcon(image, color: color, rect: NSRect(x: 16, y: (bounds.height - 26) / 2, width: 26, height: 26))
        (title as NSString).draw(in: NSRect(x: 52, y: (bounds.height - 22) / 2, width: bounds.width - 78, height: 24), withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: color])
        if selected {
            let check = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            drawIcon(check, color: .controlAccentColor, rect: NSRect(x: bounds.width - 28, y: (bounds.height - 18) / 2, width: 18, height: 18))
        }
    }
}
private final class PrimaryActionButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 7, yRadius: 7).fill()
        let style = NSMutableParagraphStyle(); style.alignment = .center
        (title as NSString).draw(in: NSRect(x: 0, y: (bounds.height - 21) / 2, width: bounds.width, height: 22), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.white, .paragraphStyle: style])
    }
}
private final class VisibleActionScroller: NSScroller {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternaryLabelColor.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 3, yRadius: 3).fill()
        let height = max(24, bounds.height * knobProportion)
        let y = (bounds.height - height) * CGFloat(doubleValue)
        NSColor.tertiaryLabelColor.setFill(); NSBezierPath(roundedRect: NSRect(x: 4, y: y, width: bounds.width - 8, height: height), xRadius: 4, yRadius: 4).fill()
    }
}
