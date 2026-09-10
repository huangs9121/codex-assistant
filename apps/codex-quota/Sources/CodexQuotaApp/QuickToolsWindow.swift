import AppKit

/// The menu-bar app has no main menu to dispatch standard window shortcuts.
@MainActor
final class QuickToolsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a":
            return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        case "c":
            return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case "v":
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case "x":
            return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
        case "w":
            performClose(nil)
            return true
        case "m":
            performMiniaturize(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}
