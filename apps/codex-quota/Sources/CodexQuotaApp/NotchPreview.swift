import AppKit
import CodexQuotaCore
import SwiftUI

/// Explicit development fixture. Never starts input hooks, network polling, or real task cleanup.
@MainActor
final class NotchPreview {
    let model = StatusPanelModel(defaults: UserDefaults(suiteName: "local.openclaw.codexquota.notch-preview")!)
    private var controller: NotchPanelController!
    private let date: Date
    private let claudeUsage = ClaudeUsageController()

    init(state: String) {
        // Claude states reuse the confirmed mock-up's moment: 2026-09-25 17:31 Beijing time.
        date = state == "claude-real" ? Date()
            : ISO8601DateFormatter().date(from: state.hasPrefix("claude") ? "2026-09-25T09:31:00Z" : "2026-09-22T13:01:00Z")!
        model.displayMode = .island
        model.selectQuotaProvider(.codex)
        model.updateCodexStatus("")
        model.updateQuickTools(scroll: true, gestures: true, mappingCount: 3, mappingEnabled: true)
        if state != "missing" {
            model.update(snapshot: QuotaSnapshot(remainingPercent: 36, observedAt: date,
                resetsAt: date.addingTimeInterval(5 * 86400), windowDuration: 7 * 86400,
                planName: "Pro", planBadgeName: state == "empty" ? "Pro 5X" : "Pro 20X",
                secondaryWindow: state == "dual" ? QuotaWindow(usedPercent: 18, resetsAt: date.addingTimeInterval(2 * 3600), windowDuration: 5 * 3600) : nil))
        }
        let count = state == "empty" || state == "missing" ? 0 : (state == "many" ? 10 : 6)
        let titles = ["整理项目文档", "修复同步异常", "检查更新链路", "优化快捷键规则", "校验图标资源", "整理发布说明", "检查网络状态", "更新测试资料", "整理开发笔记", "检查运行结果"]
        let tasks = (0..<count).map { index in
            TaskStatusSnapshot(id: "preview-\(index)", startedAt: date.addingTimeInterval(-300), sessionUUID: nil, mode: nil,
                taskName: titles[index], isBackgroundTask: false, status: state != "all-completed" && index < 3 ? .running : .done,
                exitCode: index < 3 ? nil : 0, lastMessage: nil, endedAt: index < 3 ? nil : date)
        }
        model.update(tasks: tasks, desktopThreads: [], desktopThreadGroups: [], cliProcesses: [:], hasCompletedTasks: count > 3)
        if state == "tree" {
            let rootID = "00000000-0000-0000-0000-000000000001"
            let samples = [
                CodexDesktopThreadSnapshot(id: rootID, title: "主任务 · 点左侧展开", source: .user, startedAt: date, lastActiveAt: date, status: .unknown),
                CodexDesktopThreadSnapshot(id: "00000000-0000-0000-0000-000000000002", parentThreadID: rootID, title: "子任务 · 运行中", source: .subagent, startedAt: date, lastActiveAt: date, status: .running),
                CodexDesktopThreadSnapshot(id: "00000000-0000-0000-0000-000000000003", title: "任务状态未知", source: .user, startedAt: date, lastActiveAt: date, status: .unknown)
            ]
            model.update(tasks: [], desktopThreads: samples,
                desktopThreadGroups: CodexDesktopThreadTree.groups(candidates: samples, now: date),
                cliProcesses: ["preview-cli": CodexCLIProcess(pid: 123, tty: "ttys000")], hasCompletedTasks: false)
        }
        if count > 0 {
            let json = """
            {"schemaVersion":1,"timezone":"Asia/Shanghai","checkedAt":"2026-09-22T13:00:00Z","historyFrom":"2026-01-01T00:00:00Z","count":1,"events":[{"id":"preview-reset","type":"direct_reset","label":"全员重置","status":"announced","title":"额度重置预告","scope":"示例数据","createdAt":"2026-09-22T12:00:00Z","updatedAt":"2026-09-22T12:00:00Z","schedule":{"precision":"exact","from":"2026-09-22T18:00:00Z","through":"2026-09-22T18:00:00Z","label":"9/23 02:00"},"posts":[],"url":"https://aihot.news/codex-reset"}]}
            """
            if let feed = try? CodexResetFeed.decode(Data(json.utf8)) {
                model.update(resetCalendar: CodexResetCache(feed: feed, etag: nil, receivedAt: date))
                model.update(showsResetForecast: true)
            }
        }
        if state.hasPrefix("claude") { applyClaudeFixture(state) }
        model.tick(at: date)
        let actions = NotchActions(settings: { _ in }, quickTools: {}, openTasks: {}, scroll: {}, gestures: {}, mappings: {}, sleep: {}, reset: {},
            mode: { [weak self] mode in self?.model.displayMode = mode },
            resume: { _, _ in .unavailable }, thread: { _ in .unavailable }, cli: { _, _ in .unavailable }, archive: { _ in },
            clear: { [weak self] in
                guard let self else { return }
                self.model.update(tasks: self.model.tasks.filter { !$0.status.isClearable }, desktopThreads: [], desktopThreadGroups: [], cliProcesses: [:], hasCompletedTasks: false)
            })
        controller = NotchPanelController(model: model, text: AppText(language: .simplifiedChinese), actions: actions)
    }
    /// Mirrors states ①–③ of work/claude-quota-review-20260925/dual-ring-states.png.
    private func applyClaudeFixture(_ state: String) {
        let desktop = state == "claude-desktop" || state == "claude-stale"
        let week = QuotaWindow(usedPercent: 3, resetsAt: desktop ? nil : date.addingTimeInterval(4 * 86_400 + 10 * 3_600 + 28 * 60),
                               windowDuration: 7 * 86_400)
        switch state {
        case "claude-real":
            // One real check through the official Claude Code CLI. The app still never reads the Keychain.
            model.updateClaude(snapshot: nil, status: "正在读取额度…")
            claudeUsage.check { [weak self] result in
                guard let self else { return }
                switch result {
                case let .snapshot(snapshot, source, stale, _):
                    model.updateClaude(snapshot: snapshot, status: source == .live ? "" : "数据来自 Claude 桌面记录", stale: stale)
                case .unavailable:
                    model.updateClaude(snapshot: nil, status: "Claude 额度暂不可用")
                }
                model.tick(at: Date())
            }
        case "claude-full":
            model.updateClaude(snapshot: QuotaSnapshot(remainingPercent: 100, observedAt: date, windowDuration: 5 * 3_600,
                planName: "Pro", planBadgeName: "Pro", secondaryWindow: week), status: "")
        case "claude-desktop", "claude-stale":
            let stale = state == "claude-stale"
            let status = stale ? "数据来自 Claude 桌面记录（较旧）" : "数据来自 Claude 桌面记录"
            model.updateClaude(snapshot: QuotaSnapshot(remainingPercent: 90, observedAt: date.addingTimeInterval(stale ? -3 * 3_600 : -9 * 60),
                windowDuration: 5 * 3_600, secondaryWindow: week), status: status,
                detail: status + "，尚未获取重置时间。 未找到可用的 Claude Code，请安装 Claude Code 或 Claude 桌面版。", stale: stale)
        default:
            model.updateClaude(snapshot: QuotaSnapshot(remainingPercent: 85, observedAt: date, resetsAt: date.addingTimeInterval(4 * 3_600 + 38 * 60),
                windowDuration: 5 * 3_600, planName: "Pro", planBadgeName: "Pro", secondaryWindow: week), status: "")
        }
        model.selectQuotaProvider(.claude)
        if state == "claude-real" {
            let sessions = ClaudeSessionScanner.scan()
            model.updateClaudeSessions(sessions)
            return
        }
        // Mirrors work/claude-tasks-proposal-20260926/claude-tasks-panel.png.
        func sample(_ id: String, _ title: String, _ minutes: Double, _ status: ClaudeCodeSession.Status) -> ClaudeCodeSession {
            ClaudeCodeSession(id: "local_preview-\(id)", title: title, folderName: "codex助手",
                              lastActiveAt: date.addingTimeInterval(-minutes * 60), status: status,
                              origin: .desktop(sessionID: "local_preview-\(id)"))
        }
        model.updateClaudeSessions([
            sample("1", "Claude 额度改走官方 CLI 并实施双圈", 0, .running),
            sample("2", "趁手首页任务区改版", 8, .waiting),
            ClaudeCodeSessionParser.terminalSession(process: CodexCLIProcess(pid: 4242, tty: "ttys003"),
                                                    cwd: "/Users/openclaw/Projects/aihot", now: date),
            sample("3", "整理 1.4.6 发布说明", 120, .completed),
            sample("4", "检查自动更新链路", 26 * 60, .completed)
        ])
    }

    func show() { controller.setEnabled(true, expand: true); controller.keepPreviewVisible(); model.tick(at: date) }
    func snapshot(to path: String) throws { try controller.snapshot(to: path) }

    func recordAnimation(to directory: String) {
        controller.setEnabled(true)
        Task { @MainActor in
            var frames: [[String: Any]] = []
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try? await Task.sleep(for: .milliseconds(100))
            @MainActor func capture(_ name: String) {
                try? controller.snapshot(to: url.appendingPathComponent(name + ".png").path)
                let frame = controller.verificationFrame
                frames.append(["name": name, "width": frame.width, "height": frame.height, "top": frame.maxY])
            }
            capture("closed")
            controller.expand(); model.tick(at: date)
            for (name, delay) in [("open-060", 60), ("open-150", 90), ("open-360", 210)] {
                try? await Task.sleep(for: .milliseconds(delay)); capture(name)
            }
            controller.collapse()
            for (name, delay) in [("close-080", 80), ("close-320", 240)] {
                try? await Task.sleep(for: .milliseconds(delay)); capture(name)
            }
            if let data = try? JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url.appendingPathComponent("frames.json"))
            }
            NSApp.terminate(nil)
        }
    }
}
