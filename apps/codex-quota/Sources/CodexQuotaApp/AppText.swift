import CodexQuotaCore
import Foundation

struct AppText {
    let language: AppLanguage

    private func choose(_ chinese: String, _ english: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }

    var selected: String { choose("已选择", "Selected") }
    var notSelected: String { choose("未选择", "Not selected") }
    var updatedPlaceholder: String { choose("更新时间：--:--:--", "Updated: --:--:--") }
    var nextResetPlaceholder: String { choose("下次重置：--", "Next reset: --") }
    var planPlaceholder: String { choose("当前套餐：--", "Plan: --") }
    var resetForecastNone: String { choose("重置预告：暂无", "Reset forecast: None") }
    var expectedTimePlaceholder: String { choose("预期时间：--", "Expected: --") }
    var displayStyle: String { choose("展示形式", "Display Style") }
    var identityStyle: String { choose("标识形式", "Identity") }
    var showResetTime: String { choose("显示重置时间", "Show Reset Time") }
    var launchAtLogin: String { choose("开机自动启动", "Launch at Login") }
    var launchAtLoginApproval: String { choose("开机自动启动（需系统确认）", "Launch at Login (Approval Required)") }
    var launchAtLoginUnavailable: String { choose("开机自动启动（不可用）", "Launch at Login (Unavailable)") }
    var moveHint: String { choose("按住 ⌘ 可自由拖动位置", "Hold ⌘ and drag to reposition") }
    var checkForUpdates: String { choose("检查更新…", "Check for Updates…") }
    var quit: String { choose("退出", "Quit") }
    var resetAnnouncementTooltip: String { choose("在 X 上查看 Tibo 的重置预告", "View Tibo's reset announcement on X") }
    var resetAnnouncementAccessibility: String { choose("查看 Tibo 的重置预告原帖", "View Tibo's original reset announcement") }
    var launchUnavailableMessage: String { choose("开机自动启动不可用", "Launch at Login Unavailable") }
    var unavailableRetry: String { choose("当前系统无法使用此功能，请稍后重试。", "This feature is unavailable on this system. Try again later.") }
    var cannotEnableLaunch: String { choose("无法开启开机自动启动", "Could Not Enable Launch at Login") }
    var cannotDisableLaunch: String { choose("无法关闭开机自动启动", "Could Not Disable Launch at Login") }
    var checkLoginItems: String { choose("请在“系统设置”中的“登录项”里检查后重试。", "Check Login Items in System Settings, then try again.") }
    var moveToApplications: String { choose("建议先将 Codex Quota 移到“应用程序”文件夹，开机启动会更稳定。", "Move Codex Quota to the Applications folder first for more reliable launch at login.") }
    var enableAnyway: String { choose("仍然开启", "Enable Anyway") }
    var cancel: String { choose("取消", "Cancel") }
    var checkingUpdates: String { choose("正在检查更新，请稍候。", "Checking for updates. Please wait.") }
    var cannotCheckUpdates: String { choose("无法检查更新", "Could Not Check for Updates") }
    var invalidVersion: String { choose("当前版本信息无效，请重新安装 Codex Quota。", "The current version information is invalid. Reinstall Codex Quota.") }
    var updateFailed: String { choose("检查更新失败，请稍后重试。", "The update check failed. Try again later.") }
    var upToDate: String { choose("当前已是最新版本", "Codex Quota Is Up to Date") }
    var goToUpdate: String { choose("前往更新", "View Update") }
    var later: String { choose("稍后", "Later") }
    var cannotOpenUpdate: String { choose("无法打开更新页面，请稍后重试。", "Could not open the update page. Try again later.") }
    var githubReleaseNotes: String { choose("前往 GitHub 查看更新说明。", "View the release notes on GitHub.") }
    var dismiss: String { choose("知道了", "Got It") }
    var launched: String { choose("Codex Quota 已启动", "Codex Quota Is Running") }
    var launchNotice: String { choose(
        "额度每 15 秒自动更新一次，无需手动刷新。按住 Command（⌘）并拖动菜单栏图标，可以自由调整位置。",
        "Your quota updates automatically every 15 seconds. Hold Command (⌘) and drag the menu bar icon to reposition it."
    ) }

    func newVersionAvailable(_ version: String) -> String {
        choose("新版本 \(version) 可用…", "Version \(version) Available…")
    }

    func foundNewVersion(_ version: String) -> String {
        choose("发现新版本 \(version)", "Version \(version) Is Available")
    }

    func nextReset(_ value: String) -> String {
        choose("下次重置：\(value)", "Next reset: \(value)")
    }

    func plan(_ value: String) -> String {
        choose("当前套餐：\(value)", "Plan: \(value)")
    }

    func resetForecast(_ value: String, linked: Bool) -> String {
        choose("重置预告：\(value)", "Reset forecast: \(value)") + (linked ? "  ↗" : "")
    }

    func expectedTime(_ value: String) -> String {
        choose("预期时间：\(value)", "Expected: \(value)")
    }

    func accessibilityStyle(_ value: String) -> String {
        choose("，\(value)", ", \(value)")
    }

    func resetNotificationTitle(kind: TiboResetSignalKind) -> String {
        switch kind {
        case .proposal:
            choose("Tibo 提到可能重置 Codex 额度", "Tibo Mentioned a Possible Codex Quota Reset")
        case .announced:
            choose("Tibo 已预告 Codex 额度重置", "Tibo Announced a Codex Quota Reset")
        case .completed:
            choose("Codex 额度重置已发起", "Codex Quota Reset Started")
        }
    }
}
