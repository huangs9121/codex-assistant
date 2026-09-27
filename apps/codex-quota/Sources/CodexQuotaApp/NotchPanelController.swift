import AppKit
import CodexQuotaCore
import SwiftUI

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
final class NotchPanelController {
    private let model: StatusPanelModel
    private let presentation = NotchPresentation()
    private let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var hosting: NSHostingView<NotchPanelView>!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var menuObservers: [NSObjectProtocol] = []
    private var hoverWork: DispatchWorkItem?
    private var animationGeneration = 0
    private var enabled = false
    private var screen: NSScreen?
    private var isHovering = false
    private var lockedOpen = false
    private var openedByHover = false
    private(set) var isExpanded = false

    init(model: StatusPanelModel, text: AppText, actions: NotchActions) {
        self.model = model
        panel.title = "趁手 · 灵动岛"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .init(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.onEscape = { [weak self] in self?.collapse() }
        hosting = NSHostingView(rootView: NotchPanelView(model: model, presentation: presentation, text: text, actions: actions,
            open: { [weak self] in self?.openFromClick() }, hover: { [weak self] inside in self?.hover(inside) }))
        hosting.sizingOptions = []
        panel.contentView = hosting
        model.onIslandContentChange = { [weak self] in self?.resizeForContent() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateScreen() }
        }
        menuObservers = [
            NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lockedOpen = true; self?.hoverWork?.cancel() }
            },
            NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lockedOpen = false
                    if !self.isHovering { self.hover(false) }
                }
            }
        ]
    }

    func setEnabled(_ value: Bool, expand: Bool = false) {
        enabled = value
        if value {
            updateScreen()
            panel.orderFrontRegardless()
            installMonitors()
            if expand { self.expand() } else { prepareContent() }
        } else {
            animationGeneration += 1
            hoverWork?.cancel()
            isExpanded = false
            presentation.expanded = false
            presentation.contentVisible = false
            presentation.contentMounted = false
            panel.orderOut(nil)
            removeMonitors()
        }
    }

    func openFromClick() {
        // Hover may have opened the panel before a click lands; click pins it.
        hoverWork?.cancel()
        openedByHover = false
        if isExpanded { panel.makeKey() } else { expand() }
    }

    /// Opening overshoots by well under a point, so the window can stay at the final size.
    private static let openSpring = Animation.spring(response: 0.4, dampingFraction: 0.9)
    private static let closeSpring = Animation.spring(response: 0.32, dampingFraction: 1)

    /// Builds the open panel once, hidden, so opening never waits for its first layout.
    private func prepareContent() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, enabled, !presentation.contentMounted else { return }
            presentation.panelHeight = openHeight()
            presentation.contentMounted = true
        }
    }

    func expand(byHover: Bool = false) {
        guard enabled, !isExpanded else { return }
        openedByHover = byHover
        hoverWork?.cancel()
        isExpanded = true
        animationGeneration += 1
        let generation = animationGeneration
        model.tick()
        presentation.panelHeight = openHeight()
        presentation.contentMounted = true
        // Size the window for the open island first; the island is still drawn at its collapsed size.
        setWindowFrame(expandedFrame())
        panel.orderFrontRegardless()
        if !byHover {
            panel.makeKey()
            panel.makeFirstResponder(hosting)
        }
        guard !reduceMotion else {
            presentation.expanded = true
            presentation.contentVisible = true
            return
        }
        // Start on the next pass so the resized window has drawn the collapsed island in place.
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == animationGeneration, isExpanded else { return }
            withAnimation(Self.openSpring) { presentation.expanded = true }
            withAnimation(.easeOut(duration: 0.2).delay(0.06)) { presentation.contentVisible = true }
        }
    }

    func collapse() {
        guard enabled, isExpanded, !lockedOpen else { return }
        hoverWork?.cancel()
        animationGeneration += 1
        let generation = animationGeneration
        isExpanded = false
        let finish = { [weak self] in
            guard let self, generation == animationGeneration, !isExpanded else { return }
            setWindowFrame(collapsedFrame())
            panel.resignKey()
        }
        guard !reduceMotion else {
            presentation.contentVisible = false
            presentation.expanded = false
            finish()
            return
        }
        withAnimation(.easeIn(duration: 0.1)) { presentation.contentVisible = false }
        withAnimation(Self.closeSpring) { presentation.expanded = false }
        // The window shrinks back only after the outline has finished closing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: finish)
    }

    func whileShowingMenu(_ body: () -> Void) {
        lockedOpen = true
        hoverWork?.cancel()
        body()
        lockedOpen = false
        if !isHovering { hover(false) }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private func updateScreen() {
        guard enabled else { return }
        // Prefer the physical notch, with a top-centred island on external displays.
        screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let notchWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            notchWidth = max(0, right.minX - left.maxX)
        } else { notchWidth = 120 }
        presentation.neckHeight = max(screen.safeAreaInsets.top, 28)
        presentation.neckWidth = max(240, notchWidth + 120)
        presentation.panelWidth = min(600, screen.frame.width - 32)
        if isExpanded { presentation.panelHeight = openHeight() }
        setWindowFrame(isExpanded ? expandedFrame() : collapsedFrame())
    }

    /// Resizes the window and lays the island out in the same pass, so a resize never shows stale content.
    private func setWindowFrame(_ frame: NSRect) {
        panel.setFrame(frame, display: true)
        hosting.layoutSubtreeIfNeeded()
    }

    private func openHeight() -> CGFloat { presentation.neckHeight + DailyPanelContent.contentHeight(model: model) }
    private func collapsedFrame() -> NSRect {
        guard let screen else { return .zero }
        return NSRect(x: screen.frame.midX - presentation.neckWidth / 2,
                      y: screen.frame.maxY - presentation.collapsedHeight,
                      width: presentation.neckWidth, height: presentation.collapsedHeight)
    }
    private func expandedFrame(height: CGFloat? = nil) -> NSRect {
        guard let screen else { return .zero }
        let height = height ?? presentation.panelHeight
        return NSRect(x: screen.frame.midX - presentation.panelWidth / 2, y: screen.frame.maxY - height,
                      width: presentation.panelWidth, height: height)
    }
    private func resizeForContent() {
        guard enabled, isExpanded else { return }
        let height = openHeight()
        guard abs(presentation.panelHeight - height) > 0.5 else { return }
        // Grow the window before the outline, and shrink it only after the outline has followed.
        if height > panel.frame.height { setWindowFrame(expandedFrame(height: height)) }
        withAnimation(reduceMotion ? nil : Self.closeSpring) { presentation.panelHeight = height }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.45)) { [weak self] in
            guard let self, isExpanded, abs(presentation.panelHeight - height) < 0.5,
                  abs(panel.frame.height - height) > 0.5 || abs(panel.frame.width - presentation.panelWidth) > 0.5 else { return }
            setWindowFrame(expandedFrame())
        }
    }
    private func hover(_ inside: Bool) {
        isHovering = inside
        hoverWork?.cancel()
        guard enabled, !lockedOpen else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if inside { expand(byHover: true) } else if openedByHover { collapse() }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.18 : 0.75), execute: work)
    }
    private func installMonitors() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.collapse() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                if event.type == .keyDown, event.keyCode == 53, self.isExpanded, !self.lockedOpen, self.panel.isKeyWindow { self.collapse(); return true }
                if event.type != .keyDown, event.window !== self.panel { self.collapse() }
                return false
            }
            return consumed ? nil : event
        }
    }
    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
    }

    func keepPreviewVisible() { lockedOpen = true }

    // Uses the running production view for a deterministic native visual fixture.
    var verificationFrame: NSRect { panel.frame }

    func snapshot(to path: String) throws {
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try png.write(to: URL(fileURLWithPath: path))
    }
}
