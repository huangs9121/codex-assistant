# Codex Quota v1.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Codex Quota v1.1.0 with plan metadata, three identity modes, an optional compact reset suffix, GitHub Release notifications, launch-at-login control, and a public arm64 release.

**Architecture:** Extend `CodexQuotaCore` with pure parsing and update-policy types, keep rendering and preferences in `CodexQuotaUI`, and isolate GitHub networking plus `SMAppService` behind small App-layer controllers. Preserve the existing 15-second local quota scan and flat AppKit menu; add only the files needed to keep each responsibility testable.

**Tech Stack:** Swift 6, Foundation, AppKit, ServiceManagement, URLSession, Swift Package Manager, UserDefaults, shell, GitHub CLI/API, `codesign`, `ditto`.

---

## File map

- Modify `apps/codex-quota/Sources/CodexQuotaCore/QuotaSnapshot.swift`: carry the normalized plan with each quota snapshot.
- Modify `apps/codex-quota/Sources/CodexQuotaCore/QuotaParser.swift`: read `rate_limits.plan_type` without changing window selection.
- Create `apps/codex-quota/Sources/CodexQuotaCore/PlanInfo.swift`: normalize plan names and parse a safe subscription expiry from `auth.json` data.
- Create `apps/codex-quota/Sources/CodexQuotaCore/ReleaseUpdate.swift`: decode GitHub Releases, compare semantic versions, and decide check/prompt timing.
- Create `apps/codex-quota/Sources/CodexQuotaUI/StatusIdentityMode.swift`: text/logo/hidden identity model and menu titles.
- Modify `apps/codex-quota/Sources/CodexQuotaUI/DisplayPreferences.swift`: migrate the old label Boolean and persist identity/reset/update state.
- Modify `apps/codex-quota/Sources/CodexQuotaUI/ResetCountdownFormatter.swift`: retain full Chinese format and add compact `D/H` output.
- Create `apps/codex-quota/Sources/CodexQuotaUI/OpenAILogoRenderer.swift`: render the exact monochrome Blossom template image from the official vector path.
- Modify `apps/codex-quota/Sources/CodexQuotaUI/BatteryStatusRenderer.swift`: compose identity, battery, percent, and optional compact reset suffix.
- Create `apps/codex-quota/Sources/CodexQuotaApp/GitHubUpdateController.swift`: perform throttled/manual latest-release checks and open release pages.
- Create `apps/codex-quota/Sources/CodexQuotaApp/LaunchAtLoginController.swift`: expose truthful `SMAppService.mainAppService` state and operations.
- Modify `apps/codex-quota/Sources/CodexQuotaApp/main.swift`: assemble the flat menu, info rows, toggles, update prompts, and timers.
- Modify `apps/codex-quota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift`: extend the existing executable runner with deterministic Core/UI tests.
- Create `apps/codex-quota/Scripts/version.env`: single source for marketing/build versions.
- Modify `apps/codex-quota/Scripts/build_app.sh`: inject version metadata and keep existing transactional bundle/ZIP verification.
- Create `apps/codex-quota/Scripts/release_github.sh`: verify, tag, publish, and upload the arm64 ZIP.
- Modify `README.md`: document v1.1 features, privacy, installation, updates, login item, and non-official trademark notice.
- Modify `.gitignore`: ignore `.superpowers/` visual-companion sessions.

### Task 1: Parse and display the current plan

**Files:**
- Create: `apps/codex-quota/Sources/CodexQuotaCore/PlanInfo.swift`
- Modify: `apps/codex-quota/Sources/CodexQuotaCore/QuotaSnapshot.swift`
- Modify: `apps/codex-quota/Sources/CodexQuotaCore/QuotaParser.swift`
- Modify: `apps/codex-quota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift`

- [ ] **Step 1: Add failing plan normalization and snapshot tests**

Register these cases in the runner and implement their bodies:

```swift
private static func testPlanNormalization() -> Bool {
    [
        ("prolite", "Pro"), ("pro", "Pro"), ("plus", "Plus"),
        ("free", "Free"), ("team", "Team"),
        ("business", "Business"), ("enterprise", "Enterprise")
    ].allSatisfy { raw, expected in
        expect(PlanInfo.normalizedName(raw), equals: expected)
    }
}

private static func testUnknownPlanIsNil() -> Bool {
    expect(PlanInfo.normalizedName("mystery"), equals: nil)
        && expect(PlanInfo.normalizedName(nil), equals: nil)
}

private static func testQuotaSnapshotCarriesPlan() -> Bool {
    let snapshot = QuotaParser.snapshot(from: tokenCountLine(
        primary: 40,
        planType: "prolite"
    ))
    return expect(snapshot?.planName, equals: "Pro")
}
```

Extend `tokenCountLine` with `planType: String? = nil` and emit `"plan_type":"..."` as a sibling of `primary` and `secondary` when present. Add one case proving an unknown plan keeps the otherwise valid snapshot and produces `planName == nil`.

- [ ] **Step 2: Run the runner and verify RED**

Run:

```bash
swift run --package-path apps/codex-quota CodexQuotaCoreTests
```

Expected: compilation fails because `PlanInfo` and `QuotaSnapshot.planName` do not exist.

- [ ] **Step 3: Implement the minimal plan model and parser change**

Create `PlanInfo.swift`:

```swift
import Foundation

public enum PlanInfo {
    public static func normalizedName(_ rawValue: String?) -> String? {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "prolite", "pro": "Pro"
        case "plus": "Plus"
        case "free": "Free"
        case "team": "Team"
        case "business": "Business"
        case "enterprise": "Enterprise"
        default: nil
        }
    }
}
```

Add `public let planName: String?` and `planName: String? = nil` to `QuotaSnapshot`. In `QuotaParser.snapshot(from:)`, compute:

```swift
let planName = PlanInfo.normalizedName(rateLimits["plan_type"] as? String)
```

and pass it to the snapshot without changing primary/secondary selection.

- [ ] **Step 4: Run tests and commit**

Run the same test command. Expected: all tests pass, including `prolite → Pro` and unknown-plan fallback.

```bash
git add apps/codex-quota/Sources/CodexQuotaCore apps/codex-quota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift
git commit -m "feat: parse Codex plan metadata"
```

### Task 2: Read subscription expiry without exposing auth data

**Files:**
- Modify: `apps/codex-quota/Sources/CodexQuotaCore/PlanInfo.swift`
- Modify: `apps/codex-quota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift`

- [ ] **Step 1: Add failing JWT and auth-file tests**

Add a test helper that builds an unsigned JWT payload without real credentials:

```swift
private static func testToken(
    plan: String,
    activeUntil: String
) -> String {
    let payload = try! JSONSerialization.data(withJSONObject: [
        "https://api.openai.com/auth": [
            "chatgpt_plan_type": plan,
            "chatgpt_subscription_active_until": activeUntil
        ]
    ])
    let body = payload.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(body).signature"
}
```

Test `PlanInfo.subscriptionExpiry(authData:currentPlan:now:)` for:

```swift
let future = "2026-08-01T00:00:00Z"
let authData = try! JSONSerialization.data(withJSONObject: [
    "tokens": ["id_token": testToken(plan: "prolite", activeUntil: future)]
])
expect(
    PlanInfo.subscriptionExpiry(
        authData: authData,
        currentPlan: "Pro",
        now: ISO8601DateFormatter().date(from: "2026-07-15T00:00:00Z")!
    ),
    equals: ISO8601DateFormatter().date(from: future)
)
```

Add mismatch (`Plus` token vs `Pro` snapshot), expired date, malformed JWT, missing claim, invalid JSON, and `currentPlan == nil` cases; each must return `nil`.

- [ ] **Step 2: Run RED**

Run the runner. Expected: compilation fails because `subscriptionExpiry` does not exist.

- [ ] **Step 3: Implement narrowly scoped payload parsing**

Add:

```swift
public static func subscriptionExpiry(
    authData: Data,
    currentPlan: String?,
    now: Date = Date()
) -> Date? {
    guard
        let currentPlan,
        let auth = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
        let tokens = auth["tokens"] as? [String: Any],
        let idToken = tokens["id_token"] as? String,
        let claims = jwtPayload(idToken),
        let namespace = claims["https://api.openai.com/auth"] as? [String: Any],
        normalizedName(namespace["chatgpt_plan_type"] as? String) == currentPlan,
        let rawDate = namespace["chatgpt_subscription_active_until"] as? String,
        let expiry = ISO8601DateFormatter().date(from: rawDate),
        expiry > now
    else { return nil }
    return expiry
}
```

`jwtPayload(_:)` must split into exactly three dot-separated parts, restore Base64URL padding locally, decode only the middle part, return a dictionary, and never print or store input data.

- [ ] **Step 4: Run tests and commit**

Expected: all auth cases pass and the test output contains no JWT or claims.

```bash
git add apps/codex-quota/Sources/CodexQuotaCore/PlanInfo.swift apps/codex-quota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift
git commit -m "feat: read matching subscription expiry"
```

### Task 3: Add identity migration and compact reset preferences

**Files:**
- Create: `apps/codex-quota/Sources/CodexQuotaUI/StatusIdentityMode.swift`
- Modify: `apps/codex-quota/Sources/CodexQuotaUI/DisplayPreferences.swift`
- Modify: `apps/codex-quota/Sources/CodexQuotaUI/ResetCountdownFormatter.swift`
- Modify: `apps/codex-quota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift`

- [ ] **Step 1: Add failing preference migration and formatter tests**

Test the stable identity order and titles:

```swift
expect(StatusIdentityMode.allCases.map(\.rawValue), equals: ["text", "logo", "hidden"])
expect(StatusIdentityMode.allCases.map(\.menuTitle), equals: [
    "显示 Codex 文字", "显示 OpenAI Logo", "不显示标识"
])
```

Using isolated `UserDefaults` suites, verify:

- no old/new key defaults to `.text`;
- old `showsCodexLabel == true` migrates to `.text` and writes the new key;
- old `showsCodexLabel == false` migrates to `.hidden` and writes the new key;
- an existing new `.logo` value wins over the old key;
- invalid new values fall back to `.text`;
- `showsResetCountdownInStatusBar` defaults to `false` and persists `true`.

Add compact reset expectations:

```swift
expect(ResetCountdownFormatter.compactString(
    resetsAt: now.addingTimeInterval(51 * 3_600), now: now
), equals: "2D")
expect(ResetCountdownFormatter.compactString(
    resetsAt: now.addingTimeInterval(23 * 3_600 + 59 * 60), now: now
), equals: "23H")
expect(ResetCountdownFormatter.compactString(
    resetsAt: now.addingTimeInterval(59 * 60), now: now
), equals: "0H")
expect(ResetCountdownFormatter.compactString(resetsAt: nil, now: now), equals: "--")
```

- [ ] **Step 2: Run RED**

Run the runner. Expected: missing `StatusIdentityMode`, new preference, and compact formatter symbols.

- [ ] **Step 3: Implement the enum, migration, and compact formatter**

Create:

```swift
public enum StatusIdentityMode: String, CaseIterable, Sendable {
    case text, logo, hidden

    public var menuTitle: String {
        switch self {
        case .text: "显示 Codex 文字"
        case .logo: "显示 OpenAI Logo"
        case .hidden: "不显示标识"
        }
    }
}
```

Add keys `statusIdentityMode` and `showsResetCountdownInStatusBar`. The `identityMode` getter first reads a valid new raw value; otherwise it maps the old Boolean, writes the migrated raw value once, and returns it. Do not delete the old key. Add:

```swift
public static func compactString(resetsAt: Date?, now: Date = Date()) -> String {
    guard let resetsAt else { return "--" }
    let seconds = resetsAt.timeIntervalSince(now)
    guard seconds.isFinite else { return "--" }
    let hours = Int(floor(max(0, seconds) / 3_600))
    return hours >= 24 ? "\(hours / 24)D" : "\(hours)H"
}
```

- [ ] **Step 4: Run tests and commit**

```bash
swift run --package-path apps/codex-quota CodexQuotaCoreTests
git add apps/codex-quota/Sources/CodexQuotaUI apps/codex-quota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift
git commit -m "feat: add identity and reset display preferences"
```

### Task 4: Render the OpenAI identity and complete status composition

**Files:**
- Create: `apps/codex-quota/Sources/CodexQuotaUI/OpenAILogoRenderer.swift`
- Modify: `apps/codex-quota/Sources/CodexQuotaUI/BatteryStatusRenderer.swift`
- Modify: `apps/codex-quota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift`

- [ ] **Step 1: Add failing renderer matrix and accessibility tests**

Replace Boolean-label renderer calls with:

```swift
renderer.presentation(
    style: style,
    remainingPercent: 60,
    identityMode: identity,
    compactReset: compactReset
)
```

Test all `3 styles × 3 identities × [nil, "2D"]` combinations for a non-empty 18pt-high template image, safe transparent margins, and no clipping at 1x/2x. Assert text mode is wider than hidden, logo mode adds exactly the documented 17pt logo plus gap, and the suffix widens every style by its measured text plus gap. Accessibility must say, for example, `Codex 剩余额度 60%，下次重置 2D，显示 OpenAI Logo`.

Add pixel-level tests that `OpenAILogoRenderer.image()` is 17×17pt, a template image, non-empty, centered, and keeps a transparent outer margin.

- [ ] **Step 2: Run RED**

Expected: compilation fails because the new renderer signature and logo renderer do not exist.

- [ ] **Step 3: Add the official monochrome Blossom renderer**

Create `OpenAILogoRenderer` using the exact normalized vector coordinates from the official OpenAI logo download linked in the design spec. Scale the path uniformly into a 15×15 drawing rect centered on a 17×17 canvas:

```swift
public enum OpenAILogoRenderer {
    public static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 17, height: 17), flipped: false) { rect in
            let path = officialBlossomPath(in: rect.insetBy(dx: 1, dy: 1))
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
```

The implementation commit must include a source comment with `https://openai.com/brand/`, must not add color/effects, and must not reuse the visual-companion Wikimedia preview asset.

- [ ] **Step 4: Compose identity, battery, percentage, and reset suffix**

Change the public API to:

```swift
public func presentation(
    style: BatteryStyle,
    remainingPercent: Int?,
    identityMode: StatusIdentityMode,
    compactReset: String?
) -> StatusPresentation
```

Draw `.text` as the existing `Codex` attributed string, `.logo` as `OpenAILogoRenderer.image()`, and `.hidden` as nothing. Keep the embedded style's number inside its badge; native and segmented styles retain the trailing percent. If `compactReset` is non-nil, append it after a 4pt gap for all styles. Generate the accessibility label from the selected identity and optional suffix.

- [ ] **Step 5: Run tests, visually inspect generated PNGs, and commit**

Run:

```bash
swift run --package-path apps/codex-quota CodexQuotaCoreTests
swift build --package-path apps/codex-quota -c release --arch arm64
```

Export the existing renderer QA matrix to `verification/v1.1-renderer/` and inspect text/logo/hidden plus reset suffix at 1x and 2x. Expected: all glyphs are legible and inside the canvas.

```bash
git add apps/codex-quota/Sources/CodexQuotaUI apps/codex-quota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift
git commit -m "feat: render status identity and reset suffix"
```

### Task 5: Implement semantic release checks and throttling

**Files:**
- Create: `apps/codex-quota/Sources/CodexQuotaCore/ReleaseUpdate.swift`
- Modify: `apps/codex-quota/Sources/CodexQuotaUI/DisplayPreferences.swift`
- Modify: `apps/codex-quota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift`

- [ ] **Step 1: Add failing semantic-version, payload, and policy tests**

Test:

```swift
expect(SemanticVersion("1.9.0")! < SemanticVersion("1.10.0")!, equals: true)
expect(SemanticVersion("v1.2.0"), equals: SemanticVersion("1.2.0"))
expect(SemanticVersion("1.2"), equals: nil)
expect(SemanticVersion("latest"), equals: nil)
```

Decode a fixture with `tag_name`, `name`, `body`, `html_url`, `draft`, and `prerelease`. Assert drafts/prereleases/invalid URLs are rejected. Assert `GitHubRelease.latestRequest()` targets only `https://api.github.com/repos/huangs9121/codex-assistant/releases/latest`, uses `GET`, sets `Accept: application/vnd.github+json` and `User-Agent: Codex-Quota/1.1.0`, has a 10-second timeout, and has no `Authorization` header. Add `UpdatePolicy.shouldAutomaticallyCheck(lastSuccess:lastFailure:now:)` tests for first launch, 23h/24h since success, 59m/1h since failure, and the stricter of the two timestamps. Add `shouldPrompt(version:lastPromptedVersion:)` tests for once-per-version behavior.

- [ ] **Step 2: Run RED**

Expected: missing semantic version, payload, and policy types.

- [ ] **Step 3: Implement pure release types**

Create:

```swift
public struct SemanticVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ rawValue: String) {
        let value = rawValue.hasPrefix("v") ? String(rawValue.dropFirst()) : rawValue
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0 else { return nil }
        self.major = major; self.minor = minor; self.patch = patch
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
```

`GitHubRelease` conforms to `Decodable` using explicit snake-case coding keys and exposes `eligibleVersion` only when `draft == false`, `prerelease == false`, the tag is valid, and `htmlURL.scheme == "https"`. Its `latestRequest()` factory constructs the exact request and headers above, making the privacy boundary testable without live networking. `UpdatePolicy` uses 24×3600 seconds after success, 3600 seconds after failure, and exact `>=` boundaries.

Add `lastUpdateCheckSuccess`, `lastUpdateCheckFailure`, and `lastPromptedVersion` typed properties to `DisplayPreferences`.

- [ ] **Step 4: Run tests and commit**

```bash
swift run --package-path apps/codex-quota CodexQuotaCoreTests
git add apps/codex-quota/Sources/CodexQuotaCore/ReleaseUpdate.swift apps/codex-quota/Sources/CodexQuotaUI/DisplayPreferences.swift apps/codex-quota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift
git commit -m "feat: add GitHub release update policy"
```

### Task 6: Add GitHub networking and launch-at-login controllers

**Files:**
- Create: `apps/codex-quota/Sources/CodexQuotaApp/GitHubUpdateController.swift`
- Create: `apps/codex-quota/Sources/CodexQuotaApp/LaunchAtLoginController.swift`
- Modify: `apps/codex-quota/Sources/CodexQuotaApp/main.swift`

- [ ] **Step 1: Implement a single-purpose GitHub update controller**

Define:

```swift
@MainActor
final class GitHubUpdateController {
    enum Result { case update(GitHubRelease), current, failure(String) }

    func check(
        currentVersion: SemanticVersion,
        manual: Bool,
        completion: @escaping (Result) -> Void
    )
}
```

Build only `https://api.github.com/repos/huangs9121/codex-assistant/releases/latest`, set `Accept: application/vnd.github+json`, `User-Agent: Codex-Quota/1.1.0`, and a 10-second timeout. Use an ephemeral `URLSessionConfiguration`; send no auth header. For automatic checks, consult `UpdatePolicy`; on success/failure persist the matching timestamp. Dispatch all completions to `MainActor`. Decode with `JSONDecoder`, compare against `Bundle.main` marketing version, and return `.current` for equal/older/ineligible releases.

- [ ] **Step 2: Implement a truthful `SMAppService` wrapper**

Define:

```swift
import AppKit
import ServiceManagement

@MainActor
final class LaunchAtLoginController {
    enum State { case enabled, disabled, requiresApproval, unavailable(String) }

    var state: State { /* map SMAppService.mainAppService.status */ }
    func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainAppService.register() }
        else { try SMAppService.mainAppService.unregister() }
    }
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
```

Map `.enabled`, `.notRegistered`, `.requiresApproval`, and `.notFound` explicitly. Do not persist a Boolean in UserDefaults.

- [ ] **Step 3: Wire controller lifecycles without changing menu structure yet**

In `AppDelegate`, retain both controllers plus an hourly policy timer. At launch, perform one policy-governed automatic update check; the hourly timer merely reevaluates the policy, so a successful check cannot happen more frequently than 24 hours and a failure cannot retry before one hour. In `applicationWillTerminate`, invalidate both timers. Keep the 15-second quota refresh timer unchanged.

- [ ] **Step 4: Build and commit**

Run:

```bash
swift build --package-path apps/codex-quota -c release --arch arm64
```

Expected: Swift 6 concurrency checks pass; no AppKit/ServiceManagement work escapes `MainActor`.

```bash
git add apps/codex-quota/Sources/CodexQuotaApp
git commit -m "feat: add update and login item controllers"
```

### Task 7: Assemble the final flat menu and prompts

**Files:**
- Modify: `apps/codex-quota/Sources/CodexQuotaApp/main.swift`

- [ ] **Step 1: Expand the four-line information row**

Replace the 52pt header with a 92pt custom row containing:

```swift
private let updateTimeLabel = NSTextField(labelWithString: "更新时间：--:--:--")
private let resetTimeLabel = NSTextField(labelWithString: "下次重置：--")
private let planLabel = NSTextField(labelWithString: "当前套餐：--")
private let expiryLabel = NSTextField(labelWithString: "套餐到期：--")
```

Lay them out vertically at 8pt top, 3pt spacing, 12pt horizontal margins. `apply(_:)` reads `~/.codex/auth.json` on the existing utility queue, calls `PlanInfo.subscriptionExpiry`, and returns only the resulting `Date?` to MainActor; it never retains raw auth data. Format expiry as `yyyy-MM-dd` in the current calendar/time zone. Missing/mismatched data displays `--`.

- [ ] **Step 2: Replace the label toggle with three identity rows and one reset toggle**

Retain `[StatusIdentityMode: NSMenuItem]`. Each identity row uses `MenuChoiceRow`, an appropriate 17pt preview (`Codex`, Blossom, or empty), and an action that writes `preferences.identityMode`, synchronizes checks, and rerenders without scanning sessions. Add `显示重置时间` as a checkable custom row whose action toggles `showsResetCountdownInStatusBar` and rerenders immediately.

Pass:

```swift
let compactReset = preferences.showsResetCountdownInStatusBar
    ? ResetCountdownFormatter.compactString(resetsAt: currentSnapshot?.resetsAt)
    : nil
```

to the renderer.

- [ ] **Step 3: Add the login item and update rows**

Menu order must exactly match the spec: info, separator, A/B/C, text/logo/hidden, separator, reset toggle, launch toggle, separator, update, quit. Sync the launch row from `LaunchAtLoginController.state` each time the menu opens. On `.requiresApproval`, title it `开机自动启动（需系统确认）` and open Login Items settings. On errors, show an `NSAlert` and immediately resync state.

The update row title is `检查更新…` unless a newer release is retained, then `新版本 X.Y.Z 可用…`. Manual checks show current/failure/update results. Automatic checks only show the update prompt once per version. Limit the release body summary to 600 characters, with buttons `前往更新` and `稍后`; open only the decoded HTTPS `html_url` through `NSWorkspace`.

- [ ] **Step 4: Preserve open-menu switching and accessibility**

Continue using custom `NSButton` rows for styles, identities, and toggles so the menu stays visible after selection. Update `MenuChoiceRow` accessibility values and the status button label after every choice. Do not make update, quit, alert, or system-settings actions keep the menu open.

- [ ] **Step 5: Build, run a 16-second smoke test, and commit**

```bash
swift run --package-path apps/codex-quota CodexQuotaCoreTests
swift build --package-path apps/codex-quota -c release --arch arm64
```

Launch the release executable, verify one process survives at least one 15-second refresh, then terminate cleanly.

```bash
git add apps/codex-quota/Sources/CodexQuotaApp/main.swift
git commit -m "feat: complete Codex Quota v1.1 menu"
```

### Task 8: Centralize versioning, document, and package

**Files:**
- Create: `apps/codex-quota/Scripts/version.env`
- Modify: `apps/codex-quota/Scripts/build_app.sh`
- Create: `apps/codex-quota/Scripts/release_github.sh`
- Modify: `README.md`
- Modify: `.gitignore`

- [ ] **Step 1: Add the version source and inject plist values**

Create:

```bash
APP_VERSION=1.1.0
BUILD_NUMBER=2
```

In `build_app.sh`, source it from `SCRIPT_DIR`, validate `APP_VERSION` against `^[0-9]+\.[0-9]+\.[0-9]+$` and `BUILD_NUMBER` against `^[1-9][0-9]*$`, then generate the plist with shell-expanded `CFBundleShortVersionString` and `CFBundleVersion`. Add post-build and post-unzip assertions for both values.

- [ ] **Step 2: Add a guarded GitHub release script**

Create an executable script that:

```bash
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PACKAGE_ROOT/../.." && pwd)"
source "$SCRIPT_DIR/version.env"
TAG="v$APP_VERSION"
cd "$REPO_ROOT"
test -z "$(git status --porcelain)"
test "$(git branch --show-current)" = "main"
git fetch origin main --tags
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
test -z "$(git tag -l "$TAG")"
"$SCRIPT_DIR/build_app.sh"
git tag -a "$TAG" -m "Codex Quota $APP_VERSION"
git push origin "$TAG"
gh release create "$TAG" "outputs/Codex Quota-arm64.zip" \
  --repo huangs9121/codex-assistant \
  --title "Codex Quota $APP_VERSION" \
  --notes-file "docs/releases/$TAG.md" \
  --verify-tag
```

The implementation must create `docs/releases/v1.1.0.md` with the user-visible changes and manual installation instructions before running this script. If `gh release create` fails after tag push, stop and report; do not delete or rewrite the public tag automatically.

- [ ] **Step 3: Update documentation and ignore local visual sessions**

README must state: Pro comes from the latest local rate-limit snapshot; expiry can be `--`; quota refresh is local every 15 seconds; update checks contact only GitHub once per policy; v1.1 opens the release page but never auto-installs; login start is off by default and works best from `/Applications`; arm64/macOS 13+ only; OpenAI owns the Blossom mark and this is an unofficial open-source project. Add `.superpowers/` to `.gitignore`.

- [ ] **Step 4: Build and verify packaging, then commit**

Run:

```bash
apps/codex-quota/Scripts/build_app.sh
plutil -extract CFBundleShortVersionString raw "outputs/Codex Quota.app/Contents/Info.plist"
plutil -extract CFBundleVersion raw "outputs/Codex Quota.app/Contents/Info.plist"
codesign --verify --deep --strict "outputs/Codex Quota.app"
unzip -t "outputs/Codex Quota-arm64.zip"
```

Expected versions: `1.1.0` and `2`; signature and archive checks succeed.

```bash
git add .gitignore README.md apps/codex-quota/Scripts docs/releases/v1.1.0.md
git commit -m "build: prepare Codex Quota 1.1 release"
```

### Task 9: Real macOS QA and public v1.1.0 release

**Files:**
- Verify: `outputs/Codex Quota.app`
- Verify: `outputs/Codex Quota-arm64.zip`
- Verify: `/Applications/Codex Quota.app`

- [ ] **Step 1: Run complete automated verification from a clean commit**

Run:

```bash
test -z "$(git status --porcelain)"
swift run --package-path apps/codex-quota CodexQuotaCoreTests
apps/codex-quota/Scripts/build_app.sh
codesign --verify --deep --strict "outputs/Codex Quota.app"
unzip -t "outputs/Codex Quota-arm64.zip"
```

Extract the ZIP to a temporary directory and repeat plist version, arm64 `file`, permission, and strict signature checks against the extracted App.

- [ ] **Step 2: Perform real menu and persistence QA**

Launch the output App and verify:

- current plan reads `Pro` from the latest local snapshot and expiry is `--` on the current mismatch;
- update time advances to seconds through at least two 15-second cycles;
- all A/B/C styles and text/logo/hidden modes switch while the menu remains open;
- compact reset is absent by default, then shows `XD` or `XH` immediately when enabled;
- selections persist after relaunch;
- automatic update check does not claim v1.1.0 is newer than itself;
- manual update check returns a truthful result without disturbing quota refresh.

Capture light/dark menu and status-bar screenshots under `verification/v1.1/` and inspect them at original resolution.

- [ ] **Step 3: Verify launch at login from `/Applications`**

Copy the built App to `/Applications/Codex Quota.app`, launch that copy, enable the menu option, and confirm the system-reported menu state is enabled or requires approval. If approval is required, use the opened Login Items settings and recheck. Disable it again at the end so QA does not alter the user's preferred startup state. Remove only the QA copy if it was not replacing an existing user installation.

- [ ] **Step 4: Push main and publish the public GitHub Release**

Push implementation commits:

```bash
git push origin main
```

Then run:

```bash
apps/codex-quota/Scripts/release_github.sh
```

Expected: public `v1.1.0`, release page visible without authentication, and `Codex Quota-arm64.zip` downloadable.

- [ ] **Step 5: Final live verification**

Query the public latest-release endpoint and verify tag `v1.1.0`, `draft == false`, `prerelease == false`, HTTPS `html_url`, and one arm64 ZIP asset. Launch the locally built v1.1.0 once more and confirm its manual check reports no update. Report the release URL, local App/ZIP paths, test count, and any expected Gatekeeper warning caused by ad-hoc signing.
