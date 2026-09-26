import AppKit
import SwiftUI

/// A first-use guide over the existing settings. It never owns or migrates feature rules.
@MainActor
final class OnboardingWindowController: NSObject, ObservableObject, NSWindowDelegate {
    enum Feature: CaseIterable, Hashable {
        case scrollReversal, rightClickGesture, keyMapping

        var title: String {
            switch self {
            case .scrollReversal: "鼠标滚轮反转"
            case .rightClickGesture: "右键手势"
            case .keyMapping: "按键映射"
            }
        }

        var symbol: String {
            switch self {
            case .scrollReversal: "computermouse"
            case .rightClickGesture: "hand.draw"
            case .keyMapping: "keyboard"
            }
        }
    }

    struct FeatureState {
        var enabled: Bool
        var running: Bool

        init(enabled: Bool = false, running: Bool = false) {
            self.enabled = enabled
            self.running = running
        }
    }

    struct Snapshot {
        var accessibilityTrusted: Bool
        var inputMonitoringTrusted: Bool
        var scrollReversal: FeatureState
        var rightClickGesture: FeatureState
        var keyMapping: FeatureState

        init(
            accessibilityTrusted: Bool = false,
            inputMonitoringTrusted: Bool = false,
            scrollReversal: FeatureState = .init(),
            rightClickGesture: FeatureState = .init(),
            keyMapping: FeatureState = .init()
        ) {
            self.accessibilityTrusted = accessibilityTrusted
            self.inputMonitoringTrusted = inputMonitoringTrusted
            self.scrollReversal = scrollReversal
            self.rightClickGesture = rightClickGesture
            self.keyMapping = keyMapping
        }

        func state(for feature: Feature) -> FeatureState {
            switch feature {
            case .scrollReversal: scrollReversal
            case .rightClickGesture: rightClickGesture
            case .keyMapping: keyMapping
            }
        }

        func hasPermission(for feature: Feature) -> Bool {
            accessibilityTrusted && (feature != .keyMapping || inputMonitoringTrusted)
        }

        func status(for feature: Feature) -> String {
            let featureState = state(for: feature)
            guard featureState.enabled else { return "未启用" }
            guard hasPermission(for: feature) else { return "待授权" }
            return featureState.running ? "已启用" : "尚未生效"
        }
    }

    fileprivate enum Step: Int, CaseIterable {
        case welcome, preferences, trial, finish
    }

    static let completedDefaultsKey = "chenshouOnboardingCompleted"

    static func shouldPresentAutomatically(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: completedDefaultsKey)
    }

    private let defaults: UserDefaults
    private let snapshotProvider: () -> Snapshot
    private let setFeatureEnabledAction: (Feature, Bool) -> Void
    private let openSettingsAction: (Feature?) -> Void
    private let requestAccessibilityAction: () -> Void
    private let requestInputMonitoringAction: () -> Void
    private var refreshTimer: Timer?
    private var awaitingSettingsReturn = false
    private var window: NSWindow?

    @Published fileprivate var step: Step = .welcome
    @Published fileprivate var currentSnapshot = Snapshot()
    @Published fileprivate var triedFeatures = Set<Feature>()

    init(
        defaults: UserDefaults = .standard,
        snapshot: @escaping () -> Snapshot,
        setFeatureEnabled: @escaping (Feature, Bool) -> Void,
        openSettings: @escaping (Feature?) -> Void,
        requestAccessibility: @escaping () -> Void,
        requestInputMonitoring: @escaping () -> Void
    ) {
        self.defaults = defaults
        snapshotProvider = snapshot
        setFeatureEnabledAction = setFeatureEnabled
        openSettingsAction = openSettings
        requestAccessibilityAction = requestAccessibility
        requestInputMonitoringAction = requestInputMonitoring
        super.init()
    }

    func showIfNeeded() {
        guard Self.shouldPresentAutomatically(defaults: defaults) else { return }
        show()
    }

    /// Reopening from About starts at the welcome page without changing saved preferences.
    func show() {
        step = .welcome
        triedFeatures.removeAll()
        awaitingSettingsReturn = false
        refresh()
        let window = makeWindowIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        startRefreshing()
    }

    func refresh() {
        currentSnapshot = snapshotProvider()
        triedFeatures = triedFeatures.filter { feature in
            let state = currentSnapshot.state(for: feature)
            return state.enabled && state.running && currentSnapshot.hasPermission(for: feature)
        }
    }

    /// Call when the shared Settings window closes. Ordinary settings use leaves this inert.
    func resumeAfterSettings() {
        guard awaitingSettingsReturn, let window, window.isVisible else { return }
        awaitingSettingsReturn = false
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) { refresh() }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        awaitingSettingsReturn = false
    }

    private func makeWindowIfNeeded() -> NSWindow {
        if let window { return window }
        let window = QuickToolsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 592),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "欢迎使用趁手"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(srgbRed: 0.043, green: 0.055, blue: 0.086, alpha: 1)
        window.contentMinSize = NSSize(width: 680, height: 592)
        window.contentMaxSize = NSSize(width: 680, height: 592)
        window.delegate = self
        window.center()
        window.contentView = NSHostingView(rootView: OnboardingView(controller: self))
        self.window = window
        return window
    }

    private func startRefreshing() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    fileprivate func setEnabled(_ feature: Feature, to enabled: Bool) {
        setFeatureEnabledAction(feature, enabled)
        triedFeatures.remove(feature)
        refresh()
    }

    fileprivate func openSettings(for feature: Feature?) {
        awaitingSettingsReturn = true
        openSettingsAction(feature)
    }

    fileprivate func requestPermissions() {
        let selected = Feature.allCases.filter { currentSnapshot.state(for: $0).enabled }
        guard !selected.isEmpty else { return }
        if !currentSnapshot.accessibilityTrusted { requestAccessibilityAction() }
        if selected.contains(.keyMapping), !currentSnapshot.inputMonitoringTrusted {
            requestInputMonitoringAction()
        }
        refresh()
    }

    fileprivate func setTried(_ feature: Feature, to tried: Bool) {
        let state = currentSnapshot.state(for: feature)
        guard state.enabled, state.running, currentSnapshot.hasPermission(for: feature) else { return }
        if tried { triedFeatures.insert(feature) } else { triedFeatures.remove(feature) }
    }

    fileprivate func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
        refresh()
    }

    fileprivate func continueForward() {
        if step == .finish {
            finish()
        } else if let next = Step(rawValue: step.rawValue + 1) {
            if next == .finish {
                defaults.set(true, forKey: Self.completedDefaultsKey)
            }
            step = next
            refresh()
        }
    }

    fileprivate func skip() {
        defaults.set(true, forKey: Self.completedDefaultsKey)
        step = .finish
        refresh()
    }

    private func finish() {
        defaults.set(true, forKey: Self.completedDefaultsKey)
        window?.close()
    }
}

private enum GuideStyle {
    static let background = Color(red: 0.052, green: 0.066, blue: 0.100)
    static let card = Color(red: 0.089, green: 0.108, blue: 0.151)
    static let border = Color(red: 0.174, green: 0.210, blue: 0.280)
    static let text = Color(red: 0.946, green: 0.958, blue: 0.982)
    static let muted = Color(red: 0.595, green: 0.663, blue: 0.777)
    static let quiet = Color(red: 0.438, green: 0.523, blue: 0.663)
    static let green = Color(red: 0.380, green: 0.704, blue: 0.573)
    static let amber = Color(red: 0.807, green: 0.648, blue: 0.403)
}

private struct OnboardingView: View {
    @ObservedObject var controller: OnboardingWindowController

    private var state: OnboardingWindowController.Snapshot { controller.currentSnapshot }
    private var selectedFeatures: [OnboardingWindowController.Feature] {
        OnboardingWindowController.Feature.allCases.filter { state.state(for: $0).enabled }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                switch controller.step {
                case .welcome: welcome
                case .preferences: preferences
                case .trial: trial
                case .finish: finish
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer
        }
        .frame(width: 680, height: 592)
        .background(GuideStyle.background)
        .foregroundStyle(GuideStyle.text)
        .environment(\.colorScheme, .dark)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            if controller.step != .welcome {
                Button(action: controller.goBack) {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 11))
                        .foregroundStyle(GuideStyle.muted)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.back")
            }
        }
        .padding(.horizontal, 27)
        // The three selected trial cards need room above the fixed footer.
        .frame(height: controller.step == .trial ? 36 : 56)
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            if let icon = NSImage(contentsOfFile: (Bundle.main.resourcePath ?? "") + "/chenshou-icon.png") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .padding(.top, 18)
            }
            Text("hello")
                .font(.custom("Snell Roundhand", size: 76))
                .padding(.top, 13)
            Text("欢迎使用趁手")
                .font(.system(size: 24, weight: .medium))
                .padding(.top, 10)
            Text("AI 时代，你的 Mac 最趁手的工具箱。")
                .font(.system(size: 13))
                .foregroundStyle(GuideStyle.muted)
                .padding(.top, 15)
            Text("花一点时间，让常用操作更合你的习惯。")
                .font(.system(size: 11))
                .foregroundStyle(GuideStyle.quiet)
                .padding(.top, 11)
        }
    }

    private var preferences: some View {
        VStack(spacing: 0) {
            heading("先把操作调成你的习惯", subtitle: "首次设置一次，以后需要调整时打开“设置”。")
            VStack(spacing: 0) {
                preferenceRow(.scrollReversal, detail: "只反转外接鼠标，触控板方向保持不变。")
                Divider().overlay(GuideStyle.border)
                preferenceRow(.rightClickGesture, detail: "按住右键滑动，执行常用操作。")
                Divider().overlay(GuideStyle.border)
                preferenceRow(.keyMapping, detail: "把原来的按键改成顺手的操作。")
            }
            .background(GuideStyle.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(GuideStyle.border, lineWidth: 1))
            .padding(.top, 25)

            HStack(spacing: 9) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 15))
                Text(permissionSummary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !selectedFeatures.isEmpty, needsPermission {
                    Button("权限设置", action: controller.requestPermissions)
                        .buttonStyle(GuideSmallButton())
                        .accessibilityIdentifier("onboarding.permissions")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(GuideStyle.muted)
            .padding(.top, 23)
            Text("鼠标与手势需要辅助功能；按键映射还需要输入监控。可以稍后再设。")
                .font(.system(size: 10))
                .foregroundStyle(GuideStyle.quiet)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 9)
        }
        .padding(.horizontal, 65)
    }

    private func preferenceRow(_ feature: OnboardingWindowController.Feature, detail: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: feature.symbol)
                .font(.system(size: 15))
                .frame(width: 19)
                .foregroundStyle(GuideStyle.muted)
            VStack(alignment: .leading, spacing: 5) {
                Text(feature.title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(GuideStyle.quiet)
            }
            Spacer(minLength: 6)
            if feature != .scrollReversal {
                Button(feature == .rightClickGesture ? "配置手势" : "配置按键") {
                    controller.openSettings(for: feature)
                }
                .buttonStyle(GuideSmallButton())
                .accessibilityIdentifier("onboarding.configure.\(feature)")
            }
            Toggle(feature.title, isOn: Binding(
                get: { state.state(for: feature).enabled },
                set: { controller.setEnabled(feature, to: $0) }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.41, green: 0.66, blue: 0.98)))
            .controlSize(.small)
            .accessibilityIdentifier("onboarding.toggle.\(feature)")
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }

    private var needsPermission: Bool {
        !state.accessibilityTrusted || (selectedFeatures.contains(.keyMapping) && !state.inputMonitoringTrusted)
    }

    private var permissionSummary: String {
        if selectedFeatures.isEmpty { return "选择功能后，再按需允许系统权限" }
        if !state.accessibilityTrusted { return "所选功能需要辅助功能权限才能生效" }
        if selectedFeatures.contains(.keyMapping), !state.inputMonitoringTrusted {
            return "按键映射还需要输入监控权限"
        }
        if selectedFeatures.contains(where: { !state.state(for: $0).running }) {
            return "权限已允许，部分功能尚未运行"
        }
        return "权限已允许，所选功能正在运行"
    }

    private var trial: some View {
        VStack(spacing: 0) {
            heading(selectedFeatures.isEmpty ? "这次先保持原来的习惯" : "现在，亲手试一下",
                    subtitle: selectedFeatures.isEmpty ? "没有启用新功能，可以直接完成引导。" : "只确认这次选中的操作。请使用真实设备亲自试用。")

            if selectedFeatures.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 30))
                        .foregroundStyle(GuideStyle.quiet)
                    Text("当前没有启用便捷操作")
                        .font(.system(size: 13, weight: .medium))
                    Text("以后可随时在“设置”中开启。")
                        .font(.system(size: 11))
                        .foregroundStyle(GuideStyle.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 67)
            } else {
                VStack(spacing: 7) {
                    ForEach(selectedFeatures, id: \.self) { feature in
                        trialCard(for: feature)
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 65)
    }

    private func trialCard(for feature: OnboardingWindowController.Feature) -> some View {
        let featureState = state.state(for: feature)
        let canConfirm = featureState.enabled && featureState.running && state.hasPermission(for: feature)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: feature.symbol)
                    .frame(width: 17)
                Text(feature.title).font(.system(size: 12, weight: .medium))
                Spacer()
                statusLabel(for: feature)
            }
            if feature == .scrollReversal {
                HStack(spacing: 12) {
                    trialScrollArea(title: "外接鼠标", subtitle: "在此滚动鼠标滚轮")
                    trialScrollArea(title: "触控板", subtitle: "在此用双指滚动")
                }
            } else {
                Text(feature == .rightClickGesture
                     ? "在熟悉的应用中按住右键，按设置的方向拖动后松开。"
                     : "在熟悉的应用中按下刚设置的触发键，确认目标动作。")
                    .font(.system(size: 10))
                    .foregroundStyle(GuideStyle.muted)
            }
            Toggle("我已亲自试用，操作符合预期", isOn: Binding(
                get: { controller.triedFeatures.contains(feature) },
                set: { controller.setTried(feature, to: $0) }
            ))
            .font(.system(size: 10))
            .toggleStyle(.checkbox)
            .disabled(!canConfirm)
            .accessibilityIdentifier("onboarding.tried.\(feature)")
            if !canConfirm {
                Text(state.hasPermission(for: feature) ? "功能尚未运行；可返回设置页检查。" : "授权后才能确认试用；也可先完成引导。")
                    .font(.system(size: 10))
                    .foregroundStyle(GuideStyle.amber)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, feature == .scrollReversal ? 10 : 12)
        .background(GuideStyle.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(GuideStyle.border, lineWidth: 1))
    }

    private func trialScrollArea(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .medium))
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach([subtitle, "第一项 · 文稿", "第二项 · 图片", "第三项 · 项目", "第四项 · 笔记", "第五项 · 灵感"], id: \.self) { item in
                        Text(item)
                            .font(.system(size: 10))
                            .foregroundStyle(GuideStyle.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 26)
                            .overlay(alignment: .bottom) { GuideStyle.border.frame(height: 1) }
                    }
                }
                .padding(.horizontal, 9)
            }
            .frame(height: 76)
            .background(Color(red: 0.036, green: 0.050, blue: 0.078), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(GuideStyle.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var finish: some View {
        VStack(spacing: 0) {
            Image(systemName: selectedFeatures.contains(where: { state.state(for: $0).running })
                  ? "checkmark.circle.fill" : "clock")
                .font(.system(size: 42))
                .foregroundStyle(selectedFeatures.contains(where: { state.state(for: $0).running })
                                 ? GuideStyle.green : GuideStyle.muted)
                .padding(.top, 8)
            Text(selectedFeatures.contains(where: { state.state(for: $0).running })
                 ? "习惯设好了，日常不用再管" : "随时可以回来继续设置")
                .font(.system(size: 23, weight: .medium))
                .padding(.top, 19)
            Text("已选偏好会被记住，功能是否生效见下方状态。")
                .font(.system(size: 12))
                .foregroundStyle(GuideStyle.muted)
                .padding(.top, 13)
            VStack(spacing: 0) {
                ForEach(OnboardingWindowController.Feature.allCases, id: \.self) { feature in
                    HStack(spacing: 12) {
                        Image(systemName: feature.symbol)
                            .font(.system(size: 14))
                            .frame(width: 19)
                            .foregroundStyle(GuideStyle.muted)
                        Text(feature.title)
                            .font(.system(size: 12))
                        Spacer()
                        statusLabel(for: feature)
                    }
                    .padding(.horizontal, 17)
                    .frame(height: 44)
                    if feature != .keyMapping { Divider().overlay(GuideStyle.border) }
                }
            }
            .background(GuideStyle.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(GuideStyle.border, lineWidth: 1))
            .padding(.top, 22)
            HStack(spacing: 11) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 5) {
                    Text("以后修改：点面板里的齿轮进入设置")
                        .font(.system(size: 12, weight: .medium))
                    Text("应用内也可按 ⌘, 打开")
                        .font(.system(size: 10))
                        .foregroundStyle(GuideStyle.quiet)
                }
            }
            .foregroundStyle(GuideStyle.muted)
            .padding(.top, 29)
        }
        .padding(.horizontal, 65)
    }

    private func statusLabel(for feature: OnboardingWindowController.Feature) -> some View {
        let title = state.status(for: feature)
        let color = title == "已启用" ? GuideStyle.green : title == "未启用" ? GuideStyle.quiet : GuideStyle.amber
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title).font(.system(size: 10))
        }
        .foregroundStyle(color)
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.system(size: 24, weight: .medium))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(GuideStyle.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: controller.continueForward) {
                Text(["开始设置", "继续", "完成引导", "开始使用"][controller.step.rawValue])
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.087, green: 0.107, blue: 0.148))
                    .frame(width: 300, height: 42)
                    .background(Color(red: 0.963, green: 0.970, blue: 0.985), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.primary")
            if controller.step == .preferences || controller.step == .trial {
                Button("暂时跳过", action: controller.skip)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.skip")
            } else if controller.step == .finish {
                Button("打开设置") { controller.openSettings(for: nil) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.openSettings")
            } else {
                Text(" ")
            }
            HStack(spacing: 7) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index == controller.step.rawValue ? GuideStyle.text : GuideStyle.border)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.top, 2)
        }
        .font(.system(size: 11))
        .foregroundStyle(GuideStyle.muted)
        .frame(height: 127, alignment: .top)
    }
}

private struct GuideSmallButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10))
            .foregroundStyle(GuideStyle.text)
            .padding(.horizontal, 10)
            .frame(height: 25)
            .background(configuration.isPressed ? GuideStyle.border : Color(red: 0.157, green: 0.184, blue: 0.236),
                        in: RoundedRectangle(cornerRadius: 5))
    }
}
