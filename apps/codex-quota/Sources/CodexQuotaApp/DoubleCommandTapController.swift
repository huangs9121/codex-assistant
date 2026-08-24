import AppKit
import CoreGraphics
import CodexQuotaCore
import Foundation

final class DoubleCommandTapController {
    static let isEnabledDefaultsKey = "doubleCommandTapEnabled"

    private let defaults: UserDefaults
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var sequence: ModifierTapSequence
    private var pressedModifierKeyCodes = Set<CGKeyCode>()
    private var isSynthesizing = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sequence = ModifierTapSequence(
            configuration: ModifierTapGesture(defaults: defaults).sequenceConfiguration
        )
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.isEnabledDefaultsKey) }
        set { defaults.set(newValue, forKey: Self.isEnabledDefaultsKey) }
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    var isInputMonitoringTrusted: Bool {
        if #available(macOS 14.4, *) {
            return CGPreflightListenEventAccess()
        }
        return canCreateKeyboardEventTap()
    }

    var permissionStatus: DoubleCommandTapPermissionStatus {
        DoubleCommandTapPermissionStatus(
            inputMonitoringAuthorized: isInputMonitoringTrusted,
            accessibilityAuthorized: isAccessibilityTrusted
        )
    }

    var isRunning: Bool {
        eventTap != nil
    }

    @discardableResult
    func startIfPermitted() -> Bool {
        reloadGestureIfNeeded()
        guard permissionStatus == .running else {
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
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        sequence.cancel()
        pressedModifierKeyCodes.removeAll()
    }

    func reloadGesture() {
        reloadGestureIfNeeded()
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func requestInputMonitoringPermission() {
        if #available(macOS 14.4, *) {
            _ = CGRequestListenEventAccess()
        }
    }

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func canCreateKeyboardEventTap() -> Bool {
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.probeEvent,
            userInfo: nil
        ) else {
            return false
        }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        return true
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

        let time = ProcessInfo.processInfo.systemUptime
        if type == .keyDown {
            _ = sequence.register(.keyDown, at: time)
            return
        }
        guard type == .flagsChanged else {
            return
        }

        reloadGestureIfNeeded()
        registerModifierChange(event, at: time)
    }

    private func registerModifierChange(_ event: CGEvent, at time: TimeInterval) {
        let rawKeyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard let keyCode = UInt16(exactly: rawKeyCode),
              let modifierFlag = ModifierTapGesture.modifierFlag(for: keyCode) else {
            _ = sequence.register(.otherModifier, at: time)
            return
        }

        let isDown: Bool
        if pressedModifierKeyCodes.contains(keyCode) {
            pressedModifierKeyCodes.remove(keyCode)
            isDown = false
        } else if event.flags.contains(modifierFlag) {
            pressedModifierKeyCodes.insert(keyCode)
            isDown = true
        } else {
            _ = sequence.register(.otherModifier, at: time)
            return
        }

        let gestureEvent: ModifierTapSequence.Event
        if hasOtherModifier(flags: event.flags, currentKeyCode: keyCode) {
            gestureEvent = .otherModifier
        } else if sequence.configuration.keyCodes.contains(keyCode) {
            gestureEvent = isDown ? .modifierDown(keyCode) : .modifierUp(keyCode)
        } else {
            gestureEvent = .otherModifier
        }

        if sequence.register(gestureEvent, at: time) {
            triggerCodexShortcut()
        }
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

    private func reloadGestureIfNeeded() {
        let configuration = ModifierTapGesture(defaults: defaults).sequenceConfiguration
        guard sequence.configuration != configuration else {
            return
        }
        sequence = ModifierTapSequence(configuration: configuration)
        pressedModifierKeyCodes.removeAll()
    }

    private func triggerCodexShortcut() {
        isSynthesizing = true
        defer { isSynthesizing = false }
        let shortcut = DoubleCommandTapShortcut(defaults: defaults)
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true)
        if let keyDown {
            keyDown.flags = shortcut.flags
            keyDown.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.04)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false)
        if let keyUp {
            keyUp.flags = shortcut.flags
            keyUp.post(tap: .cghidEventTap)
        }
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

    private static let probeEvent: CGEventTapCallBack = { _, _, event, _ in
        Unmanaged.passUnretained(event)
    }
}
