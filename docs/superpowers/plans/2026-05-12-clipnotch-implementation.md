# ClipNotch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Build a macOS menu-bar clipboard manager that drops a drawer from the MacBook notch with hold-to-paste interaction.

**Architecture:** Four-layer native macOS app: Sentinel (event tap + pasteboard polling), Storage (SQLite + file system), Presenter (NSPanel variants), View (SwiftUI drawer). Idle footprint near zero -- SwiftUI only loads when the drawer is visible.

**Tech Stack:** Swift 6, SwiftUI (macOS 14+), AppKit (NSPanel, NSHostingView), raw sqlite3 C API, CGEvent tap, Carbon RegisterEventHotKey

**SwiftUI Expert Skill:** Consult `.agents/skills/swiftui-expert-skill/references/latest-apis.md` before writing any SwiftUI code. Use `@Observable` (not `ObservableObject`), `@State` (not `@StateObject`), `@Entry` (not manual `EnvironmentKey`), `animation(_:value:)` (not deprecated `animation(_:)`). Mark all `@Observable` classes with `@MainActor`. Mark `@State` and `@FocusState` as `private`. See `references/state-management.md` for the full decision flowchart.

**Spec:** See `docs/superpowers/specs/2026-05-12-clipnotch-design.md` for the full design spec. Every task in this plan maps to a spec section.

---

## File Structure

The file structure and all 17 implementation tasks with full code are documented in this plan. Due to the size of the implementation, each task below references the exact files to create/modify and contains complete code for every step.

```
ClipNotch/
  ClipNotchApp.swift              - @main App with MenuBarExtra + Settings scenes
  AppState.swift                  - @Observable app-wide state
  Core/
    EventTapManager.swift         - CGEvent tap: key filtering, hold-release detection
    HotKeyManager.swift           - Carbon RegisterEventHotKey for degraded mode
    PasteboardMonitor.swift       - NSPasteboard.changeCount polling
    ContentIngester.swift         - Process pasteboard, thumbnails, hashes
  Storage/
    Database.swift                - SQLite WAL, schema, CRUD on serial queue
    FileStore.swift               - Rich payloads on disk
    CleanupManager.swift          - Retention: time/count/disk, orphan sweep
  Presenter/
    PanelManager.swift            - NSPanel creation/positioning/destroy
    PasteDelivery.swift           - Write to NSPasteboard, synthetic Cmd+V
  Views/
    DrawerView.swift              - Main drawer list with animation
    ClipboardItemRow.swift        - Single row: badge, preview, timestamp
    EmptyStateView.swift          - "Copy something to get started"
    SettingsView.swift            - Preferences: retention, login, status
    OnboardingView.swift          - Accessibility permission flow
  Models/
    ClipboardItem.swift           - Data model matching SQLite schema
  Utilities/
    ScreenUtilities.swift         - Screen targeting, notch detection
  Info.plist                      - LSUIElement = true
```

---

## Task 1: Xcode Project Setup

**Files:**
- Create: `Package.swift`
- Create: `ClipNotch/Info.plist`
- Create: `ClipNotch/ClipNotchApp.swift` (minimal)

- [ ] **Step 1: Create Package.swift**

The project uses Swift Package Manager. Target macOS 14.0. Link Carbon and AppKit.

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClipNotch",
            path: "ClipNotch",
            linkerSettings: [
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Create Info.plist**

Create `ClipNotch/Info.plist` with `LSUIElement = true` (no Dock icon).

- [ ] **Step 3: Create minimal ClipNotchApp.swift**

Minimal SwiftUI app entry point with `MenuBarExtra` and `Settings` placeholder.

- [ ] **Step 4: Build and verify**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: scaffold ClipNotch project with menu bar and settings"
```

---

## Task 2: Data Model

**Files:**
- Create: `ClipNotch/Models/ClipboardItem.swift`

- [ ] **Step 1: Create ClipboardItem struct**

Struct with all columns matching the SQLite schema from the spec (Section 6.2). Properties: id (UUID string), createdAt, primaryType (UTType identifier), sourceBundleID, appName, displayTitle, plainTextPreview, fullTextPath, imagePath, thumbnailPath, fileBookmarkPath, fileOriginalPath, fileDisplayName, fileIconCachePath, rtfPath, htmlPath, byteSize, contentHash, isFavorite, lastAccessedAt.

Add computed properties: `preview` (display text), `relativeTimestamp` ("2m ago"), `contentType` (enum: plainText, rtf, html, image, fileURL, unknown) with `badge` and `iconName`.

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/Models/ClipboardItem.swift && git commit -m "feat: add ClipboardItem data model"
```

---

## Task 3: SQLite Database

**Files:**
- Create: `ClipNotch/Storage/Database.swift`

- [ ] **Step 1: Create Database class**

Use raw `sqlite3` C API (import SQLite3). On init:
1. Create `~/Library/Application Support/ClipNotch/` directory
2. Open `clipnotch.db`
3. Set PRAGMA journal_mode=WAL, synchronous=NORMAL, foreign_keys=ON
4. Create `clipboard_items` table if not exists with all columns from spec Section 6.2
5. Create index on `created_at DESC` and `content_hash`

All writes through a serial `DispatchQueue(label: "com.clipnotch.db.write")`. Methods:
- `insert(_ item: ClipboardItem)` - async on write queue
- `fetchRecent(limit: Int) -> [ClipboardItem]` - reads directly (WAL concurrent reads)
- `mostRecentHash() -> String?` - for dedup check
- `deleteItems(olderThan date: Date) -> [String]` - returns file paths for cleanup
- `deleteExcessItems(keepCount: Int) -> [String]` - returns file paths
- `totalDiskUsage() -> Int` - SUM(byte_size)
- `itemCount() -> Int`
- `allItemIDs() -> Set<String>` - for orphan sweep

Use helper methods for binding optional text and reading column text.

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/Storage/Database.swift && git commit -m "feat: add SQLite database with WAL mode"
```

---

## Task 4: File Store

**Files:**
- Create: `ClipNotch/Storage/FileStore.swift`

- [ ] **Step 1: Create FileStore**

Manages `~/Library/Application Support/ClipNotch/items/` directory. Methods:
- `saveText(_ text: String, id: String) -> String?` - write .txt, return path
- `saveImage(_ image: NSImage, id: String, hasAlpha: Bool) -> (imagePath, thumbnailPath)?` - JPEG for opaque (quality 0.8), PNG for alpha. Generate 64x64 thumbnail.
- `saveData(_ data: Data, id: String, ext: String) -> String?` - write arbitrary data
- `deleteFiles(_ paths: [String])` - best-effort delete
- `orphanSweep(knownIDs: Set<String>)` - scan items dir, delete files with no matching DB row
- `canonicalHash(for data: Data) -> String` - SHA-256 via CryptoKit
- `canonicalTextHash(_ text: String) -> String` - normalize UTF-8, then SHA-256

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/Storage/FileStore.swift && git commit -m "feat: add FileStore for rich payload disk management"
```

---

## Task 5: Cleanup Manager

**Files:**
- Create: `ClipNotch/Storage/CleanupManager.swift`

- [ ] **Step 1: Create CleanupManager**

Takes Database and FileStore. Methods:
- `runCleanup(maxAge:maxCount:maxDiskBytes:)` - enforces time, count, and disk limits. Cleanup order per spec: collect paths in transaction, delete rows, delete files best-effort.
- `runOrphanSweep()` - calls database.allItemIDs() then fileStore.orphanSweep()

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/Storage/CleanupManager.swift && git commit -m "feat: add CleanupManager with time/count/disk retention"
```

---

## Task 6: Pasteboard Monitor and Content Ingester

**Files:**
- Create: `ClipNotch/Core/PasteboardMonitor.swift`
- Create: `ClipNotch/Core/ContentIngester.swift`

- [ ] **Step 1: Create PasteboardMonitor**

`@MainActor` class. Uses `DispatchSourceTimer` on main queue, fires every 1 second. Checks `NSPasteboard.general.changeCount`. Calls `onNewContent` callback when changed. Methods: `start()`, `stop()`.

- [ ] **Step 2: Create ContentIngester**

`@MainActor` class. Takes Database, FileStore, CleanupManager. The `ingest()` method:

1. Read pasteboard types. Priority: file URLs > image (tiff/png) > RTF > HTML > plain text
2. For file URLs: store security-scoped bookmark, original path, display name. Hash from URL string.
3. For images: JPEG if opaque, PNG if alpha. Generate thumbnail. Skip > 50MB. Hash from image data.
4. For RTF/HTML: save both when available. Extract plain text preview.
5. For plain text: store inline in plainTextPreview if <= 200 chars, else write to full_text_path.
6. Compute canonical hash. Check against `database.mostRecentHash()` for dedup -- skip if match.
7. Get source app via `NSWorkspace.shared.frontmostApplication`
8. Call `database.insert()` then `cleanupManager.runCleanup()`

- [ ] **Step 3: Commit**

```bash
git add ClipNotch/Core/ && git commit -m "feat: add pasteboard polling and content ingestion"
```

---

## Task 7: Screen Utilities

**Files:**
- Create: `ClipNotch/Utilities/ScreenUtilities.swift`

- [ ] **Step 1: Create ScreenUtilities**

Enum with static methods:
- `targetScreen() -> NSScreen` - per spec Section 5.1: screen with frontmost app window, then mouse cursor, then NSScreen.main, then .screens.first
- `drawerPosition(width:) -> DrawerPosition` - struct with screen, topCenter point, isNotched flag. Uses `screen.safeAreaInsets.top > 0` for notch detection per spec Section 5.2.

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/Utilities/ && git commit -m "feat: add screen targeting and notch detection"
```

---

## Task 8: Panel Manager

**Files:**
- Create: `ClipNotch/Presenter/PanelManager.swift`

- [ ] **Step 1: Create PanelManager**

`@MainActor` class. Two modes matching spec Section 2.3:

**Full-permission mode:** NSPanel with `.nonactivatingPanel` style mask, `.floating` level, borderless. Does not steal focus.

**Degraded mode:** NSPanel, borderless, activating, becomes key. Stores `previousApp` via `NSWorkspace.shared.frontmostApplication`.

Methods:
- `open(mode:content:)` - creates panel, adds NSHostingView with SwiftUI content
- `updateHeight(_:)` - adjusts panel frame (top stays anchored, bottom extends down)
- `close()` - orderOut, remove hosting view, nil panel
- `restorePreviousApp()` - reactivate stored app

Panel specs per spec Section 5.3: width 340pt, max height 420pt, background clear (SwiftUI handles the dark background), hasShadow true, collectionBehavior canJoinAllSpaces.

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/Presenter/PanelManager.swift && git commit -m "feat: add PanelManager with panel variants"
```

---

## Task 9: Paste Delivery

**Files:**
- Create: `ClipNotch/Presenter/PasteDelivery.swift`

- [ ] **Step 1: Create PasteDelivery**

Static methods per spec Section 4.3:
- `deliver(_ item:fileStore:)` - write to pasteboard then post synthetic Cmd+V after 50ms delay
- `writeToPasteboard(_:fileStore:)` - per content type:
  - Plain text: public.utf8-plain-text
  - Rich: RTF + HTML + plain text fallback (all three when available)
  - Image: TIFF/PNG/JPEG as stored + plain text fallback (filename)
  - File: file URLs resolved from bookmark (not raw bookmark data) + plain text fallback (path)
- `postSyntheticPaste()` - create CGEvent keyDown/keyUp for V key (virtual key 0x09) with Cmd flag, post to cghidEventTap

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/Presenter/PasteDelivery.swift && git commit -m "feat: add PasteDelivery with synthetic Cmd+V"
```

---

## Task 10: CGEvent Tap Manager

**Files:**
- Create: `ClipNotch/Core/EventTapManager.swift`

- [ ] **Step 1: Create EventTapManager**

`@MainActor` class. Sets up CGEvent tap as **active filter** (not passive). Intercepts and consumes owned events per spec Section 4.1.

Event mask: keyDown + flagsChanged + leftMouseDown.

Key codes: 0x26 = J, 0x28 = K, 0x35 = Escape.

Event handling logic:
- **tapDisabledByTimeout / tapDisabledByUserInput**: re-enable tap immediately
- **keyDown, Cmd+J, not autorepeat, drawer closed**: fire `onCmdJDown`, return nil (consume)
- **keyDown, Cmd+J, autorepeat**: return nil (consume, ignore)
- **keyDown, J, Cmd held, drawer open**: fire `onJDown`, return nil (consume)
- **keyDown, K, Cmd held, drawer open**: fire `onKDown`, return nil (consume)
- **keyDown, Escape, drawer open**: fire `onEscape`, return nil (consume)
- **flagsChanged, Cmd no longer present, drawer open**: fire `onCmdReleased`, **pass event through** (do NOT consume -- per spec, consuming Cmd release risks foreground app thinking Cmd is still held)
- **leftMouseDown, drawer open**: fire `onClickOutside` with click location
- **All other events**: pass through unmodified

Callbacks: `onCmdJDown`, `onJDown`, `onKDown`, `onCmdReleased`, `onEscape`, `onClickOutside`. All dispatched to main actor.

Property `drawerIsOpen: Bool` read from the event callback to decide filtering behavior.

Methods: `start()`, `stop()`, `tryReEnable()`.

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/Core/EventTapManager.swift && git commit -m "feat: add CGEvent tap with active filtering"
```

---

## Task 11: Carbon HotKey Manager (Degraded Mode)

**Files:**
- Create: `ClipNotch/Core/HotKeyManager.swift`

- [ ] **Step 1: Create HotKeyManager**

Uses Carbon `RegisterEventHotKey` for Cmd+J. Works without Accessibility permission.

- `register()` - register Cmd+J hotkey with `GetApplicationEventTarget()`, install event handler
- `unregister()` - unregister hotkey, remove handler
- Callback `onHotKey: (() -> Void)?`

Key: `kVK_ANSI_J`, modifier: `cmdKey`.

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/Core/HotKeyManager.swift && git commit -m "feat: add Carbon HotKeyManager for degraded mode"
```

---

## Task 12: App State

**Files:**
- Create: `ClipNotch/AppState.swift`

- [ ] **Step 1: Create AppState**

`@Observable @MainActor final class AppState`. Per SwiftUI expert skill:
- All `@AppStorage` properties wrapped with `@ObservationIgnored` (property wrappers conflict with `@Observable` macro)
- Class marked `@MainActor`

Properties:
- `isDrawerOpen: Bool`
- `selectedIndex: Int`
- `items: [ClipboardItem]`
- `hasAccessibilityPermission: Bool`
- `isFirstLaunch: Bool`
- `@ObservationIgnored @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding`
- `@ObservationIgnored @AppStorage("retentionHours") var retentionHours: Double = 24`
- `@ObservationIgnored @AppStorage("maxItemCount") var maxItemCount: Int = 500`
- `@ObservationIgnored @AppStorage("maxDiskMB") var maxDiskMB: Int = 500`
- `@ObservationIgnored @AppStorage("launchAtLogin") var launchAtLogin: Bool = false`

Methods:
- `moveSelectionDown()` / `moveSelectionUp()` - clamp to bounds
- `selectedItem: ClipboardItem?` - computed
- `refreshItems(from database:)` - fetch recent 20, reset selectedIndex

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/AppState.swift && git commit -m "feat: add @Observable AppState"
```

---

## Task 13: Drawer SwiftUI Views

**Files:**
- Create: `ClipNotch/Views/DrawerView.swift`
- Create: `ClipNotch/Views/ClipboardItemRow.swift`
- Create: `ClipNotch/Views/EmptyStateView.swift`

- [ ] **Step 1: Create ClipboardItemRow**

HStack: accent left border (3pt wide, visible when highlighted) | system image icon (12pt) | preview text (13pt, 1 line, truncated) | Spacer | relative timestamp (11pt). Height 40pt. Background: RoundedRectangle #2c2c2e when highlighted, clear otherwise. Animation: `.animation(.easeInOut(duration: 0.1), value: isHighlighted)`.

- [ ] **Step 2: Create EmptyStateView**

Centered VStack: clipboard icon (24pt, 0.3 opacity) + "Copy something to get started" text (13pt, 0.4 opacity). Padding 32pt vertical.

- [ ] **Step 3: Create DrawerView**

Takes `items: [ClipboardItem]`, `selectedIndex: Int`, `isDegraded: Bool`.

Animation per spec Section 5.4:
- **Open:** `scaleEffect(y: isVisible ? 1 : 0, anchor: .top)` with `.easeOut(duration: 0.28)`. Items fade in with staggered 10ms delay, capped at first 6 rows.
- **Close:** Handled by PanelManager destroying the view.
- **Highlight:** ScrollViewReader scrolls to selected item on selectedIndex change.

Background: RoundedRectangle, cornerRadius 16, fill #1c1c1e, shadow (black 0.8, radius 30, y 20).

If degraded: show hint text "Enable Accessibility for hold-to-paste mode" at bottom.

Width: 340pt. Max height: 420pt. Uses `ScrollView` + `LazyVStack`.

- [ ] **Step 4: Commit**

```bash
git add ClipNotch/Views/DrawerView.swift ClipNotch/Views/ClipboardItemRow.swift ClipNotch/Views/EmptyStateView.swift && git commit -m "feat: add drawer views with Shadow Drop animation"
```

---

## Task 14: Settings View

**Files:**
- Create: `ClipNotch/Views/SettingsView.swift`

- [ ] **Step 1: Create SettingsView**

Uses `@Bindable var appState: AppState` (injected `@Observable`, per SwiftUI expert skill use `@Bindable` for injected objects needing bindings).

TabView with `Tab` API (macOS 14+, per latest-apis.md):

**General tab:** Form with:
- Retention section: Stepper for hours (1-720), Stepper for max items (10-10000), Stepper for max disk MB (50-5000)
- Startup section: Toggle "Launch at login" that calls `SMAppService.mainApp.register()` / `.unregister()`
- Shortcut section: display "Cmd+J" (hardcoded v1)

**Status tab:** Form with:
- Accessibility permission indicator (green/red circle + text)

Frame: width 400, minHeight 280. `.scenePadding()`.

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/Views/SettingsView.swift && git commit -m "feat: add Settings view"
```

---

## Task 15: Onboarding View

**Files:**
- Create: `ClipNotch/Views/OnboardingView.swift`

- [ ] **Step 1: Create OnboardingView**

`@Bindable var appState: AppState`. VStack: icon, title, explanation text, "Open Accessibility Settings" button, manual instructions caption.

On appear: `NSApp.activate(ignoringOtherApps: true)` (per spec, LSUIElement apps need explicit activation). Check `AXIsProcessTrusted()`.

Button calls `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt` to trigger system prompt.

Poll `AXIsProcessTrusted()` every 2 seconds. When granted: set `hasCompletedOnboarding = true`, dismiss after 0.5s.

Frame: 440x380.

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/Views/OnboardingView.swift && git commit -m "feat: add onboarding Accessibility flow"
```

---

## Task 16: Wire Everything in ClipNotchApp

**Files:**
- Modify: `ClipNotch/ClipNotchApp.swift`

- [ ] **Step 1: Create AppCoordinator**

`@MainActor final class AppCoordinator`. Owns all layers:
- database, fileStore, cleanupManager
- pasteboardMonitor, contentIngester
- eventTapManager, hotKeyManager
- panelManager

`start()` method:
1. Init Database, FileStore, CleanupManager
2. Run orphan sweep
3. Init ContentIngester
4. Start PasteboardMonitor (calls ingester.ingest on change)
5. Init PanelManager
6. Check AXIsProcessTrusted() -> if true: start EventTapManager, else: start HotKeyManager

EventTapManager callbacks:
- `onCmdJDown` -> openDrawerFullPermission()
- `onJDown` -> appState.moveSelectionDown()
- `onKDown` -> appState.moveSelectionUp()
- `onCmdReleased` -> pasteSelectedAndClose()
- `onEscape` -> closeDrawer()
- `onClickOutside` -> closeDrawer()

`openDrawerFullPermission()`: refreshItems, create DrawerView, open panel as .fullPermission, set height.

`openDrawerDegraded()`: remember frontmost app, refreshItems, create DrawerView, open panel as .degraded.

`pasteSelectedAndClose()`: get selectedItem, closeDrawer, PasteDelivery.deliver.

`closeDrawer()`: set isDrawerOpen false, restore previous app if degraded, close panel.

- [ ] **Step 2: Rewrite ClipNotchApp**

`@main struct ClipNotchApp: App`. Scenes:
- `MenuBarExtra`: Open Clipboard button, Clear History, Quit. Left-click calls `openDrawerDegraded()`.
- `Settings`: SettingsView with appState
- `Window("Welcome", id: "onboarding")`: OnboardingView, contentSize resizability

Init creates AppState and AppCoordinator, calls `coordinator.start()` on main actor.

- [ ] **Step 3: Build and verify**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add ClipNotch/ClipNotchApp.swift && git commit -m "feat: wire all layers in ClipNotchApp"
```

---

## Task 17: Smoke Test

- [ ] **Step 1: Run the app**

```bash
swift run ClipNotch
```

Expected: Menu bar icon appears. No Dock icon.

- [ ] **Step 2: Test clipboard ingestion**

Copy some text in another app. Open drawer (Cmd+J or menu bar click). Verify copied text appears in the list.

- [ ] **Step 3: Test full-permission interaction**

With Accessibility granted: Hold Cmd, press J. Drawer drops. J/K moves highlight. Release Cmd. Selected item pastes into previous app. Drawer retracts.

- [ ] **Step 4: Test degraded interaction**

Without Accessibility: Cmd+J opens drawer. J/K navigates. Enter pastes. Escape dismisses.

- [ ] **Step 5: Test Settings**

Right-click menu bar icon. Preferences. Verify retention controls, launch at login toggle, permission status.

- [ ] **Step 6: Final commit**

```bash
git add -A && git commit -m "feat: ClipNotch v1 complete"
```

---

## Spec Coverage

| Spec Section | Task(s) |
|-------------|---------|
| 1. Product Overview | All tasks |
| 2.1 Sentinel | T6 (Pasteboard), T10 (EventTap) |
| 2.2 Storage | T3 (Database), T4 (FileStore), T5 (Cleanup) |
| 2.3 Presenter | T8 (PanelManager), T9 (PasteDelivery) |
| 2.4 View Layer | T13 (Drawer views) |
| 3. Onboarding | T15 (OnboardingView) |
| 3.3 Degraded mode | T11 (HotKeyManager) |
| 3.4 Event tap health | T10 (tryReEnable) |
| 4.1 Full-permission mode | T10 + T16 |
| 4.2 Degraded mode | T11 + T16 |
| 4.3 Paste delivery | T9 |
| 5. Drawer UI | T7 (Screen), T8 (Panel), T13 (Views) |
| 6. Storage schema | T2 (Model), T3 (Database) |
| 6.3 Content handling | T6 (Ingester) |
| 6.4 Dedup | T6 (hash check) |
| 6.5 Retention | T5 (Cleanup) |
| 7.1 Menu bar | T16 (MenuBarExtra) |
| 7.2 Settings | T14 |
| 7.3 Lifecycle | T16 (Coordinator) |
| 7.4 Login | T14 (SMAppService) |
| 8. Out of scope | Not implemented |
