import AppKit
import CoreGraphics
import CodexQuotaCore

final class MouseScrollReversalController {
    static let isEnabledDefaultsKey = "mouseScrollReversalEnabled"

    private let defaults: UserDefaults
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var scrollDiagnostics: ScrollDiagnostics?

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
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.handleEvent,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.eventTap = eventTap
        runLoopSource = source
        scrollDiagnostics = ScrollDiagnostics()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return true
    }

    func requestAccessibilityPermission() {
        // This is the documented string value of kAXTrustedCheckOptionPrompt.
        // Using it directly avoids Swift 6's shared-C-global concurrency warning.
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func stop() {
        scrollDiagnostics?.close()
        scrollDiagnostics = nil
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

        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        let shouldReverse = MouseScrollReversal.shouldReverseVerticalAxis(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous)
        )
        if let scrollDiagnostics = controller.scrollDiagnostics,
           !scrollDiagnostics.record(event, reversed: shouldReverse) {
            controller.scrollDiagnostics = nil
        }

        guard shouldReverse else {
            return Unmanaged.passUnretained(event)
        }

        let delta1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let fixedPt1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let point1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)

        // DeltaAxis updates the derived point and fixed-point values internally, so it
        // must be written first. Preserve the fixed-point value before the point value.
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -delta1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixedPt1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -point1)
        return Unmanaged.passUnretained(event)
    }
}

private final class ScrollDiagnostics {
    private static let maximumEventCount = 20

    private var fileHandle: FileHandle?
    private var recordedEventCount = 0

    init() {
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        let logURL = logsDirectory.appendingPathComponent("CodexQuota-scroll.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: logURL)
    }

    @discardableResult
    func record(_ event: CGEvent, reversed: Bool) -> Bool {
        guard recordedEventCount < Self.maximumEventCount, let fileHandle else {
            return false
        }

        recordedEventCount += 1
        let line = [
            "isContinuous=\(event.getIntegerValueField(.scrollWheelEventIsContinuous))",
            "scrollWheelEventDeltaAxis1=\(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))",
            "scrollWheelEventDeltaAxis2=\(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))",
            "scrollWheelEventPointDeltaAxis1=\(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))",
            "scrollWheelEventPointDeltaAxis2=\(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))",
            "scrollWheelEventFixedPtDeltaAxis1=\(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))",
            "scrollWheelEventFixedPtDeltaAxis2=\(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2))",
            "scrollPhase=\(event.getIntegerValueField(.scrollWheelEventScrollPhase))",
            "momentumPhase=\(event.getIntegerValueField(.scrollWheelEventMomentumPhase))",
            "kCGEventSourceUnixProcessID=\(event.getIntegerValueField(.eventSourceUnixProcessID))",
            "reversed=\(reversed)"
        ].joined(separator: " ") + "\n"
        do {
            try fileHandle.write(contentsOf: Data(line.utf8))
        } catch {
            close()
            return false
        }

        if recordedEventCount == Self.maximumEventCount {
            close()
            return false
        }
        return true
    }

    func close() {
        try? fileHandle?.close()
        fileHandle = nil
    }
}
