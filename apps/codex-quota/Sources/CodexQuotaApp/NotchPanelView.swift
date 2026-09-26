import AppKit
import CodexQuotaCore
import CodexQuotaUI
import SwiftUI

@MainActor
final class NotchPresentation: ObservableObject {
    @Published var expanded = false
    @Published var contentVisible = false
    @Published var neckHeight: CGFloat = 32
    @Published var neckWidth: CGFloat = 340
    @Published var panelWidth: CGFloat = 750
}

struct NotchActions {
    var settings: (NSView) -> Void
    var quickTools: () -> Void
    var openTasks: () -> Void
    var scroll: () -> Void
    var gestures: () -> Void
    var mappings: () -> Void
    var sleep: () -> Void
    var reset: () -> Void
    var mode: (PanelDisplayMode) -> Void
    var resume: (String, Bool) -> TaskResumeActionResult
    var thread: (CodexDesktopThreadSnapshot) -> CodexThreadOpenActionResult
    var cli: (String, CodexCLIProcess) -> CodexCLIProcessOpenActionResult
    var archive: (TaskStatusSnapshot) -> Void
    var clear: () -> Void
}

struct NotchPanelView: View {
    @ObservedObject var model: StatusPanelModel
    @ObservedObject var presentation: NotchPresentation
    let text: AppText
    let actions: NotchActions
    let open: () -> Void
    let hover: (Bool) -> Void

    private var mainPercent: Int? {
        let data = StatusPanelQuotaData(snapshot: model.snapshot, now: model.now)
        return data.secondaryWindow?.remainingPercent ?? data.primaryWindow?.remainingPercent
    }
    var body: some View {
        ZStack(alignment: .top) {
            NotchOutline(neckWidth: presentation.neckWidth, neckHeight: presentation.neckHeight, expanded: presentation.expanded).fill(.black)
            if presentation.expanded {
                VStack(spacing: 0) {
                    Color.clear.frame(height: presentation.neckHeight).contentShape(Rectangle()).onTapGesture(perform: open)
                    DailyPanelContent(model: model, text: text, actions: actions)
                        .opacity(presentation.contentVisible ? 1 : 0)
                        .offset(y: presentation.contentVisible ? 0 : -10)
                        .allowsHitTesting(presentation.contentVisible)
                }
            } else {
                HStack {
                    Button(action: open) {
                        HStack(spacing: 7) {
                            ChenshouMark().frame(width: 18, height: 18)
                            if model.sleepState == .on { Circle().fill(.orange).frame(width: 5, height: 5) }
                        }.frame(width: 46, height: presentation.neckHeight + 3)
                    }.accessibilityLabel("展开趁手灵动岛")
                    Spacer(minLength: 0)
                    Button(action: open) {
                        HStack(spacing: 4) {
                            Text(model.selectedQuotaProvider == .claude ? "Cl" : "Cx").font(.system(size: 9))
                            Text(mainPercent.map { "\($0)%" } ?? "—").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        }.frame(width: 62, height: presentation.neckHeight + 3)
                    }.accessibilityLabel("\(model.selectedQuotaProvider.title) 额度与任务")
                }.padding(.horizontal, 8).buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .clipShape(NotchOutline(neckWidth: presentation.neckWidth, neckHeight: presentation.neckHeight, expanded: presentation.expanded))
        .onHover(perform: hover)
    }
}

/// The same daily surface is used by the island and menu bar popover.
struct DailyPanelContent: View {
    @ObservedObject var model: StatusPanelModel
    let text: AppText
    let actions: NotchActions
    private var cn: Bool { text.language == .simplifiedChinese }
    private var accent: Color { model.selectedQuotaProvider == .claude ? Color(red: 0.85, green: 0.49, blue: 0.36) : Color(red: 0.14, green: 0.55, blue: 1) }
    private var data: StatusPanelQuotaData { StatusPanelQuotaData(snapshot: model.snapshot, now: model.now) }
    private var windows: [StatusPanelQuotaWindow] { [data.primaryWindow, data.secondaryWindow].compactMap { $0 } }
    private var mainWindow: StatusPanelQuotaWindow? { windows.first { StatusPanelQuotaWindowKind(windowDuration: $0.windowDuration) == .weekly } ?? windows.first }
    private var forecast: CodexResetEvent? {
        guard model.selectedQuotaProvider == .codex, model.showsResetForecast else { return nil }
        return model.resetCalendar?.feed.upcomingAnnouncement(now: model.now)
    }
    static func contentHeight(model: StatusPanelModel) -> CGFloat {
        max(390, NotchTaskList.contentHeight(model: model) + 40) + 78
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                ChenshouMark().frame(width: 22, height: 22)
                Text("趁手").font(.system(size: 13, weight: .medium))
                if model.sleepState == .on {
                    Button(action: actions.sleep) { Label(cn ? "正在防睡眠" : "Awake", systemImage: "moon") }
                        .font(.system(size: 11)).foregroundStyle(.orange).buttonStyle(.plain)
                        .help(model.sleepDetail)
                }
                Spacer()
                NotchSettingsButton(action: actions.settings).frame(width: 66, height: 30)
            }.frame(height: 56)
            HStack(alignment: .top, spacing: 24) {
                quota.frame(width: 198)
                Rectangle().fill(.white.opacity(0.13)).frame(width: 1)
                VStack(spacing: 0) {
                    if NotchTaskList.totalCount(model: model) > 0 {
                        NotchTaskList(model: model, text: text, onResumeSession: actions.resume, onOpenCodexThread: actions.thread,
                                      onOpenCLIProcess: actions.cli, onArchiveTask: actions.archive, onClearCompleted: actions.clear)
                    } else {
                        VStack(spacing: 12) {
                            Text(cn ? "Codex 任务" : "Codex tasks").frame(maxWidth: .infinity, alignment: .leading)
                            Spacer()
                            Image(systemName: "checkmark.circle").font(.system(size: 28)).foregroundStyle(.secondary)
                            Text(cn ? "当前没有任务" : "No current tasks").foregroundStyle(.secondary)
                            Spacer()
                        }.font(.system(size: 13))
                    }
                    Spacer(minLength: 0)
                    HStack {
                        Text(cn ? "桌面任务与终端会话" : "Desktop and terminal sessions").foregroundStyle(.white.opacity(0.45))
                        Spacer()
                        Button(action: actions.openTasks) { Label(cn ? "打开 Codex" : "Open Codex", systemImage: "arrow.up.right") }
                            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
                    }.font(.system(size: 11)).frame(height: 36)
                }.frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(height: Self.contentHeight(model: model) - 78)
            Color.clear.frame(height: 22)
        }
        .padding(.horizontal, 28)
        .background(.black)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
    private var quota: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(cn ? "额度账户" : "Quota account", selection: Binding(get: { model.selectedQuotaProvider }, set: { model.selectQuotaProvider($0) })) {
                ForEach(QuotaProvider.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Text(cn ? "剩余额度" : "Remaining quota").foregroundStyle(.white.opacity(0.65))
                Spacer()
                if let plan = data.planBadgeName ?? data.planName {
                    Text(plan).font(.system(size: 10)).padding(.horizontal, 5).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.25), lineWidth: 1))
                }
            }.font(.system(size: 11))
            HStack {
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 6)
                    if let window = mainWindow {
                        Circle().trim(from: 0, to: CGFloat(window.remainingPercent) / 100)
                            .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack(spacing: 4) {
                            Text("\(window.remainingPercent)%").font(.system(size: 25, weight: .semibold)).monospacedDigit()
                            Text(windowLabel(window)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                        }
                    } else { Text("—").font(.system(size: 26)).foregroundStyle(.secondary) }
                }.frame(width: 92, height: 92).padding(4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(model.selectedQuotaProvider.title) \(mainWindow.map { windowLabel($0) + String($0.remainingPercent) + "%" } ?? "暂无数据")")
                Spacer()
            }
            ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(windowLabel(window)).foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        Text("\(window.remainingPercent)%").fontWeight(.medium).monospacedDigit()
                    }.font(.system(size: 12))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12))
                            Capsule().fill(accent).frame(width: g.size.width * CGFloat(window.remainingPercent) / 100)
                        }
                    }.frame(height: 4)
                    if let reset = window.resetsAt {
                        Text(ResetCountdownFormatter.compactString(resetsAt: reset, now: model.now, language: text.language) + (cn ? "后重置" : " to reset") + " · " + shortDate(reset))
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                            .resetTimeHelp(resetTimeHelp(for: reset))
                    } else {
                        Text(cn ? "重置时间暂不可用" : "Reset time unavailable").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            if !model.quotaStatus.isEmpty {
                Text(model.quotaStatus).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button { model.onRefreshQuota?() } label: { Label(cn ? "刷新" : "Refresh", systemImage: "arrow.clockwise") }.buttonStyle(.plain)
                Spacer()
                if let date = data.observedAt { Text(shortDate(date)).font(.system(size: 10)).help(cn ? "最近成功读取时间" : "Last successful read") }
            }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            if model.selectedQuotaProvider == .codex, model.showsResetForecast {
                Button(action: actions.reset) {
                    Label(forecast.map { $0.detailText(now: model.now, language: text.language) } ?? (cn ? "重置日历" : "Reset calendar"), systemImage: "calendar").lineLimit(2).multilineTextAlignment(.leading)
                }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(accent)
            }
        }
    }
    private func windowLabel(_ window: StatusPanelQuotaWindow) -> String {
        switch StatusPanelQuotaWindowKind(windowDuration: window.windowDuration) {
        case .fiveHour: cn ? "5 小时剩余" : "5h left"
        case .weekly: cn ? "本周剩余" : "Week left"
        case .generic: cn ? "额度剩余" : "Remaining"
        }
    }
    private func resetTimeHelp(for date: Date) -> ResetTimeHelp {
        let formatter = DateFormatter()
        formatter.locale = text.language.locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = text.language == .simplifiedChinese ? "yyyy年M月d日 HH:mm" : "MMM d, yyyy HH:mm"
        let value = formatter.string(from: date)
        formatter.dateFormat = "ZZZZ"
        let zoneName = TimeZone.current.identifier == "Asia/Shanghai"
            ? (text.language == .simplifiedChinese ? "北京时间" : "Beijing time")
            : (text.language == .simplifiedChinese ? "本地时间" : "Local time")
        return ResetTimeHelp(
            title: text.language == .simplifiedChinese ? "重置时间" : "Reset time",
            date: value, timeZone: "\(zoneName) · \(formatter.string(from: date))"
        )
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = text.language.locale; f.dateFormat = "M/d HH:mm"
        return f.string(from: date)
    }
}

private struct ChenshouMark: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "chenshou-mark", withExtension: "png"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
        } else { Image(systemName: "circle.lefthalf.filled").resizable().scaledToFit() }
    }
}

struct NotchOutline: Shape {
    var neckWidth: CGFloat
    var neckHeight: CGFloat
    var expanded: Bool
    func path(in rect: CGRect) -> Path {
        if !expanded || rect.width < neckWidth + 40 || rect.height < neckHeight + 40 {
            return Path(roundedRect: rect, cornerRadius: 12)
        }
        let w = rect.width, h = rect.height, top = min(neckHeight, h), r: CGFloat = 20
        let l = max(r, (w - neckWidth) / 2), right = w - l
        var p = Path()
        p.move(to: CGPoint(x: l-r, y: 0))
        p.addQuadCurve(to: CGPoint(x: l, y: min(r, top)), control: CGPoint(x: l, y: 0))
        p.addLine(to: CGPoint(x: l, y: max(r, top-r)))
        p.addQuadCurve(to: CGPoint(x: l-r, y: top), control: CGPoint(x: l, y: top))
        p.addLine(to: CGPoint(x: r, y: top))
        p.addQuadCurve(to: CGPoint(x: 0, y: top+r), control: CGPoint(x: 0, y: top))
        p.addLine(to: CGPoint(x: 0, y: h-r))
        p.addQuadCurve(to: CGPoint(x: r, y: h), control: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: w-r, y: h))
        p.addQuadCurve(to: CGPoint(x: w, y: h-r), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: w, y: top+r))
        p.addQuadCurve(to: CGPoint(x: w-r, y: top), control: CGPoint(x: w, y: top))
        p.addLine(to: CGPoint(x: right+r, y: top))
        p.addQuadCurve(to: CGPoint(x: right, y: max(r, top-r)), control: CGPoint(x: right, y: top))
        p.addLine(to: CGPoint(x: right, y: min(r, top)))
        p.addQuadCurve(to: CGPoint(x: right+r, y: 0), control: CGPoint(x: right, y: 0))
        p.closeSubpath()
        return p
    }
}

struct NotchButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.white)
            .background(primary ? Color(red: 0.08, green: 0.48, blue: 1) : .white.opacity(configuration.isPressed ? 0.14 : 0.075), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.12), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct NotchSettingsButton: NSViewRepresentable {
    let action: (NSView) -> Void
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "设置", image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置")!, target: context.coordinator, action: #selector(Coordinator.click(_:)))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.cornerRadius = 9
        button.layer?.borderWidth = 0
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        button.setAccessibilityLabel("设置")
        button.toolTip = "设置"
        return button
    }
    func updateNSView(_ view: NSButton, context: Context) { context.coordinator.action = action }
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    class Coordinator: NSObject {
        var action: (NSView) -> Void
        init(_ action: @escaping (NSView) -> Void) { self.action = action }
        @objc func click(_ sender: NSButton) { action(sender) }
    }
}
