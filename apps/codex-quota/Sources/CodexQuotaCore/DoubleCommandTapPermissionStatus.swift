public enum DoubleCommandTapPermissionStatus: Equatable {
    case running
    case inputMonitoringRequired
    case accessibilityRequired
    case inputMonitoringAndAccessibilityRequired

    public init(inputMonitoringAuthorized: Bool, accessibilityAuthorized: Bool) {
        switch (inputMonitoringAuthorized, accessibilityAuthorized) {
        case (true, true):
            self = .running
        case (false, true):
            self = .inputMonitoringRequired
        case (true, false):
            self = .accessibilityRequired
        case (false, false):
            self = .inputMonitoringAndAccessibilityRequired
        }
    }
}
