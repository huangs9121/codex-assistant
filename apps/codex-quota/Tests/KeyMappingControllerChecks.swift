import AppKit
import CodexQuotaCore

@main
struct KeyMappingControllerChecks {
    static func main() {
        let suite = "CodexQuotaKeyMappingChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var failures: [String] = []
        var checks = 0
        func check(_ name: String, _ result: Bool) {
            checks += 1
            if !result { failures.append(name) }
            print("\(result ? "PASS" : "FAIL") \(name)")
        }
        defaults.set(true, forKey: DoubleCommandTapController.isEnabledDefaultsKey)
        ModifierTapGesture(keyCodes: [55], tapCount: 2).save(to: defaults)
        DoubleCommandTapShortcut(keyCode: 8, flags: [.maskControl, .maskCommand]).save(to: defaults)
        defaults.set(Data([1, 2, 3]), forKey: "mouseGestureRules")
        var posted: [CGEvent] = []
        let controller = DoubleCommandTapController(defaults: defaults, eventSink: { posted.append($0) })
        let migrated = controller.rules
        check("legacy source and target migrate without altering right-click rules",
              migrated.count == 1 && migrated[0].trigger == .modifierTap(keyCodes: [55], tapCount: 2)
              && migrated[0].target == .init(keyCode: 8, flags: KeyboardShortcut.controlFlag | KeyboardShortcut.commandFlag)
              && controller.isEnabled && defaults.data(forKey: "mouseGestureRules") == Data([1, 2, 3]))
        func event(_ code: UInt16, _ type: CGEventType, _ flags: CGEventFlags = []) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type == .keyDown)!
            event.type = type; event.flags = flags
            return event
        }
        for flags: CGEventFlags in [[.maskCommand], [], [.maskCommand], []] {
            _ = controller.handle(type: .flagsChanged, event: event(55, .flagsChanged, flags))
        }
        check("migrated double modifier posts one marked down-up pair",
              posted.map(\.type) == [.keyDown, .keyUp]
              && posted.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == DoubleCommandTapController.syntheticEventMarker })
        let target = KeyMappingShortcut(keyCode: 8, flags: KeyboardShortcut.commandFlag)
        let chord = KeyMappingRule(trigger: .shortcut(.init(keyCode: 40, flags: KeyboardShortcut.controlFlag)), target: target)
        let chain = KeyMappingRule(trigger: .shortcut(target), target: .init(keyCode: 0, flags: 0))
        DoubleCommandTapController.saveRules([chord, chain], to: defaults); controller.reloadGesture()
        let down = event(40, .keyDown, .maskControl)
        down.keyboardSetUnicodeString(stringLength: 1, unicodeString: [0x006b])
        _ = controller.handle(type: .keyDown, event: down)
        check("real controller rewrites chord and marks it against recursion",
              down.getIntegerValueField(.keyboardEventKeycode) == 8 && down.flags == .maskCommand)
        check("mapped event carries the target character instead of the source", NSEvent(cgEvent: down)?.charactersIgnoringModifiers == "c")
        _ = controller.handle(type: .keyDown, event: down)
        check("mapped output does not trigger a second mapping", down.getIntegerValueField(.keyboardEventKeycode) == 8)
        let up = event(40, .keyUp)
        DoubleCommandTapController.saveRules([], to: defaults); controller.reloadGesture()
        _ = controller.handle(type: .keyUp, event: up)
        check("paired key up survives removed rules and released modifiers",
              up.getIntegerValueField(.keyboardEventKeycode) == 8 && up.flags == .maskCommand)
        check("empty mapping list survives controller restart", DoubleCommandTapController(defaults: defaults).rules.isEmpty)
        DoubleCommandTapController.saveRules([chord], to: defaults); controller.reloadGesture()
        _ = controller.handle(type: .keyDown, event: event(40, .keyDown, .maskControl))
        posted.removeAll(); controller.setRecording(true)
        let recordingKey = event(40, .keyDown, .maskControl)
        _ = controller.handle(type: .keyDown, event: recordingKey)
        check("recording releases held target and bypasses source keys", posted.count == 1
              && posted[0].type == .keyUp && recordingKey.getIntegerValueField(.keyboardEventKeycode) == 40)
        controller.setRecording(false); controller.isEnabled = false
        let disabledKey = event(40, .keyDown, .maskControl)
        _ = controller.handle(type: .keyDown, event: disabledKey)
        check("master switch bypasses mappings", disabledKey.getIntegerValueField(.keyboardEventKeycode) == 40)
        controller.isEnabled = true
        let fnRule = KeyMappingRule(trigger: .shortcut(.init(keyCode: 110, flags: 0)), target: .init(keyCode: 63, flags: 0))
        DoubleCommandTapController.saveRules([fnRule], to: defaults); controller.reloadGesture()
        let fnDown = event(110, .keyDown)
        _ = controller.handle(type: .keyDown, event: fnDown)
        check("Menu to Fn emits a modifier press rather than a printable key",
              fnDown.type == .flagsChanged && fnDown.getIntegerValueField(.keyboardEventKeycode) == 63 && fnDown.flags == .maskSecondaryFn)
        let repeatedFn = event(110, .keyDown)
        repeatedFn.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        check("held Fn does not emit repeat presses", controller.handle(type: .keyDown, event: repeatedFn) == nil)
        let duringFn = event(12, .keyDown)
        _ = controller.handle(type: .keyDown, event: duringFn)
        check("held Fn remains present on subsequent keyboard events", duringFn.flags.contains(.maskSecondaryFn))
        _ = controller.handle(type: .keyUp, event: event(12, .keyUp))
        let fnUp = event(110, .keyUp)
        _ = controller.handle(type: .keyUp, event: fnUp)
        check("Menu release emits Fn release", fnUp.type == .flagsChanged && fnUp.flags.isEmpty)
        _ = controller.handle(type: .keyDown, event: event(110, .keyDown))
        posted.removeAll(); controller.stop()
        check("stopping mapping releases held Fn", posted.count == 1 && posted[0].type == .flagsChanged && posted[0].flags.isEmpty)
        let fnTap = KeyMappingRule(trigger: .modifierTap(keyCodes: [63], tapCount: 1), target: .init(keyCode: 8, flags: KeyboardShortcut.commandFlag))
        DoubleCommandTapController.saveRules([fnTap], to: defaults); controller.reloadGesture(); posted.removeAll()
        _ = controller.handle(type: .flagsChanged, event: event(63, .flagsChanged, .maskSecondaryFn))
        _ = controller.handle(type: .flagsChanged, event: event(63, .flagsChanged))
        check("physical Fn can be used as a source gesture", posted.map(\.type) == [.keyDown, .keyUp])
        print("\(checks - failures.count)/\(checks) controller checks passed; no events posted to desktop")
        exit(failures.isEmpty ? 0 : 1)
    }
}
