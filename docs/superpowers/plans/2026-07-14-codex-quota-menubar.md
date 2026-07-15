# Codex Quota Menu Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Apple Silicon macOS menu bar app that renders the freshest locally recorded Codex remaining quota as `Codex [██████░░░░] 60%`.

**Architecture:** A small Swift package separates JSONL parsing and session-file lookup from presentation. An AppKit `NSStatusItem` controller refreshes every 15 seconds and renders a ten-cell bar; a shell build script creates and validates a standard agent-style `.app` bundle in `outputs`.

**Tech Stack:** Swift 6.3, Foundation, AppKit, XCTest, Swift Package Manager, `sips`, `iconutil`, `plutil`, Launch Services.

**Repository note:** This projectless workspace is not a Git worktree. Commit steps are omitted rather than initializing a repository the user did not request.

---

## File map

- `work/CodexQuota/Package.swift`: Swift package definition and macOS deployment target.
- `work/CodexQuota/Sources/CodexQuotaCore/QuotaSnapshot.swift`: quota value type.
- `work/CodexQuota/Sources/CodexQuotaCore/QuotaParser.swift`: parses one Codex JSONL event.
- `work/CodexQuota/Sources/CodexQuotaCore/QuotaStore.swift`: locates and reads recent session files.
- `work/CodexQuota/Sources/CodexQuotaCore/QuotaRenderer.swift`: converts remaining percentage into menu text.
- `work/CodexQuota/Sources/CodexQuotaApp/main.swift`: AppKit menu bar lifecycle and refresh timer.
- `work/CodexQuota/Tests/CodexQuotaCoreTests/*.swift`: parser, store, and renderer tests.
- `work/CodexQuota/Scripts/generate_icon.swift`: produces the 1024 px icon source.
- `work/CodexQuota/Scripts/build_app.sh`: release build, iconset creation, bundle assembly, signing, and validation.
- `outputs/Codex Quota.app`: final user-facing application bundle.

### Task 1: Package skeleton and quota parser

**Files:**
- Create: `work/CodexQuota/Package.swift`
- Create: `work/CodexQuota/Sources/CodexQuotaCore/QuotaSnapshot.swift`
- Create: `work/CodexQuota/Sources/CodexQuotaCore/QuotaParser.swift`
- Test: `work/CodexQuota/Tests/CodexQuotaCoreTests/QuotaParserTests.swift`

- [ ] **Step 1: Create the Swift package manifest and empty production files**

`Package.swift` defines a library and executable:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexQuota",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexQuotaCore", targets: ["CodexQuotaCore"]),
        .executable(name: "CodexQuotaApp", targets: ["CodexQuotaApp"]),
    ],
    targets: [
        .target(name: "CodexQuotaCore"),
        .executableTarget(name: "CodexQuotaApp", dependencies: ["CodexQuotaCore"]),
        .testTarget(name: "CodexQuotaCoreTests", dependencies: ["CodexQuotaCore"]),
    ]
)
```

- [ ] **Step 2: Write failing parser tests**

Tests must assert a primary-only event returns `60`, a primary/secondary event returns the tighter `25`, out-of-range values clamp to `0...100`, and invalid/non-token events return `nil`.

```swift
func testParsesPrimaryRemainingPercent() throws {
    let line = #"{"timestamp":"2026-07-14T15:29:53.526Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":40.0}}}}"#
    XCTAssertEqual(QuotaParser.snapshot(from: line)?.remainingPercent, 60)
}

func testUsesTightestWindow() throws {
    let line = #"{"timestamp":"2026-07-14T15:29:53.526Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":20.0},"secondary":{"used_percent":75.0}}}}"#
    XCTAssertEqual(QuotaParser.snapshot(from: line)?.remainingPercent, 25)
}
```

- [ ] **Step 3: Run tests and verify RED**

Run: `cd work/CodexQuota && swift test --filter QuotaParserTests`

Expected: compilation fails because `QuotaParser` and `QuotaSnapshot` are not implemented.

- [ ] **Step 4: Implement the minimal parser**

Use `JSONSerialization`, require `type == event_msg` and `payload.type == token_count`, inspect `primary` and `secondary`, choose the largest `used_percent`, and compute `Int((100 - used).rounded())` clamped to `0...100`. Parse `timestamp` with `ISO8601DateFormatter` using fractional seconds first and the standard internet-date formatter as fallback.

```swift
public struct QuotaSnapshot: Equatable, Sendable {
    public let remainingPercent: Int
    public let observedAt: Date
}

public enum QuotaParser {
    public static func snapshot(from line: String) -> QuotaSnapshot? {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == "event_msg",
              let payload = root["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let limits = payload["rate_limits"] as? [String: Any]
        else { return nil }

        let used = ["primary", "secondary"].compactMap { key -> Double? in
            guard let window = limits[key] as? [String: Any] else { return nil }
            return (window["used_percent"] as? NSNumber)?.doubleValue
        }.max()
        guard let used, let timestamp = root["timestamp"] as? String,
              let observedAt = parseDate(timestamp) else { return nil }
        let remaining = min(100, max(0, Int((100 - used).rounded())))
        return QuotaSnapshot(remainingPercent: remaining, observedAt: observedAt)
    }
}
```

- [ ] **Step 5: Run all parser tests and verify GREEN**

Run: `cd work/CodexQuota && swift test --filter QuotaParserTests`

Expected: all `QuotaParserTests` pass with zero failures.

### Task 2: Session lookup and menu text renderer

**Files:**
- Create: `work/CodexQuota/Sources/CodexQuotaCore/QuotaStore.swift`
- Create: `work/CodexQuota/Sources/CodexQuotaCore/QuotaRenderer.swift`
- Test: `work/CodexQuota/Tests/CodexQuotaCoreTests/QuotaStoreTests.swift`
- Test: `work/CodexQuota/Tests/CodexQuotaCoreTests/QuotaRendererTests.swift`

- [ ] **Step 1: Write failing store tests with temporary JSONL trees**

Create two nested files with distinct quota timestamps and assert the newest event wins regardless of filename. Add an empty-root test returning `nil`.

```swift
func testChoosesNewestSnapshotAcrossFiles() throws {
    let root = try makeTemporarySessionsRoot()
    try writeEvent(used: 20, timestamp: "2026-07-14T10:00:00.000Z", to: root.appendingPathComponent("old.jsonl"))
    try writeEvent(used: 45, timestamp: "2026-07-14T11:00:00.000Z", to: root.appendingPathComponent("nested/new.jsonl"))
    XCTAssertEqual(QuotaStore().latestSnapshot(in: root)?.remainingPercent, 55)
}
```

- [ ] **Step 2: Write failing renderer tests**

```swift
XCTAssertEqual(QuotaRenderer.title(remainingPercent: 60), "Codex [██████░░░░] 60%")
XCTAssertEqual(QuotaRenderer.title(remainingPercent: 0), "Codex [░░░░░░░░░░] 0%")
XCTAssertEqual(QuotaRenderer.title(remainingPercent: 100), "Codex [██████████] 100%")
XCTAssertEqual(QuotaRenderer.title(remainingPercent: nil), "Codex [░░░░░░░░░░] --%")
```

- [ ] **Step 3: Run tests and verify RED**

Run: `cd work/CodexQuota && swift test --filter 'Quota(Store|Renderer)Tests'`

Expected: compilation fails because `QuotaStore` and `QuotaRenderer` do not exist.

- [ ] **Step 4: Implement recent-file scanning**

`QuotaStore.latestSnapshot(in:)` enumerates regular `.jsonl` files, sorts them by modification time descending, limits the scan to 50 files, reads at most the final 4 MiB from each file, ignores an initial partial line when reading a suffix, parses lines in reverse, and returns the snapshot with the greatest `observedAt`.

```swift
public struct QuotaStore: Sendable {
    public init() {}

    public func latestSnapshot(in root: URL) -> QuotaSnapshot? {
        let files = recentJSONLFiles(in: root, limit: 50)
        return files.compactMap(latestSnapshotInFile).max { $0.observedAt < $1.observedAt }
    }
}
```

- [ ] **Step 5: Implement the ten-cell renderer**

Round the filled-cell count to the nearest tenth with `(percent + 5) / 10`, clamped to `0...10`.

```swift
public enum QuotaRenderer {
    public static func title(remainingPercent: Int?) -> String {
        guard let remainingPercent else { return "Codex [░░░░░░░░░░] --%" }
        let percent = min(100, max(0, remainingPercent))
        let filled = min(10, max(0, (percent + 5) / 10))
        return "Codex [\(String(repeating: "█", count: filled))\(String(repeating: "░", count: 10 - filled))] \(percent)%"
    }
}
```

- [ ] **Step 6: Run the full core test suite and verify GREEN**

Run: `cd work/CodexQuota && swift test`

Expected: parser, store, and renderer tests all pass with zero failures.

### Task 3: Native AppKit status item

**Files:**
- Create: `work/CodexQuota/Sources/CodexQuotaApp/main.swift`

- [ ] **Step 1: Add the smallest AppKit application controller**

Create an `NSStatusItem` with variable length, a menu containing a disabled snapshot-time row, “立即刷新”, separator, and “退出”. Resolve the sessions root as `~/.codex/sessions`. Refresh once at launch and every 15 seconds.

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store = QuotaStore()
    private let sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)
    private var timer: Timer?
    private let updatedItem = NSMenuItem(title: "快照时间：--", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refresh() }
    }

    @objc private func refresh() {
        DispatchQueue.global(qos: .utility).async { [store, sessionsRoot] in
            let snapshot = store.latestSnapshot(in: sessionsRoot)
            DispatchQueue.main.async { [weak self] in self?.apply(snapshot) }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 2: Build the executable**

Run: `cd work/CodexQuota && swift build -c release --arch arm64`

Expected: build completes successfully and `.build/arm64-apple-macosx/release/CodexQuotaApp` exists.

### Task 4: Bundle, validate, and smoke test

**Files:**
- Create: `work/CodexQuota/Scripts/generate_icon.swift`
- Create: `work/CodexQuota/Scripts/build_app.sh`
- Create: `outputs/Codex Quota.app`

- [ ] **Step 1: Implement icon generation**

Use AppKit to draw a 1024×1024 rounded dark tile with a white ten-cell quota bar, then write PNG data to the path passed as the first argument. The build script generates the exact ten standard iconset filenames with `sips` and compiles them with `iconutil`.

- [ ] **Step 2: Implement deterministic app-bundle assembly**

The script must remove only the previous `outputs/Codex Quota.app`, create `Contents/MacOS` and `Contents/Resources`, copy the release executable, generate `icon.icns`, and write an `Info.plist` containing:

```xml
<key>CFBundleExecutable</key><string>CodexQuotaApp</string>
<key>CFBundleIconFile</key><string>icon</string>
<key>CFBundleIdentifier</key><string>local.openclaw.codexquota</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
```

Then run `chmod`, `xattr -cr`, ad-hoc sign with `codesign --force --deep --sign -`, and register using `lsregister -f -R`.

- [ ] **Step 3: Run complete automated verification**

Run:

```bash
cd work/CodexQuota
swift test
./Scripts/build_app.sh
plutil -lint ../../outputs/Codex\ Quota.app/Contents/Info.plist
codesign --verify --deep --strict ../../outputs/Codex\ Quota.app
test "$(iconutil -c iconset ../../outputs/Codex\ Quota.app/Contents/Resources/icon.icns -o /tmp/codex-quota-verify.iconset >/dev/null 2>&1; find /tmp/codex-quota-verify.iconset -type f | wc -l | tr -d ' ')" = "10"
mdls -name kMDItemContentType ../../outputs/Codex\ Quota.app
```

Expected: tests have zero failures; plist is `OK`; signature verification exits 0; iconset count is 10; content type is `com.apple.application-bundle`.

- [ ] **Step 4: Verify the displayed value against the latest local snapshot**

Run a test helper or one-line `jq` scan to establish the latest local `used_percent`, calculate expected remaining percentage, launch the app with `open`, and inspect the status item through macOS UI. For the current snapshot observed during planning, `used_percent = 29`, so the expected display is `Codex [███████░░░] 71%`; re-compute at test time rather than hard-coding 71.

- [ ] **Step 5: Verify agent-app lifecycle**

After launch, confirm `pgrep -x CodexQuotaApp` returns exactly one PID and `NSWorkspace` reports the app with activation policy accessory. Trigger the menu's “退出” item through UI, then confirm `pgrep -x CodexQuotaApp` returns no PID and no Dock icon remains.
