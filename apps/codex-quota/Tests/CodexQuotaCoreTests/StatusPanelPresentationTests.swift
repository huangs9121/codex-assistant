import CodexQuotaCore
import CodexQuotaUI
import Foundation

enum StatusPanelPresentationTests {
    static let all: [TaskStatusParserTestCase] = [
        TaskStatusParserTestCase(
            name: "status panel running task subtitle",
            run: testRunningSubtitle
        ),
        TaskStatusParserTestCase(
            name: "status panel completed task subtitle with and without duration",
            run: testCompletedSubtitles
        ),
        TaskStatusParserTestCase(
            name: "status panel failed task subtitle with and without exit code",
            run: testFailedSubtitles
        ),
        TaskStatusParserTestCase(
            name: "status panel interrupted task subtitle",
            run: testInterruptedSubtitle
        ),
        TaskStatusParserTestCase(
            name: "status panel relative time localizes now and minutes",
            run: testRelativeTime
        ),
        TaskStatusParserTestCase(
            name: "status panel counts running tasks",
            run: testRunningCount
        ),
        TaskStatusParserTestCase(
            name: "status panel duration string switches to hours and days",
            run: testDurationStringTiers
        ),
        TaskStatusParserTestCase(
            name: "status panel falls back to one quota window",
            run: testSingleWindowFallback
        ),
        TaskStatusParserTestCase(
            name: "status panel orders quota windows by duration",
            run: testWindowOrdering
        ),
        TaskStatusParserTestCase(
            name: "status panel reset countdown formats hour boundary",
            run: testResetCountdown
        ),
        TaskStatusParserTestCase(
            name: "status panel weekly reset follows locale and time zone",
            run: testWeeklyReset
        ),
        TaskStatusParserTestCase(
            name: "reset forecast quiet state is always present",
            run: testQuietResetForecast
        ),
        TaskStatusParserTestCase(
            name: "reset forecast proposal state",
            run: testProposalResetForecast
        ),
        TaskStatusParserTestCase(
            name: "reset forecast announced state",
            run: testAnnouncedResetForecast
        ),
        TaskStatusParserTestCase(
            name: "reset forecast completed state",
            run: testCompletedResetForecast
        ),
        TaskStatusParserTestCase(
            name: "expired reset forecast falls back to quiet",
            run: testExpiredResetForecast
        ),
        TaskStatusParserTestCase(
            name: "reset forecast countdown covers all boundaries",
            run: testResetForecastCountdownBoundaries
        ),
        TaskStatusParserTestCase(
            name: "reset forecast notification deduplicates by id and kind",
            run: testResetNotificationKey
        ),
        TaskStatusParserTestCase(
            name: "quota panel supports primary window only",
            run: testPrimaryWindowOnly
        ),
        TaskStatusParserTestCase(
            name: "quota panel supports secondary window only",
            run: testSecondaryWindowOnly
        ),
        TaskStatusParserTestCase(
            name: "quota panel supports both windows",
            run: testBothWindows
        ),
        TaskStatusParserTestCase(
            name: "quota panel supports no windows",
            run: testNoWindows
        ),
        TaskStatusParserTestCase(
            name: "quota panel classifies five hour weekly and generic windows",
            run: testWindowKinds
        )
    ]

    private static let now = Date(timeIntervalSince1970: 2_000_000_000)
    private static let chineseText = TaskStatusPresentationText(
        justNow: "刚刚",
        runningFormat: "已运行 {duration} · {relative}开始",
        completedWithDurationFormat: "{relative} · 耗时 {duration}",
        failedWithExitCodeFormat: "{relative} · 退出码 {exitCode}",
        interrupted: "已中断"
    )

    private static func testRunningSubtitle() -> Bool {
        let task = snapshot(
            startedAt: now.addingTimeInterval(-30),
            status: .running
        )
        return TaskStatusPresentationFormatter.subtitle(
            for: task,
            now: now,
            language: .simplifiedChinese,
            text: chineseText
        ) == "已运行 0:30 · 刚刚开始"
    }

    private static func testCompletedSubtitles() -> Bool {
        let withDuration = snapshot(
            startedAt: now.addingTimeInterval(-95),
            endedAt: now.addingTimeInterval(-30),
            status: .done,
            exitCode: 0
        )
        let withoutDuration = snapshot(
            startedAt: now.addingTimeInterval(-30),
            status: .done,
            exitCode: 0
        )
        return TaskStatusPresentationFormatter.subtitle(
            for: withDuration,
            now: now,
            language: .simplifiedChinese,
            text: chineseText
        ) == "刚刚 · 耗时 1:05"
            && TaskStatusPresentationFormatter.subtitle(
                for: withoutDuration,
                now: now,
                language: .simplifiedChinese,
                text: chineseText
            ) == "刚刚"
    }

    private static func testFailedSubtitles() -> Bool {
        let withExitCode = snapshot(
            startedAt: now.addingTimeInterval(-90),
            endedAt: now.addingTimeInterval(-30),
            status: .failed,
            exitCode: 7
        )
        let withoutExitCode = snapshot(
            startedAt: now.addingTimeInterval(-30),
            status: .failed
        )
        return TaskStatusPresentationFormatter.subtitle(
            for: withExitCode,
            now: now,
            language: .simplifiedChinese,
            text: chineseText
        ) == "刚刚 · 退出码 7"
            && TaskStatusPresentationFormatter.subtitle(
                for: withoutExitCode,
                now: now,
                language: .simplifiedChinese,
                text: chineseText
            ) == "刚刚"
    }

    private static func testInterruptedSubtitle() -> Bool {
        let task = snapshot(
            startedAt: now.addingTimeInterval(-30),
            status: .interrupted
        )
        return TaskStatusPresentationFormatter.subtitle(
            for: task,
            now: now,
            language: .simplifiedChinese,
            text: chineseText
        ) == "已中断"
    }

    private static func testRelativeTime() -> Bool {
        let justNow = TaskStatusPresentationFormatter.relativeTime(
            from: now.addingTimeInterval(-59),
            to: now,
            language: .simplifiedChinese,
            justNow: "刚刚"
        )
        let minutes = TaskStatusPresentationFormatter.relativeTime(
            from: now.addingTimeInterval(-120),
            to: now,
            language: .english,
            justNow: "Just now"
        )
        return justNow == "刚刚" && minutes == "2 minutes ago"
    }

    private static func testDurationStringTiers() -> Bool {
        let formatter = TaskStatusPresentationFormatter.self
        return formatter.durationString(30, language: .simplifiedChinese)
            == "0:30"
            && formatter.durationString(599, language: .english) == "9:59"
            && formatter.durationString(3_600, language: .simplifiedChinese)
                == "1 小时 0 分钟"
            && formatter.durationString(5_430, language: .simplifiedChinese)
                == "1 小时 30 分钟"
            && formatter.durationString(5_430, language: .english) == "1h 30m"
            && formatter.durationString(90_306, language: .simplifiedChinese)
                == "1 天 1 小时"
            && formatter.durationString(90_306, language: .english) == "1d 1h"
    }

    private static func testRunningCount() -> Bool {
        let tasks = [
            snapshot(startedAt: now, status: .running),
            snapshot(startedAt: now, status: .done, exitCode: 0),
            snapshot(startedAt: now, status: .running),
            snapshot(startedAt: now, status: .failed, exitCode: 1)
        ]
        return TaskStatusPresentationFormatter.runningCount(in: tasks) == 2
    }

    private static func testSingleWindowFallback() -> Bool {
        let snapshot = QuotaSnapshot(
            remainingPercent: 72,
            observedAt: now,
            resetsAt: now.addingTimeInterval(3_600),
            windowDuration: 5 * 3_600,
            planName: "Pro",
            secondaryWindow: nil
        )
        let data = StatusPanelQuotaData(snapshot: snapshot, now: now)
        return data.primaryWindow?.remainingPercent == 72
            && data.primaryWindow?.windowDuration == 5 * 3_600
            && data.secondaryWindow == nil
            && data.planName == "Pro"
            && data.observedAt == now
    }

    private static func testWindowOrdering() -> Bool {
        let snapshot = QuotaSnapshot(
            remainingPercent: 30,
            observedAt: now,
            resetsAt: now.addingTimeInterval(7 * 86_400),
            windowDuration: 7 * 86_400,
            secondaryWindow: QuotaWindow(
                usedPercent: 25,
                resetsAt: now.addingTimeInterval(3_600),
                windowDuration: 5 * 3_600
            )
        )
        let data = StatusPanelQuotaData(snapshot: snapshot, now: now)
        return data.primaryWindow?.remainingPercent == 75
            && data.primaryWindow?.windowDuration == 5 * 3_600
            && data.secondaryWindow?.remainingPercent == 30
            && data.secondaryWindow?.windowDuration == 7 * 86_400
    }

    private static func testResetCountdown() -> Bool {
        let overAnHour = ResetCountdownFormatter.panelCountdownValue(
            resetsAt: now.addingTimeInterval(3_600 + 5 * 60),
            now: now,
            language: .simplifiedChinese
        )
        let underAnHour = ResetCountdownFormatter.panelCountdownValue(
            resetsAt: now.addingTimeInterval(59 * 60),
            now: now,
            language: .english
        )
        return overAnHour == "1 小时 5 分钟"
            && underAnHour == "59m"
    }

    private static func testWeeklyReset() -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)
        components.year = 2026
        components.month = 8
        components.day = 1
        components.hour = 8
        components.minute = 30
        guard let reset = components.date else {
            return false
        }
        return ResetCountdownFormatter.weeklyResetValue(
            resetsAt: reset,
            timeZone: components.timeZone!,
            language: .simplifiedChinese
        ) == "周六 08:30"
            && ResetCountdownFormatter.weeklyResetValue(
                resetsAt: reset,
                timeZone: components.timeZone!,
                language: .english
            ) == "Sat 08:30"
    }

    private static func testQuietResetForecast() -> Bool {
        let forecast = StatusPanelResetForecast(
            signal: nil,
            quotaSnapshot: nil,
            now: now
        )
        return forecast.state == .quiet && forecast.signal == nil
    }

    private static func testProposalResetForecast() -> Bool {
        let signal = resetSignal(kind: .proposal)
        let forecast = StatusPanelResetForecast(
            signal: signal,
            quotaSnapshot: nil,
            now: now
        )
        return forecast.state == .proposal && forecast.signal == signal
    }

    private static func testAnnouncedResetForecast() -> Bool {
        let signal = resetSignal(kind: .announced)
        let forecast = StatusPanelResetForecast(
            signal: signal,
            quotaSnapshot: nil,
            now: now
        )
        return forecast.state == .announced && forecast.signal == signal
    }

    private static func testCompletedResetForecast() -> Bool {
        let signal = resetSignal(kind: .completed, expectedAt: nil)
        let forecast = StatusPanelResetForecast(
            signal: signal,
            quotaSnapshot: nil,
            now: now
        )
        return forecast.state == .completed && forecast.signal == signal
    }

    private static func testExpiredResetForecast() -> Bool {
        let signal = resetSignal(
            kind: .announced,
            expectedAt: now.addingTimeInterval(-1)
        )
        let forecast = StatusPanelResetForecast(
            signal: signal,
            quotaSnapshot: nil,
            now: now
        )
        return forecast.state == .quiet && forecast.signal == nil
    }

    private static func testResetForecastCountdownBoundaries() -> Bool {
        let text = ResetForecastCountdownText(
            hoursMinutesFormat: "{hours}h {minutes}m left",
            minutesFormat: "{minutes}m left",
            imminent: "imminent"
        )
        return ResetForecastCountdownFormatter.string(
            until: now.addingTimeInterval(2 * 3_600 + 5 * 60),
            now: now,
            text: text
        ) == "2h 5m left"
            && ResetForecastCountdownFormatter.string(
                until: now.addingTimeInterval(59 * 60),
                now: now,
                text: text
            ) == "59m left"
            && ResetForecastCountdownFormatter.string(
                until: now.addingTimeInterval(59),
                now: now,
                text: text
            ) == "imminent"
            && ResetForecastCountdownFormatter.string(
                until: now.addingTimeInterval(-1),
                now: now,
                text: text
            ) == "imminent"
    }

    private static func testResetNotificationKey() -> Bool {
        let proposal = TiboResetNotificationKey(
            signal: resetSignal(kind: .proposal)
        )
        let sameProposal = TiboResetNotificationKey(
            signal: resetSignal(kind: .proposal)
        )
        let announced = TiboResetNotificationKey(
            signal: resetSignal(kind: .announced)
        )
        return !sameProposal.shouldNotify(after: proposal)
            && announced.shouldNotify(after: proposal)
            && TiboResetNotificationKey(
                storageValue: announced.storageValue
            ) == announced
    }

    private static func testPrimaryWindowOnly() -> Bool {
        let data = quotaData(primary: quotaWindow(remainingPercent: 80))
        return data.primaryWindow != nil && data.secondaryWindow == nil
    }

    private static func testSecondaryWindowOnly() -> Bool {
        let data = quotaData(secondary: quotaWindow(remainingPercent: 70))
        return data.primaryWindow == nil && data.secondaryWindow != nil
    }

    private static func testBothWindows() -> Bool {
        let data = quotaData(
            primary: quotaWindow(remainingPercent: 80),
            secondary: quotaWindow(remainingPercent: 70)
        )
        return data.primaryWindow != nil && data.secondaryWindow != nil
    }

    private static func testNoWindows() -> Bool {
        let data = quotaData()
        return data.primaryWindow == nil && data.secondaryWindow == nil
    }

    private static func testWindowKinds() -> Bool {
        StatusPanelQuotaWindowKind(windowDuration: 5 * 3_600) == .fiveHour
            && StatusPanelQuotaWindowKind(
                windowDuration: 7 * 86_400
            ) == .weekly
            && StatusPanelQuotaWindowKind(windowDuration: 12 * 3_600) == .generic
            && StatusPanelQuotaWindowKind(windowDuration: nil) == .generic
    }

    private static func resetSignal(
        kind: TiboResetSignalKind,
        expectedAt: Date? = now.addingTimeInterval(3_600)
    ) -> TiboResetSignal {
        TiboResetSignal(
            id: "same-signal",
            kind: kind,
            publishedAt: now.addingTimeInterval(-60),
            text: "Reset signal",
            url: URL(string: "https://x.com/thsottiaux/status/123")!,
            signalStrength: 80,
            expectedAt: expectedAt,
            expectationHint: nil
        )
    }

    private static func quotaWindow(
        remainingPercent: Int
    ) -> StatusPanelQuotaWindow {
        StatusPanelQuotaWindow(
            remainingPercent: remainingPercent,
            resetsAt: now.addingTimeInterval(3_600),
            windowDuration: 5 * 3_600
        )
    }

    private static func quotaData(
        primary: StatusPanelQuotaWindow? = nil,
        secondary: StatusPanelQuotaWindow? = nil
    ) -> StatusPanelQuotaData {
        StatusPanelQuotaData(
            planName: nil,
            observedAt: now,
            primaryWindow: primary,
            secondaryWindow: secondary
        )
    }

    private static func snapshot(
        startedAt: Date,
        endedAt: Date? = nil,
        status: TaskExecutionStatus,
        exitCode: Int? = nil
    ) -> TaskStatusSnapshot {
        TaskStatusSnapshot(
            id: UUID().uuidString,
            startedAt: startedAt,
            sessionUUID: nil,
            mode: .sync,
            taskName: "Test",
            isBackgroundTask: false,
            status: status,
            exitCode: exitCode,
            lastMessage: nil,
            endedAt: endedAt
        )
    }
}
