import AppKit
import CoreGraphics
import CodexQuotaCore

final class DoubleCommandTapController {
    static let isEnabledDefaultsKey = "doubleCommandTapEnabled"

    private let defaults: UserDefaults
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var sequence = DoubleCommandTapSequence()
    private var commandIsDown = false
    private var isSynthesizing = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.isEnabledDefaultsKey) }
        set { defaults.set(newValue, forKey: Self.isEnabledDefaultsKey) }
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    var isRunning: Bool {
        eventTap != nil
    }

    @discardableResult
    func startIfPermitted() -> Bool {
        guard isAccessibilityTrusted else {
            stop()
            return false
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return true
        }

        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.handleEvent,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.eventTap = eventTap
        runLoopSource = source
        return true
    }

    func stop() {
        guard let eventTap else {
            return
        }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        self.eventTap = nil
        runLoopSource = nil
        sequence.cancel()
        commandIsDown = false
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        guard !isSynthesizing else {
            return
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }
        if type == .keyDown {
            sequence.cancel()
            return
        }
        guard type == .flagsChanged else {
            return
        }

        let flags = event.flags
        let commandIsNowDown = flags.contains(.maskCommand)
        let otherModifiers: CGEventFlags = [
            .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn, .maskAlphaShift
        ]
        if commandIsNowDown, !flags.intersection(otherModifiers).isEmpty {
            sequence.cancel()
        }
        if commandIsNowDown, !commandIsDown,
           flags.intersection(otherModifiers).isEmpty,
           sequence.registerPureCommandTap(at: ProcessInfo.processInfo.systemUptime) {
            triggerCodexShortcut()
        }
        commandIsDown = commandIsNowDown
    }

    private func triggerCodexShortcut() {
        isSynthesizing = true
        let shortcut = DoubleCommandTapShortcut(defaults: defaults)
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true)
        keyDown?.flags = shortcut.flags
        keyDown?.post(tap: .cghidEventTap)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false)
        keyUp?.flags = shortcut.flags
        keyUp?.post(tap: .cghidEventTap)
        isSynthesizing = false
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        Unmanaged<DoubleCommandTapController>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
            .handle(type: type, event: event)
        return Unmanaged.passUnretained(event)
    }
}
