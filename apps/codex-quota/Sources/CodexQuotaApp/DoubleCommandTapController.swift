import AppKit
import CoreGraphics
import CodexQuotaCore
import Foundation

// Retains the legacy name and enable key for existing installations.
final class DoubleCommandTapController {
    static let isEnabledDefaultsKey = "doubleCommandTapEnabled"
    static let rulesDefaultsKey = "globalKeyMappingRules"
    static let syntheticEventMarker: Int64 = 0x4351_4B4D
    private let defaults: UserDefaults
    private let eventSink: ((CGEvent) -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var sequences: [UUID: ModifierTapSequence] = [:]
    private var pressedModifierKeyCodes = Set<CGKeyCode>()
    private var engine = KeyMappingEngine()
    private var isRecording = false
    private(set) var rules: [KeyMappingRule] = []

    init(defaults: UserDefaults = .standard, eventSink: ((CGEvent) -> Void)? = nil) {
        self.defaults = defaults
        self.eventSink = eventSink
        rules = Self.loadRules(from: defaults)
        resetSequences()
    }
    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.isEnabledDefaultsKey) }
        set { defaults.set(newValue, forKey: Self.isEnabledDefaultsKey); if !newValue { stop() } }
    }
    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }
    var isInputMonitoringTrusted: Bool {
        if #available(macOS 14.4, *) { return CGPreflightListenEventAccess() }
        return canCreateKeyboardEventTap()
    }
    var permissionStatus: DoubleCommandTapPermissionStatus {
        DoubleCommandTapPermissionStatus(inputMonitoringAuthorized: isInputMonitoringTrusted,
                                         accessibilityAuthorized: isAccessibilityTrusted)
    }
    var isRunning: Bool { eventTap != nil }

    static func loadRules(from defaults: UserDefaults) -> [KeyMappingRule] {
        if let data = defaults.data(forKey: rulesDefaultsKey) {
            return (try? JSONDecoder().decode([KeyMappingRule].self, from: data)) ?? []
        }
        let gesture = ModifierTapGesture(defaults: defaults)
        let shortcut = DoubleCommandTapShortcut(defaults: defaults)
        let migrated = [KeyMappingRule(
            trigger: .modifierTap(keyCodes: gesture.keyCodes, tapCount: gesture.tapCount),
            target: KeyMappingShortcut(keyCode: shortcut.keyCode, flags: shortcut.flags.rawValue), note: "Codex"
        )]
        saveRules(migrated, to: defaults)
        return migrated
    }
    static func saveRules(_ rules: [KeyMappingRule], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: rulesDefaultsKey)
    }
    func reloadGesture() {
        rules = Self.loadRules(from: defaults)
        resetSequences()
    }
    private var activeRules: [KeyMappingRule] {
        rules.reduce(into: []) { selected, rule in
            guard rule.isEnabled, rule.isComplete,
                  KeyMappingRule.conflictingRule(for: rule, in: selected) == nil else { return }
            selected.append(rule)
        }
    }
    @discardableResult
    func startIfPermitted() -> Bool {
        guard isEnabled, permissionStatus == .running else { stop(); return false }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true); return true }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: Self.eventMask, callback: Self.handleEvent,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        eventTap = tap; runLoopSource = source
        return true
    }
    func stop() {
        releaseMappedKeys()
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil; runLoopSource = nil
        resetSequences()
    }
    func setRecording(_ recording: Bool) {
        isRecording = recording
        releaseMappedKeys()
        resetSequences()
    }
    func requestAccessibilityPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
    func requestInputMonitoringPermission() {
        if #available(macOS 14.4, *) { _ = CGRequestListenEventAccess() }
    }
    func openInputMonitoringSettings() { openSettings("Privacy_ListenEvent") }
    func openAccessibilitySettings() { openSettings("Privacy_Accessibility") }
    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
    private static let eventMask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
        | CGEventMask(1) << CGEventType.keyDown.rawValue | CGEventMask(1) << CGEventType.keyUp.rawValue
    private func canCreateKeyboardEventTap() -> Bool {
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: Self.eventMask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil) else { return false }
        CGEvent.tapEnable(tap: tap, enable: false)
        return true
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            releaseMappedKeys()
            resetSequences()
            if isEnabled, let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard isEnabled, !isRecording,
              event.getIntegerValueField(.eventSourceUserData) != Self.syntheticEventMarker else {
            return Unmanaged.passUnretained(event)
        }
        let time = ProcessInfo.processInfo.systemUptime
        if type == .keyDown || type == .keyUp {
            if type == .keyDown {
                for id in Array(sequences.keys) { _ = sequences[id]?.register(.keyDown, at: time) }
            }
            guard let keyCode = UInt16(exactly: event.getIntegerValueField(.keyboardEventKeycode)) else {
                return Unmanaged.passUnretained(event)
            }
            if let target = engine.process(phase: type == .keyDown ? .down : .up, keyCode: keyCode,
                flags: event.flags.rawValue, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                rules: activeRules) {
                if target.isFunctionKey {
                    // Fn is a flagsChanged event, not a printable key. Repeats must not retrigger it.
                    if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                    event.type = .flagsChanged
                    event.setIntegerValueField(.keyboardEventKeycode, value: 63)
                    event.flags = (type == .keyDown || isMappedFunctionHeld || pressedModifierKeyCodes.contains(63)) ? .maskSecondaryFn : []
                    event.keyboardSetUnicodeString(stringLength: 0, unicodeString: [])
                    event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
                    return Unmanaged.passUnretained(event)
                }
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(target.keyCode))
                event.flags = CGEventFlags(rawValue: target.flags)
                // Discard the source event's cached characters so AppKit translates the target key.
                event.keyboardSetUnicodeString(stringLength: 0, unicodeString: [])
                event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            }
        } else if type == .flagsChanged { registerModifierChange(event, at: time) }
        if isMappedFunctionHeld { event.flags.insert(.maskSecondaryFn) }
        return Unmanaged.passUnretained(event)
    }
    private var isMappedFunctionHeld: Bool { engine.pressed.values.contains { $0.isFunctionKey } }
    private func registerModifierChange(_ event: CGEvent, at time: TimeInterval) {
        guard let keyCode = UInt16(exactly: event.getIntegerValueField(.keyboardEventKeycode)),
              let flag = ModifierTapGesture.modifierFlag(for: keyCode) else { resetSequences(); return }
        let isDown: Bool
        if pressedModifierKeyCodes.remove(keyCode) != nil { isDown = false }
        else if event.flags.contains(flag) { pressedModifierKeyCodes.insert(keyCode); isDown = true }
        else { resetSequences(); return }
        var otherFlags = ModifierTapGesture.allModifierFlags()
        otherFlags.remove(flag)
        let hasOther = pressedModifierKeyCodes.contains { $0 != keyCode } || !event.flags.intersection(otherFlags).isEmpty
        for rule in activeRules {
            guard let sequence = sequences[rule.id] else { continue }
            let gestureEvent: ModifierTapSequence.Event = hasOther || !sequence.configuration.keyCodes.contains(keyCode)
                ? .otherModifier : (isDown ? .modifierDown(keyCode) : .modifierUp(keyCode))
            if sequences[rule.id]?.register(gestureEvent, at: time) == true, let target = rule.target {
                post(target, keyDown: true)
                post(target, keyDown: false)
                break
            }
        }
    }
    private func resetSequences() {
        sequences.removeAll()
        pressedModifierKeyCodes.removeAll()
        for rule in activeRules {
            if case let .modifierTap(keys, count) = rule.trigger {
                sequences[rule.id] = ModifierTapSequence(configuration: .init(keyCodes: keys, requiredTapCount: count))
            }
        }
    }
    private func releaseMappedKeys() {
        for target in engine.releaseAll() { post(target, keyDown: false) }
    }
    private func post(_ shortcut: KeyMappingShortcut, keyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: keyDown) else { return }
        event.flags = CGEventFlags(rawValue: shortcut.flags)
        if shortcut.isFunctionKey {
            event.type = .flagsChanged
            event.flags = (keyDown || pressedModifierKeyCodes.contains(63)) ? .maskSecondaryFn : []
        }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        if let eventSink { eventSink(event) }
        else { event.post(tap: .cghidEventTap) }
    }
    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        return Unmanaged<DoubleCommandTapController>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
    }
}
