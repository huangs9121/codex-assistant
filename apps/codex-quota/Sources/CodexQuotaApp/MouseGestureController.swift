import AppKit
import CodexQuotaCore
import CoreGraphics
import Darwin

private final class ShortcutEventSource: @unchecked Sendable {
    let source = CGEventSource(stateID: .hidSystemState)
}

final class MouseGestureController: NSObject {
    static let rulesDefaultsKey = "mouseGestureRules"
    private static let syntheticEventMarker: Int64 = 0x4351_4753

    private enum State {
        case idle
        case cancelled
        case pending(start: CGPoint, recognizer: MouseGestureRecognizer)
        case recognizing(
            start: CGPoint,
            recognizer: MouseGestureRecognizer,
            hasConsumedGesture: Bool
        )
    }

    private let defaults: UserDefaults
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timeoutTimer: Timer?
    private var state: State = .idle
    private(set) var rules: [MouseGestureRule] = []
    private(set) var preferences: MouseGesturePreferences
    private var gestureTargetPID: pid_t?
    private let shortcutPostingQueue = DispatchQueue(
        label: "CodexQuota.mouseGestureShortcutPosting",
        qos: .userInteractive
    )
    private let shortcutEventSource = ShortcutEventSource()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = MouseGesturePreferences(defaults: defaults)
        super.init()
        reloadRules()
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    var hasEnabledRules: Bool {
        rules.contains { $0.isEnabled && $0.hasValidGesture && $0.hasValidShortcut }
    }

    var isRunning: Bool {
        eventTap != nil
    }

    func reloadRules() {
        rules = Self.loadRules(from: defaults)
        preferences = MouseGesturePreferences(defaults: defaults)
        if !preferences.isEnabled || !hasEnabledRules {
            stop()
        }
    }

    @discardableResult
    func startIfPermitted() -> Bool {
        guard preferences.isEnabled, hasEnabledRules, isAccessibilityTrusted else {
            stop()
            return false
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return true
        }

        let eventMask = CGEventMask(1) << CGEventType.rightMouseDown.rawValue
            | CGEventMask(1) << CGEventType.rightMouseDragged.rawValue
            | CGEventMask(1) << CGEventType.rightMouseUp.rawValue
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.handleEvent,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.eventTap = eventTap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return true
    }

    func stop() {
        resetState()
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        self.eventTap = nil
        runLoopSource = nil
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func loadRules(from defaults: UserDefaults) -> [MouseGestureRule] {
        guard let data = defaults.data(forKey: rulesDefaultsKey) else { return [] }
        return (try? JSONDecoder().decode([MouseGestureRule].self, from: data)) ?? []
    }

    static func saveRules(_ rules: [MouseGestureRule], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: rulesDefaultsKey)
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<MouseGestureController>.fromOpaque(userInfo).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = controller.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }
        return controller.handle(type: type, event: event)
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let application = NSWorkspace.shared.frontmostApplication
        return handle(
            type: type, event: event,
            bundleIdentifier: application?.bundleIdentifier,
            targetPID: application?.processIdentifier,
            pointedBundleIdentifier: type == .rightMouseDown ? applicationBundleIdentifier(at: event.location) : nil
        )
    }

    // Keep the event decision independently testable without posting real input.
    func handle(
        type: CGEventType, event: CGEvent,
        bundleIdentifier: String?, targetPID: pid_t?, pointedBundleIdentifier: String?
    ) -> Unmanaged<CGEvent>? {
        switch type {
        case .rightMouseDown:
            resetState()
            guard hasEnabledRules,
                  preferences.allows(bundleIdentifier: bundleIdentifier),
                  preferences.allows(bundleIdentifier: pointedBundleIdentifier) else {
                return Unmanaged.passUnretained(event)
            }
            gestureTargetPID = targetPID
            let point = event.location
            state = .pending(
                start: point,
                recognizer: MouseGestureRecognizer(start: gesturePoint(point))
            )
            scheduleTimeout()
            return nil
        case .rightMouseDragged:
            guard !isIdle else { return Unmanaged.passUnretained(event) }
            guard preferences.allows(bundleIdentifier: bundleIdentifier), targetPID == gestureTargetPID else {
                state = .cancelled
                return nil
            }
            handleDrag(at: event.location)
            return nil
        case .rightMouseUp:
            guard !isIdle else { return Unmanaged.passUnretained(event) }
            guard preferences.allows(bundleIdentifier: bundleIdentifier), targetPID == gestureTargetPID else {
                resetState()
                return nil
            }
            handleMouseUp()
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func applicationBundleIdentifier(at point: CGPoint) -> String? {
        // Also protect an excluded window clicked before it becomes the frontmost app.
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.contains(point),
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t else { continue }
            return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        return nil
    }

    private func handleDrag(at point: CGPoint) {
        switch state {
        case .idle, .cancelled:
            return
        case let .pending(start, recognizer):
            var recognizer = recognizer
            guard recognizer.update(point: gesturePoint(point), isRecognizing: false) else { return }
            let sequenceBeforeUpdate = recognizer.sequence
            _ = recognizer.update(point: gesturePoint(point), isRecognizing: true)
            let hasConsumedGesture = recognizer.sequence != sequenceBeforeUpdate
                && fireImmediateRuleIfMatched(sequence: recognizer.sequence)
            state = .recognizing(
                start: start,
                recognizer: recognizer,
                hasConsumedGesture: hasConsumedGesture
            )
        case let .recognizing(start, recognizer, hasConsumedGesture):
            var recognizer = recognizer
            let sequenceBeforeUpdate = recognizer.sequence
            _ = recognizer.update(point: gesturePoint(point), isRecognizing: true)
            let didConsumeGesture = !hasConsumedGesture
                && recognizer.sequence != sequenceBeforeUpdate
                && fireImmediateRuleIfMatched(sequence: recognizer.sequence)
            state = .recognizing(
                start: start,
                recognizer: recognizer,
                hasConsumedGesture: hasConsumedGesture || didConsumeGesture
            )
        }
    }

    private func handleMouseUp() {
        let completedState = state
        resetState()
        switch completedState {
        case .idle, .cancelled:
            return
        case let .pending(start, _):
            repostRightClick(at: start)
        case let .recognizing(start, recognizer, hasConsumedGesture):
            guard !hasConsumedGesture else { return }
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
            let bundleIdentifier = frontmostApplication?.bundleIdentifier
            let targetPID = frontmostApplication?.processIdentifier
            guard preferences.allows(bundleIdentifier: bundleIdentifier) else { return }
            if let rule = MouseGestureRuleMatcher.firstMatch(
                sequence: recognizer.sequence,
                bundleIdentifier: bundleIdentifier,
                rules: rules
            ) {
                postShortcut(rule, targetPID: targetPID)
            } else {
                repostRightClick(at: start)
            }
        }
    }

    private func fireImmediateRuleIfMatched(sequence: [MouseGestureDirection]) -> Bool {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        guard preferences.allows(bundleIdentifier: frontmostApplication?.bundleIdentifier) else { return false }
        guard let rule = MouseGestureRuleMatcher.firstImmediateMatch(
            sequence: sequence,
            bundleIdentifier: frontmostApplication?.bundleIdentifier,
            rules: rules
        ) else {
            return false
        }
        postShortcut(rule, targetPID: frontmostApplication?.processIdentifier)
        return true
    }

    private func scheduleTimeout() {
        timeoutTimer?.invalidate()
        let timer = Timer(
            timeInterval: 5,
            target: self,
            selector: #selector(resetGestureAfterTimeout(_:)),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        timeoutTimer = timer
    }

    private func resetState() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        state = .idle
        gestureTargetPID = nil
    }

    @objc private func resetGestureAfterTimeout(_ timer: Timer) {
        resetState()
    }

    private var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }

    private func repostRightClick(at point: CGPoint) {
        for type in [CGEventType.rightMouseDown, .rightMouseUp] {
            guard let event = CGEvent(
                mouseEventSource: nil,
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: .right
            ) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    private func postShortcut(_ rule: MouseGestureRule, targetPID: pid_t?) {
        if let action = SystemGestureAction.action(
            keyCode: rule.keyCode,
            modifierFlags: rule.modifierFlags
        ) {
            runSystemAction(action)
            return
        }
        let source = shortcutEventSource
        shortcutPostingQueue.async {
            Self.postShortcut(rule, targetPID: targetPID, eventSource: source)
        }
    }

    private func runSystemAction(_ action: SystemGestureAction.Definition) {
        SystemActionRunner.run(action)
    }

    private static func postShortcut(
        _ rule: MouseGestureRule,
        targetPID: pid_t?,
        eventSource: ShortcutEventSource
    ) {
        let modifierDefinitions: [(keyCode: CGKeyCode, flag: CGEventFlags)] = [
            (59, CGEventFlags(rawValue: KeyboardShortcut.controlFlag)),
            (58, CGEventFlags(rawValue: KeyboardShortcut.optionFlag)),
            (56, CGEventFlags(rawValue: KeyboardShortcut.shiftFlag)),
            (55, CGEventFlags(rawValue: KeyboardShortcut.commandFlag))
        ]
        let modifiers = modifierDefinitions.filter { rule.modifierFlags & $0.flag.rawValue != 0 }
        let fullFlags = CGEventFlags(rawValue: rule.modifierFlags)

        func post(
            keyCode: CGKeyCode,
            type: CGEventType,
            flags: CGEventFlags
        ) {
            guard let event = CGEvent(
                keyboardEventSource: eventSource.source,
                virtualKey: keyCode,
                keyDown: type != .keyUp
            ) else {
                return
            }
            event.type = type
            event.flags = flags
            if let targetPID {
                event.postToPid(targetPID)
            } else {
                event.post(tap: .cghidEventTap)
            }
            usleep(10_000)
        }

        var currentFlags = CGEventFlags()
        for modifier in modifiers {
            currentFlags.insert(modifier.flag)
            post(
                keyCode: modifier.keyCode,
                type: .flagsChanged,
                flags: currentFlags
            )
        }

        post(keyCode: rule.keyCode, type: .keyDown, flags: fullFlags)
        post(keyCode: rule.keyCode, type: .keyUp, flags: fullFlags)

        for modifier in modifiers.reversed() {
            currentFlags.remove(modifier.flag)
            post(
                keyCode: modifier.keyCode,
                type: .flagsChanged,
                flags: currentFlags
            )
        }

    }

    private func gesturePoint(_ point: CGPoint) -> MouseGesturePoint {
        MouseGesturePoint(x: point.x, y: point.y)
    }
}
