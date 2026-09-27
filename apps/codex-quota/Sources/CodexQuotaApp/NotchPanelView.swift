import AppKit
import CodexQuotaCore
import CodexQuotaUI
import SwiftUI

@MainActor
final class NotchPresentation: ObservableObject {
    /// Drives the island's size; changed inside a spring so the outline grows out of the notch.
    @Published var expanded = false
    /// The daily panel is built once and then kept, hidden while the island is collapsed.
    @Published var contentMounted = false
    @Published var contentVisible = false
    @Published var neckHeight: CGFloat = 32
    @Published var neckWidth: CGFloat = 340
    /// Width of the camera housing the collapsed island's content must stay clear of.
    @Published var notchWidth: CGFloat = 180
    @Published var panelWidth: CGFloat = 600
    /// Open height measured from the top of the screen.
    @Published var panelHeight: CGFloat = 500
    /// The collapsed island is exactly as tall as the menu bar.
    var collapsedHeight: CGFloat { neckHeight }
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
    var claude: (ClaudeCodeSession) -> Void = { _ in }
}

struct NotchPanelView: View {
    @ObservedObject var model: StatusPanelModel
    @ObservedObject var presentation: NotchPresentation
    let text: AppText
    let actions: NotchActions
    let open: () -> Void
    let hover: (Bool) -> Void

    /// The collapsed island shows the 5-hour window when there is one, otherwise the weekly one.
    private var collapsedWindow: StatusPanelQuotaWindow? {
        let data = StatusPanelQuotaData(snapshot: model.snapshot, now: model.now)
        let windows = [data.primaryWindow, data.secondaryWindow].compactMap { $0 }
        return windows.first { StatusPanelQuotaWindowKind(windowDuration: $0.windowDuration) == .fiveHour }
            ?? data.outerRingWindow
    }
    private var collapsedWindowTitle: String {
        guard let window = collapsedWindow else { return "暂无额度" }
        let name = switch StatusPanelQuotaWindowKind(windowDuration: window.windowDuration) {
        case .fiveHour: "5小时剩余"
        case .weekly: "本周剩余"
        case .generic: "额度剩余"
        }
        return "\(model.selectedQuotaProvider.title) \(name) \(window.remainingPercent)%"
    }
    var body: some View {
        let expanded = presentation.expanded
        let outline = IslandShape(neckWidth: presentation.neckWidth, neckHeight: presentation.neckHeight)
        // The window is already at its open size while this frame animates, so the outline and
        // the revealed content move at display rate instead of following window resizes.
        ZStack(alignment: .top) {
            outline.fill(.black)
            if presentation.contentMounted {
                VStack(spacing: 0) {
                    Color.clear.frame(height: presentation.neckHeight).contentShape(Rectangle()).onTapGesture(perform: open)
                    DailyPanelContent(model: model, text: text, actions: actions)
                }
                .frame(width: presentation.panelWidth, height: presentation.panelHeight, alignment: .top)
                .opacity(presentation.contentVisible ? 1 : 0)
                .offset(y: presentation.contentVisible ? 0 : -8)
                .allowsHitTesting(presentation.contentVisible)
                .accessibilityHidden(!presentation.contentVisible)
            }
            // Each side only uses the visible strip beside the notch; nothing is drawn under the camera housing.
            let side = max(0, (presentation.neckWidth - presentation.notchWidth) / 2)
            HStack(spacing: 0) {
                Button(action: open) {
                    HStack(spacing: 7) {
                        ChenshouMark().frame(width: 18, height: 18)
                        if model.sleepState == .on { Circle().fill(.orange).frame(width: 5, height: 5) }
                    }.frame(width: side, height: presentation.collapsedHeight)
                }.accessibilityLabel("展开趁手灵动岛")
                Spacer(minLength: 0)
                Button(action: open) {
                    HStack(spacing: 4) {
                        ProviderMark(provider: model.selectedQuotaProvider)
                        Text(collapsedWindow.map { "\($0.remainingPercent)%" } ?? "—").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                            .minimumScaleFactor(0.8).lineLimit(1)
                    }
                    // Keep at least 3pt between the content and the notch; "100%" shrinks slightly if needed.
                    .frame(maxWidth: max(0, side - 11), alignment: .trailing)
                    .padding(.trailing, 8)
                    .frame(width: side, height: presentation.collapsedHeight, alignment: .trailing)
                }
                .buttonHelp(collapsedWindowTitle)
                .accessibilityLabel(collapsedWindowTitle + "，展开额度与任务")
            }
            .buttonStyle(.plain)
            .frame(width: presentation.neckWidth, height: presentation.collapsedHeight)
            .opacity(expanded ? 0 : 1)
            // Leaves quickly on open and returns only as the outline closes around it.
            .animation(expanded ? .easeOut(duration: 0.1) : .easeInOut(duration: 0.16).delay(0.16), value: expanded)
            .allowsHitTesting(!expanded)
        }
        .frame(width: expanded ? presentation.panelWidth : presentation.neckWidth,
               height: expanded ? presentation.panelHeight : presentation.collapsedHeight, alignment: .top)
        .clipShape(outline)
        .contentShape(outline)
        .onHover(perform: hover)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

/// The island's open panel: quota on the left, tasks on the right, as tall as the taller column.
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
    private static let headerHeight: CGFloat = 40
    private static let bottomPadding: CGFloat = 16
    private static let quotaWidth: CGFloat = 196
    private static let lineHeight: CGFloat = 15

    /// Height below the neck. The island is as tall as its content, with no fixed minimum.
    static func contentHeight(model: StatusPanelModel) -> CGFloat {
        headerHeight + bodyHeight(model: model) + bottomPadding
    }
    private static func bodyHeight(model: StatusPanelModel) -> CGFloat {
        max(quotaHeight(model: model), NotchTaskList.columnHeight(model: model))
    }
    /// Mirrors the fixed row heights in `quota`, so the island can be sized before it opens.
    private static func quotaHeight(model: StatusPanelModel) -> CGFloat {
        let data = StatusPanelQuotaData(snapshot: model.snapshot, now: model.now)
        var lines = switch StatusPanelResetSummary(windows: [data.primaryWindow, data.secondaryWindow].compactMap { $0 }) {
        case .allUnknown: 1
        case let .lines(lines): lines.count
        }
        if !model.quotaStatus.isEmpty { lines += 1 }
        var height = 16 + 10 + QuotaRings.size + 8 + 16
        if lines > 0 { height += 12 + CGFloat(lines) * lineHeight + CGFloat(lines - 1) * 4 }
        if model.selectedQuotaProvider == .codex, model.showsResetForecast { height += 8 + lineHeight }
        return height
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ChenshouMark().frame(width: 18, height: 18)
                Text("趁手").font(.system(size: 13, weight: .medium))
                if model.sleepState == .on {
                    Button(action: actions.sleep) { Label(cn ? "正在防睡眠" : "Awake", systemImage: "moon") }
                        .font(.system(size: 11)).foregroundStyle(.orange).buttonStyle(.plain)
                        .help(model.sleepDetail)
                }
                Spacer()
                Picker(cn ? "额度账户" : "Quota account", selection: Binding(get: { model.selectedQuotaProvider }, set: { model.selectQuotaProvider($0) })) {
                    ForEach(QuotaProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 128)
                NotchSettingsButton(action: actions.settings).frame(width: 60, height: 26).padding(.leading, 8)
            }.frame(height: Self.headerHeight)
            HStack(alignment: .top, spacing: 14) {
                quota.frame(width: Self.quotaWidth, alignment: .topLeading)
                Rectangle().fill(.white.opacity(0.13)).frame(width: 1)
                NotchTaskList(model: model, text: text, onResumeSession: actions.resume, onOpenCodexThread: actions.thread,
                              onOpenCLIProcess: actions.cli, onArchiveTask: actions.archive, onClearCompleted: actions.clear,
                              onOpenClaudeSession: actions.claude, onOpenTasks: actions.openTasks)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(height: Self.bodyHeight(model: model), alignment: .top)
            Color.clear.frame(height: Self.bottomPadding)
        }
        .padding(.horizontal, 20)
        .background(.black)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
    /// Every row has a fixed height; `quotaHeight` depends on it.
    private var quota: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(cn ? "剩余额度" : "Remaining quota").foregroundStyle(.white.opacity(0.65))
                Spacer()
                if let plan = data.planBadgeName ?? data.planName {
                    Text(plan).font(.system(size: 10)).padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.25), lineWidth: 1))
                }
            }.font(.system(size: 11)).frame(height: 16)
            QuotaRings(outer: data.outerRingWindow, inner: data.innerRingWindow,
                       outerColor: accent, innerColor: innerAccent, label: windowLabel)
                .opacity(model.quotaStale ? 0.45 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(model.selectedQuotaProvider.title) " + (windows.isEmpty ? "暂无数据"
                    : [data.outerRingWindow, data.innerRingWindow].compactMap { $0 }
                        .map { windowLabel($0) + " \($0.remainingPercent)%" }.joined(separator: "，")))
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            let resets = StatusPanelResetSummary(windows: windows)
            if resets != .lines([]) || !model.quotaStatus.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    switch resets {
                    case .allUnknown:
                        Text(cn ? "尚未获取重置时间" : "Reset time not received yet")
                            .fontWeight(.medium).foregroundStyle(.white.opacity(0.65)).frame(height: Self.lineHeight)
                    case .lines(let lines):
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in resetLine(line).frame(height: Self.lineHeight) }
                    }
                    if !model.quotaStatus.isEmpty {
                        Text(model.quotaStatus).foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1).truncationMode(.tail)
                            .frame(height: Self.lineHeight)
                            .buttonHelp(model.quotaDetail)
                    }
                }.font(.system(size: 11)).padding(.top, 12)
            }
            HStack {
                Button { model.onRefreshQuota?() } label: { Label(cn ? "刷新" : "Refresh", systemImage: "arrow.clockwise") }.buttonStyle(.plain)
                Spacer()
                if let date = data.observedAt { Text(shortDate(date)).font(.system(size: 10)).help(cn ? "最近成功读取时间" : "Last successful read") }
            }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).frame(height: 16).padding(.top, 8)
            if model.selectedQuotaProvider == .codex, model.showsResetForecast {
                let detail = forecast.map { $0.detailText(now: model.now, language: text.language) }
                Button(action: actions.reset) {
                    // The forecast's first two lines on one line; the full record is in the help.
                    Label(detail.map { $0.split(separator: "\n").prefix(2).joined(separator: " · ") } ?? (cn ? "重置日历" : "Reset calendar"),
                          systemImage: "calendar").lineLimit(1).truncationMode(.tail)
                }
                .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(accent)
                .frame(height: Self.lineHeight).padding(.top, 8)
                .buttonHelp(detail ?? (cn ? "打开重置日历" : "Open reset calendar"))
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
                .frame(width: cn ? 32 : 38, alignment: .leading)
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
    static let size: CGFloat = 108
    private let lineWidth: CGFloat = 6
    private let gap: CGFloat = 4

    var body: some View {
        ZStack {
            ring(outer, color: outerColor, diameter: Self.size)
            if inner != nil { ring(inner, color: innerColor, diameter: Self.size - 2 * (lineWidth + gap)) }
            VStack(spacing: 0) {
                if let outer {
                    let dual = inner != nil
                    Text("\(outer.remainingPercent)%").font(.system(size: dual ? 19 : 22, weight: .semibold)).monospacedDigit()
                    Text(label(outer)).font(.system(size: dual ? 9 : 10)).foregroundStyle(outerColor).padding(.top, dual ? 1 : 3)
                    if let inner {
                        Text("\(inner.remainingPercent)%").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(innerColor).padding(.top, 3)
                        Text(label(inner)).font(.system(size: 9)).foregroundStyle(innerColor).padding(.top, 1)
                    }
                } else {
                    Text("—").font(.system(size: 22)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: Self.size, height: Self.size)
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

/// The provider's own menu bar glyph, read from its installed app so 趁手 never ships another
/// company's artwork. Without the app it falls back to a short text tag.
private struct ProviderMark: View {
    let provider: QuotaProvider
    private let size: CGFloat = 13

    var body: some View {
        if let glyph = ProviderGlyph.glyph(for: provider) {
            // Scale so the visible glyph, not its padded canvas, is `size` points.
            Image(nsImage: glyph.image).renderingMode(.template).resizable().interpolation(.high).scaledToFit()
                .frame(width: size / glyph.fill, height: size / glyph.fill)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Text(provider == .claude ? "Cl" : "Cx").font(.system(size: 9))
        }
    }
}

@MainActor
private enum ProviderGlyph {
    private static var cache: [QuotaProvider: (image: NSImage, fill: CGFloat)?] = [:]

    static func glyph(for provider: QuotaProvider) -> (image: NSImage, fill: CGFloat)? {
        if let cached = cache[provider] { return cached }
        let glyph = load(provider)
        cache[provider] = glyph
        return glyph
    }

    private static func load(_ provider: QuotaProvider) -> (image: NSImage, fill: CGFloat)? {
        let (bundleIDs, name) = switch provider {
        case .codex: (["com.openai.codex", "com.openai.chat"], "chatgptTemplate")
        case .claude: (["com.anthropic.claudefordesktop"], "TrayIconTemplate")
        }
        for id in bundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
                  let image = Bundle(url: url)?.image(forResource: name) else { continue }
            image.isTemplate = true
            return (image, fill(of: image))
        }
        return nil
    }

    /// Share of the canvas the glyph occupies; tray icons carry different amounts of padding.
    private static func fill(of image: NSImage) -> CGFloat {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 1 }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 1 }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height { for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 24 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= minX, maxY >= minY else { return 1 }
        return CGFloat(max(maxX - minX + 1, maxY - minY + 1)) / CGFloat(max(width, height))
    }
}

private struct ChenshouMark: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "chenshou-mark", withExtension: "png"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
        } else { Image(systemName: "circle.lefthalf.filled").resizable().scaledToFit() }
    }
}

/// One outline for every size, so opening is a continuous grow instead of a swap between shapes.
/// A neck fills the menu bar around the notch and a body hangs below the menu bar; the top edge is
/// always flush with the screen and the body's top corners are square, so the island stays attached.
/// At the neck's width it is simply the collapsed island: square top, rounded bottom.
struct IslandShape: Shape {
    var neckWidth: CGFloat
    var neckHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let side = max(0, (w - neckWidth) / 2)
        let bottom = min(10 + 10 * min(1, side / 24), w / 2, h / 2)
        // While the island is still short, the body's top rises with its bottom corners.
        let join = max(0, min(neckHeight, h - bottom))
        let flare = min(12, side, join / 2)
        let shoulder = min(20, side, join - flare)
        let left = side, right = w - side
        var p = Path()
        p.move(to: CGPoint(x: left - shoulder, y: 0))
        p.addLine(to: CGPoint(x: right + shoulder, y: 0))
        if side > 0 {
            p.addQuadCurve(to: CGPoint(x: right, y: shoulder), control: CGPoint(x: right, y: 0))
            p.addLine(to: CGPoint(x: right, y: join - flare))
            p.addQuadCurve(to: CGPoint(x: right + flare, y: join), control: CGPoint(x: right, y: join))
            p.addLine(to: CGPoint(x: w, y: join))
        }
        p.addLine(to: CGPoint(x: w, y: h - bottom))
        p.addQuadCurve(to: CGPoint(x: w - bottom, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: bottom, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - bottom), control: CGPoint(x: 0, y: h))
        if side > 0 {
            p.addLine(to: CGPoint(x: 0, y: join))
            p.addLine(to: CGPoint(x: left - flare, y: join))
            p.addQuadCurve(to: CGPoint(x: left, y: join - flare), control: CGPoint(x: left, y: join))
            p.addLine(to: CGPoint(x: left, y: shoulder))
            p.addQuadCurve(to: CGPoint(x: left - shoulder, y: 0), control: CGPoint(x: left, y: 0))
        }
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
