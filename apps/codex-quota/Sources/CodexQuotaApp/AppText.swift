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
    var expectedTimePlaceholder: String { choose("预期时间：--", "Expected: --") }
    var displayStyle: String { choose("展示形式", "Display Style") }
    var identityStyle: String { choose("标识形式", "Identity") }
    var showResetTime: String { choose("显示重置时间", "Show Reset Time") }
    var launchAtLogin: String { choose("开机自动启动", "Launch at Login") }
    var taskSleep: String { choose("手动合盖不睡眠", "Keep Awake Manually (Lid Closed)") }
    var taskSleepConfirm: String { choose("启用手动合盖不睡眠？", "Keep the Mac awake manually?") }
    var taskSleepExplanation: String { choose("开启后会一直阻止合盖睡眠，直到手动关闭或退出应用。此功能会接管系统的全局禁止睡眠设置（包括已有设置），首次启用需要 macOS 管理员授权。合盖运行时请保持通风。", "When enabled, sleep remains blocked until you turn it off or quit the app. This takes control of the system-wide sleep override, including any existing override, and requires macOS administrator authorization on first use. Keep the Mac ventilated when running with the lid closed.") }
    var taskSleepFailed: String { choose("合盖防睡眠未能生效", "Could Not Enable Task Sleep Protection") }
    var launchAtLoginApproval: String { choose("开机自动启动（需系统确认）", "Launch at Login (Approval Required)") }
    var launchAtLoginUnavailable: String { choose("开机自动启动（不可用）", "Launch at Login (Unavailable)") }
    var mouseScrollReversal: String { choose("鼠标滚轮方向反转", "Reverse Mouse Scroll Direction") }
    var mouseScrollReversalHint: String { choose("反转外接鼠标滚轮方向；启用时需要辅助功能权限。", "Reverse external mouse-wheel direction. Accessibility permission is required when enabled.") }
    var enableModifierTapOpenCodex: String { choose("启用修饰键呼出", "Enable Modifier Gesture") }
    var globalShortcutSettings: String { choose("全局快捷键设置", "Global Shortcut Settings") }
    var enableKeyMappings: String { choose("启用全局按键映射", "Enable Global Key Mappings") }
    var originalShortcut: String { choose("原始快捷键", "Original Shortcut") }
    var mappedShortcut: String { choose("映射快捷键", "Mapped Shortcut") }
    var keyMappingHint: String { choose("点击快捷键录制；支持组合键和修饰键单击/双击，可配置多条映射。", "Click a shortcut to record. Add multiple mappings using key combinations or modifier taps.") }
    var addKeyMapping: String { choose("添加映射", "Add Mapping") }
    var removeKeyMapping: String { choose("移除所选映射", "Remove Selected Mapping") }
    var configureShortcut: String { choose("手动设置快捷键", "Set Shortcut Manually") }
    var recordOriginalShortcut: String { choose("录制原始快捷键，Esc 取消", "Record original shortcut; Esc to cancel") }
    var recordMappedShortcut: String { choose("录制映射快捷键，Esc 取消", "Record mapped shortcut; Esc to cancel") }
    var keyCombination: String { choose("组合快捷键", "Key Combination") }
    var modifierSingleTap: String { choose("修饰键单击", "Single Modifier Tap") }
    var modifierDoubleTap: String { choose("修饰键双击", "Double Modifier Tap") }
    var keyMappingConflict: String { choose("原始快捷键已被使用", "Original Shortcut Already Used") }
    var keyMappingConflictHint: String { choose("请更换原始快捷键，或先停用已有映射。同一修饰键的单击与双击也不能同时启用。", "Choose another original shortcut or disable the existing mapping. Single and double taps of the same modifier also conflict.") }
    var inputMonitoringSettings: String { choose("输入监听设置…", "Input Monitoring Settings…") }
    var accessibilitySettings: String { choose("辅助功能设置…", "Accessibility Settings…") }
    var rightClickShortcutOperations: String { choose("右键快捷操作", "Right-Click Shortcuts") }
    var quickTools: String { choose("便捷工具", "Quick Tools") }
    var quickToolsMenu: String { choose("便捷工具…", "Quick Tools…") }
    var gesture: String { choose("手势", "Gesture") }
    var filter: String { choose("过滤", "Filter") }
    var action: String { choose("行为", "Action") }
    var description: String { choose("说明", "Description") }
    var enabled: String { choose("启用", "Enabled") }
    var recordShortcut: String { choose("录制快捷键", "Record Shortcut") }
    var recordingShortcut: String { choose("按下快捷键…", "Press a shortcut…") }
    var noShortcut: String { choose("未设置", "Not Set") }
    var rightClickShortcutHint: String { choose("按住右键拖出方向后松开，触发匹配的快捷键。", "Hold the right mouse button, draw a direction, then release to trigger a shortcut.") }
    var enableRightClickShortcuts: String { choose("启用右键快捷操作", "Enable Right-Click Shortcuts") }
    var rightClickShortcutsDisabledHint: String { choose("已关闭右键监听。所有应用使用原生右键，已保存的规则保留。", "Right-click monitoring is off. All apps use their native right-click behavior; saved rules are preserved.") }
    var gestureExclusions: String { choose("全局排除应用", "Excluded Apps") }
    var gestureExclusionsHint: String { choose("以下应用不触发任何右键快捷操作，右键点击和拖动保持原生行为。修改立即生效。", "These apps use native right-click and drag behavior for all gesture rules. Changes take effect immediately.") }
    var gestureExclusionsEmpty: String { choose("尚未排除任何应用", "No Excluded Apps") }
    var addExcludedApplication: String { choose("添加应用…", "Add Apps…") }
    var removeExcludedApplication: String { choose("移除所选应用", "Remove Selected App") }
    var invalidExcludedApplication: String { choose("所选应用缺少应用标识，未加入排除清单。", "The selected app has no bundle identifier and could not be excluded.") }
    var done: String { choose("完成", "Done") }
    var rightClickShortcutPermissionGranted: String { choose("辅助功能权限：已授权", "Accessibility: Authorized") }
    var rightClickShortcutPermissionRequired: String { choose("辅助功能权限：未授权，右键快捷操作不可用。", "Accessibility permission is required; right-click shortcuts are unavailable.") }
    var appPickerButton: String { choose("选择应用", "Pick App") }
    var appPickerTooltip: String { choose("选取当前运行的应用，插入其 Bundle ID 到过滤条件", "Pick a running app to insert its bundle ID into the filter") }
    var appPickerSearchPlaceholder: String { choose("搜索应用", "Search Apps") }
    var appPickerEmptyHint: String { choose("没有找到匹配的应用", "No Matching Apps") }
    var appPickerColumnTitle: String { choose("应用", "App") }
    var triggerGestureSection: String { choose("触发手势", "Trigger Gesture") }
    var targetShortcutSection: String { choose("目标快捷键", "Target Shortcut") }
    var permissionsSection: String { choose("权限", "Permissions") }
    var rerecord: String { choose("重新录制", "Record Again") }
    var currentTriggerGesture: String { choose("当前触发手势", "Current Trigger Gesture") }
    var triggerGestureRecordingHint: String { choose("按下左侧或右侧的 ⌘ ⌥ ⇧ ⌃，单击或双击", "Press the left or right ⌘ ⌥ ⇧ ⌃ once or twice") }
    var recordingTriggerGesture: String { choose("请按下修饰键…", "Press a modifier key…") }
    var codexShortcutMatchHint: String { choose("必须与 Codex 设置中的『弹出窗口快捷键』保持一致", "Must match Codex Settings' ‘Pop-out window shortcut’") }
    var currentCodexShortcut: String { choose("当前快捷键", "Current shortcut") }
    var recordingCodexShortcut: String { choose("请按下快捷键…", "Press a shortcut…") }
    var openSettings: String { choose("打开设置", "Open Settings") }
    var codexInvocationShortcutHint: String { choose("触发手势后，App 会模拟发送目标快捷键", "After the gesture, the app simulates the target shortcut") }
    var moveHint: String { choose("按住 ⌘ 可自由拖动位置", "Hold ⌘ and drag to reposition") }
    var checkForUpdates: String { choose("检查更新…", "Check for Updates…") }
    var quit: String { choose("退出", "Quit") }
    var launchUnavailableMessage: String { choose("开机自动启动不可用", "Launch at Login Unavailable") }
    var unavailableRetry: String { choose("当前系统无法使用此功能，请稍后重试。", "This feature is unavailable on this system. Try again later.") }
    var cannotEnableLaunch: String { choose("无法开启开机自动启动", "Could Not Enable Launch at Login") }
    var cannotDisableLaunch: String { choose("无法关闭开机自动启动", "Could Not Disable Launch at Login") }
    var checkLoginItems: String { choose("请在“系统设置”中的“登录项”里检查后重试。", "Check Login Items in System Settings, then try again.") }
    var moveToApplications: String { choose("建议先将 Codex Quota 移到“应用程序”文件夹，开机启动会更稳定。", "Move Codex Quota to the Applications folder first for more reliable launch at login.") }
    var enableAnyway: String { choose("仍然开启", "Enable Anyway") }
    var cancel: String { choose("取消", "Cancel") }
    var save: String { choose("保存", "Save") }
    var none: String { choose("无", "None") }
    var systemActions: String { choose("系统动作", "System Actions") }
    var immediateTrigger: String { choose("立即触发", "Fire Immediately") }
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
    var codexClientThreads: String { choose("Codex 会话", "Codex Sessions") }
    var codexCLIProcesses: String { choose("CLI 进程", "CLI Processes") }
    var openCLIProcessHelp: String { choose("定位当前 CLI 终端", "Locate the active CLI terminal") }
    var createdByCLI: String { choose("CLI 创建", "Created by CLI") }
    var createdByDesktop: String { choose("桌面端创建", "Created by Desktop") }
    func cliOccupiedCount(_ count: Int) -> String { choose("\(count) 个占用", "\(count) occupied") }
    func cliOccupied(_ pid: Int, tty: String?) -> String { choose("占用中 · PID \(pid)\(tty.map { " · \($0)" } ?? "")", "Occupied · PID \(pid)\(tty.map { " · \($0)" } ?? "")") }
    var cliOccupiedElsewhere: String { choose("该 CLI 会话正在其它终端中占用，未创建重复会话", "This CLI session is occupied in another terminal; no duplicate session was created") }
    var cliOwningAppOpened: String { choose("已打开所属应用；请在原终端继续，或关闭会话后再在终端恢复", "The owning app was opened. Continue in the original terminal, or close the session before resuming in Terminal.") }
    var clearCompletedTasks: String { choose("清理完成任务", "Clear Completed") }
    var clearFinishedThreads: String { choose("清除完成任务", "Clear completed tasks") }
    var continueTask: String { choose("继续", "Continue") }
    var deleteTask: String { choose("删除", "Delete") }
    var quotaTitle: String { choose("Codex 配额", "Codex Quota") }
    var fiveHourWindow: String { choose("5 小时窗口", "5-hour window") }
    var weeklyWindow: String { choose("每周窗口", "Weekly window") }
    var quotaWindow: String { choose("额度窗口", "Quota window") }
    var waitingForData: String { choose("等待数据", "Waiting for data") }
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
    var taskInterruptedSubtitle: String { choose("已中断", "Interrupted") }
    func codexClientRunning(_ duration: String) -> String {
        choose("已运行 \(duration)", "Running \(duration)")
    }
    func codexClientLastActive(_ time: String) -> String {
        choose("最后活跃 \(time)", "Last active \(time)")
    }
    var copyResumeCommandHelp: String {
        choose("点击复制恢复命令", "Click to copy the resume command")
    }
    var openCodexThreadHelp: String {
        choose("打开 Codex 聊天", "Open Codex conversation")
    }
    var openParentCodexThreadHelp: String {
        choose("打开所属聊天", "Open parent conversation")
    }
    var subagentThreadUnavailableHelp: String {
        choose(
            "子 Agent 聊天需从父任务打开",
            "Subagent conversations must be opened from their parent task"
        )
    }
    var codexThreadOpenFailedTitle: String {
        choose("无法打开 Codex 聊天", "Could Not Open Codex Conversation")
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

    func expectedTime(_ value: String) -> String {
        choose("预期时间：\(value)", "Expected: \(value)")
    }

    func accessibilityStyle(_ value: String) -> String {
        choose("，\(value)", ", \(value)")
    }

    func inputMonitoringPermissionStatus(isAuthorized: Bool) -> String {
        choose(
            "输入监听：\(isAuthorized ? "已授权" : "未授权")",
            "Input Monitoring: \(isAuthorized ? "Authorized" : "Not Authorized")"
        )
    }

    func accessibilityPermissionStatus(isAuthorized: Bool) -> String {
        choose(
            "辅助功能：\(isAuthorized ? "已授权" : "未授权")",
            "Accessibility: \(isAuthorized ? "Authorized" : "Not Authorized")"
        )
    }

    func modifierTapGestureDisplay(keyCodes: Set<UInt16>, tapCount: Int) -> String {
        let keyName: String
        if keyCodes == Set([UInt16(54), 55]) {
            keyName = choose("任意 ⌘", "Any ⌘")
        } else {
            let names = keyCodes.sorted().map(modifierGestureKeyName)
            keyName = names.joined(separator: choose("、", " + "))
        }
        let tapName = tapCount == 1
            ? choose("单击", "Single Tap")
            : choose("双击", "Double Tap")
        return "\(keyName) \(tapName)"
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
            failedWithExitCodeFormat: taskFailedSubtitleFormat,
            interrupted: taskInterruptedSubtitle
        )
    }

    func taskNotificationBody(name: String, time: String) -> String {
        "\(name) · \(time)"
    }

    private func modifierGestureKeyName(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 54:
            choose("右 ⌘", "Right ⌘")
        case 55:
            choose("左 ⌘", "Left ⌘")
        case 56:
            choose("左 ⇧", "Left ⇧")
        case 58:
            choose("左 ⌥", "Left ⌥")
        case 59:
            choose("左 ⌃", "Left ⌃")
        case 60:
            choose("右 ⇧", "Right ⇧")
        case 61:
            choose("右 ⌥", "Right ⌥")
        case 62:
            choose("右 ⌃", "Right ⌃")
        case 63:
            "Fn / 🌐"
        default:
            choose("修饰键", "Modifier Key")
        }
    }
}
