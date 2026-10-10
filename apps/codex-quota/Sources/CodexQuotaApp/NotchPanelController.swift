import AppKit
import CodexQuotaCore
import CodexQuotaUI
import ColorSync
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
    private var preferences: DisplayPreferences
    private struct DisplayScreen {
        let screen: NSScreen
        let displayID: CGDirectDisplayID
        let descriptor: IslandDisplayDescriptor
    }
    private var displayScreens: [DisplayScreen] = []
    private var availableScreens: [NSScreen] = []
    var onDisplaysChanged: (() -> Void)?
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

    init(model: StatusPanelModel, text: AppText, actions: NotchActions, defaults: UserDefaults = .standard) {
        self.model = model
        preferences = DisplayPreferences(defaults: defaults)
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
        refreshDisplayInventory()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshDisplayInventory()
                self.updateScreen()
                self.onDisplaysChanged?()
            }
        }
        menuObservers = [
            NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lockedOpen = true; self?.hoverWork?.cancel() }
            },
            NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lockedOpen = false
                    self.hover(self.visibleIslandContainsMouse(), force: true)
                }
            }
        ]
    }

    func setEnabled(_ value: Bool, expand: Bool = false) {
        enabled = value
        if value {
            refreshDisplayInventory()
            updateScreen()
            installMonitors()
            if expand { self.expand() } else { prepareContent() }
        } else {
            animationGeneration += 1
            hoverWork?.cancel()
            hoverWork = nil
            isHovering = false
            openedByHover = false
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
        // Start on the next pass so newly mounted content has been laid out.
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == animationGeneration, isExpanded else { return }
            withAnimation(Self.openSpring) { presentation.expanded = true }
            withAnimation(.easeOut(duration: 0.2).delay(0.06)) { presentation.contentVisible = true }
        }
    }

    func collapse() {
        guard enabled, isExpanded, !lockedOpen else { return }
        hoverWork?.cancel()
        hoverWork = nil
        animationGeneration += 1
        let generation = animationGeneration
        isExpanded = false
        let finish = { [weak self] in
            guard let self, generation == animationGeneration, !isExpanded else { return }
            panel.resignKey()
        }
        guard !reduceMotion else {
            presentation.contentVisible = false
            presentation.expanded = false
            isHovering = visibleIslandContainsMouse()
            finish()
            return
        }
        withAnimation(.easeIn(duration: 0.1)) { presentation.contentVisible = false }
        withAnimation(Self.closeSpring) { presentation.expanded = false }
        // A stationary pointer in the old body is outside the newly collapsed island.
        isHovering = visibleIslandContainsMouse()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: finish)
    }

    func whileShowingMenu(_ body: () -> Void) {
        lockedOpen = true
        hoverWork?.cancel()
        body()
        lockedOpen = false
        hover(visibleIslandContainsMouse(), force: true)
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var selectedDisplayID: String? { preferences.islandDisplayID }

    var displayOptions: [IslandDisplayOption] {
        IslandDisplaySelection.options(displays: displayScreens.map(\.descriptor),
            preferredID: preferences.islandDisplayID, preferredName: preferences.islandDisplayName)
    }

    var displaySelectionDetail: String {
        guard let preferredID = preferences.islandDisplayID,
              !displayScreens.contains(where: { $0.descriptor.id == preferredID }) else {
            return "选择灵动岛显示在哪块屏幕。"
        }
        let current = resolvedScreen().flatMap { target in
            displayScreens.first { $0.displayID == Self.displayID(for: target) }?.descriptor
        }
        let name = current.map { $0.isBuiltIn ? "内置显示器" : $0.name } ?? "可用屏幕"
        return "暂用\(name)，重连后恢复。"
    }

    func selectDisplay(_ id: String?) {
        let display = id.flatMap { id in displayScreens.first { $0.descriptor.id == id } }
        guard id == nil || display != nil else { return }
        preferences.islandDisplayID = id
        preferences.islandDisplayName = display.map { $0.descriptor.isBuiltIn ? "内置显示器" : $0.descriptor.name }
        updateScreen()
        onDisplaysChanged?()
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func refreshDisplayInventory() {
        availableScreens = NSScreen.screens
        displayScreens = availableScreens.compactMap { screen in
            guard let displayID = Self.displayID(for: screen),
                  let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
            let id = CFUUIDCreateString(nil, uuid) as String
            return DisplayScreen(screen: screen, displayID: displayID, descriptor: IslandDisplayDescriptor(
                id: id, name: screen.localizedName, isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                isPrimary: CGDisplayIsMain(displayID) != 0, hasNotch: screen.safeAreaInsets.top > 0))
        }
    }

    private func resolvedScreen() -> NSScreen? {
        let automaticScreen = availableScreens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main ?? availableScreens.first
        // UUID lookup can briefly fail during reconfiguration. Keep that physical screen in
        // automatic selection instead of preferring another screen just because its UUID exists.
        if let automaticScreen,
           !displayScreens.contains(where: { $0.displayID == Self.displayID(for: automaticScreen) }) {
            return displayScreens.first { $0.descriptor.id == preferences.islandDisplayID }?.screen ?? automaticScreen
        }
        let mainID = NSScreen.main.flatMap(Self.displayID(for:))
        let mainUUID = displayScreens.first { $0.displayID == mainID }?.descriptor.id
        let id = IslandDisplaySelection.resolvedDisplayID(preferredID: preferences.islandDisplayID,
            displays: displayScreens.map(\.descriptor), mainDisplayID: mainUUID)
        return displayScreens.first { $0.descriptor.id == id }?.screen ?? automaticScreen
    }

    private func resetInteractionForRelocation() {
        animationGeneration += 1
        hoverWork?.cancel()
        hoverWork = nil
        isHovering = false
        openedByHover = false
        isExpanded = false
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentation.expanded = false
            presentation.contentVisible = false
        }
        panel.resignKey()
    }

    private func updateScreen() {
        guard enabled else { return }
        let nextScreen = resolvedScreen()
        if screen?.frame != nextScreen?.frame || screen.flatMap(Self.displayID(for:)) != nextScreen.flatMap(Self.displayID(for:)) {
            resetInteractionForRelocation()
        }
        screen = nextScreen
        guard let screen else {
            panel.orderOut(nil)
            return
        }
        let notchWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            notchWidth = max(0, right.minX - left.maxX)
        } else { notchWidth = 120 }
        presentation.neckHeight = max(screen.safeAreaInsets.top, 28)
        presentation.notchWidth = notchWidth
        presentation.neckWidth = max(240, notchWidth + 120)
        presentation.panelWidth = min(600, screen.frame.width - 32)
        if isExpanded { presentation.panelHeight = openHeight() }
        panel.setFrame(windowFrame(), display: true)
        hosting.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
    }

    private func openHeight() -> CGFloat { presentation.neckHeight + DailyPanelContent.contentHeight(model: model) }
    /// The window never changes size: it covers the largest open island, and everything outside the
    /// island is transparent, so clicks there reach the windows below. Resizing a visible window after
    /// a click on the wallpaper makes macOS play its own scaling transition, which showed as a flash.
    private func windowFrame() -> NSRect {
        guard let screen else { return .zero }
        let size = presentation.windowSize
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }
    private func resizeForContent() {
        guard enabled, isExpanded else { return }
        let height = openHeight()
        guard abs(presentation.panelHeight - height) > 0.5 else { return }
        withAnimation(reduceMotion ? nil : Self.closeSpring) { presentation.panelHeight = height }
    }
    private func visibleIslandContainsMouse() -> Bool {
        let mouse = NSEvent.mouseLocation
        let location = CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)
        let outline = IslandShape(neckWidth: presentation.neckWidth, neckHeight: presentation.neckHeight)
        return outline.contains(location, inWindowOfSize: panel.frame.size, islandSize: presentation.islandSize)
    }
    private func hover(_ inside: Bool, force: Bool = false) {
        // Continuous hover reports every move; repeated points must not restart the delay.
        guard inside != isHovering || force else { return }
        isHovering = inside
        hoverWork?.cancel()
        guard enabled, !lockedOpen else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, enabled, !lockedOpen, isHovering == inside else { return }
            // Recheck at the deadline as well, including after dismissal or a screen change.
            guard visibleIslandContainsMouse() == inside else { hover(!inside); return }
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
