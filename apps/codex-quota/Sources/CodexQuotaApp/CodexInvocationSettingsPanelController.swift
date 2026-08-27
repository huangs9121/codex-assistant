import AppKit
import CodexQuotaCore
import CoreGraphics

@MainActor
final class CodexInvocationSettingsPanelController: NSObject {
    private let defaults: UserDefaults
    private let text: AppText
    private let doubleCommandTapController: DoubleCommandTapController
    private let onEnabledChanged: (Bool) -> Void
    private let onGestureSaved: () -> Void
    private let onPermissionRefresh: () -> Void

    private var gestureMonitor: Any?
    private var shortcutMonitor: Any?
    private var gestureRecordingTimer: Timer?
    private var permissionTimer: Timer?
    private var candidateKeyCode: CGKeyCode?
    private var candidateTapCount = 0
    private var pressedModifierKeyCodes = Set<CGKeyCode>()

    private let enabledButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let gestureValueLabel = NSTextField(labelWithString: "")
    private let shortcutValueLabel = NSTextField(labelWithString: "")
    private let gestureRecordButton = NSButton(title: "", target: nil, action: nil)
    private let shortcutRecordButton = NSButton(title: "", target: nil, action: nil)
    private let inputMonitoringStatusLabel = NSTextField(labelWithString: "")
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let inputMonitoringSettingsButton = NSButton(title: "", target: nil, action: nil)
    private let accessibilitySettingsButton = NSButton(title: "", target: nil, action: nil)
    private lazy var embeddedContentView = makeContentView()

    init(
        defaults: UserDefaults = .standard,
        text: AppText,
        doubleCommandTapController: DoubleCommandTapController,
        onEnabledChanged: @escaping (Bool) -> Void,
        onGestureSaved: @escaping () -> Void,
        onPermissionRefresh: @escaping () -> Void
    ) {
        self.defaults = defaults
        self.text = text
        self.doubleCommandTapController = doubleCommandTapController
        self.onEnabledChanged = onEnabledChanged
        self.onGestureSaved = onGestureSaved
        self.onPermissionRefresh = onPermissionRefresh
        super.init()
    }

    var contentView: NSView {
        embeddedContentView
    }

    func didBecomeVisible() {
        refreshConfiguration()
        refreshPermissionStatus()
        startPermissionPolling()
    }

    func didHide() {
        stopRecording()
        stopPermissionPolling()
    }

    func hostWindowDidResignKey() {
        stopRecording()
    }

    private func makeContentView() -> NSView {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 480))
        content.translatesAutoresizingMaskIntoConstraints = false

        enabledButton.title = text.enableModifierTapOpenCodex
        enabledButton.target = self
        enabledButton.action = #selector(toggleEnabled)
        enabledButton.allowsMixedState = false
        enabledButton.font = .systemFont(ofSize: 14, weight: .medium)

        gestureValueLabel.font = .monospacedSystemFont(ofSize: 17, weight: .medium)
        gestureValueLabel.setAccessibilityLabel(text.currentTriggerGesture)
        gestureRecordButton.title = text.rerecord
        gestureRecordButton.target = self
        gestureRecordButton.action = #selector(startGestureRecording)
        gestureRecordButton.bezelStyle = .rounded

        shortcutValueLabel.font = .monospacedSystemFont(ofSize: 17, weight: .medium)
        shortcutValueLabel.setAccessibilityLabel(text.currentCodexShortcut)
        shortcutRecordButton.title = text.rerecord
        shortcutRecordButton.target = self
        shortcutRecordButton.action = #selector(startShortcutRecording)
        shortcutRecordButton.bezelStyle = .rounded

        inputMonitoringStatusLabel.font = .systemFont(ofSize: 13)
        accessibilityStatusLabel.font = .systemFont(ofSize: 13)
        inputMonitoringSettingsButton.title = text.openSettings
        inputMonitoringSettingsButton.target = self
        inputMonitoringSettingsButton.action = #selector(openInputMonitoringSettings)
        inputMonitoringSettingsButton.bezelStyle = .rounded
        accessibilitySettingsButton.title = text.openSettings
        accessibilitySettingsButton.target = self
        accessibilitySettingsButton.action = #selector(openAccessibilitySettings)
        accessibilitySettingsButton.bezelStyle = .rounded

        let gestureCurrentTitle = makeSecondaryLabel(text.currentTriggerGesture)
        let gestureHint = NSTextField(wrappingLabelWithString: text.triggerGestureRecordingHint)
        gestureHint.font = .systemFont(ofSize: 12)
        gestureHint.textColor = .secondaryLabelColor
        let gestureRow = makeValueRow(gestureValueLabel, button: gestureRecordButton)
        let gestureSection = makeSection(
            title: text.triggerGestureSection,
            views: [gestureCurrentTitle, gestureRow, gestureHint]
        )
        constrainToSectionWidth([gestureCurrentTitle, gestureRow, gestureHint], in: gestureSection)

        let shortcutCurrentTitle = makeSecondaryLabel(text.currentCodexShortcut)
        let shortcutWarning = NSTextField(wrappingLabelWithString: text.codexShortcutMatchHint)
        shortcutWarning.font = .systemFont(ofSize: 12, weight: .medium)
        shortcutWarning.textColor = .systemRed
        let shortcutRow = makeValueRow(shortcutValueLabel, button: shortcutRecordButton)
        let shortcutSection = makeSection(
            title: text.targetShortcutSection,
            views: [shortcutCurrentTitle, shortcutRow, shortcutWarning]
        )
        constrainToSectionWidth([shortcutCurrentTitle, shortcutRow, shortcutWarning], in: shortcutSection)

        let inputMonitoringRow = makeValueRow(
            inputMonitoringStatusLabel,
            button: inputMonitoringSettingsButton
        )
        let accessibilityRow = makeValueRow(
            accessibilityStatusLabel,
            button: accessibilitySettingsButton
        )
        let permissionsSection = makeSection(
            title: text.permissionsSection,
            views: [inputMonitoringRow, accessibilityRow]
        )
        constrainToSectionWidth([inputMonitoringRow, accessibilityRow], in: permissionsSection)

        let bottomHint = NSTextField(wrappingLabelWithString: text.codexInvocationShortcutHint)
        bottomHint.font = .systemFont(ofSize: 12)
        bottomHint.textColor = .secondaryLabelColor

        let gestureDivider = makeDivider()
        let shortcutDivider = makeDivider()
        let permissionsDivider = makeDivider()

        let root = NSStackView(views: [
            enabledButton,
            gestureDivider,
            gestureSection,
            shortcutDivider,
            shortcutSection,
            permissionsDivider,
            permissionsSection,
            bottomHint
        ])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 13
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            gestureSection.widthAnchor.constraint(equalTo: root.widthAnchor),
            shortcutSection.widthAnchor.constraint(equalTo: root.widthAnchor),
            permissionsSection.widthAnchor.constraint(equalTo: root.widthAnchor),
            bottomHint.widthAnchor.constraint(equalTo: root.widthAnchor),
            gestureDivider.widthAnchor.constraint(equalTo: root.widthAnchor),
            shortcutDivider.widthAnchor.constraint(equalTo: root.widthAnchor),
            permissionsDivider.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
        return content
    }

    @objc private func toggleEnabled() {
        onEnabledChanged(enabledButton.state == .on)
        refreshConfiguration()
        refreshPermissionStatus()
    }

    @objc private func startGestureRecording() {
        stopRecording()
        gestureRecordButton.title = text.recordingTriggerGesture
        gestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self, self.contentView.window?.isKeyWindow == true else {
                return event
            }
            if event.type == .keyDown, event.keyCode == 53 {
                self.stopRecording()
                return nil
            }
            if event.type == .flagsChanged {
                self.recordGestureModifierChange(event)
            }
            return event
        }
    }

    @objc private func startShortcutRecording() {
        stopRecording()
        shortcutRecordButton.title = text.recordingCodexShortcut
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.contentView.window?.isKeyWindow == true else {
                return event
            }
            if event.keyCode == 53 {
                self.stopRecording()
                return nil
            }
            let flags = CGEventFlags(rawValue: UInt64(
                event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            ))
            guard KeyboardShortcut.isValid(keyCode: event.keyCode, flags: flags.rawValue) else {
                return nil
            }
            DoubleCommandTapShortcut(keyCode: event.keyCode, flags: flags).save(to: self.defaults)
            self.stopRecording()
            self.refreshConfiguration()
            return nil
        }
    }

    @objc private func openInputMonitoringSettings() {
        doubleCommandTapController.openInputMonitoringSettings()
    }

    @objc private func openAccessibilitySettings() {
        doubleCommandTapController.openAccessibilitySettings()
    }

    @objc private func refreshPermissionStatusFromTimer() {
        refreshPermissionStatus()
    }

    private func recordGestureModifierChange(_ event: NSEvent) {
        let keyCode = event.keyCode
        guard let modifierFlag = ModifierTapGesture.modifierFlag(for: keyCode) else {
            clearGestureCandidate()
            return
        }
        let flags = CGEventFlags(rawValue: UInt64(
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        ))

        let isDown: Bool
        if pressedModifierKeyCodes.contains(keyCode) {
            pressedModifierKeyCodes.remove(keyCode)
            isDown = false
        } else if flags.contains(modifierFlag) {
            pressedModifierKeyCodes.insert(keyCode)
            isDown = true
        } else {
            clearGestureCandidate()
            return
        }

        if hasOtherModifier(flags: flags, currentKeyCode: keyCode) {
            clearGestureCandidate()
            return
        }
        guard ModifierTapGesture.isSupported(keyCode: keyCode) else {
            clearGestureCandidate()
            return
        }
        guard isDown else {
            return
        }

        guard let candidateKeyCode else {
            self.candidateKeyCode = keyCode
            candidateTapCount = 1
            scheduleSingleTapConfirmation()
            return
        }
        guard candidateKeyCode == keyCode else {
            clearGestureCandidate()
            return
        }

        candidateTapCount += 1
        if candidateTapCount == 2 {
            finishGestureRecording(keyCode: keyCode, tapCount: 2)
        }
    }

    private func scheduleSingleTapConfirmation() {
        gestureRecordingTimer?.invalidate()
        let timer = Timer(
            timeInterval: ModifierTapSequence.maximumInterval,
            target: self,
            selector: #selector(confirmSingleTap),
            userInfo: nil,
            repeats: false
        )
        gestureRecordingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func confirmSingleTap(_ timer: Timer) {
        guard gestureRecordingTimer === timer,
              let candidateKeyCode,
              candidateTapCount == 1 else {
            return
        }
        finishGestureRecording(keyCode: candidateKeyCode, tapCount: 1)
    }

    private func finishGestureRecording(keyCode: CGKeyCode, tapCount: Int) {
        ModifierTapGesture(keyCodes: [keyCode], tapCount: tapCount).save(to: defaults)
        stopRecording()
        onGestureSaved()
        refreshConfiguration()
    }

    private func stopRecording() {
        if let gestureMonitor {
            NSEvent.removeMonitor(gestureMonitor)
        }
        gestureMonitor = nil
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
        shortcutMonitor = nil
        gestureRecordingTimer?.invalidate()
        gestureRecordingTimer = nil
        candidateKeyCode = nil
        candidateTapCount = 0
        pressedModifierKeyCodes.removeAll()
        gestureRecordButton.title = text.rerecord
        shortcutRecordButton.title = text.rerecord
    }

    private func clearGestureCandidate() {
        gestureRecordingTimer?.invalidate()
        gestureRecordingTimer = nil
        candidateKeyCode = nil
        candidateTapCount = 0
    }

    private func hasOtherModifier(flags: CGEventFlags, currentKeyCode: CGKeyCode) -> Bool {
        if pressedModifierKeyCodes.contains(where: { $0 != currentKeyCode }) {
            return true
        }
        guard let currentModifierFlag = ModifierTapGesture.modifierFlag(for: currentKeyCode) else {
            return true
        }
        var otherModifierFlags = ModifierTapGesture.allModifierFlags()
        otherModifierFlags.remove(currentModifierFlag)
        return !flags.intersection(otherModifierFlags).isEmpty
    }

    private func refreshConfiguration() {
        enabledButton.state = doubleCommandTapController.isEnabled ? .on : .off
        gestureValueLabel.stringValue = ModifierTapGesture(defaults: defaults).displayString(text: text)
        shortcutValueLabel.stringValue = DoubleCommandTapShortcut(defaults: defaults).displayString
    }

    private func refreshPermissionStatus() {
        onPermissionRefresh()
        refreshConfiguration()
        inputMonitoringStatusLabel.stringValue = text.inputMonitoringPermissionStatus(
            isAuthorized: doubleCommandTapController.isInputMonitoringTrusted
        )
        accessibilityStatusLabel.stringValue = text.accessibilityPermissionStatus(
            isAuthorized: doubleCommandTapController.isAccessibilityTrusted
        )
    }

    private func startPermissionPolling() {
        stopPermissionPolling()
        let timer = Timer(
            timeInterval: 2,
            target: self,
            selector: #selector(refreshPermissionStatusFromTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func makeSection(title: String, views: [NSView]) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let section = NSStackView(views: [titleLabel] + views)
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 7
        return section
    }

    private func makeSecondaryLabel(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeValueRow(_ value: NSTextField, button: NSButton) -> NSStackView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [value, spacer, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func makeDivider() -> NSBox {
        let divider = NSBox()
        divider.boxType = .separator
        return divider
    }

    private func constrainToSectionWidth(_ views: [NSView], in section: NSStackView) {
        for view in views {
            view.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
    }
}
