import AppKit
import ServiceManagement

@MainActor
final class LaunchAtLoginController {
    enum State: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable(String)
    }

    var state: State {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable("系统未找到此登录项")
        @unknown default:
            return .unavailable("未知的登录项状态")
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
