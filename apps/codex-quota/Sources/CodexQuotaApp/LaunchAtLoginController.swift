import AppKit
import CodexQuotaCore
import ServiceManagement

@MainActor
final class LaunchAtLoginController {
    enum State: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable(String)
    }

    private let fallback: LaunchAgentFile?

    init() {
        fallback = Bundle.main.executableURL.map {
            LaunchAgentFile(
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                executableURL: $0
            )
        }
    }

    var state: State {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return fallback?.isInstalled == true ? .enabled : .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return fallback?.isInstalled == true ? .enabled : .disabled
        @unknown default:
            return .unavailable("未知的登录项状态")
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status == .notFound, let fallback {
                try fallback.install()
            } else {
                try SMAppService.mainApp.register()
            }
        } else {
            try fallback?.uninstall()
            if [.enabled, .requiresApproval].contains(SMAppService.mainApp.status) {
                try SMAppService.mainApp.unregister()
            }
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
