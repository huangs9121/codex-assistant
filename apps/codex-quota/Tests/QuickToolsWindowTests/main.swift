import AppKit

@MainActor
final class CloseObserver: NSObject, NSWindowDelegate {
    var closed = false
    func windowWillClose(_ notification: Notification) { closed = true }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.finishLaunching()
let window = QuickToolsWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 540),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
window.isReleasedWhenClosed = false
let observer = CloseObserver()
window.delegate = observer
window.makeKeyAndOrderFront(nil)
@MainActor
func key(_ character: String, modifiers: NSEvent.ModifierFlags = .command) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers,
        timestamp: 0, windowNumber: window.windowNumber, context: nil,
        characters: character, charactersIgnoringModifiers: character,
        isARepeat: false, keyCode: character == "w" ? 13 : 46
    )!
}
precondition(!window.hidesOnDeactivate)
precondition(window.canBecomeKey)
precondition(!window.performKeyEquivalent(with: key("w", modifiers: [])))
precondition(!observer.closed)
precondition(window.performKeyEquivalent(with: key("m")))
// AppKit completes miniaturization asynchronously; wait for that transition
// instead of depending on animation timing in the current desktop session.
let miniaturizationDeadline = Date().addingTimeInterval(3)
while !window.isMiniaturized && Date() < miniaturizationDeadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
}
precondition(window.isMiniaturized)
window.deminiaturize(nil)
precondition(window.performKeyEquivalent(with: key("w")))
precondition(observer.closed)
print("PASS: normal window stays on deactivation; plain W is ignored; Command-M minimizes; Command-W closes")
