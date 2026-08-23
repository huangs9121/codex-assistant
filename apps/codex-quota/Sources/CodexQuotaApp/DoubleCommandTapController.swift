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
    private var lastLoggedPermissionStatus: DoubleCommandTapPermissionStatus?
    private var lastLoggedTapCreationFailure: String?

    private static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/CodexQuota-doublecmd.log")
    private static let maximumLogSize = 1_024 * 1_024

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sequence = ModifierTapSequence(
            configuration: ModifierTapGesture(defaults: defaults).sequenceConfiguration
        )
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.isEnabledDefaultsKey) }
        set {
            defaults.set(newValue, forKey: Self.isEnabledDefaultsKey)
            if !newValue {
                lastLoggedPermissionStatus = nil
                lastLoggedTapCreationFailure = nil
            }
        }
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
        let status = permissionStatus
        logPermissionStatusIfChanged(status)
        guard status == .running else {
            logTapCreationFailureIfChanged(status)
            stop()
            return false
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            log("tap re-enabled")
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
            logTapCreationFailureIfChanged(status)
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.eventTap = eventTap
        runLoopSource = source
        lastLoggedTapCreationFailure = nil
        log("tap created successfully")
        return true
    }

    func stop() {
        let hadEventTap = eventTap != nil
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
        if hadEventTap {
            log("tap stopped")
        }
    }

    func reloadGesture() {
        reloadGestureIfNeeded()
    }

    func observePermissionStatus() {
        guard isEnabled else {
            return
        }
        logPermissionStatusIfChanged(permissionStatus)
    }

    func testTriggerCodexShortcut() {
        log("test trigger menu item selected")
        triggerCodexShortcut()
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
            log("tap disabled by system (\(type == .tapDisabledByTimeout ? "timeout" : "user input"))")
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                log("tap re-enabled")
            }
            return
        }

        let time = ProcessInfo.processInfo.systemUptime
        if type == .keyDown {
            if sequence.isTracking {
                log("keyDown cancelled modifier gesture (keyCode=\(event.getIntegerValueField(.keyboardEventKeycode)))")
            }
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
            log("modifier gesture triggered")
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
            log("trigger keyDown keyCode=\(shortcut.keyCode) flags=\(shortcut.flags.rawValue) constructed=true post completed")
        } else {
            log("trigger keyDown keyCode=\(shortcut.keyCode) flags=\(shortcut.flags.rawValue) constructed=false")
        }
        Thread.sleep(forTimeInterval: 0.04)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false)
        if let keyUp {
            keyUp.flags = shortcut.flags
            keyUp.post(tap: .cghidEventTap)
            log("trigger keyUp keyCode=\(shortcut.keyCode) flags=\(shortcut.flags.rawValue) constructed=true post completed")
        } else {
            log("trigger keyUp keyCode=\(shortcut.keyCode) flags=\(shortcut.flags.rawValue) constructed=false")
        }
    }

    private func logPermissionStatusIfChanged(_ status: DoubleCommandTapPermissionStatus) {
        guard lastLoggedPermissionStatus != status else { return }
        lastLoggedPermissionStatus = status
        log("permissions changed status=\(status)")
    }

    private func logTapCreationFailureIfChanged(_ status: DoubleCommandTapPermissionStatus) {
        let message = "tap creation failed (status=\(status))"
        guard lastLoggedTapCreationFailure != message else { return }
        lastLoggedTapCreationFailure = message
        log(message)
    }

    private func log(_ message: String) {
        guard isEnabled || eventTap != nil else { return }
        let fileManager = FileManager.default
        let url = Self.logURL
        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber,
           size.intValue >= Self.maximumLogSize {
            try? Data().write(to: url, options: .atomic)
        }
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let timestamp = Self.logDateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        guard let data = line.data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

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
