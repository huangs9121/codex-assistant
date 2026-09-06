import AppKit

/// The menu-bar app has no main menu to dispatch standard window shortcuts.
@MainActor
final class QuickToolsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
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
