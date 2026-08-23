import AppKit
import CoreGraphics
import CodexQuotaCore
import Foundation

final class DoubleCommandTapController {
    static let isEnabledDefaultsKey = "doubleCommandTapEnabled"

    private let defaults: UserDefaults
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var sequence = DoubleCommandTapSequence()
    private var commandIsDown = false
    private var isSynthesizing = false
    private var lastLoggedPermissionStatus: DoubleCommandTapPermissionStatus?
    private var diagnosticFirstTapAt: TimeInterval?
    private var diagnosticCooldownEndsAt: TimeInterval?

    private static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/CodexQuota-doublecmd.log")
    private static let maximumLogSize = 1_024 * 1_024

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
        let status = permissionStatus
        logPermissionStatusIfChanged(status)
        guard status == .running else {
            log("tap creation failed (inputMonitoring=\(isInputMonitoringTrusted), accessibility=\(isAccessibilityTrusted))")
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
            log("tap creation failed (inputMonitoring=\(isInputMonitoringTrusted), accessibility=\(isAccessibilityTrusted))")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.eventTap = eventTap
        runLoopSource = source
        log("tap created successfully")
        return true
    }

    func stop() {
        log("tap stopped")
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
        diagnosticFirstTapAt = nil
        commandIsDown = false
    }

    func observePermissionStatus() {
        guard isEnabled else {
            lastLoggedPermissionStatus = nil
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
        if type == .keyDown {
            log("keyDown cancelled sequence (keyCode=\(event.getIntegerValueField(.keyboardEventKeycode)))")
            sequence.cancel()
            diagnosticFirstTapAt = nil
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
        if commandIsNowDown || commandIsDown {
            log("flagsChanged command=\(commandIsNowDown ? "down" : "up") otherModifiers=\(!flags.intersection(otherModifiers).isEmpty)")
        }
        if commandIsNowDown, !flags.intersection(otherModifiers).isEmpty {
            sequence.cancel()
            diagnosticFirstTapAt = nil
        }
        if commandIsNowDown, !commandIsDown, flags.intersection(otherModifiers).isEmpty {
            let time = ProcessInfo.processInfo.systemUptime
            let resultDescription = diagnosticTapResultDescription(at: time)
            let result = sequence.registerPureCommandTap(at: time)
            log("pure command tap result=\(resultDescription) triggered=\(result)")
            if result {
                triggerCodexShortcut()
            }
        }
        commandIsDown = commandIsNowDown
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
        log("permissions changed inputMonitoring=\(isInputMonitoringTrusted) accessibility=\(isAccessibilityTrusted)")
    }

    private func diagnosticTapResultDescription(at time: TimeInterval) -> String {
        if let diagnosticCooldownEndsAt, time < diagnosticCooldownEndsAt {
            diagnosticFirstTapAt = nil
            return "cooling down"
        }
        guard let diagnosticFirstTapAt else {
            self.diagnosticFirstTapAt = time
            return "first tap"
        }
        if time - diagnosticFirstTapAt <= DoubleCommandTapSequence.maximumInterval {
            self.diagnosticFirstTapAt = nil
            diagnosticCooldownEndsAt = time + DoubleCommandTapSequence.cooldownDuration
            return "triggered"
        }
        self.diagnosticFirstTapAt = time
        return "interval timeout reset"
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
