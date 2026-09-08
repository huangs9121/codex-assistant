import AppKit

// Shared with right-click tools so new rule editors inherit the same density and controls.
@MainActor enum QuickToolsTableStyle {
    static func configure(_ table: NSTableView) {
        table.headerView = NSTableHeaderView()
        table.rowHeight = 34
        table.usesAlternatingRowBackgroundColors = true
    }
}

final class SingleClickTextField: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
