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
    var resetForecastNone: String { choose("重置预告 · 暂无动静", "Reset forecast · quiet") }
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
    var installUpdate: String { choose("立即更新", "Update Now") }
    var downloadingUpdate: String { choose("正在下载并校验更新…", "Downloading and verifying update…") }
    var automaticUpdateFailed: String { choose("自动更新失败", "Automatic Update Failed") }
    var automaticUpdateFailedDetail: String { choose(
        "旧版本没有被更改。你可以稍后重试，或前往 GitHub 手动下载安装。",
        "The installed version was not changed. Try again later or download the update manually from GitHub."
    ) }
    var openDownloadPage: String { choose("打开下载页", "Open Download Page") }
    var later: String { choose("稍后", "Later") }
    var cannotOpenUpdate: String { choose("无法打开更新页面，请稍后重试。", "Could not open the update page. Try again later.") }
    var githubReleaseNotes: String { choose("前往 GitHub 查看更新说明。", "View the release notes on GitHub.") }
    var dismiss: String { choose("知道了", "Got It") }
    var launched: String { choose("Codex Quota 已启动", "Codex Quota Is Running") }
    var launchNotice: String { choose(
        "额度每 15 秒自动更新一次，无需手动刷新。按住 Command（⌘）并拖动菜单栏图标，可以自由调整位置。",
        "Your quota updates automatically every 15 seconds. Hold Command (⌘) and drag the menu bar icon to reposition it."
    ) }
    var quotaResetNotificationTitle: String {
        choose("Codex 额度已重置", "Codex Quota Has Reset")
    }
    var quotaResetNotificationBody: String {
        choose("新周期额度已经生效。", "Your new quota cycle is now active.")
    }
    var scheduledTasks: String { choose("调度任务", "Scheduled Tasks") }
    var quotaTitle: String { choose("Codex 配额", "Codex Quota") }
    var fiveHourWindow: String { choose("5 小时窗口", "5-hour window") }
    var weeklyWindow: String { choose("每周窗口", "Weekly window") }
    var quotaWindow: String { choose("额度窗口", "Quota window") }
    var waitingForData: String { choose("等待数据", "Waiting for data") }
    var resetMonitoringSource: String {
        choose("来自 Tibo X 动态监测", "From Tibo X monitoring")
    }
    var resetCompletedTitle: String {
        choose("重置已发起 · 额度即将恢复", "Reset started · Quota returning soon")
    }
    var resetAnnouncedBadge: String { choose("已预告", "Announced") }
    var resetCountdownText: ResetForecastCountdownText {
        ResetForecastCountdownText(
            hoursMinutesFormat: choose(
                "还剩 {hours} 小时 {minutes} 分 · 点击查看 X 原帖",
                "{hours}h {minutes}m left · View on X"
            ),
            minutesFormat: choose(
                "还剩 {minutes} 分 · 点击查看 X 原帖",
                "{minutes}m left · View on X"
            ),
            imminent: choose(
                "即将重置 · 点击查看 X 原帖",
                "Reset imminent · View on X"
            )
        )
    }
    var noScheduledTasks: String { choose("暂无调度任务", "No scheduled tasks") }
    var scheduledTasksEmptyDetail: String {
        choose(
            "在 Kimi 会话中派发任务后，可在这里跟踪进度",
            "Tasks dispatched from Kimi sessions will appear here"
        )
    }
    var backgroundTask: String { choose("后台任务", "Background task") }
    var unknownTask: String { choose("未知任务", "Unknown task") }
    var settings: String { choose("设置", "Settings") }
    var justNow: String { choose("刚刚", "Just now") }
    var taskRunningSubtitleFormat: String {
        choose(
            "已运行 {duration} · {relative}开始",
            "Running {duration} · started {relative}"
        )
    }
    var taskCompletedSubtitleFormat: String {
        choose(
            "{relative} · 耗时 {duration}",
            "{relative} · Duration {duration}"
        )
    }
    var taskFailedSubtitleFormat: String {
        choose(
            "{relative} · 退出码 {exitCode}",
            "{relative} · Exit code {exitCode}"
        )
    }
    var resumeSessionHelp: String {
        choose(
            "点击在终端恢复会话，Option+点击复制命令",
            "Click to resume in Terminal, Option+click to copy"
        )
    }
    var resumeCommandCopiedFallback: String {
        choose(
            "无法打开终端，恢复命令已复制",
            "Could not open Terminal; resume command copied"
        )
    }
    var taskCompletedNotificationTitle: String {
        choose("Codex 任务完成", "Codex Task Completed")
    }
    var taskFailedNotificationTitle: String {
        choose("Codex 任务失败", "Codex Task Failed")
    }

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

    func resetProposalTitle(_ expectedTime: String) -> String {
        choose(
            "可能重置 · \(expectedTime)",
            "Possible reset · \(expectedTime)"
        )
    }

    func resetAnnouncedTitle(_ expectedTime: String) -> String {
        choose(
            "已预告 · 预计\(expectedTime)重置",
            "Announced · Reset expected \(expectedTime)"
        )
    }

    func expectedTime(_ value: String) -> String {
        choose("预期时间：\(value)", "Expected: \(value)")
    }

    func accessibilityStyle(_ value: String) -> String {
        choose("，\(value)", ", \(value)")
    }

    func taskExitCode(_ value: Int) -> String {
        choose("退出码 \(value)", "exit \(value)")
    }

    func resetsIn(_ value: String) -> String {
        choose("\(value)后重置", "resets in \(value)")
    }

    func weeklyReset(_ value: String) -> String {
        choose("\(value) 重置", "Resets \(value)")
    }

    func runningTaskCount(_ value: Int) -> String {
        choose("\(value) 运行中", "\(value) running")
    }

    func updatedAt(_ value: String) -> String {
        choose("更新于 \(value)", "Updated \(value)")
    }

    var taskStatusPresentationText: TaskStatusPresentationText {
        TaskStatusPresentationText(
            justNow: justNow,
            runningFormat: taskRunningSubtitleFormat,
            completedWithDurationFormat: taskCompletedSubtitleFormat,
            failedWithExitCodeFormat: taskFailedSubtitleFormat
        )
    }

    func taskNotificationBody(name: String, time: String) -> String {
        "\(name) · \(time)"
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

    func resetNotificationBody(for signal: TiboResetSignal) -> String {
        switch signal.kind {
        case .proposal:
            return choose(
                "重置预告更新：可能重置，预计\(signal.expectedTimeText(language: language))",
                "Reset forecast update: possible reset, \(signal.expectedTimeText(language: language))"
            )
        case .announced:
            return choose(
                "重置预告升级：已预告，预计\(signal.expectedTimeText(language: language))",
                "Reset forecast upgraded: announced, \(signal.expectedTimeText(language: language))"
            )
        case .completed:
            return choose(
                "重置预告升级：重置已发起，额度即将恢复",
                "Reset forecast upgraded: reset started; quota should return soon"
            )
        }
    }
}
