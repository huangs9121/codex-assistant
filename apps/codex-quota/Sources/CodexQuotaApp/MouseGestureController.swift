import AppKit
import CodexQuotaCore
import CoreGraphics

final class MouseGestureController: NSObject {
    static let rulesDefaultsKey = "mouseGestureRules"
    private static let syntheticEventMarker: Int64 = 0x4351_4753

    private enum State {
        case idle
        case pending(start: CGPoint, recognizer: MouseGestureRecognizer)
        case recognizing(start: CGPoint, recognizer: MouseGestureRecognizer)
    }

    private let defaults: UserDefaults
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timeoutTimer: Timer?
    private var state: State = .idle
    private(set) var rules: [MouseGestureRule] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        if !hasEnabledRules {
            stop()
        }
    }

    @discardableResult
    func startIfPermitted() -> Bool {
        guard hasEnabledRules, isAccessibilityTrusted else {
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

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .rightMouseDown:
            guard hasEnabledRules else { return Unmanaged.passUnretained(event) }
            let point = event.location
            state = .pending(
                start: point,
                recognizer: MouseGestureRecognizer(start: gesturePoint(point))
            )
            scheduleTimeout()
            return nil
        case .rightMouseDragged:
            guard !isIdle else { return Unmanaged.passUnretained(event) }
            handleDrag(at: event.location)
            return nil
        case .rightMouseUp:
            guard !isIdle else { return Unmanaged.passUnretained(event) }
            handleMouseUp()
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleDrag(at point: CGPoint) {
        switch state {
        case .idle:
            return
        case let .pending(start, recognizer):
            var recognizer = recognizer
            guard recognizer.update(point: gesturePoint(point), isRecognizing: false) else { return }
            _ = recognizer.update(point: gesturePoint(point), isRecognizing: true)
            state = .recognizing(start: start, recognizer: recognizer)
        case let .recognizing(start, recognizer):
            var recognizer = recognizer
            _ = recognizer.update(point: gesturePoint(point), isRecognizing: true)
            state = .recognizing(start: start, recognizer: recognizer)
        }
    }

    private func handleMouseUp() {
        let completedState = state
        resetState()
        switch completedState {
        case .idle:
            return
        case let .pending(start, _):
            repostRightClick(at: start)
        case let .recognizing(start, recognizer):
            let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if let rule = MouseGestureRuleMatcher.firstMatch(
                sequence: recognizer.sequence,
                bundleIdentifier: bundleIdentifier,
                rules: rules
            ) {
                postShortcut(rule)
            } else {
                repostRightClick(at: start)
            }
        }
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

    private func postShortcut(_ rule: MouseGestureRule) {
        let flags = CGEventFlags(rawValue: rule.modifierFlags)
        for isKeyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: rule.keyCode, keyDown: isKeyDown) else {
                continue
            }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    private func gesturePoint(_ point: CGPoint) -> MouseGesturePoint {
        MouseGesturePoint(x: point.x, y: point.y)
    }
}
