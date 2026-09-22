import AppKit
import SwiftUI

/// All application button help uses this delay, in seconds.
enum ButtonHelp {
    static let delay: TimeInterval = 0.5
}

struct ResetTimeHelp {
    let title: String
    let date: String
    let timeZone: String
    var accessibilityText: String { "\(title)：\(date)，\(timeZone)" }

    func makeSurface() -> NSView {
        let surface = NSView(frame: NSRect(x: 0, y: 0, width: 224, height: 90))
        surface.wantsLayer = true
        surface.layer?.backgroundColor = NSColor(srgbRed: 0.145, green: 0.153, blue: 0.169, alpha: 0.98).cgColor
        surface.layer?.cornerRadius = 10
        surface.layer?.borderWidth = 1
        surface.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        let rows: [(String, CGFloat, CGFloat, NSFont.Weight, CGFloat)] = [
            (title, 60, 12, .regular, 0.65),
            (date, 34, 15, .semibold, 1),
            (timeZone, 12, 11, .regular, 0.65)
        ]
        let width = max(224, rows.map { text, _, size, weight, _ in
            ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width) + 28
        }.max() ?? 224)
        surface.setFrameSize(NSSize(width: width, height: 90))
        for (text, y, size, weight, opacity) in rows {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: size, weight: weight)
            label.textColor = NSColor.white.withAlphaComponent(opacity)
            label.frame = NSRect(x: 12, y: y, width: width - 24, height: 20)
            surface.addSubview(label)
        }
        return surface
    }
}

@MainActor
final class ButtonHelpPresenter {
    static let shared = ButtonHelpPresenter()
    private var pending: Task<Void, Never>?
    private weak var source: NSView?
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    private init() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            self?.dismiss()
            return event
        }
        for name in [NSApplication.didResignActiveNotification, NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        }
    }

    func schedule(for view: NSView, text: String, resetTime: ResetTimeHelp? = nil) {
        dismiss()
        guard !text.isEmpty else { return }
        source = view
        pending = Task { @MainActor [weak self, weak view] in
            try? await Task.sleep(nanoseconds: UInt64(ButtonHelp.delay * 1_000_000_000))
            guard !Task.isCancelled, let self, let view, self.source === view,
                  let window = view.window, window.isVisible,
                  !view.isHiddenOrHasHiddenAncestor else { return }
            let point = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            guard view.visibleRect.contains(point) else { self.dismiss(); return }
            self.show(text, at: view, in: window, resetTime: resetTime)
        }
    }

    func dismiss(for view: NSView? = nil) {
        if let view, source !== view { return }
        pending?.cancel()
        pending = nil
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panel = nil
        source = nil
    }

    private func show(_ text: String, at view: NSView, in window: NSWindow, resetTime: ResetTimeHelp?) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: 296, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: label.font!]
        )
        let width = min(300, max(32, ceil(measured.width) + 4))
        label.preferredMaxLayoutWidth = width
        let height = max(18, ceil(measured.height) + 4)
        let surface = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width + 16, height: height + 10))
        surface.material = .toolTip
        surface.state = .active
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 6
        label.frame = NSRect(x: 8, y: 5, width: width, height: height)
        surface.addSubview(label)
        let content: NSView = resetTime?.makeSurface() ?? surface
        let panel = NSPanel(contentRect: content.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = true
        panel.contentView = content
        panel.appearance = view.effectiveAppearance
        panel.level = .popUpMenu
        let anchor = window.convertToScreen(view.convert(view.visibleRect, to: nil))
        let mouse = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? window.screen ?? NSScreen.main)?.visibleFrame ?? anchor
        var origin: NSPoint
        if resetTime != nil {
            origin = NSPoint(x: mouse.x, y: mouse.y - 12 - content.frame.height)
            if origin.y < screen.minY + 4 { origin.y = mouse.y + 20 }
        } else {
            origin = NSPoint(x: anchor.midX - content.frame.width / 2, y: anchor.maxY + 6)
            if origin.y + content.frame.height > screen.maxY { origin.y = anchor.minY - content.frame.height - 6 }
        }
        origin.x = max(screen.minX + 4, min(origin.x, screen.maxX - content.frame.width - 4))
        origin.y = max(screen.minY + 4, min(origin.y, screen.maxY - content.frame.height - 4))
        panel.setFrameOrigin(origin)
        self.panel = panel
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
    }
}

/// Native buttons retain their standard click, keyboard and accessibility behavior.
class HelpButton: NSButton {
    private var helpText: String?
    private var helpTracking: NSTrackingArea?
    override var toolTip: String? {
        get { helpText }
        set { helpText = newValue; super.toolTip = nil }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let helpTracking { removeTrackingArea(helpTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        helpTracking = area
    }
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        ButtonHelpPresenter.shared.schedule(for: self, text: toolTip ?? title)
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        ButtonHelpPresenter.shared.dismiss(for: self)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        ButtonHelpPresenter.shared.dismiss(for: self)
        super.viewWillMove(toWindow: newWindow)
    }
}

private struct ButtonHelpAnchor: NSViewRepresentable {
    var text: String
    var resetTime: ResetTimeHelp? = nil
    func makeNSView(context: Context) -> HelpAnchorView { HelpAnchorView() }
    func updateNSView(_ view: HelpAnchorView, context: Context) { view.text = text; view.resetTime = resetTime }
    static func dismantleNSView(_ view: HelpAnchorView, coordinator: ()) { ButtonHelpPresenter.shared.dismiss(for: view) }
}

private final class HelpAnchorView: NSView {
    var text = ""
    var resetTime: ResetTimeHelp?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { ButtonHelpPresenter.shared.schedule(for: self, text: text, resetTime: resetTime) }
    override func mouseExited(with event: NSEvent) { ButtonHelpPresenter.shared.dismiss(for: self) }
}

extension View {
    func resetTimeHelp(_ help: ResetTimeHelp) -> some View {
        background(ButtonHelpAnchor(text: help.accessibilityText, resetTime: help))
            .accessibilityHint(help.accessibilityText)
    }

    func buttonHelp(_ text: String) -> some View {
        background(ButtonHelpAnchor(text: text)).accessibilityHint(text)
    }
}

class HelpPopUpButton: NSPopUpButton {
    private let helpAnchor = HelpAnchorView()
    private var helpText: String?
    override var toolTip: String? {
        get { helpText }
        set { helpText = newValue; super.toolTip = nil; helpAnchor.text = newValue ?? title }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        helpAnchor.frame = bounds
        helpAnchor.autoresizingMask = [.width, .height]
        if helpAnchor.superview == nil { addSubview(helpAnchor) }
        helpAnchor.text = toolTip ?? title
        if window == nil { ButtonHelpPresenter.shared.dismiss(for: helpAnchor) }
    }
}

extension NSAlert {
    @discardableResult func runWithButtonHelp() -> NSApplication.ModalResponse {
        layout()
        for button in buttons {
            let anchor = HelpAnchorView(frame: button.bounds)
            anchor.text = button.title
            anchor.autoresizingMask = [.width, .height]
            button.addSubview(anchor)
        }
        return runModal()
    }
}

/// The cell supplies actual segment frames, so help follows each tab without guessing widths.
final class HelpSegmentedCell: NSSegmentedCell {
    private var anchors: [Int: HelpAnchorView] = [:]
    private var labels: [Int: String] = [:]
    override func setToolTip(_ toolTip: String?, forSegment segment: Int) {
        labels[segment] = toolTip
        super.setToolTip(nil, forSegment: segment)
    }
    override func drawSegment(_ segment: Int, inFrame frame: NSRect, with controlView: NSView) {
        super.drawSegment(segment, inFrame: frame, with: controlView)
        let anchor = anchors[segment] ?? HelpAnchorView()
        anchors[segment] = anchor
        anchor.text = labels[segment] ?? label(forSegment: segment) ?? ""
        let bounds = NSRect(x: frame.minX, y: 0, width: frame.width, height: controlView.bounds.height)
        if anchor.frame != bounds { anchor.frame = bounds }
        if anchor.superview !== controlView { controlView.addSubview(anchor) }
    }
}

extension NSView {
    func installButtonHelp(_ text: String) {
        let anchor = subviews.compactMap { $0 as? HelpAnchorView }.first ?? HelpAnchorView(frame: bounds)
        anchor.text = text
        anchor.autoresizingMask = [.width, .height]
        if anchor.superview == nil { addSubview(anchor) }
    }
}
