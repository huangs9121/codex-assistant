import AppKit
import CodexQuotaCore

// Compiled with the actual controller. Events are constructed but never posted to the desktop.
@main
enum MouseGestureControllerChecks {
    static func main() {
        let suite = "CodexQuotaGestureControllerChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let rules = [MouseGestureRule(gesture: [.down], keyCode: 17, modifierFlags: KeyboardShortcut.commandFlag, firesImmediately: true)]
        MouseGestureController.saveRules(rules, to: defaults)
        let controller = MouseGestureController(defaults: defaults)
        let blender = "org.blenderfoundation.blender"
        let safari = "com.apple.Safari"
        let types: [CGEventType] = [.rightMouseDown, .rightMouseDragged, .rightMouseUp]

        func event(_ type: CGEventType) -> CGEvent {
            CGEvent(mouseEventSource: nil, mouseType: type,
                    mouseCursorPosition: CGPoint(x: 100, y: type == .rightMouseDown ? 100 : 200), mouseButton: .right)!
        }
        func checkPassthrough(_ label: String, bundle: String, pointed: String? = nil, releaseBundle: String? = nil) {
            for type in types {
                let input = event(type)
                input.setIntegerValueField(.eventSourceUserData, value: 12345)
                let output = controller.handle(type: type, event: input,
                    bundleIdentifier: type == .rightMouseDown ? bundle : releaseBundle ?? bundle,
                    targetPID: 123, pointedBundleIdentifier: pointed)
                precondition(output?.takeUnretainedValue() === input, "\(label): \(type) was intercepted")
                precondition(input.getIntegerValueField(.eventSourceUserData) == 12345)
            }
            print("PASS: \(label) preserves original down / drag / up events")
        }
        checkPassthrough("Blender exclusion overrides a global immediate rule", bundle: blender)
        checkPassthrough("First click into inactive Blender", bundle: safari, pointed: blender)
        checkPassthrough("Excluded drag stays native across focus changes", bundle: blender, releaseBundle: safari)

        var preferences = controller.preferences
        preferences.isEnabled = false
        preferences.save(to: defaults)
        controller.reloadRules()
        precondition(!controller.startIfPermitted() && !controller.isRunning)
        checkPassthrough("Master off", bundle: safari)
        // Saving a rule must not restart the tap when the master switch is off.
        MouseGestureController.saveRules(rules, to: defaults)
        controller.reloadRules()
        precondition(!controller.startIfPermitted() && !controller.isRunning)
        precondition(controller.rules == rules)
        print("PASS: master off remains off when rules reload; saved rules unchanged")

        preferences.isEnabled = true
        preferences.save(to: defaults)
        controller.reloadRules()
        precondition(controller.handle(type: .rightMouseDown, event: event(.rightMouseDown),
            bundleIdentifier: safari, targetPID: 123, pointedBundleIdentifier: nil) == nil)
        // Switching to an excluded app while a gesture is held must cancel both immediate and release actions.
        precondition(controller.handle(type: .rightMouseDragged, event: event(.rightMouseDragged),
            bundleIdentifier: blender, targetPID: 456, pointedBundleIdentifier: nil) == nil)
        precondition(controller.handle(type: .rightMouseUp, event: event(.rightMouseUp),
            bundleIdentifier: safari, targetPID: 123, pointedBundleIdentifier: nil) == nil)
        print("PASS: allowed app starts recognition; focus change cancels the pending gesture")
        controller.stop()

        preferences.removeExclusion(bundleIdentifier: blender)
        preferences.save(to: defaults)
        controller.reloadRules()
        precondition(controller.handle(type: .rightMouseDown, event: event(.rightMouseDown),
            bundleIdentifier: blender, targetPID: 456, pointedBundleIdentifier: nil) == nil)
        controller.stop()
        print("PASS: removing an exclusion restores recognition")
    }
}
