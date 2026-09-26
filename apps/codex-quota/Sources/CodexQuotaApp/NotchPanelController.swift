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
            if expand { self.expand() }
        } else {
            animationGeneration += 1
            hoverWork?.cancel()
            isExpanded = false
            presentation.expanded = false
            presentation.contentVisible = false
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

    func expand(byHover: Bool = false) {
        guard enabled, !isExpanded else { return }
        openedByHover = byHover
        hoverWork?.cancel()
        isExpanded = true
        animationGeneration += 1
        let generation = animationGeneration
        model.tick()
        presentation.expanded = true
        presentation.contentVisible = false
        animate(to: expandedFrame(), duration: 0.32)
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.16)) { [weak self] in
            guard let self, generation == animationGeneration, isExpanded else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { presentation.contentVisible = true }
        }
        panel.orderFrontRegardless()
        if !byHover {
            panel.makeKey()
            panel.makeFirstResponder(hosting)
        }
    }

    func collapse() {
        guard enabled, isExpanded, !lockedOpen else { return }
        hoverWork?.cancel()
        animationGeneration += 1
        let generation = animationGeneration
        isExpanded = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.10)) { presentation.contentVisible = false }
        animate(to: collapsedFrame(), duration: 0.26)
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.26)) { [weak self] in
            guard let self, generation == animationGeneration, !isExpanded else { return }
            presentation.expanded = false
            panel.resignKey()
        }
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
        presentation.panelWidth = min(750, screen.frame.width - 32)
        panel.setFrame(isExpanded ? expandedFrame() : collapsedFrame(), display: true)
    }

    private func collapsedFrame() -> NSRect {
        guard let screen else { return .zero }
        return NSRect(x: screen.frame.midX - presentation.neckWidth / 2,
                      y: screen.frame.maxY - presentation.neckHeight - 3,
                      width: presentation.neckWidth, height: presentation.neckHeight + 3)
    }
    private func expandedFrame() -> NSRect {
        guard let screen else { return .zero }
        let height = presentation.neckHeight + DailyPanelContent.contentHeight(model: model)
        return NSRect(x: screen.frame.midX - presentation.panelWidth / 2, y: screen.frame.maxY - height,
                      width: presentation.panelWidth, height: height)
    }
    private func resizeForContent() {
        guard enabled, isExpanded else { return }
        let target = expandedFrame()
        guard abs(panel.frame.height - target.height) > 0.5 || abs(panel.frame.width - target.width) > 0.5 else { return }
        animate(to: target, duration: 0.24)
    }
    private func animate(to frame: NSRect, duration: TimeInterval) {
        guard !reduceMotion else { panel.setFrame(frame, display: true); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.26, 1)
            panel.animator().setFrame(frame, display: true)
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
