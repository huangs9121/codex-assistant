import CodexQuotaCore
import Darwin
import Foundation

@MainActor
final class TaskSleepController {
    static let enabledDefaultsKey = "taskSleepEnabled"

    enum ControllerError: LocalizedError {
        case bundledHelperMissing
        case authorizationFailed
        case leaseWriteFailed

        var errorDescription: String? {
            switch self {
            case .bundledHelperMissing:
                return "未找到睡眠保护组件，无法启用。"
            case .authorizationFailed:
                return "管理员授权或睡眠保护组件安装未完成。"
            case .leaseWriteFailed:
                return "无法创建受限睡眠租约，未启用睡眠保护。"
            }
        }
    }

    private enum Paths {
        static let root = "/Library/Application Support/CodexQuotaSleep"
        static let helper = root + "/CodexQuotaSleepHelper"
        static let daemon = "/Library/LaunchDaemons/local.openclaw.codexquota.sleephelper.plist"
    }

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let uid: UInt32
    private let ownerPID: Int32
    private var hasFreshRunningTasks = false
    private(set) var lastError: Error?

    var onChange: (() -> Void)?

    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledDefaultsKey)
    }

    var statusDescription: String {
        if let lastError {
            return lastError.localizedDescription
        }
        guard isEnabled else {
            return "合盖睡眠保护未启用。"
        }
        guard helperFilesAreSafe else {
            return "合盖睡眠保护已启用，但受限服务文件不可用；未显示为已保护。"
        }
        guard daemonIsRunning else {
            return "合盖睡眠保护已启用，但服务未运行；未显示为已保护。"
        }
        guard let helperStatus else {
            return "合盖睡眠保护已启用，等待服务确认实际电源状态；未显示为已保护。"
        }
        guard helperStatus.success else {
            return "合盖睡眠保护服务未确认电源设置；未显示为已保护。"
        }
        if hasFreshRunningTasks && (!helperStatus.active || !helperStatus.sleepDisabled) {
            return "运行任务已发现，等待服务确认合盖睡眠已阻止；未显示为已保护。"
        }
        if !hasFreshRunningTasks && helperStatus.sleepDisabled {
            return "任务已结束，等待服务恢复普通睡眠；未显示为已恢复。"
        }
        return hasFreshRunningTasks
            ? "运行中的 Codex 任务正在临时阻止合盖睡眠；任务结束、扫描停止或一分钟未收到新扫描后恢复。"
            : "合盖睡眠保护已接管为普通睡眠，等待本轮新扫描发现运行中的 Codex 任务。"
    }

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        uid = getuid()
        ownerPID = getpid()
    }

    func setEnabled(_ enabled: Bool) async throws {
        if !enabled {
            defaults.set(false, forKey: Self.enabledDefaultsKey)
            hasFreshRunningTasks = false
            removeLease()
            lastError = nil
            onChange?()
            return
        }

        do {
            if !isInstalled {
                try await installHelper()
                try await waitForInstalledService()
            }
            defaults.set(true, forKey: Self.enabledDefaultsKey)
            hasFreshRunningTasks = false
            lastError = nil
            onChange?()
        } catch {
            defaults.set(false, forKey: Self.enabledDefaultsKey)
            hasFreshRunningTasks = false
            removeLease()
            lastError = error
            onChange?()
            throw error
        }
    }

    /// Call only after a new task scan has completed. This method deliberately
    /// has no timer: a stale scan cannot keep extending the privileged lease.
    func update(hasRunningTasks: Bool) {
        guard isEnabled else { return }
        hasFreshRunningTasks = hasRunningTasks
        do {
            try writeFreshLease(hasRunningTasks: hasRunningTasks)
            lastError = nil
        } catch {
            lastError = ControllerError.leaseWriteFailed
            removeLease()
        }
        onChange?()
    }

    /// App termination and invalidation use the same narrow operation: remove
    /// this app's lease. The root daemon restores only a journal it created.
    func stop() {
        hasFreshRunningTasks = false
        removeLease()
        onChange?()
    }

    private var isInstalled: Bool {
        helperFilesAreSafe && daemonIsRunning
    }

    private var helperFilesAreSafe: Bool {
        safePath(Paths.root, owner: 0, type: S_IFDIR, exactMode: 0o755)
            && safePath(Paths.helper, owner: 0, type: S_IFREG, exactMode: 0o755)
            && safePath(Paths.daemon, owner: 0, type: S_IFREG, exactMode: 0o644)
            && safePath(userDirectory.path, owner: uid, type: S_IFDIR, exactMode: 0o700)
    }

    private var daemonIsRunning: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/local.openclaw.codexquota.sleephelper"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private var userDirectory: URL {
        URL(fileURLWithPath: Paths.root, isDirectory: true)
            .appendingPathComponent("uid-\(uid)", isDirectory: true)
    }

    private var leaseURL: URL {
        userDirectory.appendingPathComponent("lease", isDirectory: false)
    }

    private var statusURL: URL {
        URL(fileURLWithPath: Paths.root, isDirectory: true)
            .appendingPathComponent("status-\(uid)", isDirectory: false)
    }

    private struct HelperStatus {
        let ownerPID: Int32
        let scannedAt: Int64
        let active: Bool
        let sleepDisabled: Bool
        let success: Bool
    }

    private var helperStatus: HelperStatus? {
        guard
            safePath(statusURL.path, owner: 0, type: S_IFREG, exactMode: 0o644),
            let data = try? Data(contentsOf: statusURL),
            data.count <= 64,
            let text = String(data: data, encoding: .utf8),
            let match = text.wholeMatch(of: /^(1)\n(\d+)\n(\d+)\n([01])\n([01])\n([01])\n$/),
            let ownerPID = Int32(match.2),
            let scannedAt = Int64(match.3),
            ownerPID == self.ownerPID,
            scannedAt <= Int64(Date().timeIntervalSince1970),
            Int64(Date().timeIntervalSince1970) - scannedAt <= Int64(TaskSleepLease.maximumLifetime)
        else { return nil }
        return HelperStatus(ownerPID: ownerPID, scannedAt: scannedAt, active: match.4 == "1", sleepDisabled: match.5 == "1", success: match.6 == "1")
    }

    private func safePath(_ path: String, owner: UInt32, type: mode_t, exactMode: mode_t) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
            && (info.st_mode & S_IFMT) == type
            && info.st_uid == owner
            && (info.st_mode & 0o777) == exactMode
    }

    private func writeFreshLease(hasRunningTasks: Bool) throws {
        let now = Int64(Date().timeIntervalSince1970)
        let lease = TaskSleepLease(
            uid: uid,
            ownerPID: ownerPID,
            scannedAt: now,
            expiresAt: now + Int64(TaskSleepLease.maximumLifetime),
            hasRunningTasks: hasRunningTasks,
            // The UI confirmation is required before enabling: Codex Quota
            // takes over the existing global setting only for active tasks,
            // then restores ordinary sleep when this lease ends.
            restoreSleepDisabled: false
        )
        guard fileManager.fileExists(atPath: userDirectory.path) else {
            throw ControllerError.leaseWriteFailed
        }
        try lease.encoded().write(to: leaseURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: leaseURL.path)
    }

    private func removeLease() {
        try? fileManager.removeItem(at: leaseURL)
    }

    private func installHelper() async throws {
        let bundledHelper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/CodexQuotaSleepHelper")
            .standardizedFileURL
        guard FileManager.default.isExecutableFile(atPath: bundledHelper.path) else {
            throw ControllerError.bundledHelperMissing
        }
        let source = """
        on run argv
            do shell script (quoted form of item 1 of argv & " --install " & quoted form of item 2 of argv) with administrator privileges
        end run
        """
        let installUID = uid
        let succeeded = await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source, "--", bundledHelper.path, String(installUID)]
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value
        guard succeeded else { throw ControllerError.authorizationFailed }
    }

    private func waitForInstalledService() async throws {
        for _ in 0..<10 {
            if isInstalled {
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        throw ControllerError.authorizationFailed
    }
}
