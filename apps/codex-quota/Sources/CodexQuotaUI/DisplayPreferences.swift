import CoreFoundation
import CodexQuotaCore
import Foundation

public struct DisplayPreferences {
    public static let batteryStyleKey = "batteryStyle"
    public static let showsCodexLabelKey = "showsCodexLabel"
    public static let statusIdentityModeKey = "statusIdentityMode"
    public static let showsResetCountdownInStatusBarKey = "showsResetCountdownInStatusBar"
    public static let hasShownAutoRefreshNoticeKey = "hasShownAutoRefreshNotice"
    public static let lastUpdateCheckSuccessKey = "lastUpdateCheckSuccess"
    public static let lastUpdateCheckFailureKey = "lastUpdateCheckFailure"
    public static let lastPromptedVersionKey = "lastPromptedVersion"
    public static let lastNotifiedResetSignalIDKey = "lastNotifiedResetSignalID"
    public static let latestResetSignalKey = "latestResetSignal"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var batteryStyle: BatteryStyle {
        get {
            guard
                let rawValue = defaults.string(forKey: Self.batteryStyleKey),
                let style = BatteryStyle(rawValue: rawValue)
            else {
                return .native
            }
            return style
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.batteryStyleKey)
        }
    }

    public var showsCodexLabel: Bool {
        get {
            guard defaults.object(forKey: Self.showsCodexLabelKey) != nil else {
                return true
            }
            return defaults.bool(forKey: Self.showsCodexLabelKey)
        }
        set {
            defaults.set(newValue, forKey: Self.showsCodexLabelKey)
        }
    }

    public var identityMode: StatusIdentityMode {
        get {
            if defaults.object(forKey: Self.statusIdentityModeKey) != nil {
                guard
                    let rawValue = defaults.string(forKey: Self.statusIdentityModeKey),
                    let mode = StatusIdentityMode(rawValue: rawValue)
                else {
                    return .text
                }
                return mode
            }

            let mode: StatusIdentityMode
            if
                let legacyValue = defaults.object(
                    forKey: Self.showsCodexLabelKey
                ) as? NSNumber,
                CFGetTypeID(legacyValue) == CFBooleanGetTypeID()
            {
                mode = legacyValue.boolValue ? .text : .hidden
            } else {
                mode = .text
            }
            defaults.set(mode.rawValue, forKey: Self.statusIdentityModeKey)
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.statusIdentityModeKey)
        }
    }

    public var showsResetCountdownInStatusBar: Bool {
        get {
            defaults.bool(forKey: Self.showsResetCountdownInStatusBarKey)
        }
        set {
            defaults.set(newValue, forKey: Self.showsResetCountdownInStatusBarKey)
        }
    }

    public var hasShownAutoRefreshNotice: Bool {
        get {
            defaults.bool(forKey: Self.hasShownAutoRefreshNoticeKey)
        }
        set {
            defaults.set(newValue, forKey: Self.hasShownAutoRefreshNoticeKey)
        }
    }

    public var lastUpdateCheckSuccess: Date? {
        get {
            defaults.object(forKey: Self.lastUpdateCheckSuccessKey) as? Date
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.lastUpdateCheckSuccessKey)
            } else {
                defaults.removeObject(forKey: Self.lastUpdateCheckSuccessKey)
            }
        }
    }

    public var lastUpdateCheckFailure: Date? {
        get {
            defaults.object(forKey: Self.lastUpdateCheckFailureKey) as? Date
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.lastUpdateCheckFailureKey)
            } else {
                defaults.removeObject(forKey: Self.lastUpdateCheckFailureKey)
            }
        }
    }

    public var lastPromptedVersion: String? {
        get {
            guard
                let value = defaults.object(forKey: Self.lastPromptedVersionKey) as? String,
                !value.isEmpty
            else {
                return nil
            }
            return value
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.lastPromptedVersionKey)
            } else {
                defaults.removeObject(forKey: Self.lastPromptedVersionKey)
            }
        }
    }

    public var lastNotifiedResetSignalID: String? {
        get {
            defaults.string(forKey: Self.lastNotifiedResetSignalIDKey)
        }
        set {
            defaults.set(newValue, forKey: Self.lastNotifiedResetSignalIDKey)
        }
    }

    public var latestResetSignal: TiboResetSignal? {
        get {
            guard
                let data = defaults.data(forKey: Self.latestResetSignalKey),
                let signal = try? JSONDecoder().decode(TiboResetSignal.self, from: data)
            else {
                return nil
            }
            return signal
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: Self.latestResetSignalKey)
                return
            }
            defaults.set(data, forKey: Self.latestResetSignalKey)
        }
    }
}
