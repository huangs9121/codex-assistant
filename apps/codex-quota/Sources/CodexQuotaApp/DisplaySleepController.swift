import AppKit
import IOKit.pwr_mgt

/// Session-only idle-sleep protection. Does not alter pmset or lid policy.
@MainActor
final class DisplaySleepController {
    private var assertion: IOPMAssertionID?
    private var hasRunningTasks = false
    var isActive: Bool { assertion != nil }
    private var isStarting = false
    private let displaySleep: @Sendable () async -> Bool

    init(displaySleep: @escaping @Sendable () async -> Bool = {
        await DisplaySleepController.runDisplaySleep()
    }) {
        self.displaySleep = displaySleep
    }

    enum Failure: LocalizedError {
        case protection, display
        var errorDescription: String? {
            switch self {
            case .protection: "无法启用临时防休眠，未执行熄屏。"
            case .display: "熄屏命令未成功，已释放临时防休眠。"
            }
        }
    }

    func start() async throws {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        stop()
        if hasRunningTasks {
            var identifier: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoIdleSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Codex Quota: running tasks while display is asleep" as CFString,
                &identifier
            )
            guard result == kIOReturnSuccess else { throw Failure.protection }
            assertion = identifier
        }
        if !(await displaySleep()) {
            stop()
            throw Failure.display
        }
    }

    nonisolated private static func runDisplaySleep() async -> Bool {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["displaysleepnow"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch { return false }
        }.value
    }

    /// Release synchronously on the first scan with no executing tasks.
    func update(hasRunningTasks: Bool) {
        self.hasRunningTasks = hasRunningTasks
        if !hasRunningTasks { stop() }
    }

    func stop() {
        if let assertion {
            IOPMAssertionRelease(assertion)
            self.assertion = nil
        }
    }
}
