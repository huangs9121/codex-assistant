import Foundation

public struct StatusPanelQuotaWindow: Equatable, Sendable {
    public let remainingPercent: Int
    public let resetsAt: Date?
    public let windowDuration: TimeInterval?

    public init(
        remainingPercent: Int,
        resetsAt: Date?,
        windowDuration: TimeInterval?
    ) {
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.windowDuration = windowDuration
    }
}

public enum StatusPanelQuotaWindowKind: Equatable, Sendable {
    case fiveHour
    case weekly
    case generic

    public init(windowDuration: TimeInterval?) {
        guard let windowDuration, windowDuration.isFinite else {
            self = .generic
            return
        }
        if (4 * 3_600)...(6 * 3_600) ~= windowDuration {
            self = .fiveHour
        } else if (6 * 86_400)...(8 * 86_400) ~= windowDuration {
            self = .weekly
        } else {
            self = .generic
        }
    }
}

public struct StatusPanelQuotaData: Equatable, Sendable {
    public let planName: String?
    public let observedAt: Date?
    public let primaryWindow: StatusPanelQuotaWindow?
    public let secondaryWindow: StatusPanelQuotaWindow?

    public init(
        planName: String?,
        observedAt: Date?,
        primaryWindow: StatusPanelQuotaWindow?,
        secondaryWindow: StatusPanelQuotaWindow?
    ) {
        self.planName = planName
        self.observedAt = observedAt
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
    }

    public init(snapshot: QuotaSnapshot?, now: Date = Date()) {
        guard let snapshot else {
            self.init(
                planName: nil,
                observedAt: nil,
                primaryWindow: nil,
                secondaryWindow: nil
            )
            return
        }

        var windows = [
            StatusPanelQuotaWindow(
                remainingPercent: snapshot.remainingPercent(at: now),
                resetsAt: snapshot.resetDate(at: now),
                windowDuration: snapshot.windowDuration
            )
        ]
        if let secondary = snapshot.secondaryWindow {
            windows.append(
                StatusPanelQuotaWindow(
                    remainingPercent: secondary.remainingPercent(at: now),
                    resetsAt: secondary.resetsAt.flatMap { $0 > now ? $0 : nil },
                    windowDuration: secondary.windowDuration
                )
            )
        }
        if
            windows.count == 2,
            let firstDuration = windows[0].windowDuration,
            let secondDuration = windows[1].windowDuration,
            secondDuration < firstDuration
        {
            windows.swapAt(0, 1)
        }
        self.init(
            planName: snapshot.planName,
            observedAt: snapshot.observedAt,
            primaryWindow: windows.first,
            secondaryWindow: windows.dropFirst().first
        )
    }
}

public enum StatusPanelResetForecastState: Equatable, Sendable {
    case quiet
    case proposal
    case announced
    case completed
}

public struct StatusPanelResetForecast: Equatable, Sendable {
    public let state: StatusPanelResetForecastState
    public let signal: TiboResetSignal?

    public init(
        signal: TiboResetSignal?,
        quotaSnapshot: QuotaSnapshot?,
        now: Date = Date()
    ) {
        guard
            let signal,
            signal.shouldDisplay(at: now, quotaSnapshot: quotaSnapshot)
        else {
            state = .quiet
            self.signal = nil
            return
        }
        self.signal = signal
        switch signal.kind {
        case .proposal:
            state = .proposal
        case .announced:
            state = .announced
        case .completed:
            state = .completed
        }
    }
}

public struct ResetForecastCountdownText: Equatable, Sendable {
    public let hoursMinutesFormat: String
    public let minutesFormat: String
    public let imminent: String

    public init(
        hoursMinutesFormat: String,
        minutesFormat: String,
        imminent: String
    ) {
        self.hoursMinutesFormat = hoursMinutesFormat
        self.minutesFormat = minutesFormat
        self.imminent = imminent
    }
}

public enum ResetForecastCountdownFormatter {
    public static func string(
        until expectedAt: Date,
        now: Date = Date(),
        text: ResetForecastCountdownText
    ) -> String {
        let remainingSeconds = expectedAt.timeIntervalSince(now)
        guard remainingSeconds >= 60 else {
            return text.imminent
        }

        let totalMinutes = Int(remainingSeconds.rounded(.down)) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let format = hours > 0
            ? text.hoursMinutesFormat
            : text.minutesFormat
        return format
            .replacingOccurrences(of: "{hours}", with: String(hours))
            .replacingOccurrences(of: "{minutes}", with: String(minutes))
    }
}

public struct TiboResetNotificationKey: Equatable, Sendable {
    public static let defaultsKey = "lastNotifiedResetSignalState"

    public let id: String
    public let kind: TiboResetSignalKind

    public init(signal: TiboResetSignal) {
        id = signal.id
        kind = signal.kind
    }

    public init?(storageValue: String) {
        let components = storageValue.split(
            separator: "|",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard
            components.count == 2,
            !components[0].isEmpty,
            let kind = TiboResetSignalKind(rawValue: String(components[1]))
        else {
            return nil
        }
        id = String(components[0])
        self.kind = kind
    }

    public var storageValue: String {
        "\(id)|\(kind.rawValue)"
    }

    public func shouldNotify(after previous: TiboResetNotificationKey?) -> Bool {
        self != previous
    }
}

public struct TaskStatusPresentationText: Equatable, Sendable {
    public let justNow: String
    public let runningFormat: String
    public let completedWithDurationFormat: String
    public let failedWithExitCodeFormat: String
    public let interrupted: String

    public init(
        justNow: String,
        runningFormat: String,
        completedWithDurationFormat: String,
        failedWithExitCodeFormat: String,
        interrupted: String
    ) {
        self.justNow = justNow
        self.runningFormat = runningFormat
        self.completedWithDurationFormat = completedWithDurationFormat
        self.failedWithExitCodeFormat = failedWithExitCodeFormat
        self.interrupted = interrupted
    }
}

public enum TaskStatusPresentationFormatter {
    public static func subtitle(
        for task: TaskStatusSnapshot,
        now: Date = Date(),
        language: AppLanguage,
        text: TaskStatusPresentationText
    ) -> String {
        switch task.status {
        case .running:
            return replacing(
                text.runningFormat,
                values: [
                    "duration": durationString(
                        max(0, now.timeIntervalSince(task.startedAt)),
                        language: language
                    ),
                    "relative": relativeTime(
                        from: task.startedAt,
                        to: now,
                        language: language,
                        justNow: text.justNow
                    )
                ]
            )
        case .done:
            let referenceDate = task.endedAt ?? task.startedAt
            let relative = relativeTime(
                from: referenceDate,
                to: now,
                language: language,
                justNow: text.justNow
            )
            guard let duration = task.duration else {
                return relative
            }
            return replacing(
                text.completedWithDurationFormat,
                values: [
                    "relative": relative,
                    "duration": durationString(duration, language: language)
                ]
            )
        case .failed:
            let referenceDate = task.endedAt ?? task.startedAt
            let relative = relativeTime(
                from: referenceDate,
                to: now,
                language: language,
                justNow: text.justNow
            )
            guard let exitCode = task.exitCode else {
                return relative
            }
            return replacing(
                text.failedWithExitCodeFormat,
                values: [
                    "relative": relative,
                    "exitCode": String(exitCode)
                ]
            )
        case .interrupted:
            return text.interrupted
        }
    }

    public static func relativeTime(
        from date: Date,
        to now: Date = Date(),
        language: AppLanguage,
        justNow: String
    ) -> String {
        let interval = now.timeIntervalSince(date)
        if interval >= 0, interval < 60 {
            return justNow
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = language.locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: date, relativeTo: now)
    }

    public static func durationString(
        _ interval: TimeInterval,
        language: AppLanguage
    ) -> String {
        let totalSeconds = Int(max(0, interval).rounded(.down))
        if totalSeconds < 3_600 {
            return String(
                format: "%d:%02d",
                totalSeconds / 60,
                totalSeconds % 60
            )
        }
        let totalMinutes = totalSeconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        switch language {
        case .simplifiedChinese:
            if hours >= 24 {
                return "\(hours / 24) 天 \(hours % 24) 小时"
            }
            return "\(hours) 小时 \(minutes) 分钟"
        case .english:
            if hours >= 24 {
                return "\(hours / 24)d \(hours % 24)h"
            }
            return "\(hours)h \(minutes)m"
        }
    }

    public static func runningCount(in tasks: [TaskStatusSnapshot]) -> Int {
        tasks.count { $0.status == .running }
    }

    private static func replacing(
        _ template: String,
        values: [String: String]
    ) -> String {
        values.reduce(template) { result, pair in
            result.replacingOccurrences(
                of: "{\(pair.key)}",
                with: pair.value
            )
        }
    }
}
