# Codex Quota Style Menu and Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Unicode quota bar with three switchable macOS-style battery presentations, persist the chosen style and Codex-label visibility, and produce a colleague-shareable Apple Silicon ZIP.

**Architecture:** Add a focused `CodexQuotaUI` library between the existing core quota reader and the AppKit application. The library owns display preferences and deterministic status-item presentations; the app owns menu wiring and live state, while the existing transactional build script extends its staged replacement to both the App and ZIP.

**Tech Stack:** Swift 6.3, Foundation, AppKit, UserDefaults, Swift Package Manager, shell, `ditto`, `codesign`, `iconutil`, Launch Services.

**Repository note:** This projectless workspace is not a Git worktree. Commit steps are omitted rather than creating a repository the user did not request.

---

## File map

- Modify `work/CodexQuota/Package.swift`: add `CodexQuotaUI` library and connect app/test runner dependencies.
- Create `work/CodexQuota/Sources/CodexQuotaUI/BatteryStyle.swift`: style identifiers and user-facing menu labels.
- Create `work/CodexQuota/Sources/CodexQuotaUI/DisplayPreferences.swift`: injected `UserDefaults` persistence and fallback behavior.
- Create `work/CodexQuota/Sources/CodexQuotaUI/BatteryStatusRenderer.swift`: vector battery image and status-button presentation generation.
- Modify `work/CodexQuota/Sources/CodexQuotaApp/main.swift`: custom update row, menu items, checkmarks, immediate style/label updates, and live snapshot reuse.
- Modify `work/CodexQuota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift`: add framework-free UI and persistence tests to the existing executable runner.
- Modify `work/CodexQuota/Scripts/build_app.sh`: stage, validate, transactionally replace, and verify the distribution ZIP.
- Create `outputs/Codex Quota-arm64.zip`: colleague-shareable archive.

### Task 1: Style model and persistent preferences

**Files:**
- Modify: `work/CodexQuota/Package.swift`
- Create: `work/CodexQuota/Sources/CodexQuotaUI/BatteryStyle.swift`
- Create: `work/CodexQuota/Sources/CodexQuotaUI/DisplayPreferences.swift`
- Modify: `work/CodexQuota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift`

- [ ] **Step 1: Add failing style and persistence tests to the executable runner**

Add cases that require:

```swift
expect(BatteryStyle.defaultStyle, equals: .native)
expect(BatteryStyle.allCases.map(\.rawValue), equals: ["native", "embedded", "segmented"])
```

Use a unique `UserDefaults(suiteName:)`, clear its persistent domain, and test:

```swift
let preferences = DisplayPreferences(defaults: defaults)
expect(preferences.batteryStyle, equals: .native)
expect(preferences.showsCodexLabel, equals: true)
preferences.batteryStyle = .segmented
preferences.showsCodexLabel = false
let restored = DisplayPreferences(defaults: defaults)
expect(restored.batteryStyle, equals: .segmented)
expect(restored.showsCodexLabel, equals: false)
defaults.set("unsupported", forKey: DisplayPreferences.batteryStyleKey)
expect(DisplayPreferences(defaults: defaults).batteryStyle, equals: .native)
```

- [ ] **Step 2: Run the runner and verify RED**

Run: `swift run --package-path work/CodexQuota CodexQuotaCoreTests`

Expected: compilation fails because `BatteryStyle` and `DisplayPreferences` do not exist.

- [ ] **Step 3: Add the UI target and minimal models**

`Package.swift` adds:

```swift
.library(name: "CodexQuotaUI", targets: ["CodexQuotaUI"])
.target(name: "CodexQuotaUI", dependencies: ["CodexQuotaCore"])
```

Both `CodexQuotaApp` and `CodexQuotaCoreTests` depend on `CodexQuotaUI`.

Define:

```swift
public enum BatteryStyle: String, CaseIterable, Sendable {
    case native
    case embedded
    case segmented

    public static let defaultStyle: BatteryStyle = .native

    public var menuTitle: String {
        switch self {
        case .native: "A · 原生电池"
        case .embedded: "B · 数字内嵌"
        case .segmented: "C · 分段电池"
        }
    }
}
```

`DisplayPreferences` stores `batteryStyle` and `showsCodexLabel` through an injected `UserDefaults`. Use `object(forKey:) == nil` to distinguish the absent label key from a stored `false`; invalid style strings fall back to `.native`.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `swift run --package-path work/CodexQuota CodexQuotaCoreTests`

Expected: all existing 24 tests and new preference tests pass.

### Task 2: Vector battery renderer and status presentations

**Files:**
- Create: `work/CodexQuota/Sources/CodexQuotaUI/BatteryStatusRenderer.swift`
- Modify: `work/CodexQuota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift`

- [ ] **Step 1: Write failing presentation tests**

Define expected button titles and image traits for every style:

```swift
expect(renderer.presentation(style: .native, remainingPercent: 49, showsCodexLabel: true).title, equals: "Codex 49%")
expect(renderer.presentation(style: .native, remainingPercent: nil, showsCodexLabel: false).title, equals: "--%")
expect(renderer.presentation(style: .embedded, remainingPercent: 49, showsCodexLabel: true).title, equals: "Codex")
expect(renderer.presentation(style: .embedded, remainingPercent: nil, showsCodexLabel: false).title, equals: "")
expect(renderer.presentation(style: .segmented, remainingPercent: 100, showsCodexLabel: false).title, equals: "100%")
```

For `.native`, `.embedded`, and `.segmented` at `nil`, `0`, `49`, and `100`, assert the image is non-nil, `isTemplate == true`, has the documented logical size, and contains non-empty TIFF data. Assert input values clamp to `0...100`.

- [ ] **Step 2: Run the runner and verify RED**

Run: `swift run --package-path work/CodexQuota CodexQuotaCoreTests`

Expected: compilation fails because `BatteryStatusRenderer` and `StatusPresentation` do not exist.

- [ ] **Step 3: Implement deterministic vector rendering**

Create:

```swift
public struct StatusPresentation {
    public let title: String
    public let image: NSImage
}

public struct BatteryStatusRenderer {
    public func presentation(
        style: BatteryStyle,
        remainingPercent: Int?,
        showsCodexLabel: Bool
    ) -> StatusPresentation
}
```

Draw using `NSImage(size:flipped:drawingHandler:)`, `NSBezierPath`, and `NSColor.black` as an alpha mask, then set `image.isTemplate = true`:

- A: 31×14 body plus a 2×6 terminal; rounded outline and one continuous inner fill proportional to the clamped percentage.
- B: 38×16 body plus terminal; outline, subtle inner fill, and centered `49` or `--` text drawn into the template mask.
- C: 36×14 body plus terminal; outline and five inner cells, with filled cells calculated using rounded-up fifths so any non-zero remainder remains visible.

Keep the renderer stateless. It must not read files, mutate preferences, or know about menu items.

- [ ] **Step 4: Run all tests and build release**

Run:

```bash
swift run --package-path work/CodexQuota CodexQuotaCoreTests
swift build --package-path work/CodexQuota -c release --arch arm64
```

Expected: all tests pass; release build succeeds without concurrency or AppKit warnings.

### Task 3: Menu integration and immediate persisted switching

**Files:**
- Modify: `work/CodexQuota/Sources/CodexQuotaApp/main.swift`

- [ ] **Step 1: Replace the legacy Unicode title path with presentation state**

Import `CodexQuotaUI`. Add one retained `DisplayPreferences`, one `BatteryStatusRenderer`, and `currentSnapshot: QuotaSnapshot?`. Remove all calls to `QuotaRenderer.title` from the app. `apply(_:)` stores the snapshot, updates the time label, and calls `updateStatusPresentation()`.

`updateStatusPresentation()` must only render from `currentSnapshot` and preferences:

```swift
let presentation = renderer.presentation(
    style: preferences.batteryStyle,
    remainingPercent: currentSnapshot?.remainingPercent,
    showsCodexLabel: preferences.showsCodexLabel
)
statusItem.button?.image = presentation.image
statusItem.button?.imagePosition = .imageLeading
statusItem.button?.title = presentation.title
```

- [ ] **Step 2: Build the required menu and actions**

Menu order must be custom update row, separator, three style items, label toggle, separator, quit. Store style items by `BatteryStyle`; use their `tag` or `representedObject` to map actions safely. Add selectors:

```swift
@objc private func selectBatteryStyle(_ sender: NSMenuItem)
@objc private func toggleCodexLabel(_ sender: NSMenuItem)
```

Each selector updates `DisplayPreferences`, refreshes checkmarks, and calls `updateStatusPresentation()` only. It must not call `refresh()` or scan sessions.

The first `NSMenuItem` owns a custom `NSView` with a left-aligned label and a right-aligned bordered `NSButton` titled `刷新`. The label is `更新时间：HH:mm`, derived from the latest snapshot in the current system time zone, or `更新时间：--:--` when no snapshot exists. The button calls the existing `refresh()` path immediately, is disabled while `isRefreshing == true`, and is re-enabled on completion. Remove the standalone `立即刷新` item. Keep the automatic selector-based timer at 15 seconds.

- [ ] **Step 3: Verify the app build and lifecycle**

Run the complete runner and release build, then launch the release executable for at least 16 seconds. Confirm a single process survives a timer cycle and terminates cleanly.

### Task 4: Transactional ZIP distribution and end-to-end visual QA

**Files:**
- Modify: `work/CodexQuota/Scripts/build_app.sh`
- Create: `outputs/Codex Quota-arm64.zip`

- [ ] **Step 1: Extend staging and rollback to the ZIP**

Add:

```bash
ZIP="$OUTPUT_DIR/Codex Quota-arm64.zip"
STAGING_ZIP="$TEMP_DIR/Codex Quota-arm64.zip"
BACKUP_ZIP="$OUTPUT_DIR/.Codex Quota-arm64.zip.backup.$$"
```

After staging App validation, create the archive with:

```bash
ditto -c -k --sequesterRsrc --keepParent "$STAGING_APP" "$STAGING_ZIP"
```

Extract into `$TEMP_DIR/verify-zip`, locate `Codex Quota.app`, and verify its plist, arm64 executable, permissions, and strict signature. Extend the existing replacement transaction so any failed App or ZIP move restores both previous outputs. Do not delete either previous output before staging verification succeeds.

- [ ] **Step 2: Run full automated bundle verification**

From `/tmp`, run `build_app.sh`, then verify:

```bash
plutil -lint "outputs/Codex Quota.app/Contents/Info.plist"
codesign --verify --deep --strict "outputs/Codex Quota.app"
unzip -t "outputs/Codex Quota-arm64.zip"
ditto -x -k "outputs/Codex Quota-arm64.zip" /tmp/codex-quota-unpacked
codesign --verify --deep --strict "/tmp/codex-quota-unpacked/Codex Quota.app"
file "/tmp/codex-quota-unpacked/Codex Quota.app/Contents/MacOS/CodexQuotaApp"
```

Expected: validation succeeds, extracted App is arm64, and no group/world writable paths exist.

- [ ] **Step 3: Failure-injection verification**

Hash every file in the existing App and the ZIP. Run the build with an invalid `DEVELOPER_DIR` or injected post-staging failure. Expected: non-zero exit, previous App and ZIP hashes unchanged, previous signatures valid, and no staging/backup paths remain.

- [ ] **Step 4: Actual menu and visual QA**

Launch the final App and verify through the real menu:

- initial/default style is A and `Codex` is shown for a clean preferences domain;
- first row displays `更新时间：HH:mm` with a clickable `刷新` button; the button disables during refresh and restores after completion;
- A/B/C menu checkmarks follow the selected style;
- toggling `显示 Codex 文字` updates immediately;
- relaunch preserves the selected style and label visibility;
- all styles render without clipping in light and dark menu-bar appearances;
- no-data images render correctly using a temporary empty sessions root or renderer QA harness;
- app survives a 15-second refresh and exits through the menu with no process left.

Capture final screenshots for A, B, and C at the current percentage and keep them under `work/verification`; only the App and ZIP belong in `outputs`.

### Task 3B: Reset countdown and persistent comparison menu

**Files:**
- Modify: `work/CodexQuota/Sources/CodexQuotaCore/QuotaSnapshot.swift`
- Modify: `work/CodexQuota/Sources/CodexQuotaCore/QuotaParser.swift`
- Create: `work/CodexQuota/Sources/CodexQuotaUI/ResetCountdownFormatter.swift`
- Modify: `work/CodexQuota/Sources/CodexQuotaApp/main.swift`
- Modify: `work/CodexQuota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift`

- [ ] **Step 1: Add failing reset-window tests**

Extend `QuotaSnapshot` expectations so the selected highest-usage window carries its `resets_at` Unix timestamp as `resetsAt: Date?`. Test primary/secondary selection, missing reset data, and an equal-use deterministic selection. Add formatter tests for `2d3h`, `0d4h`, expired `0d0h`, and missing `--` using an injected `now`.

- [ ] **Step 2: Implement the minimal reset model and formatter**

`QuotaParser` selects a complete window record rather than only a numeric percentage, then computes remaining percentage and optional reset date from that same window. `ResetCountdownFormatter.string(resetsAt:now:)` floors complete days/hours after clamping negative intervals to zero.

- [ ] **Step 3: Replace style menu items with custom persistent rows**

Create custom row views containing a checkmark, style title, and a right-aligned preview from the real vector renderer. The entire row is clickable. Its action updates preferences and all row states without cancelling menu tracking, so the menu remains visible while comparing styles. The label toggle must also remain open after clicking.

Expand the custom information area to two text rows plus the existing refresh button:

```text
更新时间：04:59                 [刷新]
下次重置：2d3h
```

Recompute the countdown on automatic/manual refresh and when the menu opens; do not alter the snapshot timestamp.

- [ ] **Step 4: Verify behavior and rebuild distribution**

Run the complete runner and release build. In the real App, open the menu once, switch A/B/C and toggle the label without the menu closing, verify previews/checkmarks, verify reset text against the current snapshot, then rebuild and revalidate both App and ZIP transactionally.

### Task 3C: Readable number badge and automatic-only refresh

**Files:**
- Modify: `work/CodexQuota/Sources/CodexQuotaUI/BatteryStatusRenderer.swift`
- Modify: `work/CodexQuota/Sources/CodexQuotaUI/ResetCountdownFormatter.swift`
- Modify: `work/CodexQuota/Sources/CodexQuotaApp/main.swift`
- Modify: `work/CodexQuota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift`

- [ ] **Step 1: Add failing presentation and copy tests**

Require style B to render a `34×18pt` rounded number badge without a battery terminal or external percentage. Cover `0`, `8`, `60`, `100`, and nil so the badge retains readable template contrast at 1× and 2×. Change reset formatter expectations to `2 天 3 小时`, `0 天 4 小时`, `0 天 0 小时`, and `--`.

- [ ] **Step 2: Verify RED**

Run `swift run --package-path work/CodexQuota CodexQuotaCoreTests`. Expected: the old outlined embedded battery size/geometry and `XdXh` strings fail the new assertions.

- [ ] **Step 3: Implement the minimal renderer and menu change**

Replace the style-B battery body/terminal with a single rounded `34×18pt` template badge. Center a monospaced semibold value using the largest size that fits all supported 1–3 digit values. Remove `refreshButton`, `refreshRequested`, its constraints, and refresh-enabled state from `main.swift`; keep the existing 15-second timer on `.common`. Display only the two header labels.

- [ ] **Step 4: Verify GREEN and real behavior**

Run the complete runner and arm64 release build. Verify the menu contains no `刷新` control, `更新时间` remains the snapshot time, the countdown uses Chinese units, style B is readable in the real menu bar and preview, keyboard/mouse switching keeps the menu open, and the process survives at least two automatic refresh periods before rebuilding App and ZIP.

### Task 3D: Second-precision update time and one-time launch notice

**Files:**
- Create: `work/CodexQuota/Sources/CodexQuotaUI/UpdateTimeFormatter.swift`
- Modify: `work/CodexQuota/Sources/CodexQuotaUI/DisplayPreferences.swift`
- Modify: `work/CodexQuota/Sources/CodexQuotaApp/main.swift`
- Modify: `work/CodexQuota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift`

- [ ] **Step 1: Add failing formatter and persistence tests**

Require a fixed UTC date to format as `12:34:56`. Require the launch-notice preference to default to `false`, persist `true`, and remain independent from style and label preferences.

- [ ] **Step 2: Verify RED**

Run `swift run --package-path work/CodexQuota CodexQuotaCoreTests`. Expected: compilation fails because `UpdateTimeFormatter` and the launch-notice preference do not exist.

- [ ] **Step 3: Implement the minimal formatter and first-launch alert**

Add a focused `UpdateTimeFormatter` using `HH:mm:ss`. Change the header placeholders to `--:--:--`. Add `hasShownAutoRefreshNotice` to `DisplayPreferences`. After configuring the status item and 15-second timer, show one informational `NSAlert` with title `Codex Quota 已启动`, content `额度每 15 秒自动更新一次，无需手动刷新。`, and button `知道了` only when the stored flag is false; persist true after dismissal.

- [ ] **Step 4: Verify GREEN and distribution**

Run the complete runner and arm64 warnings-as-errors build. Rebuild App and ZIP, verify signatures/architecture/permissions, then launch twice with a clean notice preference and confirm the alert appears only on the first launch.
