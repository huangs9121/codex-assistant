import Darwin
import AppKit
import Foundation
import CodexQuotaCore
import CodexQuotaUI

@main
enum QuotaParserTests {
    private typealias TestCase = (name: String, run: () -> Bool)

    static func main() {
        let tests: [TestCase] = [
            ("primary used 40 leaves 60", testPrimaryUsedPercent),
            ("highest used percent wins", testHighestUsedPercent),
            ("known plan names are normalized", testKnownPlanNames),
            ("unknown and missing plan names are nil", testUnknownAndMissingPlanNames),
            ("matching active subscription expiry is returned", testMatchingSubscriptionExpiry),
            ("fractional subscription expiry is returned", testFractionalSubscriptionExpiry),
            ("subscription expiry requires matching known plans", testSubscriptionExpiryPlanValidation),
            ("subscription expiry must be in the future", testSubscriptionExpiryDateValidation),
            ("malformed subscription JWTs are rejected", testMalformedSubscriptionJWTs),
            ("standard Base64 JWT payload characters are rejected", testStandardBase64JWTPayloadCharacters),
            ("JWT payload padding and invalid lengths are rejected", testJWTPayloadPaddingAndLength),
            ("missing subscription auth claims are rejected", testMissingSubscriptionAuthClaims),
            ("prolite snapshot carries Pro plan", testProliteSnapshotPlan),
            ("unknown plan keeps snapshot valid", testUnknownPlanKeepsSnapshotValid),
            ("primary window carries its reset", testPrimaryWindowReset),
            ("secondary window carries its reset", testSecondaryWindowReset),
            ("missing reset keeps snapshot valid", testMissingReset),
            ("invalid reset keeps snapshot valid", testInvalidReset),
            ("boolean reset is rejected", testBooleanReset),
            ("huge reset is rejected", testHugeReset),
            ("negative reset is rejected", testNegativeReset),
            ("equal usage chooses primary reset", testEqualUsageChoosesPrimaryReset),
            ("scheduled reset restores displayed quota", testScheduledResetRestoresQuota),
            ("future reset preserves snapshot quota", testFutureResetPreservesQuota),
            ("missing reset countdown is unknown", testMissingResetCountdown),
            ("reset countdown formats days and hours", testResetCountdownDaysAndHours),
            ("reset countdown formats hours only", testResetCountdownHoursOnly),
            ("expired reset countdown clamps to zero", testExpiredResetCountdown),
            ("huge reset countdown is unknown", testHugeResetCountdown),
            ("compact reset countdown formats day and hour boundaries", testCompactResetCountdownBoundaries),
            ("compact reset countdown handles zero and unknown values", testCompactResetCountdownFallbacks),
            ("negative used clamps to 100", testNegativeUsedPercent),
            ("used above 100 clamps to 0", testUsedPercentAboveOneHundred),
            ("invalid JSON returns nil", testInvalidJSON),
            ("non-token-count returns nil", testNonTokenCountEvent),
            ("missing rate limits returns nil", testMissingRateLimits),
            ("invalid timestamp returns nil", testInvalidTimestamp),
            ("standard internet date is accepted", testStandardInternetDate),
            ("newest observed snapshot wins across nested files", testNewestObservedSnapshotWins),
            ("empty root returns nil", testEmptyRoot),
            ("latest valid event wins within a file", testLatestValidEventInFile),
            ("truncated large-file prefix is ignored", testTruncatedLargeFilePrefix),
            ("whole-file first line is preserved", testWholeFileFirstLine),
            ("exact four MiB line boundary preserves first event", testExactFourMiBLineBoundary),
            ("UTF-8 split before newline preserves later event", testUTF8SplitBeforeNewline),
            ("tail search expands beyond sixty-four KiB", testTailSearchExpansion),
            ("equal modification dates use stable path tie-break", testStableTopFiftyTieBreak),
            ("corrupt file is skipped", testCorruptFileIsSkipped),
            ("renderer shows unknown quota", testRendererUnknown),
            ("renderer shows empty bar at zero", testRendererZero),
            ("renderer shows six filled segments at sixty", testRendererSixty),
            ("renderer rounds sixty-five to seven segments", testRendererSixtyFive),
            ("renderer shows full bar at one hundred", testRendererOneHundred),
            ("battery style defaults to native", testDefaultBatteryStyle),
            ("battery styles have stable order and raw values", testBatteryStyleCases),
            ("battery styles have exact menu titles", testBatteryStyleMenuTitles),
            ("status identity modes have stable order and raw values", testStatusIdentityModeCases),
            ("status identity modes have exact menu titles", testStatusIdentityModeMenuTitles),
            ("update time includes seconds", testUpdateTimeIncludesSeconds),
            ("update time label describes the latest refresh", testUpdateTimeLabel),
            ("missing update time uses second precision placeholder", testMissingUpdateTime),
            ("Codex label defaults to visible", testDefaultCodexLabel),
            ("launch notice defaults to not shown", testLaunchNoticeDefaultsToNotShown),
            ("launch notice dismissal persists", testLaunchNoticeDismissalPersists),
            ("display preferences persist across instances", testDisplayPreferencesPersistence),
            ("invalid stored battery style falls back to native", testInvalidBatteryStyleFallback),
            ("stored false label preference is preserved", testStoredFalseCodexLabel),
            ("identity mode defaults to text and writes the new key", testDefaultIdentityModeMigration),
            ("legacy true identity preference migrates to text", testLegacyTrueIdentityMigration),
            ("legacy false identity preference migrates to hidden", testLegacyFalseIdentityMigration),
            ("legacy string identity preference migrates to text", testLegacyStringIdentityMigration),
            ("legacy numeric identity preference migrates to text", testLegacyNumericIdentityMigration),
            ("valid new identity preference takes priority", testValidNewIdentityPreferencePriority),
            ("invalid new identity preference falls back without migration", testInvalidNewIdentityPreferenceFallback),
            ("identity mode persists across instances", testIdentityModePersistence),
            ("reset countdown status preference defaults to false", testDefaultResetCountdownStatusPreference),
            ("reset countdown status preference persists true", testResetCountdownStatusPreferencePersistence),
            ("launch agent file installs a valid login item", testLaunchAgentFileInstall),
            ("launch agent file uninstalls cleanly", testLaunchAgentFileUninstall),
            ("semantic versions accept exact numeric triples", testSemanticVersionAcceptedValues),
            ("semantic versions reject malformed values", testSemanticVersionRejectedValues),
            ("semantic versions compare components numerically", testSemanticVersionComparison),
            ("GitHub releases decode required fields", testGitHubReleaseDecoding),
            ("GitHub release eligibility rejects unsafe releases", testGitHubReleaseEligibility),
            ("GitHub release decoding rejects invalid fixtures", testGitHubReleaseInvalidDecoding),
            ("latest release request contains only public metadata", testLatestReleaseRequest),
            ("update check policy enforces success and failure throttles", testUpdateCheckPolicy),
            ("update prompt policy normalizes semantic versions", testUpdatePromptPolicy),
            ("update preferences persist typed optional values", testUpdatePreferences),
            ("OpenAI logo is a centered template glyph with safe margins", testOpenAILogoRendering),
            ("status presentation supports every style identity and reset combination", testStatusPresentationMatrix),
            ("status identity and reset widths compose exactly", testStatusPresentationWidthRelationships),
            ("status presentation exposes identity and reset accessibility semantics", testStatusPresentationAccessibility),
            ("battery renderer produces template glyphs for every style and value", testBatteryRendererImageMatrix),
            ("full status images compose label battery and percent in order", testFullStatusComposition),
            ("full status images keep safe margins at one and two x", testFullStatusCanvasMargins),
            ("battery renderer exposes exact accessibility semantics", testBatteryRendererAccessibility),
            ("battery renderer clamps values outside zero through one hundred", testBatteryRendererClamping),
            ("native battery fill changes with percentage", testNativeBatteryFillChanges),
            ("embedded battery renders its value inside the image", testEmbeddedBatteryValueChanges),
            ("segmented battery changes only across segment boundaries", testSegmentedBatteryBoundaries),
            ("battery artwork keeps safe transparent canvas margins", testBatteryCanvasMargins),
            ("battery outlines and terminals remain visible", testBatteryOutlineAndTerminalVisibility),
            ("native battery fill coverage increases continuously", testNativeBatteryFillCoverage),
            ("embedded values retain readable template contrast", testEmbeddedValueContrast),
            ("segmented battery cell centers match filled segment counts", testSegmentedCellCenters),
            ("battery artwork maintains reasonable alpha coverage", testBatteryAlphaCoverage)
        ]

        var failureCount = 0
        for test in tests {
            if test.run() {
                print("PASS: \(test.name)")
            } else {
                print("FAIL: \(test.name)")
                failureCount += 1
            }
        }

        guard failureCount == 0 else {
            print("\(failureCount) tests failed")
            exit(1)
        }

        print("\(tests.count) tests passed")
    }

    private static func testPrimaryUsedPercent() -> Bool {
        let snapshot = QuotaParser.snapshot(from: tokenCountLine(primary: 40))
        let expectedDate = fractionalDate("2026-07-14T08:30:00.123Z")
        return expect(snapshot?.remainingPercent, equals: 60)
            && expect(snapshot?.observedAt, equals: expectedDate)
    }

    private static func testHighestUsedPercent() -> Bool {
        let snapshot = QuotaParser.snapshot(
            from: tokenCountLine(primary: 20, secondary: 75)
        )
        return expect(snapshot?.remainingPercent, equals: 25)
    }

    private static func testKnownPlanNames() -> Bool {
        let cases: [(String, String)] = [
            ("prolite", "Pro"),
            ("pro", "Pro"),
            ("plus", "Plus"),
            ("free", "Free"),
            ("team", "Team"),
            ("business", "Business"),
            ("enterprise", "Enterprise"),
            ("  PROLITE\n", "Pro")
        ]
        return cases.allSatisfy { rawValue, expected in
            expect(PlanInfo.normalizedName(rawValue), equals: expected)
        }
    }

    private static func testUnknownAndMissingPlanNames() -> Bool {
        expect(PlanInfo.normalizedName("unknown"), equals: nil)
            && expect(PlanInfo.normalizedName(nil), equals: nil)
    }

    private static func testMatchingSubscriptionExpiry() -> Bool {
        let expiry = "2026-08-01T00:00:00Z"
        let authData = subscriptionAuthData(plan: "prolite", expiry: expiry)
        return expect(
            PlanInfo.subscriptionExpiry(
                authData: authData,
                currentPlan: "Pro",
                now: standardDate("2026-07-15T00:00:00Z")!
            ),
            equals: standardDate(expiry)
        )
    }

    private static func testFractionalSubscriptionExpiry() -> Bool {
        let expiry = "2026-08-01T00:00:00.123Z"
        return expect(
            PlanInfo.subscriptionExpiry(
                authData: subscriptionAuthData(plan: "prolite", expiry: expiry),
                currentPlan: "Pro",
                now: standardDate("2026-07-15T00:00:00Z")!
            ),
            equals: fractionalDate(expiry)
        )
    }

    private static func testSubscriptionExpiryPlanValidation() -> Bool {
        let now = standardDate("2026-07-15T00:00:00Z")!
        return expect(
            PlanInfo.subscriptionExpiry(
                authData: subscriptionAuthData(plan: "plus", expiry: "2026-08-01T00:00:00Z"),
                currentPlan: "Pro",
                now: now
            ),
            equals: nil
        ) && expect(
            PlanInfo.subscriptionExpiry(
                authData: subscriptionAuthData(plan: "unknown", expiry: "2026-08-01T00:00:00Z"),
                currentPlan: "Pro",
                now: now
            ),
            equals: nil
        ) && expect(
            PlanInfo.subscriptionExpiry(
                authData: subscriptionAuthData(plan: "prolite", expiry: "2026-08-01T00:00:00Z"),
                currentPlan: nil,
                now: now
            ),
            equals: nil
        )
    }

    private static func testSubscriptionExpiryDateValidation() -> Bool {
        let now = standardDate("2026-07-15T00:00:00Z")!
        return [
            "2026-07-14T23:59:59Z",
            "2026-07-15T00:00:00Z",
            "not-a-date"
        ].allSatisfy { expiry in
            expect(
                PlanInfo.subscriptionExpiry(
                    authData: subscriptionAuthData(plan: "prolite", expiry: expiry),
                    currentPlan: "Pro",
                    now: now
                ),
                equals: nil
            )
        }
    }

    private static func testMalformedSubscriptionJWTs() -> Bool {
        let now = standardDate("2026-07-15T00:00:00Z")!
        let nonJSONPayload = base64URL(Data("not json".utf8))
        let tokens = [
            "header.payload",
            "header.payload.signature.extra",
            "header.***.signature",
            "header.\(nonJSONPayload).signature"
        ]
        return tokens.allSatisfy { token in
            expect(
                PlanInfo.subscriptionExpiry(
                    authData: authData(idToken: token),
                    currentPlan: "Pro",
                    now: now
                ),
                equals: nil
            )
        }
    }

    private static func testStandardBase64JWTPayloadCharacters() -> Bool {
        let now = standardDate("2026-07-15T00:00:00Z")!
        let cases: [(nonce: String, forbiddenCharacter: Character)] = [
            ("ƛ씻", "+"),
            ("欿粶", "/")
        ]
        return cases.allSatisfy { testCase in
            let token = standardBase64JWT(payload: subscriptionPayload(
                plan: "prolite",
                expiry: "2026-08-01T00:00:00Z",
                nonce: testCase.nonce
            ))
            let payloadSegment = token.components(separatedBy: ".")[1]
            guard payloadSegment.contains(testCase.forbiddenCharacter) else {
                return diagnostic("test JWT does not contain \(testCase.forbiddenCharacter)")
            }
            return expect(
                PlanInfo.subscriptionExpiry(
                    authData: authData(idToken: token),
                    currentPlan: "Pro",
                    now: now
                ),
                equals: nil
            )
        }
    }

    private static func testJWTPayloadPaddingAndLength() -> Bool {
        let now = standardDate("2026-07-15T00:00:00Z")!
        let validToken = fakeJWT(payload: subscriptionPayload(
            plan: "prolite",
            expiry: "2026-08-01T00:00:00Z"
        ))
        let validSegment = validToken.components(separatedBy: ".")[1]
        let invalidSegments = [
            validSegment + "=",
            validSegment + "=====",
            validSegment + "AA"
        ]
        guard invalidSegments[2].count % 4 == 1 else {
            return diagnostic("test JWT payload does not have invalid Base64URL length")
        }
        return invalidSegments.allSatisfy { segment in
            expect(
                PlanInfo.subscriptionExpiry(
                    authData: authData(idToken: "header.\(segment).signature"),
                    currentPlan: "Pro",
                    now: now
                ),
                equals: nil
            )
        }
    }

    private static func testMissingSubscriptionAuthClaims() -> Bool {
        let now = standardDate("2026-07-15T00:00:00Z")!
        let validNamespace: [String: Any] = [
            "chatgpt_plan_type": "prolite",
            "chatgpt_subscription_active_until": "2026-08-01T00:00:00Z"
        ]
        let authCases: [Data] = [
            Data("not json".utf8),
            jsonData([:]),
            jsonData(["tokens": [:]]),
            jsonData(["tokens": ["id_token": 123]]),
            authData(idToken: fakeJWT(payload: [:])),
            authData(idToken: fakeJWT(payload: ["https://api.openai.com/auth": [
                "chatgpt_subscription_active_until": "2026-08-01T00:00:00Z"
            ]])),
            authData(idToken: fakeJWT(payload: ["https://api.openai.com/auth": [
                "chatgpt_plan_type": "prolite"
            ]])),
            authData(idToken: fakeJWT(payload: ["wrong_namespace": validNamespace]))
        ]
        return authCases.allSatisfy { authData in
            expect(
                PlanInfo.subscriptionExpiry(
                    authData: authData,
                    currentPlan: "Pro",
                    now: now
                ),
                equals: nil
            )
        }
    }

    private static func testProliteSnapshotPlan() -> Bool {
        let snapshot = QuotaParser.snapshot(
            from: tokenCountLine(primary: 40, planType: "prolite")
        )
        return expect(snapshot?.planName, equals: "Pro")
    }

    private static func testUnknownPlanKeepsSnapshotValid() -> Bool {
        let snapshot = QuotaParser.snapshot(
            from: tokenCountLine(primary: 40, planType: "unknown")
        )
        return expect(snapshot?.remainingPercent, equals: 60)
            && expect(snapshot?.planName, equals: nil)
    }

    private static func testPrimaryWindowReset() -> Bool {
        let snapshot = QuotaParser.snapshot(from: tokenCountLine(
            primary: 75,
            primaryReset: 1_800_000_000,
            secondary: 20,
            secondaryReset: 1_900_000_000
        ))
        return expect(snapshot?.remainingPercent, equals: 25)
            && expect(snapshot?.resetsAt, equals: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private static func testSecondaryWindowReset() -> Bool {
        let snapshot = QuotaParser.snapshot(from: tokenCountLine(
            primary: 20,
            primaryReset: 1_800_000_000,
            secondary: 75,
            secondaryReset: 1_900_000_000
        ))
        return expect(snapshot?.remainingPercent, equals: 25)
            && expect(snapshot?.resetsAt, equals: Date(timeIntervalSince1970: 1_900_000_000))
    }

    private static func testMissingReset() -> Bool {
        let snapshot = QuotaParser.snapshot(from: tokenCountLine(primary: 40))
        return expect(snapshot?.remainingPercent, equals: 60)
            && expect(snapshot?.resetsAt, equals: nil)
    }

    private static func testInvalidReset() -> Bool {
        let snapshot = QuotaParser.snapshot(from: tokenCountLine(
            primary: 40,
            primaryReset: "invalid"
        ))
        return expect(snapshot?.remainingPercent, equals: 60)
            && expect(snapshot?.resetsAt, equals: nil)
    }

    private static func testBooleanReset() -> Bool {
        let snapshot = QuotaParser.snapshot(from: tokenCountLine(
            primary: 40,
            primaryReset: true
        ))
        return expect(snapshot?.remainingPercent, equals: 60)
            && expect(snapshot?.resetsAt, equals: nil)
    }

    private static func testHugeReset() -> Bool {
        let snapshot = QuotaParser.snapshot(from: tokenCountLine(
            primary: 40,
            primaryReset: 1e308
        ))
        return expect(snapshot?.remainingPercent, equals: 60)
            && expect(snapshot?.resetsAt, equals: nil)
    }

    private static func testNegativeReset() -> Bool {
        let snapshot = QuotaParser.snapshot(from: tokenCountLine(
            primary: 40,
            primaryReset: -1
        ))
        return expect(snapshot?.remainingPercent, equals: 60)
            && expect(snapshot?.resetsAt, equals: nil)
    }

    private static func testEqualUsageChoosesPrimaryReset() -> Bool {
        let snapshot = QuotaParser.snapshot(from: tokenCountLine(
            primary: 40,
            primaryReset: 1_800_000_000,
            secondary: 40,
            secondaryReset: 1_900_000_000
        ))
        return expect(snapshot?.resetsAt, equals: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private static func testScheduledResetRestoresQuota() -> Bool {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = QuotaSnapshot(
            remainingPercent: 17,
            observedAt: reset.addingTimeInterval(-60),
            resetsAt: reset
        )
        return expect(snapshot.remainingPercent(at: reset), equals: 100)
            && expect(snapshot.remainingPercent(at: reset.addingTimeInterval(1)), equals: 100)
            && expect(snapshot.resetDate(at: reset), equals: nil)
    }

    private static func testFutureResetPreservesQuota() -> Bool {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(60)
        let snapshot = QuotaSnapshot(
            remainingPercent: 17,
            observedAt: now,
            resetsAt: reset
        )
        return expect(snapshot.remainingPercent(at: now), equals: 17)
            && expect(snapshot.resetDate(at: now), equals: reset)
    }

    private static func testResetCountdownDaysAndHours() -> Bool {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return expect(
            ResetCountdownFormatter.string(
                resetsAt: now.addingTimeInterval((2 * 24 + 3) * 60 * 60),
                now: now
            ),
            equals: "2 天 3 小时"
        )
    }

    private static func testMissingResetCountdown() -> Bool {
        expect(ResetCountdownFormatter.string(resetsAt: nil), equals: "--")
    }

    private static func testResetCountdownHoursOnly() -> Bool {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return expect(
            ResetCountdownFormatter.string(
                resetsAt: now.addingTimeInterval(4 * 60 * 60 + 59 * 60),
                now: now
            ),
            equals: "0 天 4 小时"
        )
    }

    private static func testExpiredResetCountdown() -> Bool {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return expect(
            ResetCountdownFormatter.string(resetsAt: now.addingTimeInterval(-1), now: now),
            equals: "0 天 0 小时"
        )
    }

    private static func testHugeResetCountdown() -> Bool {
        expect(
            ResetCountdownFormatter.string(
                resetsAt: Date(timeIntervalSince1970: 1e308),
                now: Date(timeIntervalSince1970: 0)
            ),
            equals: "--"
        )
    }

    private static func testCompactResetCountdownBoundaries() -> Bool {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cases: [(TimeInterval, String)] = [
            (51 * 60 * 60, "2D"),
            (24 * 60 * 60, "1D"),
            (23 * 60 * 60 + 59 * 60, "23H"),
            (60 * 60, "1H"),
            (59 * 60, "0H"),
            (-1, "0H")
        ]
        return cases.allSatisfy { interval, expected in
            expect(
                ResetCountdownFormatter.compactString(
                    resetsAt: now.addingTimeInterval(interval),
                    now: now
                ),
                equals: expected
            )
        }
    }

    private static func testCompactResetCountdownFallbacks() -> Bool {
        let now = Date(timeIntervalSince1970: 0)
        return expect(ResetCountdownFormatter.compactString(resetsAt: nil), equals: "--")
            && expect(
                ResetCountdownFormatter.compactString(
                    resetsAt: Date(timeIntervalSince1970: 1e308),
                    now: now
                ),
                equals: "--"
            )
            && expect(
                ResetCountdownFormatter.compactString(
                    resetsAt: Date(timeIntervalSince1970: .infinity),
                    now: now
                ),
                equals: "--"
            )
    }



    private static func testNegativeUsedPercent() -> Bool {
        let snapshot = QuotaParser.snapshot(from: tokenCountLine(primary: -10))
        return expect(snapshot?.remainingPercent, equals: 100)
    }

    private static func testUsedPercentAboveOneHundred() -> Bool {
        let snapshot = QuotaParser.snapshot(from: tokenCountLine(primary: 150))
        return expect(snapshot?.remainingPercent, equals: 0)
    }

    private static func testInvalidJSON() -> Bool {
        expect(QuotaParser.snapshot(from: "not json"), equals: nil)
    }

    private static func testNonTokenCountEvent() -> Bool {
        let line = """
        {"timestamp":"2026-07-14T08:30:00Z","type":"event_msg","payload":{"type":"other","rate_limits":{"primary":{"used_percent":40}}}}
        """
        return expect(QuotaParser.snapshot(from: line), equals: nil)
    }

    private static func testMissingRateLimits() -> Bool {
        let line = """
        {"timestamp":"2026-07-14T08:30:00Z","type":"event_msg","payload":{"type":"token_count"}}
        """
        return expect(QuotaParser.snapshot(from: line), equals: nil)
    }

    private static func testInvalidTimestamp() -> Bool {
        let line = """
        {"timestamp":"not-a-date","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":40}}}}
        """
        return expect(QuotaParser.snapshot(from: line), equals: nil)
    }

    private static func testStandardInternetDate() -> Bool {
        let snapshot = QuotaParser.snapshot(
            from: tokenCountLine(primary: 40, timestamp: "2026-07-14T08:30:00Z")
        )
        return expect(snapshot == nil, equals: false)
    }

    private static func testNewestObservedSnapshotWins() -> Bool {
        withTemporaryDirectory { root in
            let nested = root.appendingPathComponent("nested", isDirectory: true)
            guard
                (try? FileManager.default.createDirectory(
                    at: nested,
                    withIntermediateDirectories: true
                )) != nil,
                write(
                    tokenCountLine(primary: 80, timestamp: "2026-07-14T09:00:00Z"),
                    to: nested.appendingPathComponent("a-old-name.jsonl")
                ),
                write(
                    tokenCountLine(primary: 30, timestamp: "2026-07-14T08:00:00Z"),
                    to: root.appendingPathComponent("z-new-name.jsonl")
                )
            else {
                return false
            }

            let snapshot = QuotaStore().latestSnapshot(in: root)
            return expect(snapshot?.remainingPercent, equals: 20)
                && expect(snapshot?.observedAt, equals: standardDate("2026-07-14T09:00:00Z"))
        }
    }

    private static func testEmptyRoot() -> Bool {
        withTemporaryDirectory { root in
            expect(QuotaStore().latestSnapshot(in: root), equals: nil)
        }
    }

    private static func testLatestValidEventInFile() -> Bool {
        withTemporaryDirectory { root in
            let contents = [
                tokenCountLine(primary: 10, timestamp: "2026-07-14T08:00:00Z"),
                tokenCountLine(primary: 70, timestamp: "2026-07-14T09:00:00Z"),
                "not json"
            ].joined(separator: "\n")
            guard write(contents, to: root.appendingPathComponent("events.jsonl")) else {
                return false
            }

            return expect(
                QuotaStore().latestSnapshot(in: root)?.remainingPercent,
                equals: 30
            )
        }
    }

    private static func testTruncatedLargeFilePrefix() -> Bool {
        withTemporaryDirectory { root in
            let prefix = String(repeating: "x", count: 4 * 1024 * 1024 + 128)
            let contents = prefix + "\n" + tokenCountLine(
                primary: 40,
                timestamp: "2026-07-14T10:00:00Z"
            )
            guard write(contents, to: root.appendingPathComponent("large.jsonl")) else {
                return false
            }

            return expect(
                QuotaStore().latestSnapshot(in: root)?.remainingPercent,
                equals: 60
            )
        }
    }

    private static func testWholeFileFirstLine() -> Bool {
        withTemporaryDirectory { root in
            guard write(
                tokenCountLine(primary: 25, timestamp: "2026-07-14T11:00:00Z"),
                to: root.appendingPathComponent("single-line.jsonl")
            ) else {
                return false
            }

            return expect(
                QuotaStore().latestSnapshot(in: root)?.remainingPercent,
                equals: 75
            )
        }
    }

    private static func testExactFourMiBLineBoundary() -> Bool {
        withTemporaryDirectory { root in
            let maximumBytes = 4 * 1024 * 1024
            let event = Data(tokenCountLine(
                primary: 35,
                timestamp: "2026-07-14T12:00:00Z"
            ).utf8)
            guard event.count + 1 < maximumBytes else {
                return false
            }

            var tail = event
            tail.append(0x0A)
            tail.append(Data(repeating: 0x78, count: maximumBytes - tail.count))
            var contents = Data("prefix\n".utf8)
            contents.append(tail)

            guard write(contents, to: root.appendingPathComponent("boundary.jsonl")) else {
                return false
            }
            return expect(
                QuotaStore().latestSnapshot(in: root)?.remainingPercent,
                equals: 65
            )
        }
    }

    private static func testUTF8SplitBeforeNewline() -> Bool {
        withTemporaryDirectory { root in
            let maximumBytes = 4 * 1024 * 1024
            let event = Data(tokenCountLine(
                primary: 45,
                timestamp: "2026-07-14T12:01:00Z"
            ).utf8)
            var postEmoji = Data([0x0A])
            postEmoji.append(event)
            postEmoji.append(0x0A)
            guard postEmoji.count < maximumBytes - 3 else {
                return false
            }
            postEmoji.append(Data(
                repeating: 0x78,
                count: maximumBytes - 3 - postEmoji.count
            ))

            var contents = Data(repeating: 0x70, count: 100)
            contents.append(Data("🙂".utf8))
            contents.append(postEmoji)

            guard write(contents, to: root.appendingPathComponent("utf8-split.jsonl")) else {
                return false
            }
            return expect(
                QuotaStore().latestSnapshot(in: root)?.remainingPercent,
                equals: 55
            )
        }
    }

    private static func testTailSearchExpansion() -> Bool {
        withTemporaryDirectory { root in
            let event = Data(tokenCountLine(
                primary: 50,
                timestamp: "2026-07-14T12:02:00Z"
            ).utf8)
            var contents = Data(repeating: 0x78, count: 128 * 1024)
            contents.append(0x0A)
            contents.append(event)
            contents.append(0x0A)
            contents.append(Data(repeating: 0x78, count: 96 * 1024))

            guard write(contents, to: root.appendingPathComponent("expansion.jsonl")) else {
                return false
            }
            return expect(
                QuotaStore().latestSnapshot(in: root)?.remainingPercent,
                equals: 50
            )
        }
    }

    private static func testStableTopFiftyTieBreak() -> Bool {
        withTemporaryDirectory { root in
            guard let modificationDate = standardDate("2026-07-14T13:00:00Z") else {
                return false
            }

            for index in stride(from: 50, through: 0, by: -1) {
                let name = String(format: "%03d.jsonl", index)
                let seconds = String(format: "%02d", index)
                let file = root.appendingPathComponent(name)
                guard
                    write(
                        tokenCountLine(
                            primary: Double(index),
                            timestamp: "2026-07-14T12:00:\(seconds)Z"
                        ),
                        to: file
                    ),
                    setModificationDate(modificationDate, for: file)
                else {
                    return false
                }
            }

            return expect(
                QuotaStore().latestSnapshot(in: root)?.remainingPercent,
                equals: 51
            )
        }
    }

    private static func testCorruptFileIsSkipped() -> Bool {
        withTemporaryDirectory { root in
            guard
                write(
                    tokenCountLine(primary: 15, timestamp: "2026-07-14T12:03:00Z"),
                    to: root.appendingPathComponent("valid.jsonl")
                ),
                write("not json\n{also broken", to: root.appendingPathComponent("corrupt.jsonl"))
            else {
                return false
            }

            return expect(
                QuotaStore().latestSnapshot(in: root)?.remainingPercent,
                equals: 85
            )
        }
    }

    private static func testRendererUnknown() -> Bool {
        expect(QuotaRenderer.title(remainingPercent: nil), equals: "Codex [░░░░░░░░░░] --%")
    }

    private static func testRendererZero() -> Bool {
        expect(QuotaRenderer.title(remainingPercent: 0), equals: "Codex [░░░░░░░░░░] 0%")
    }

    private static func testRendererSixty() -> Bool {
        expect(QuotaRenderer.title(remainingPercent: 60), equals: "Codex [██████░░░░] 60%")
    }

    private static func testRendererSixtyFive() -> Bool {
        expect(QuotaRenderer.title(remainingPercent: 65), equals: "Codex [███████░░░] 65%")
    }

    private static func testRendererOneHundred() -> Bool {
        expect(QuotaRenderer.title(remainingPercent: 100), equals: "Codex [██████████] 100%")
    }

    private static func testDefaultBatteryStyle() -> Bool {
        expect(BatteryStyle.defaultStyle, equals: .native)
    }

    private static func testBatteryStyleCases() -> Bool {
        expect(BatteryStyle.allCases, equals: [.native, .embedded, .segmented])
            && expect(BatteryStyle.allCases.map(\.rawValue), equals: [
                "native", "embedded", "segmented"
            ])
    }

    private static func testBatteryStyleMenuTitles() -> Bool {
        expect(BatteryStyle.allCases.map(\.menuTitle), equals: [
            "A · 原生电池",
            "B · 数字徽章",
            "C · 分段电池"
        ])
    }

    private static func testStatusIdentityModeCases() -> Bool {
        expect(StatusIdentityMode.allCases, equals: [.text, .logo, .hidden])
            && expect(StatusIdentityMode.allCases.map(\.rawValue), equals: [
                "text", "logo", "hidden"
            ])
    }

    private static func testStatusIdentityModeMenuTitles() -> Bool {
        expect(StatusIdentityMode.allCases.map(\.menuTitle), equals: [
            "显示 Codex 文字",
            "显示 OpenAI Logo",
            "不显示标识"
        ])
    }

    private static func testUpdateTimeIncludesSeconds() -> Bool {
        guard let utc = TimeZone(secondsFromGMT: 0) else {
            return diagnostic("UTC timezone is unavailable")
        }
        return expect(
            UpdateTimeFormatter.string(
                observedAt: Date(timeIntervalSince1970: 45_296),
                timeZone: utc
            ),
            equals: "12:34:56"
        )
    }

    private static func testUpdateTimeLabel() -> Bool {
        guard let utc = TimeZone(secondsFromGMT: 0) else {
            return diagnostic("UTC timezone is unavailable")
        }
        return expect(
            UpdateTimeFormatter.label(
                lastRefreshAt: Date(timeIntervalSince1970: 45_296),
                timeZone: utc
            ),
            equals: "更新时间：12:34:56"
        )
    }

    private static func testMissingUpdateTime() -> Bool {
        expect(UpdateTimeFormatter.string(observedAt: nil), equals: "--:--:--")
    }

    private static func testDefaultCodexLabel() -> Bool {
        withPreferencesSuite { defaults in
            expect(DisplayPreferences(defaults: defaults).showsCodexLabel, equals: true)
        }
    }

    private static func testLaunchNoticeDefaultsToNotShown() -> Bool {
        withPreferencesSuite { defaults in
            expect(
                DisplayPreferences(defaults: defaults).hasShownAutoRefreshNotice,
                equals: false
            )
        }
    }

    private static func testLaunchNoticeDismissalPersists() -> Bool {
        withPreferencesSuite { defaults in
            var preferences = DisplayPreferences(defaults: defaults)
            preferences.hasShownAutoRefreshNotice = true
            return expect(
                DisplayPreferences(defaults: defaults).hasShownAutoRefreshNotice,
                equals: true
            )
        }
    }

    private static func testDisplayPreferencesPersistence() -> Bool {
        withPreferencesSuite { defaults in
            var preferences = DisplayPreferences(defaults: defaults)
            preferences.batteryStyle = .embedded
            preferences.showsCodexLabel = false

            let restored = DisplayPreferences(defaults: defaults)
            return expect(restored.batteryStyle, equals: .embedded)
                && expect(restored.showsCodexLabel, equals: false)
        }
    }

    private static func testSemanticVersionAcceptedValues() -> Bool {
        guard
            let plain = SemanticVersion("1.2.3"),
            let prefixed = SemanticVersion("v1.2.3"),
            let zero = SemanticVersion("0.0.0")
        else {
            return false
        }
        return expect(plain.major, equals: 1)
            && expect(plain.minor, equals: 2)
            && expect(plain.patch, equals: 3)
            && expect(prefixed, equals: plain)
            && expect(zero.major, equals: 0)
            && expect(zero.minor, equals: 0)
            && expect(zero.patch, equals: 0)
    }

    private static func testSemanticVersionRejectedValues() -> Bool {
        let invalid = [
            "", "1.2", "1.2.3.4", "vv1.2.3", "v", "-1.2.3",
            "1.-2.3", "1.2.-3", "1..3", ".1.2", "1.2.", "1.a.3",
            " 1.2.3", "1.2.3 ", "1. 2.3", "1.2.3\n",
            "01.2.3", "1.02.3", "v1.2.03",
            "999999999999999999999999999999999.2.3"
        ]
        return invalid.allSatisfy { SemanticVersion($0) == nil }
    }

    private static func testSemanticVersionComparison() -> Bool {
        guard
            let oneNine = SemanticVersion("1.9.0"),
            let oneTen = SemanticVersion("1.10.0"),
            let two = SemanticVersion("2.0.0"),
            let same = SemanticVersion("v1.10.0")
        else {
            return false
        }
        return oneNine < oneTen
            && oneTen < two
            && expect(oneTen, equals: same)
            && !(same < oneTen)
            && !(oneTen < same)
    }

    private static func testGitHubReleaseDecoding() -> Bool {
        let fixture = """
        {
          "tag_name": "v1.2.0",
          "name": "Codex Quota 1.2",
          "body": "Release notes",
          "html_url": "https://github.com/huangs9121/codex-assistant/releases/tag/v1.2.0",
          "draft": false,
          "prerelease": false
        }
        """
        guard let release = try? JSONDecoder().decode(
            GitHubRelease.self,
            from: Data(fixture.utf8)
        ) else {
            return false
        }
        return expect(release.tagName, equals: "v1.2.0")
            && expect(release.name, equals: "Codex Quota 1.2")
            && expect(release.body, equals: "Release notes")
            && expect(
                release.htmlURL.absoluteString,
                equals: "https://github.com/huangs9121/codex-assistant/releases/tag/v1.2.0"
            )
            && expect(release.draft, equals: false)
            && expect(release.prerelease, equals: false)
            && expect(release.eligibleVersion, equals: SemanticVersion("1.2.0"))
    }

    private static func testGitHubReleaseEligibility() -> Bool {
        func release(
            tag: String = "v1.2.0",
            url: String = "https://github.com/huangs9121/codex-assistant/releases/tag/v1.2.0",
            draft: Bool = false,
            prerelease: Bool = false
        ) -> GitHubRelease? {
            let object: [String: Any] = [
                "tag_name": tag,
                "html_url": url,
                "draft": draft,
                "prerelease": prerelease
            ]
            return try? JSONDecoder().decode(GitHubRelease.self, from: jsonData(object))
        }

        guard
            let valid = release(),
            let validWithoutPrefix = release(
                tag: "1.2.0",
                url: "https://github.com/huangs9121/codex-assistant/releases/tag/1.2.0"
            )
        else {
            return false
        }
        let rejected = [
            release(draft: true),
            release(prerelease: true),
            release(url: "http://github.com/huangs9121/codex-assistant/releases/tag/v1.2.0"),
            release(url: "https://user:pass@github.com/huangs9121/codex-assistant/releases/tag/v1.2.0"),
            release(url: "https://user@github.com/huangs9121/codex-assistant/releases/tag/v1.2.0"),
            release(url: "https://:pass@github.com/huangs9121/codex-assistant/releases/tag/v1.2.0"),
            release(url: "https://example.com/huangs9121/codex-assistant/releases/tag/v1.2.0"),
            release(url: "https://github.com/huangs9121/codex-assistant/releases/tag/v1.2.0#notes"),
            release(url: "https://github.com/wrong-owner/codex-assistant/releases/tag/v1.2.0"),
            release(url: "https://github.com/huangs9121/wrong-repo/releases/tag/v1.2.0"),
            release(url: "https://github.com/huangs9121/codex-assistant/releases/v1.2.0"),
            release(url: "https://github.com/huangs9121/codex-assistant/releases/tag/v1.3.0"),
            release(url: "https://github.com:443/huangs9121/codex-assistant/releases/tag/v1.2.0"),
            release(url: "https://github.com:8443/huangs9121/codex-assistant/releases/tag/v1.2.0"),
            release(url: "https://github.com/huangs9121/codex-assistant/releases/tag/v1.2.0?source=app"),
            release(url: "https://github.com/huangs9121/codex-assistant/releases/tag/%761.2.0"),
            release(tag: "not-a-version")
        ]
        return expect(valid.eligibleVersion, equals: SemanticVersion("1.2.0"))
            && expect(validWithoutPrefix.eligibleVersion, equals: SemanticVersion("1.2.0"))
            && rejected.allSatisfy { $0?.eligibleVersion == nil }
    }

    private static func testGitHubReleaseInvalidDecoding() -> Bool {
        let invalid: [[String: Any]] = [
            ["html_url": "https://example.com", "draft": false, "prerelease": false],
            ["tag_name": "v1.2.0", "draft": false, "prerelease": false],
            ["tag_name": 120, "html_url": "https://example.com", "draft": false, "prerelease": false],
            ["tag_name": "v1.2.0", "html_url": 120, "draft": false, "prerelease": false],
            ["tag_name": "v1.2.0", "html_url": "https://example.com", "draft": "false", "prerelease": false]
        ]
        return invalid.allSatisfy {
            (try? JSONDecoder().decode(GitHubRelease.self, from: jsonData($0))) == nil
        }
    }

    private static func testLatestReleaseRequest() -> Bool {
        guard let request = GitHubRelease.latestRequest(
            appVersion: SemanticVersion("1.2.3")!
        ) else {
            return false
        }
        return expect(
            request.url?.absoluteString,
            equals: "https://api.github.com/repos/huangs9121/codex-assistant/releases/latest"
        )
            && expect(request.httpMethod, equals: "GET")
            && expect(request.timeoutInterval, equals: 10)
            && expect(request.value(forHTTPHeaderField: "Accept"), equals: "application/vnd.github+json")
            && expect(request.value(forHTTPHeaderField: "User-Agent"), equals: "Codex-Quota/1.2.3")
            && expect(request.value(forHTTPHeaderField: "Authorization"), equals: nil)
            && expect(request.value(forHTTPHeaderField: "Cookie"), equals: nil)
            && expect(request.allHTTPHeaderFields?.count, equals: 2)
            && expect(request.httpBody, equals: nil)
    }

    private static func testUpdateCheckPolicy() -> Bool {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return UpdatePolicy.shouldAutomaticallyCheck(lastSuccess: nil, lastFailure: nil, now: now)
            && !UpdatePolicy.shouldAutomaticallyCheck(
                lastSuccess: nil,
                lastFailure: nil,
                now: Date(timeIntervalSinceReferenceDate: .infinity)
            )
            && !UpdatePolicy.shouldAutomaticallyCheck(
                lastSuccess: now.addingTimeInterval(-(24 * 60 * 60 - 60)),
                lastFailure: nil,
                now: now
            )
            && UpdatePolicy.shouldAutomaticallyCheck(
                lastSuccess: now.addingTimeInterval(-24 * 60 * 60),
                lastFailure: nil,
                now: now
            )
            && !UpdatePolicy.shouldAutomaticallyCheck(
                lastSuccess: nil,
                lastFailure: now.addingTimeInterval(-(60 * 60 - 60)),
                now: now
            )
            && UpdatePolicy.shouldAutomaticallyCheck(
                lastSuccess: nil,
                lastFailure: now.addingTimeInterval(-60 * 60),
                now: now
            )
            && !UpdatePolicy.shouldAutomaticallyCheck(
                lastSuccess: now.addingTimeInterval(-25 * 60 * 60),
                lastFailure: now.addingTimeInterval(-30 * 60),
                now: now
            )
            && !UpdatePolicy.shouldAutomaticallyCheck(
                lastSuccess: now.addingTimeInterval(-23 * 60 * 60),
                lastFailure: now.addingTimeInterval(-2 * 60 * 60),
                now: now
            )
            && !UpdatePolicy.shouldAutomaticallyCheck(
                lastSuccess: now.addingTimeInterval(1),
                lastFailure: nil,
                now: now
            )
            && !UpdatePolicy.shouldAutomaticallyCheck(
                lastSuccess: nil,
                lastFailure: now.addingTimeInterval(1),
                now: now
            )
            && !UpdatePolicy.shouldAutomaticallyCheck(
                lastSuccess: Date(timeIntervalSince1970: -.infinity),
                lastFailure: nil,
                now: now
            )
    }

    private static func testUpdatePromptPolicy() -> Bool {
        guard let version = SemanticVersion("1.2.0") else {
            return false
        }
        return !UpdatePolicy.shouldPrompt(version: version, lastPromptedVersion: "1.2.0")
            && !UpdatePolicy.shouldPrompt(version: version, lastPromptedVersion: "v1.2.0")
            && UpdatePolicy.shouldPrompt(version: version, lastPromptedVersion: "1.2.1")
            && UpdatePolicy.shouldPrompt(version: version, lastPromptedVersion: "invalid")
            && UpdatePolicy.shouldPrompt(version: version, lastPromptedVersion: "")
            && UpdatePolicy.shouldPrompt(version: version, lastPromptedVersion: nil)
    }

    private static func testUpdatePreferences() -> Bool {
        withPreferencesSuite { defaults in
            var preferences = DisplayPreferences(defaults: defaults)
            guard preferences.lastUpdateCheckSuccess == nil,
                  preferences.lastUpdateCheckFailure == nil,
                  preferences.lastPromptedVersion == nil else {
                return false
            }

            let success = Date(timeIntervalSince1970: 100)
            let failure = Date(timeIntervalSince1970: 200)
            preferences.lastUpdateCheckSuccess = success
            preferences.lastUpdateCheckFailure = failure
            preferences.lastPromptedVersion = "v1.2.0"
            guard DisplayPreferences(defaults: defaults).lastUpdateCheckSuccess == success,
                  DisplayPreferences(defaults: defaults).lastUpdateCheckFailure == failure,
                  DisplayPreferences(defaults: defaults).lastPromptedVersion == "v1.2.0" else {
                return false
            }

            preferences.lastUpdateCheckSuccess = nil
            preferences.lastUpdateCheckFailure = nil
            preferences.lastPromptedVersion = nil
            guard defaults.object(forKey: DisplayPreferences.lastUpdateCheckSuccessKey) == nil,
                  defaults.object(forKey: DisplayPreferences.lastUpdateCheckFailureKey) == nil,
                  defaults.object(forKey: DisplayPreferences.lastPromptedVersionKey) == nil else {
                return false
            }

            defaults.set("not a date", forKey: DisplayPreferences.lastUpdateCheckSuccessKey)
            defaults.set(123, forKey: DisplayPreferences.lastUpdateCheckFailureKey)
            defaults.set(123, forKey: DisplayPreferences.lastPromptedVersionKey)
            guard preferences.lastUpdateCheckSuccess == nil,
                  preferences.lastUpdateCheckFailure == nil,
                  preferences.lastPromptedVersion == nil else {
                return false
            }

            defaults.set(Date(), forKey: DisplayPreferences.lastPromptedVersionKey)
            guard preferences.lastPromptedVersion == nil else {
                return false
            }

            defaults.set("", forKey: DisplayPreferences.lastPromptedVersionKey)
            return preferences.lastPromptedVersion == nil
        }
    }

    private static func testInvalidBatteryStyleFallback() -> Bool {
        withPreferencesSuite { defaults in
            defaults.set("unknown", forKey: DisplayPreferences.batteryStyleKey)
            return expect(
                DisplayPreferences(defaults: defaults).batteryStyle,
                equals: .native
            )
        }
    }

    private static func testStoredFalseCodexLabel() -> Bool {
        withPreferencesSuite { defaults in
            defaults.set(false, forKey: DisplayPreferences.showsCodexLabelKey)
            return expect(
                DisplayPreferences(defaults: defaults).showsCodexLabel,
                equals: false
            )
        }
    }

    private static func testDefaultIdentityModeMigration() -> Bool {
        withPreferencesSuite { defaults in
            let preferences = DisplayPreferences(defaults: defaults)
            return expect(preferences.identityMode, equals: .text)
                && expect(
                    defaults.string(forKey: DisplayPreferences.statusIdentityModeKey),
                    equals: StatusIdentityMode.text.rawValue
                )
        }
    }

    private static func testLegacyTrueIdentityMigration() -> Bool {
        withPreferencesSuite { defaults in
            defaults.set(true, forKey: DisplayPreferences.showsCodexLabelKey)
            let preferences = DisplayPreferences(defaults: defaults)
            return expect(preferences.identityMode, equals: .text)
                && expect(
                    defaults.string(forKey: DisplayPreferences.statusIdentityModeKey),
                    equals: StatusIdentityMode.text.rawValue
                )
        }
    }

    private static func testLegacyFalseIdentityMigration() -> Bool {
        withPreferencesSuite { defaults in
            defaults.set(false, forKey: DisplayPreferences.showsCodexLabelKey)
            let preferences = DisplayPreferences(defaults: defaults)
            return expect(preferences.identityMode, equals: .hidden)
                && expect(
                    defaults.string(forKey: DisplayPreferences.statusIdentityModeKey),
                    equals: StatusIdentityMode.hidden.rawValue
                )
        }
    }

    private static func testLegacyStringIdentityMigration() -> Bool {
        withPreferencesSuite { defaults in
            defaults.set("invalid", forKey: DisplayPreferences.showsCodexLabelKey)
            let preferences = DisplayPreferences(defaults: defaults)
            return expect(preferences.identityMode, equals: .text)
                && expect(
                    defaults.string(forKey: DisplayPreferences.statusIdentityModeKey),
                    equals: StatusIdentityMode.text.rawValue
                )
        }
    }

    private static func testLegacyNumericIdentityMigration() -> Bool {
        withPreferencesSuite { defaults in
            defaults.set(0, forKey: DisplayPreferences.showsCodexLabelKey)
            let preferences = DisplayPreferences(defaults: defaults)
            return expect(preferences.identityMode, equals: .text)
                && expect(
                    defaults.string(forKey: DisplayPreferences.statusIdentityModeKey),
                    equals: StatusIdentityMode.text.rawValue
                )
        }
    }

    private static func testValidNewIdentityPreferencePriority() -> Bool {
        withPreferencesSuite { defaults in
            defaults.set(false, forKey: DisplayPreferences.showsCodexLabelKey)
            defaults.set(
                StatusIdentityMode.logo.rawValue,
                forKey: DisplayPreferences.statusIdentityModeKey
            )
            return expect(
                DisplayPreferences(defaults: defaults).identityMode,
                equals: .logo
            )
        }
    }

    private static func testInvalidNewIdentityPreferenceFallback() -> Bool {
        withPreferencesSuite { defaults in
            defaults.set(false, forKey: DisplayPreferences.showsCodexLabelKey)
            defaults.set("invalid", forKey: DisplayPreferences.statusIdentityModeKey)
            let preferences = DisplayPreferences(defaults: defaults)
            return expect(preferences.identityMode, equals: .text)
                && expect(
                    defaults.string(forKey: DisplayPreferences.statusIdentityModeKey),
                    equals: "invalid"
                )
        }
    }

    private static func testIdentityModePersistence() -> Bool {
        withPreferencesSuite { defaults in
            var preferences = DisplayPreferences(defaults: defaults)
            preferences.identityMode = .logo
            return expect(
                DisplayPreferences(defaults: defaults).identityMode,
                equals: .logo
            )
        }
    }

    private static func testDefaultResetCountdownStatusPreference() -> Bool {
        withPreferencesSuite { defaults in
            expect(
                DisplayPreferences(defaults: defaults).showsResetCountdownInStatusBar,
                equals: false
            )
        }
    }

    private static func testResetCountdownStatusPreferencePersistence() -> Bool {
        withPreferencesSuite { defaults in
            var preferences = DisplayPreferences(defaults: defaults)
            preferences.showsResetCountdownInStatusBar = true
            return expect(
                DisplayPreferences(defaults: defaults).showsResetCountdownInStatusBar,
                equals: true
            )
        }
    }

    private static func testLaunchAgentFileInstall() -> Bool {
        withTemporaryDirectory { root in
            let home = root.appendingPathComponent("home", isDirectory: true)
            let executable = root.appendingPathComponent("Codex Quota.app/Contents/MacOS/CodexQuotaApp")
            let launchAgent = LaunchAgentFile(
                homeDirectory: home,
                executableURL: executable
            )
            do {
                try launchAgent.install()
                let data = try Data(contentsOf: launchAgent.fileURL)
                guard
                    let properties = try PropertyListSerialization.propertyList(
                        from: data,
                        format: nil
                    ) as? [String: Any],
                    let permissions = try FileManager.default.attributesOfItem(
                        atPath: launchAgent.fileURL.path
                    )[.posixPermissions] as? NSNumber
                else {
                    return false
                }
                return launchAgent.isInstalled
                    && expect(
                        launchAgent.fileURL.path,
                        equals: home.appendingPathComponent(
                            "Library/LaunchAgents/local.openclaw.codexquota.plist"
                        ).path
                    )
                    && expect(properties["Label"] as? String, equals: LaunchAgentFile.defaultLabel)
                    && expect(properties["ProgramArguments"] as? [String], equals: [executable.path])
                    && expect(properties["RunAtLoad"] as? Bool, equals: true)
                    && expect(permissions.intValue, equals: 0o644)
            } catch {
                return diagnostic("launch agent install failed: \(error)")
            }
        }
    }

    private static func testLaunchAgentFileUninstall() -> Bool {
        withTemporaryDirectory { root in
            let launchAgent = LaunchAgentFile(
                homeDirectory: root,
                executableURL: root.appendingPathComponent("CodexQuotaApp")
            )
            do {
                try launchAgent.install()
                try launchAgent.uninstall()
                try launchAgent.uninstall()
                return expect(launchAgent.isInstalled, equals: false)
            } catch {
                return diagnostic("launch agent uninstall failed: \(error)")
            }
        }
    }

    private static func testOpenAILogoRendering() -> Bool {
        let image = OpenAILogoRenderer.image()
        guard
            image.size == NSSize(width: 17, height: 17),
            image.isTemplate,
            let tiff = image.tiffRepresentation,
            !tiff.isEmpty
        else {
            return diagnostic("OpenAI logo does not expose the required 17pt template image")
        }

        for scale in [1, 2] {
            guard
                let bitmap = AlphaBitmap(image: image, scale: scale),
                let bounds = bitmap.nonTransparentBounds(threshold: 0.03)
            else {
                return diagnostic("OpenAI logo @\(scale)x has no visible pixels")
            }
            let requiredMargin = scale
            let centerX: Double = Double(bounds.minX + bounds.maxX) / 2.0
            let centerY: Double = Double(bounds.minY + bounds.maxY) / 2.0
            let canvasCenterX: Double = Double(bitmap.width - 1) / 2.0
            let canvasCenterY: Double = Double(bitmap.height - 1) / 2.0
            guard
                bounds.minX >= requiredMargin,
                bounds.minY >= requiredMargin,
                bounds.maxX <= bitmap.width - requiredMargin - 1,
                bounds.maxY <= bitmap.height - requiredMargin - 1,
                centerX - canvasCenterX >= -1,
                centerX - canvasCenterX <= 1,
                centerY - canvasCenterY >= -1,
                centerY - canvasCenterY <= 1
            else {
                return diagnostic("OpenAI logo @\(scale)x bounds \(bounds) are clipped or off-center")
            }
        }
        return true
    }

    private static func testStatusPresentationMatrix() -> Bool {
        let renderer = BatteryStatusRenderer()
        for scale in [1, 2] {
            for style in BatteryStyle.allCases {
                for identityMode in StatusIdentityMode.allCases {
                    for compactReset in [nil, "2D"] as [String?] {
                        let presentation = renderer.presentation(
                            style: style,
                            remainingPercent: 60,
                            identityMode: identityMode,
                            compactReset: compactReset
                        )
                        guard
                            presentation.image.size.height == 18,
                            presentation.image.isTemplate,
                            let tiff = presentation.image.tiffRepresentation,
                            !tiff.isEmpty,
                            let bitmap = AlphaBitmap(image: presentation.image, scale: scale),
                            let bounds = bitmap.nonTransparentBounds(threshold: 0.03),
                            bounds.minX > 0,
                            bounds.minY > 0,
                            bounds.maxX < bitmap.width - 1,
                            bounds.maxY < bitmap.height - 1
                        else {
                            return diagnostic(
                                "\(style)/\(identityMode)/\(compactReset ?? "nil") @\(scale)x is empty or clipped"
                            )
                        }
                    }
                }
            }
        }
        return true
    }

    private static func testStatusPresentationWidthRelationships() -> Bool {
        let renderer = BatteryStatusRenderer()
        let suffixAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: NSColor.black.withAlphaComponent(0.9)
        ]
        let suffixWidth = ceil(NSAttributedString(
            string: "2D",
            attributes: suffixAttributes
        ).size().width)

        for style in BatteryStyle.allCases {
            let hidden = renderer.presentation(
                style: style,
                remainingPercent: 60,
                identityMode: .hidden,
                compactReset: nil
            )
            let logo = renderer.presentation(
                style: style,
                remainingPercent: 60,
                identityMode: .logo,
                compactReset: nil
            )
            let text = renderer.presentation(
                style: style,
                remainingPercent: 60,
                identityMode: .text,
                compactReset: nil
            )
            let reset = renderer.presentation(
                style: style,
                remainingPercent: 60,
                identityMode: .hidden,
                compactReset: "2D"
            )
            guard
                logo.image.size.width == hidden.image.size.width + 21,
                text.image.size.width > hidden.image.size.width,
                reset.image.size.width == hidden.image.size.width + suffixWidth + 4
            else {
                return diagnostic("\(style) identity or suffix width relationship is incorrect")
            }
        }
        return true
    }

    private static func testStatusPresentationAccessibility() -> Bool {
        let renderer = BatteryStatusRenderer()
        return expect(renderer.presentation(
            style: .native,
            remainingPercent: 60,
            identityMode: .text,
            compactReset: nil
        ).accessibilityLabel, equals: "Codex 剩余额度 60%，显示 Codex 文字")
            && expect(renderer.presentation(
                style: .embedded,
                remainingPercent: nil,
                identityMode: .logo,
                compactReset: "2D"
            ).accessibilityLabel, equals: "Codex 剩余额度未知，下次重置 2D，显示 OpenAI Logo")
            && expect(renderer.presentation(
                style: .segmented,
                remainingPercent: 0,
                identityMode: .hidden,
                compactReset: ""
            ).accessibilityLabel, equals: "Codex 剩余额度 0%，下次重置 ，不显示标识")
    }

    private static func testBatteryRendererImageMatrix() -> Bool {
        let renderer = BatteryStatusRenderer()
        let expectedSizes: [BatteryStyle: NSSize] = [
            .native: NSSize(width: 36, height: 16),
            .embedded: NSSize(width: 34, height: 18),
            .segmented: NSSize(width: 40, height: 16)
        ]

        for style in BatteryStyle.allCases {
            for remainingPercent in [nil, 0, 8, 60, 100] as [Int?] {
                let image = renderer.presentation(
                    style: style,
                    remainingPercent: remainingPercent,
                    showsCodexLabel: true
                ).batteryImage
                guard
                    image.isTemplate,
                    image.size == expectedSizes[style],
                    let tiff = image.tiffRepresentation,
                    !tiff.isEmpty
                else {
                    return false
                }
            }
        }
        return true
    }

    private static func testFullStatusComposition() -> Bool {
        let renderer = BatteryStatusRenderer()
        for style in BatteryStyle.allCases {
            let withLabel = renderer.presentation(
                style: style,
                remainingPercent: 49,
                showsCodexLabel: true
            )
            let withoutLabel = renderer.presentation(
                style: style,
                remainingPercent: 49,
                showsCodexLabel: false
            )
            guard
                withLabel.image.isTemplate,
                withoutLabel.image.isTemplate,
                withLabel.image.size.height == 18,
                withoutLabel.image.size.height == 18,
                withLabel.image.size.width > withoutLabel.image.size.width
            else {
                return diagnostic("\(style) full image label sizing is incorrect")
            }

            if style == .embedded {
                guard withoutLabel.image.size.width == withoutLabel.batteryImage.size.width + 2 else {
                    return diagnostic("embedded style repeats an external percentage")
                }
            } else {
                guard
                    withoutLabel.image.size.width > withoutLabel.batteryImage.size.width + 6,
                    let bitmap = AlphaBitmap(image: withoutLabel.image, scale: 2),
                    bitmap.maxAlpha(in: NSRect(
                        x: withoutLabel.batteryImage.size.width + 5,
                        y: 1,
                        width: withoutLabel.image.size.width - withoutLabel.batteryImage.size.width - 6,
                        height: 16
                    )) > 0.30
                else {
                    return diagnostic("\(style) has no visible external percentage after its battery")
                }
            }
        }
        return true
    }

    private static func testFullStatusCanvasMargins() -> Bool {
        let renderer = BatteryStatusRenderer()
        for scale in [1, 2] {
            for style in BatteryStyle.allCases {
                for showsLabel in [false, true] {
                    let image = renderer.presentation(
                        style: style,
                        remainingPercent: 49,
                        showsCodexLabel: showsLabel
                    ).image
                    guard
                        let bitmap = AlphaBitmap(image: image, scale: scale),
                        let bounds = bitmap.nonTransparentBounds(threshold: 0.03),
                        bounds.minX > 0,
                        bounds.minY > 0,
                        bounds.maxX < bitmap.width - 1,
                        bounds.maxY < bitmap.height - 1
                    else {
                        return diagnostic("\(style) full image @\(scale)x clips its composed artwork")
                    }
                }
            }
        }
        return true
    }

    private static func testBatteryRendererAccessibility() -> Bool {
        let renderer = BatteryStatusRenderer()
        return expect(renderer.presentation(
            style: .native,
            remainingPercent: 60,
            showsCodexLabel: true
        ).accessibilityLabel, equals: "Codex 剩余额度 60%")
            && expect(renderer.presentation(
                style: .embedded,
                remainingPercent: nil,
                showsCodexLabel: false
            ).accessibilityLabel, equals: "Codex 剩余额度未知")
            && expect(renderer.presentation(
                style: .segmented,
                remainingPercent: 0,
                showsCodexLabel: false
            ).accessibilityLabel, equals: "Codex 剩余额度 0%")
    }

    private static func testBatteryRendererClamping() -> Bool {
        let renderer = BatteryStatusRenderer()
        for style in BatteryStyle.allCases {
            let below = renderer.presentation(
                style: style,
                remainingPercent: -10,
                showsCodexLabel: false
            )
            let zero = renderer.presentation(
                style: style,
                remainingPercent: 0,
                showsCodexLabel: false
            )
            let above = renderer.presentation(
                style: style,
                remainingPercent: 150,
                showsCodexLabel: false
            )
            let hundred = renderer.presentation(
                style: style,
                remainingPercent: 100,
                showsCodexLabel: false
            )
            guard
                below.accessibilityLabel == zero.accessibilityLabel,
                bitmapData(below.image) == bitmapData(zero.image),
                above.accessibilityLabel == hundred.accessibilityLabel,
                bitmapData(above.image) == bitmapData(hundred.image)
            else {
                return false
            }
        }
        return true
    }

    private static func testNativeBatteryFillChanges() -> Bool {
        let renderer = BatteryStatusRenderer()
        let images = [0, 49, 100].map {
            renderer.presentation(
                style: .native,
                remainingPercent: $0,
                showsCodexLabel: true
            ).batteryImage
        }
        return bitmapData(images[0]) != bitmapData(images[1])
            && bitmapData(images[1]) != bitmapData(images[2])
    }

    private static func testEmbeddedBatteryValueChanges() -> Bool {
        let renderer = BatteryStatusRenderer()
        let images = [nil, 0, 8, 60, 100].map { value in
            renderer.presentation(
                style: .embedded,
                remainingPercent: value,
                showsCodexLabel: true
            ).batteryImage
        }
        return images.allSatisfy { $0.size == NSSize(width: 34, height: 18) }
            && Set(images.compactMap(bitmapData)).count == images.count
    }

    private static func testSegmentedBatteryBoundaries() -> Bool {
        let renderer = BatteryStatusRenderer()
        func image(at percent: Int) -> Data? {
            bitmapData(renderer.presentation(
                style: .segmented,
                remainingPercent: percent,
                showsCodexLabel: true
            ).batteryImage)
        }

        return image(at: 1) == image(at: 20)
            && image(at: 20) != image(at: 21)
            && image(at: 21) != image(at: 100)
    }

    private static func testBatteryCanvasMargins() -> Bool {
        let renderer = BatteryStatusRenderer()
        var passed = true
        for scale in [1, 2] {
            for style in BatteryStyle.allCases {
                let image = renderer.presentation(
                    style: style,
                    remainingPercent: 49,
                    showsCodexLabel: true
                ).batteryImage
                guard
                    let bitmap = AlphaBitmap(image: image, scale: scale),
                    let bounds = bitmap.nonTransparentBounds(threshold: 0.03)
                else {
                    return diagnostic("\(style) @\(scale)x has no alpha bounds")
                }

                if !(
                    bounds.minX > 0
                    && bounds.minY > 0
                    && bounds.maxX < bitmap.width - 1
                    && bounds.maxY < bitmap.height - 1
                ) {
                    passed = false
                    _ = diagnostic(
                        "\(style) @\(scale)x bounds \(bounds) touch \(bitmap.width)x\(bitmap.height) canvas; edge max alpha \(bitmap.edgeMaxAlphas)"
                    )
                }

                let corners = [
                    bitmap.alpha(x: 0, y: 0),
                    bitmap.alpha(x: bitmap.width - 1, y: 0),
                    bitmap.alpha(x: 0, y: bitmap.height - 1),
                    bitmap.alpha(x: bitmap.width - 1, y: bitmap.height - 1)
                ]
                if !corners.allSatisfy({ $0 < 0.03 }) {
                    passed = false
                    _ = diagnostic("\(style) @\(scale)x opaque corner alphas: \(corners)")
                }
            }
        }
        return passed
    }

    private static func testBatteryOutlineAndTerminalVisibility() -> Bool {
        let renderer = BatteryStatusRenderer()
        let geometry: [BatteryStyle: (bodyWidth: CGFloat, height: CGFloat, terminalX: CGFloat)] = [
            .native: (29.5, 16, 32.75),
            .segmented: (32.5, 16, 35.75)
        ]

        for scale in [1, 2] {
            for (style, dimensions) in geometry {
                guard let bitmap = AlphaBitmap(
                        image: renderer.presentation(
                            style: style,
                            remainingPercent: 0,
                            showsCodexLabel: true
                        ).batteryImage,
                        scale: scale
                    ) else {
                    return diagnostic("\(style) @\(scale)x could not render outline bitmap")
                }

                let bodyRight = 1.75 + dimensions.bodyWidth
                let bodyTop = dimensions.height - 1.75
                let left = bitmap.maxAlpha(in: NSRect(x: 1, y: 4, width: 2.5, height: dimensions.height - 8))
                let top = bitmap.maxAlpha(in: NSRect(x: 5, y: bodyTop - 1.5, width: bodyRight - 10, height: 2.5))
                let bottom = bitmap.maxAlpha(in: NSRect(x: 5, y: 0, width: bodyRight - 10, height: 2.5))
                let terminal = bitmap.maxAlpha(in: NSRect(
                    x: dimensions.terminalX,
                    y: dimensions.height / 2 - 3,
                    width: bitmap.logicalWidth - dimensions.terminalX,
                    height: 6
                ))

                guard min(left, top, bottom) >= 0.45, terminal >= 0.45 else {
                    return diagnostic(
                        "\(style) @\(scale)x outline alpha left/top/bottom=\(left)/\(top)/\(bottom), terminal=\(terminal)"
                    )
                }
            }
        }
        return true
    }

    private static func testNativeBatteryFillCoverage() -> Bool {
        let renderer = BatteryStatusRenderer()
        let interior = NSRect(x: 3.5, y: 3.5, width: 26.5, height: 9)
        for scale in [1, 2] {
            var coverage: [Double] = []
            for percent in [0, 49, 100] {
                guard let bitmap = AlphaBitmap(
                    image: renderer.presentation(
                        style: .native,
                        remainingPercent: percent,
                        showsCodexLabel: false
                    ).batteryImage,
                    scale: scale
                ) else {
                    return diagnostic("native \(percent)% @\(scale)x could not render")
                }
                coverage.append(bitmap.coverage(in: interior, alphaAtLeast: 0.55))
            }

            guard
                coverage[0] < 0.08,
                coverage[1] > 0.30,
                coverage[1] < 0.70,
                coverage[2] > 0.72,
                coverage[0] < coverage[1],
                coverage[1] < coverage[2]
            else {
                return diagnostic("native fill coverage @\(scale)x for 0/49/100: \(coverage)")
            }
        }
        return true
    }

    private static func testEmbeddedValueContrast() -> Bool {
        let renderer = BatteryStatusRenderer()
        let center = NSRect(x: 7, y: 3.5, width: 24, height: 11)
        for scale in [1, 2] {
            for percent in [nil, 49] as [Int?] {
                guard let bitmap = AlphaBitmap(
                    image: renderer.presentation(
                        style: .embedded,
                        remainingPercent: percent,
                        showsCodexLabel: false
                    ).batteryImage,
                    scale: scale
                ) else {
                    return diagnostic("embedded \(String(describing: percent)) @\(scale)x could not render")
                }

                let stats = bitmap.alphaStats(in: center)
                let lowAlphaCount = stats.values.filter { $0 >= 0.08 && $0 <= 0.32 }.count
                let contrastOnLight = stats.max
                let contrastOnDark = stats.max
                guard
                    lowAlphaCount > 0,
                    stats.max - stats.min > 0.50,
                    contrastOnLight > 0.50,
                    contrastOnDark > 0.50
                else {
                    return diagnostic(
                        "embedded \(String(describing: percent)) @\(scale)x min/max=\(stats.min)/\(stats.max), lowAlphaPixels=\(lowAlphaCount), template contrast=\(contrastOnLight)/\(contrastOnDark)"
                    )
                }
            }
        }
        return true
    }

    private static func testSegmentedCellCenters() -> Bool {
        let renderer = BatteryStatusRenderer()
        let cases = [(0, 0), (1, 1), (20, 1), (21, 2), (100, 5)]
        let centerXs: [CGFloat] = [6, 12, 18, 24, 30]
        for scale in [1, 2] {
            for (percent, expectedFilled) in cases {
                guard let bitmap = AlphaBitmap(
                    image: renderer.presentation(
                        style: .segmented,
                        remainingPercent: percent,
                        showsCodexLabel: false
                    ).batteryImage,
                    scale: scale
                ) else {
                    return diagnostic("segmented \(percent)% @\(scale)x could not render")
                }
                let alphas = centerXs.map {
                    bitmap.logicalAlpha(x: $0, y: 8)
                }
                let filled = alphas.filter { $0 >= 0.50 }.count
                guard filled == expectedFilled else {
                    return diagnostic(
                        "segmented \(percent)% @\(scale)x expected \(expectedFilled) cells, got \(filled), center alphas=\(alphas)"
                    )
                }
            }
        }
        return true
    }

    private static func testBatteryAlphaCoverage() -> Bool {
        let renderer = BatteryStatusRenderer()
        for scale in [1, 2] {
            for style in BatteryStyle.allCases {
                for percent in [nil, 0, 49, 100] as [Int?] {
                    guard let bitmap = AlphaBitmap(
                        image: renderer.presentation(
                            style: style,
                            remainingPercent: percent,
                            showsCodexLabel: false
                        ).batteryImage,
                        scale: scale
                    ) else {
                        return diagnostic("\(style) \(String(describing: percent)) @\(scale)x could not render")
                    }
                    let coverage = bitmap.coverage(alphaAtLeast: 0.03)
                    guard coverage >= 0.08, coverage <= 0.85 else {
                        return diagnostic(
                            "\(style) \(String(describing: percent)) @\(scale)x alpha coverage \(coverage) outside 0.08...0.85"
                        )
                    }
                }
            }
        }
        return true
    }

    private static func diagnostic(_ message: String) -> Bool {
        print("  DIAGNOSTIC: \(message)")
        return false
    }

    private static func bitmapData(_ image: NSImage) -> Data? {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        guard let bytes = representation.bitmapData else {
            return nil
        }
        return Data(bytes: bytes, count: representation.bytesPerRow * height)
    }

    private struct AlphaBitmap {
        let width: Int
        let height: Int
        let scale: Int
        let alphas: [Double]

        var logicalWidth: CGFloat { CGFloat(width) / CGFloat(scale) }
        var edgeMaxAlphas: (left: Double, right: Double, bottom: Double, top: Double) {
            (
                (0..<height).map { alpha(x: 0, y: $0) }.max() ?? 0,
                (0..<height).map { alpha(x: width - 1, y: $0) }.max() ?? 0,
                (0..<width).map { alpha(x: $0, y: 0) }.max() ?? 0,
                (0..<width).map { alpha(x: $0, y: height - 1) }.max() ?? 0
            )
        }

        init?(image: NSImage, scale: Int) {
            width = Int(image.size.width) * scale
            height = Int(image.size.height) * scale
            self.scale = scale
            guard let representation = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                return nil
            }

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
            image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
            NSGraphicsContext.restoreGraphicsState()

            var values: [Double] = []
            values.reserveCapacity(width * height)
            for y in 0..<height {
                for x in 0..<width {
                    values.append(Double(representation.colorAt(x: x, y: y)?.alphaComponent ?? 0))
                }
            }
            alphas = values
        }

        func alpha(x: Int, y: Int) -> Double {
            guard x >= 0, x < width, y >= 0, y < height else {
                return 0
            }
            return alphas[y * width + x]
        }

        func logicalAlpha(x: CGFloat, y: CGFloat) -> Double {
            alpha(
                x: min(Int(x * CGFloat(scale)), width - 1),
                y: min(Int(y * CGFloat(scale)), height - 1)
            )
        }

        func nonTransparentBounds(
            threshold: Double
        ) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
            var minX = width
            var maxX = -1
            var minY = height
            var maxY = -1
            for y in 0..<height {
                for x in 0..<width where alpha(x: x, y: y) >= threshold {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
            guard maxX >= 0 else {
                return nil
            }
            return (minX, maxX, minY, maxY)
        }

        func alphaStats(in logicalRect: NSRect) -> (min: Double, max: Double, values: [Double]) {
            let values = alphaValues(in: logicalRect)
            return (values.min() ?? 0, values.max() ?? 0, values)
        }

        func maxAlpha(in logicalRect: NSRect) -> Double {
            alphaValues(in: logicalRect).max() ?? 0
        }

        func coverage(
            in logicalRect: NSRect? = nil,
            alphaAtLeast threshold: Double
        ) -> Double {
            let values = logicalRect.map(alphaValues(in:)) ?? alphas
            guard !values.isEmpty else {
                return 0
            }
            return Double(values.filter { $0 >= threshold }.count) / Double(values.count)
        }

        private func alphaValues(in logicalRect: NSRect) -> [Double] {
            let minX = max(0, Int(floor(logicalRect.minX * CGFloat(scale))))
            let maxX = min(width, Int(ceil(logicalRect.maxX * CGFloat(scale))))
            let minY = max(0, Int(floor(logicalRect.minY * CGFloat(scale))))
            let maxY = min(height, Int(ceil(logicalRect.maxY * CGFloat(scale))))
            var values: [Double] = []
            values.reserveCapacity(max(0, maxX - minX) * max(0, maxY - minY))
            for y in minY..<maxY {
                for x in minX..<maxX {
                    values.append(alpha(x: x, y: y))
                }
            }
            return values
        }
    }

    private static func expect<T: Equatable>(_ actual: T, equals expected: T) -> Bool {
        actual == expected
    }

    private static func tokenCountLine(
        primary: Double,
        primaryReset: Any? = nil,
        secondary: Double? = nil,
        secondaryReset: Any? = nil,
        planType: String? = nil,
        timestamp: String = "2026-07-14T08:30:00.123Z"
    ) -> String {
        var primaryWindow: [String: Any] = ["used_percent": primary]
        if let primaryReset {
            primaryWindow["resets_at"] = primaryReset
        }
        var rateLimits: [String: Any] = ["primary": primaryWindow]
        if let secondary {
            var secondaryWindow: [String: Any] = ["used_percent": secondary]
            if let secondaryReset {
                secondaryWindow["resets_at"] = secondaryReset
            }
            rateLimits["secondary"] = secondaryWindow
        }
        if let planType {
            rateLimits["plan_type"] = planType
        }

        let root: [String: Any] = [
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "rate_limits": rateLimits
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: root)
        return String(decoding: data, as: UTF8.self)
    }

    private static func subscriptionAuthData(plan: String, expiry: String) -> Data {
        authData(idToken: fakeJWT(payload: subscriptionPayload(plan: plan, expiry: expiry)))
    }

    private static func subscriptionPayload(
        plan: String,
        expiry: String,
        nonce: String? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "https://api.openai.com/auth": [
                "chatgpt_plan_type": plan,
                "chatgpt_subscription_active_until": expiry
            ]
        ]
        if let nonce {
            payload["nonce"] = nonce
        }
        return payload
    }

    private static func authData(idToken: Any) -> Data {
        jsonData(["tokens": ["id_token": idToken]])
    }

    private static func fakeJWT(payload: [String: Any]) -> String {
        let payloadData = jsonData(payload)
        return "header.\(base64URL(payloadData)).signature"
    }

    private static func standardBase64JWT(payload: [String: Any]) -> String {
        let payloadData = try! JSONSerialization.data(
            withJSONObject: payload,
            options: .sortedKeys
        )
        let segment = payloadData.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        return "header.\(segment).signature"
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func jsonData(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private static func fractionalDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func standardDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func write(_ contents: String, to url: URL) -> Bool {
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    private static func write(_ contents: Data, to url: URL) -> Bool {
        do {
            try contents.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private static func setModificationDate(_ date: Date, for url: URL) -> Bool {
        do {
            try FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: url.path
            )
            return true
        } catch {
            return false
        }
    }

    private static func withTemporaryDirectory(_ body: (URL) -> Bool) -> Bool {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexQuotaTests-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            return false
        }
        defer { try? FileManager.default.removeItem(at: root) }
        return body(root)
    }

    private static func withPreferencesSuite(_ body: (UserDefaults) -> Bool) -> Bool {
        let suiteName = "CodexQuotaTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return false
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        return body(defaults)
    }
}
