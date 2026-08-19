import AppKit
import CoreGraphics
import CodexQuotaCore

final class MouseScrollReversalController {
    static let isEnabledDefaultsKey = "mouseScrollReversalEnabled"

    private let defaults: UserDefaults
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

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

        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
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

    func requestAccessibilityPermission() {
        // This is the documented string value of kAXTrustedCheckOptionPrompt.
        // Using it directly avoids Swift 6's shared-C-global concurrency warning.
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
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
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static let verticalFields: [CGEventField] = [
        .scrollWheelEventDeltaAxis1,
        .scrollWheelEventPointDeltaAxis1,
        .scrollWheelEventFixedPtDeltaAxis1
    ]

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let controller = Unmanaged<MouseScrollReversalController>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = controller.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel,
              MouseScrollReversal.shouldReverseVerticalAxis(
                isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous)
              )
        else {
            return Unmanaged.passUnretained(event)
        }

        for field in verticalFields {
            event.setIntegerValueField(field, value: -event.getIntegerValueField(field))
        }
        return Unmanaged.passUnretained(event)
    }
}
