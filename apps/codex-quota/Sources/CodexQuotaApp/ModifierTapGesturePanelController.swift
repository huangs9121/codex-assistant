import AppKit
import CoreGraphics

@MainActor
final class ModifierTapGesturePanelController: NSObject, NSWindowDelegate {
    private let defaults: UserDefaults
    private let text: AppText
    private let onGestureSaved: () -> Void
    private var monitor: Any?
    private var recordingTimer: Timer?
    private var candidateKeyCode: CGKeyCode?
    private var candidateTapCount = 0
    private var pressedModifierKeyCodes = Set<CGKeyCode>()
    private let gestureLabel = NSTextField(labelWithString: "")
    private let confirmationLabel = NSTextField(labelWithString: "")
    private let recordButton = NSButton(title: "", target: nil, action: nil)
    private lazy var panel = makePanel()

    init(
        defaults: UserDefaults = .standard,
        text: AppText,
        onGestureSaved: @escaping () -> Void
    ) {
        self.defaults = defaults
        self.text = text
        self.onGestureSaved = onGestureSaved
        super.init()
    }

    func show() {
        updateGestureLabel()
        confirmationLabel.stringValue = ""
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 260),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = text.recordTriggerGesture
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let content = NSView(frame: panel.contentView?.bounds ?? .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = content

        let hint = NSTextField(wrappingLabelWithString: text.triggerGestureRecordingHint)
        hint.font = .systemFont(ofSize: 13, weight: .semibold)
        hint.maximumNumberOfLines = 2

        let currentTitle = NSTextField(labelWithString: text.currentTriggerGesture)
        currentTitle.font = .systemFont(ofSize: 13)
        gestureLabel.font = .monospacedSystemFont(ofSize: 22, weight: .medium)

        recordButton.title = text.recordTriggerGesture
        recordButton.target = self
        recordButton.action = #selector(startRecording)
        recordButton.bezelStyle = .rounded

        confirmationLabel.font = .systemFont(ofSize: 12)
        confirmationLabel.textColor = .systemGreen

        let cancelHint = NSTextField(labelWithString: text.escapeCancelsRecording)
        cancelHint.font = .systemFont(ofSize: 12)
        cancelHint.textColor = .secondaryLabelColor

        let stack = NSStackView(
            views: [hint, currentTitle, gestureLabel, recordButton, confirmationLabel, cancelHint]
        )
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20)
        ])
        return panel
    }

    @objc private func startRecording() {
        stopRecording()
        confirmationLabel.stringValue = ""
        recordButton.title = text.recordingTriggerGesture
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.cancelRecording()
                return nil
            }
            if event.type == .flagsChanged {
                self.recordModifierChange(event)
            }
            return event
        }
    }

    private func recordModifierChange(_ event: NSEvent) {
        let keyCode = event.keyCode
        guard let modifierFlag = ModifierTapGesture.modifierFlag(for: keyCode) else {
            clearCandidate()
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
            clearCandidate()
            return
        }

        if hasOtherModifier(flags: flags, currentKeyCode: keyCode) {
            clearCandidate()
            return
        }
        guard ModifierTapGesture.isSupported(keyCode: keyCode) else {
            clearCandidate()
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
            clearCandidate()
            return
        }

        candidateTapCount += 1
        if candidateTapCount == 2 {
            finishRecording(keyCode: keyCode, tapCount: 2)
        }
    }

    private func scheduleSingleTapConfirmation() {
        recordingTimer?.invalidate()
        let timer = Timer(
            timeInterval: 0.6,
            target: self,
            selector: #selector(confirmSingleTap),
            userInfo: nil,
            repeats: false
        )
        recordingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func confirmSingleTap(_ timer: Timer) {
        guard recordingTimer === timer,
              let candidateKeyCode,
              candidateTapCount == 1 else {
            return
        }
        finishRecording(keyCode: candidateKeyCode, tapCount: 1)
    }

    private func finishRecording(keyCode: CGKeyCode, tapCount: Int) {
        let gesture = ModifierTapGesture(keyCodes: [keyCode], tapCount: tapCount)
        gesture.save(to: defaults)
        stopRecording()
        updateGestureLabel()
        confirmationLabel.stringValue = text.triggerGestureSaved(gesture.displayString(text: text))
        onGestureSaved()
    }

    private func cancelRecording() {
        stopRecording()
        confirmationLabel.stringValue = text.triggerGestureRecordingCancelled
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        candidateKeyCode = nil
        candidateTapCount = 0
        pressedModifierKeyCodes.removeAll()
        recordButton.title = text.recordTriggerGesture
    }

    private func clearCandidate() {
        recordingTimer?.invalidate()
        recordingTimer = nil
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

    private func updateGestureLabel() {
        gestureLabel.stringValue = ModifierTapGesture(defaults: defaults).displayString(text: text)
    }
}
