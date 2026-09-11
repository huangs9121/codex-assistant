import AppKit
import CodexQuotaCore

/// Both trigger sources execute the same catalog, without forwarding sentinel key codes.
enum SystemActionRunner {
    static let syntheticEventMarker: Int64 = 0x4351_4B4D
    static func run(_ action: SystemGestureAction.Definition, eventSink: ((CGEvent) -> Void)? = nil) {
        switch action.invocation {
        case let .keyboardShortcut(keyCode, flags):
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { continue }
                event.flags = CGEventFlags(rawValue: flags)
                event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
                if let eventSink { eventSink(event) } else { event.post(tap: .cghidEventTap) }
            }
        case let .openApplication(path):
            DispatchQueue.main.async { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        case let .runCommand(path, arguments):
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
                try? process.run()
            }
        }
    }
}
