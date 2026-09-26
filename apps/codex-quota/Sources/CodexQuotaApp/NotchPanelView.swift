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
    /// Outer ring and its text use the provider colour; the inner 5-hour ring uses a light tint of it.
    private var accent: Color { model.selectedQuotaProvider == .claude ? Color(red: 0.85, green: 0.49, blue: 0.36) : Color(red: 0.14, green: 0.55, blue: 1) }
    private var innerAccent: Color { model.selectedQuotaProvider == .claude ? Color(red: 0.953, green: 0.749, blue: 0.663) : Color(red: 0.616, green: 0.796, blue: 1) }
    private var data: StatusPanelQuotaData { StatusPanelQuotaData(snapshot: model.snapshot, now: model.now) }
    private var windows: [StatusPanelQuotaWindow] { [data.primaryWindow, data.secondaryWindow].compactMap { $0 } }
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
                QuotaRings(outer: data.outerRingWindow, inner: data.innerRingWindow,
                           outerColor: accent, innerColor: innerAccent, label: windowLabel)
                    .opacity(model.quotaStale ? 0.45 : 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(model.selectedQuotaProvider.title) " + (windows.isEmpty ? "暂无数据"
                        : [data.outerRingWindow, data.innerRingWindow].compactMap { $0 }
                            .map { windowLabel($0) + " \($0.remainingPercent)%" }.joined(separator: "，")))
                Spacer()
            }
            let resets = StatusPanelResetSummary(windows: windows)
            if resets != .lines([]) || !model.quotaStatus.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    switch resets {
                    case .allUnknown:
                        Text(cn ? "尚未获取重置时间" : "Reset time not received yet")
                            .fontWeight(.medium).foregroundStyle(.white.opacity(0.65))
                    case .lines(let lines):
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in resetLine(line) }
                    }
                    if !model.quotaStatus.isEmpty {
                        Text(model.quotaStatus).foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                            .buttonHelp(model.quotaDetail)
                            .padding(.top, resets == .allUnknown ? -3 : 0)
                    }
                }.font(.system(size: 11))
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
        case .fiveHour: cn ? "5小时剩余" : "5h left"
        case .weekly: cn ? "本周剩余" : "Week left"
        case .generic: cn ? "额度剩余" : "Remaining"
        }
    }

    /// One reset line per window; the period name uses the colour of its ring.
    @ViewBuilder private func resetLine(_ line: StatusPanelResetSummary.Line) -> some View {
        switch line {
        case let .resets(kind, date):
            // Panel countdowns keep two units (days + hours, or hours + minutes).
            resetRow(kind, (ResetCountdownFormatter.panelCountdownValue(resetsAt: date, now: model.now, language: text.language) ?? "--")
                + (cn ? "后重置" : " to reset") + " · " + shortDate(date))
                .resetTimeHelp(resetTimeHelp(for: date))
        case let .unknown(kind):
            resetRow(kind, cn ? "尚未获取重置时间" : "Reset time not received yet")
        }
    }

    private func resetRow(_ kind: StatusPanelQuotaWindowKind, _ value: String) -> some View {
        let inner = data.innerRingWindow.map { StatusPanelQuotaWindowKind(windowDuration: $0.windowDuration) == kind } ?? false
        let period = switch kind {
        case .fiveHour: cn ? "5小时" : "5h"
        case .weekly: cn ? "本周" : "Week"
        case .generic: cn ? "额度" : "Quota"
        }
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(period).fontWeight(.semibold).foregroundStyle(inner ? innerAccent : accent)
                .frame(width: cn ? 36 : 40, alignment: .leading)
            Text(value).foregroundStyle(.white.opacity(0.55)).monospacedDigit().lineLimit(1)
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

/// Outer ring: weekly window. Inner ring: 5-hour window, only when both exist.
/// Each number and label uses the colour of its ring; the weekly number stays white as the main reading.
private struct QuotaRings: View {
    let outer: StatusPanelQuotaWindow?
    let inner: StatusPanelQuotaWindow?
    let outerColor: Color
    let innerColor: Color
    let label: (StatusPanelQuotaWindow) -> String
    private let size: CGFloat = 136
    private let lineWidth: CGFloat = 7
    private let gap: CGFloat = 4

    var body: some View {
        ZStack {
            ring(outer, color: outerColor, diameter: size)
            if inner != nil { ring(inner, color: innerColor, diameter: size - 2 * (lineWidth + gap)) }
            VStack(spacing: 0) {
                if let outer {
                    Text("\(outer.remainingPercent)%").font(.system(size: 25, weight: .semibold)).monospacedDigit()
                    Text(label(outer)).font(.system(size: 10)).foregroundStyle(outerColor).padding(.top, 4)
                    if let inner {
                        Text("\(inner.remainingPercent)%").font(.system(size: 16, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(innerColor).padding(.top, 7)
                        Text(label(inner)).font(.system(size: 10)).foregroundStyle(innerColor).padding(.top, 4)
                    }
                } else {
                    Text("—").font(.system(size: 26)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func ring(_ window: StatusPanelQuotaWindow?, color: Color, diameter: CGFloat) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.11), lineWidth: lineWidth)
            if let window {
                Circle().trim(from: 0, to: CGFloat(window.remainingPercent) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        // Strokes straddle the path; inset so the ring's outer edge matches the diameter.
        .frame(width: diameter - lineWidth, height: diameter - lineWidth)
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
