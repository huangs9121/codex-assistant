import AppKit
import CodexQuotaCore

@MainActor
final class DoubleCommandTapShortcutPanelController: NSObject, NSWindowDelegate {
    private let defaults: UserDefaults
    private let text: AppText
    private var monitor: Any?
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let recordButton = NSButton(title: "", target: nil, action: nil)
    private lazy var panel = makePanel()

    init(defaults: UserDefaults = .standard, text: AppText) {
        self.defaults = defaults
        self.text = text
    }

    func show() {
        updateShortcutLabel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 230),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = text.setCodexShortcut
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let content = NSView(frame: panel.contentView?.bounds ?? .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = content

        let hint = NSTextField(wrappingLabelWithString: text.codexShortcutMatchHint)
        hint.font = .systemFont(ofSize: 13, weight: .semibold)
        hint.textColor = .systemRed
        hint.maximumNumberOfLines = 2

        let currentTitle = NSTextField(labelWithString: text.currentCodexShortcut)
        currentTitle.font = .systemFont(ofSize: 13)
        shortcutLabel.font = .monospacedSystemFont(ofSize: 24, weight: .medium)

        recordButton.title = text.recordCodexShortcut
        recordButton.target = self
        recordButton.action = #selector(startRecording)
        recordButton.bezelStyle = .rounded

        let cancelHint = NSTextField(labelWithString: text.escapeCancelsRecording)
        cancelHint.font = .systemFont(ofSize: 12)
        cancelHint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [hint, currentTitle, shortcutLabel, recordButton, cancelHint])
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
        recordButton.title = text.recordingCodexShortcut
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
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
            self.updateShortcutLabel()
            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recordButton.title = text.recordCodexShortcut
    }

    private func updateShortcutLabel() {
        shortcutLabel.stringValue = DoubleCommandTapShortcut(defaults: defaults).displayString
    }
}
