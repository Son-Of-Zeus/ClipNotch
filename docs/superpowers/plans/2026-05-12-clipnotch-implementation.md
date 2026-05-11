# ClipNotch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Build a macOS menu-bar clipboard manager that drops a drawer from the MacBook notch with hold-to-paste interaction.

**Architecture:** Four-layer native macOS app: Sentinel (event tap + pasteboard polling), Storage (SQLite + file system), Presenter (NSPanel variants), View (SwiftUI drawer). Idle footprint near zero -- SwiftUI only loads when the drawer is visible.

**Tech Stack:** Swift 6, SwiftUI (macOS 14+), AppKit (NSPanel, NSHostingView, NSStatusItem), raw sqlite3 C API, CGEvent tap, Carbon RegisterEventHotKey

**SwiftUI Expert Skill:** Consult `.agents/skills/swiftui-expert-skill/references/latest-apis.md` before writing any SwiftUI code. Use `@Observable` (not `ObservableObject`), `@State` (not `@StateObject`), `@Entry` (not manual `EnvironmentKey`), `animation(_:value:)` (not deprecated `animation(_:)`). Mark all `@Observable` classes with `@MainActor`. Mark `@State` and `@FocusState` as `private`. See `references/state-management.md` for the full decision flowchart.

**Spec:** See `docs/superpowers/specs/2026-05-12-clipnotch-design.md` for the full design spec. Every task in this plan maps to a spec section.

---

## File Structure

```
ClipNotch/                          (Xcode macOS App target)
  ClipNotchApp.swift                - @main App with Settings scene
  AppState.swift                    - @Observable app-wide state
  StatusItemController.swift        - NSStatusItem for menu bar (left-click drawer, right-click menu)
  Core/
    EventTapManager.swift           - CGEvent tap: key filtering, hold-release detection
    HotKeyManager.swift             - Carbon RegisterEventHotKey for degraded mode
    PasteboardMonitor.swift         - NSPasteboard.changeCount polling (main actor)
    ContentIngester.swift           - Process pasteboard on background queue: thumbnails, hashes, disk writes
  Storage/
    DatabaseActor.swift             - Swift actor wrapping sqlite3: serialized access, WAL mode
    FileStore.swift                 - Rich payloads on disk
    CleanupManager.swift            - Retention: time/count/disk, orphan sweep
  Presenter/
    PanelManager.swift              - NSPanel creation/positioning/destroy
    PasteDelivery.swift             - Write to NSPasteboard (writeObjects for files), synthetic Cmd+V
  Views/
    DrawerView.swift                - Main drawer list with animation
    ClipboardItemRow.swift          - Single row: badge, preview, timestamp
    EmptyStateView.swift            - "Copy something to get started"
    SettingsView.swift              - Preferences: retention, login, status
    OnboardingView.swift            - Accessibility permission flow (prompt + open Settings pane)
  Models/
    ClipboardItem.swift             - Data model for clipboard_items table
    FileReference.swift             - Data model for clipboard_file_references table
  Utilities/
    ScreenUtilities.swift           - Screen targeting, notch detection via safeAreaInsets
  Info.plist                        - LSUIElement = true, bundle ID, etc.
  ClipNotch.entitlements            - App Sandbox disabled (CGEvent tap requires it)
```

---

## Task 1: Xcode Project Setup

**Files:**
- Create: Xcode macOS App project `ClipNotch.xcodeproj`
- Create: `ClipNotch/Info.plist`
- Create: `ClipNotch/ClipNotch.entitlements`
- Create: `ClipNotch/ClipNotchApp.swift` (minimal)

- [ ] **Step 1: Create the Xcode project**

Create a macOS App target using Xcode project format (not SPM-only). The project needs a proper .app bundle for LSUIElement, Accessibility identity, SMAppService login items, and future notarization.

Use `xcodebuild` or create the project structure manually:

1. Create `ClipNotch.xcodeproj` using Xcode CLI or template
2. Set deployment target: macOS 14.0
3. Set product bundle identifier: `com.clipnotch.app`
4. Link frameworks: Carbon, AppKit, SwiftUI
5. Link library: sqlite3
6. App Sandbox: **disabled** (required for CGEvent tap and global key monitoring)

If using a `Package.swift` for internal library code alongside the Xcode target, that is acceptable. But the final product must be a .app bundle built via `xcodebuild`.

- [ ] **Step 2: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ClipNotch</string>
    <key>CFBundleIdentifier</key>
    <string>com.clipnotch.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
```

`LSUIElement = true` makes this an agent app with no Dock icon.

- [ ] **Step 3: Create entitlements**

`ClipNotch.entitlements` with App Sandbox disabled. CGEvent taps require running outside the sandbox.

- [ ] **Step 4: Create minimal ClipNotchApp.swift**

```swift
import SwiftUI

@main
struct ClipNotchApp: App {
    var body: some Scene {
        Settings {
            Text("Settings placeholder")
                .frame(width: 300, height: 200)
        }
    }
}
```

Note: No `MenuBarExtra` here. The menu bar icon will be managed by `NSStatusItem` (see Task 16) for proper left-click/right-click behavior.

- [ ] **Step 5: Build and verify**

```bash
xcodebuild -project ClipNotch.xcodeproj -scheme ClipNotch build
```

Expected: Build succeeds, producing a .app bundle.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: scaffold ClipNotch Xcode project with app bundle"
```

---

## Task 2: Data Models

**Files:**
- Create: `ClipNotch/Models/ClipboardItem.swift`
- Create: `ClipNotch/Models/FileReference.swift`

- [ ] **Step 1: Create ClipboardItem struct**

Struct with all columns matching the `clipboard_items` table from spec Section 6.2. Properties: id (UUID string), createdAt, primaryType (UTType identifier), sourceBundleID, appName, displayTitle, plainTextPreview, fullTextPath, imagePath, thumbnailPath, rtfPath, htmlPath, byteSize, contentHash, isFavorite, lastAccessedAt.

**Note:** Single-file fields (fileBookmarkPath, fileOriginalPath, fileDisplayName, fileIconCachePath) are removed from this table. Multi-file references are stored in the separate `clipboard_file_references` table (see FileReference).

Add computed properties: `preview` (display text), `relativeTimestamp` ("2m ago"), `contentType` (enum: plainText, rtf, html, image, fileURL, unknown) with `badge` and `iconName`.

- [ ] **Step 2: Create FileReference struct**

```swift
struct FileReference: Identifiable, Equatable {
    let id: String          // UUID
    let itemID: String      // FK to ClipboardItem.id
    let bookmarkPath: String?
    let originalPath: String
    let displayName: String
    let typeIdentifier: String?   // UTType identifier
    let iconCachePath: String?
    let sortOrder: Int
}
```

This supports Finder's multi-file copy. A single clipboard item can have many file references.

- [ ] **Step 3: Commit**

```bash
git add ClipNotch/Models/ && git commit -m "feat: add ClipboardItem and FileReference data models"
```

---

## Task 3: SQLite Database (Actor-Based)

**Files:**
- Create: `ClipNotch/Storage/DatabaseActor.swift`

- [ ] **Step 1: Create DatabaseActor**

Use a **Swift actor** wrapping the raw sqlite3 C API. The actor serializes all access (reads and writes) to the sqlite3 connection, avoiding threading issues with Swift 6 concurrency. WAL mode still provides performance benefits (OS-level I/O optimization).

```swift
actor DatabaseActor {
    private let db: OpaquePointer
    
    init() throws { ... }
}
```

**On init:**
1. Create `~/Library/Application Support/ClipNotch/` directory
2. Open `clipnotch.db`
3. Set pragmas: `PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA foreign_keys=ON;`
4. Create `clipboard_items` table (all columns from ClipboardItem, minus file-specific fields)
5. Create `clipboard_file_references` table:
   ```sql
   CREATE TABLE IF NOT EXISTS clipboard_file_references (
       id TEXT PRIMARY KEY,
       item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
       bookmark_path TEXT,
       original_path TEXT NOT NULL,
       display_name TEXT NOT NULL,
       type_identifier TEXT,
       icon_cache_path TEXT,
       sort_order INTEGER NOT NULL DEFAULT 0
   )
   ```
6. Create indexes on `clipboard_items(created_at DESC)`, `clipboard_items(content_hash)`, `clipboard_file_references(item_id)`

**Methods (all async, serialized by the actor):**
- `insert(_ item: ClipboardItem)` - INSERT OR REPLACE
- `insertFileReferences(_ refs: [FileReference])` - batch INSERT for file items
- `fetchRecent(limit: Int = 20) -> [ClipboardItem]`
- `fetchFileReferences(for itemID: String) -> [FileReference]`
- `mostRecentHash() -> String?` - for dedup
- `deleteItems(olderThan date: Date) -> [String]` - returns file paths, CASCADE deletes references
- `deleteExcessItems(keepCount: Int) -> [String]`
- `totalDiskUsage() -> Int`
- `itemCount() -> Int`
- `allItemIDs() -> Set<String>`

Add DatabaseError enum with cases `cannotOpen` and `statementFailed(String)`.

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/Storage/DatabaseActor.swift && git commit -m "feat: add DatabaseActor with serialized sqlite3 access"
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

FileStore is `Sendable` and thread-safe (all methods are stateless file I/O).

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/Storage/FileStore.swift && git commit -m "feat: add FileStore for rich payload disk management"
```

---

## Task 5: Cleanup Manager

**Files:**
- Create: `ClipNotch/Storage/CleanupManager.swift`

- [ ] **Step 1: Create CleanupManager**

Takes DatabaseActor and FileStore. Methods are async (database calls are actor-isolated).
- `runCleanup(maxAge:maxCount:maxDiskBytes:)` - enforces time, count, and disk limits. Cleanup order per spec: collect paths, delete rows (CASCADE deletes file references), delete files best-effort.
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

PasteboardMonitor stays on the main actor because `NSPasteboard` is most reliably read from the main thread.

- [ ] **Step 2: Create ContentIngester**

**NOT @MainActor.** The ingester briefly reads pasteboard data on the main thread (via a passed-in snapshot), then does all heavy work on a background queue/Task.

```swift
final class ContentIngester: Sendable {
    func ingest(snapshot: PasteboardSnapshot) async { ... }
}
```

The `PasteboardSnapshot` is a struct captured on the main thread containing the raw pasteboard data (types, text, image data, file URLs, RTF data, HTML data, source app info). This snapshot is then processed off-main:

1. **Background processing:** Compute canonical hash, compress images, generate thumbnails, write files to disk via FileStore. All of this runs in a detached task or background queue -- NOT on the main actor.
2. **Multi-file handling:** If pasteboard contains multiple file URLs, create a FileReference for each. Store bookmarks, original paths, display names, UTTypes.
3. **Dedup:** Check `await database.mostRecentHash()` before inserting.
4. **Insert:** `await database.insert(item)` and `await database.insertFileReferences(refs)`.
5. **Cleanup:** `await cleanupManager.runCleanup()`.

Content type priority for `primary_type`: file URLs > image (tiff/png) > RTF > HTML > plain text.

For images: JPEG if opaque, PNG if alpha/lossless. Generate 64x64 thumbnail at ingest. Skip images > 50MB.

For plain text <= 200 chars: store inline in `plainTextPreview` (also serves as full payload). For > 200 chars: write to `full_text_path`.

- [ ] **Step 3: Commit**

```bash
git add ClipNotch/Core/ && git commit -m "feat: add pasteboard polling and background content ingestion"
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

Restores **supported v1 representations only**: plain text, RTF, HTML, image, file URLs.

Static methods per spec Section 4.3:
- `deliver(_ item:fileRefs:fileStore:)` - write to pasteboard then post synthetic Cmd+V after delay
- `writeToPasteboard(_:fileRefs:fileStore:)` - per content type:
  - Plain text: `public.utf8-plain-text`
  - Rich: RTF + HTML + plain text fallback (write all three when available)
  - Image: TIFF/PNG/JPEG as stored + plain text fallback (filename)
  - File: **Use `NSPasteboard.writeObjects` with resolved `NSURL` array** (not raw string writing). Apple documents writeObjects as the correct way to write URLs to the pasteboard. Include plain text fallback with file paths.
- `postSyntheticPaste()` - create CGEvent keyDown/keyUp for V key (virtual key 0x09) with Cmd flag, post to cghidEventTap

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/Presenter/PasteDelivery.swift && git commit -m "feat: add PasteDelivery with writeObjects for files"
```

---

## Task 10: CGEvent Tap Manager

**Files:**
- Create: `ClipNotch/Core/EventTapManager.swift`

- [ ] **Step 1: Create EventTapManager**

`@MainActor` class. Sets up CGEvent tap as **active filter** (not passive). Intercepts and consumes owned events per spec Section 4.1.

**CRITICAL: The CGEvent callback must be tiny.** Apple can disable event taps that take too long. The callback must:
1. Inspect keycode and modifier flags
2. Decide consume or pass through
3. Enqueue a MainActor callback via DispatchQueue.main.async (do NOT do any real work)
4. Return immediately

Event mask: keyDown + flagsChanged + leftMouseDown.

Key codes: 0x26 = J, 0x28 = K, 0x35 = Escape.

Event handling logic:
- **tapDisabledByTimeout / tapDisabledByUserInput**: re-enable tap immediately via CGEvent.tapEnable
- **keyDown, Cmd+J, not autorepeat, drawer closed**: enqueue `onCmdJDown`, return nil (consume)
- **keyDown, Cmd+J, autorepeat**: return nil (consume, ignore repeated opens)
- **keyDown, J, Cmd held, drawer open**: enqueue `onJDown`, return nil (consume). J with autorepeat is also consumed and navigates at system key-repeat rate.
- **keyDown, K, Cmd held, drawer open**: enqueue `onKDown`, return nil (consume). Same autorepeat behavior.
- **keyDown, Escape, drawer open**: enqueue `onEscape`, return nil (consume)
- **flagsChanged, Cmd no longer present, drawer open**: enqueue `onCmdReleased`, **return event (pass through, do NOT consume)**. Consuming Cmd release risks the foreground app or system believing Cmd is still held.
- **leftMouseDown, drawer open**: enqueue `onClickOutside` with click location, pass event through
- **All other events**: pass through unmodified

Property `drawerIsOpen: Bool` — read atomically from the callback to decide filtering. Use `nonisolated(unsafe)` or an atomic wrapper since the callback runs on a different thread than MainActor.

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
- `refreshItems(from database:)` - async, fetch recent 20, reset selectedIndex

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

`@Bindable var appState: AppState`. VStack: icon, title, explanation text, two actions, manual instructions caption.

**On appear:**
- `NSApp.activate(ignoringOtherApps: true)` (LSUIElement apps need explicit activation)
- Optionally call `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt` once to trigger the system prompt

**Button "Open Accessibility Settings":**
- Opens System Settings Accessibility pane via URL: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`
- Also calls `AXIsProcessTrustedWithOptions` if not already prompted

**Manual instructions** below the button: "Open System Settings, go to Privacy & Security > Accessibility, and enable ClipNotch" (visible fallback in case deep link breaks).

**Permission polling:** Check `AXIsProcessTrusted()` every 2 seconds after user navigates to Settings. When granted: set `hasCompletedOnboarding = true`, dismiss after 0.5s.

Frame: 440x380.

- [ ] **Step 2: Commit**

```bash
git add ClipNotch/Views/OnboardingView.swift && git commit -m "feat: add onboarding with Settings pane link and permission polling"
```

---

## Task 16: Wire Everything (ClipNotchApp + StatusItemController + AppCoordinator)

**Files:**
- Modify: `ClipNotch/ClipNotchApp.swift`
- Create: `ClipNotch/StatusItemController.swift`

- [ ] **Step 1: Create StatusItemController**

`@MainActor` class managing an `NSStatusItem` directly (not SwiftUI `MenuBarExtra`). This is necessary because `MenuBarExtra` does not support separate left-click/right-click behavior. Apple documents `NSStatusItem` with `NSStatusBarButton` for custom click handling.

**Left-click:** Opens the drawer in degraded/menu-bar mode (remember frontmost app, Enter to paste).

**Right-click:** Shows context menu with "Preferences...", "Clear History", "Quit".

The status item displays a clipboard system image icon.

- [ ] **Step 2: Create AppCoordinator**

`@MainActor final class AppCoordinator`. Owns all layers:
- databaseActor, fileStore, cleanupManager
- pasteboardMonitor, contentIngester
- eventTapManager, hotKeyManager
- panelManager, statusItemController

`start()` method:
1. Init DatabaseActor, FileStore, CleanupManager
2. Run orphan sweep (async)
3. Init ContentIngester (takes database, fileStore, cleanupManager)
4. Start PasteboardMonitor — on change, capture PasteboardSnapshot on main, pass to ingester
5. Init PanelManager
6. Init StatusItemController
7. Check AXIsProcessTrusted() -> if true: start EventTapManager, else: start HotKeyManager

EventTapManager callbacks:
- `onCmdJDown` -> openDrawerFullPermission()
- `onJDown` -> appState.moveSelectionDown()
- `onKDown` -> appState.moveSelectionUp()
- `onCmdReleased` -> pasteSelectedFullMode()
- `onEscape` -> closeDrawer()
- `onClickOutside` -> closeDrawer()

**Full-mode paste sequence (spec Section 4.1 ordering):**
```
pasteSelectedFullMode():
  1. Get selected item
  2. Write item representations to NSPasteboard
  3. Start close animation / mark drawer as dismissing
  4. After a short delay (50-100ms, allowing Cmd release to propagate), post synthetic Cmd+V
  5. Destroy panel after close animation completes
```

Do NOT close the drawer then paste. Write pasteboard first, start closing, then paste after the real Cmd key-up has propagated. This avoids the timing bug where closing before pasting loses the target app.

**Degraded-mode paste sequence:**
```
pasteSelectedDegraded():
  1. Get selected item
  2. Write item representations to NSPasteboard
  3. Close drawer
  4. Reactivate previous frontmost app
  5. After next runloop tick, post synthetic Cmd+V
```

`closeDrawer()`: set isDrawerOpen false, eventTapManager.drawerIsOpen = false, close panel.

- [ ] **Step 3: Rewrite ClipNotchApp**

`@main struct ClipNotchApp: App`. Scenes:
- `Settings`: SettingsView with appState
- `Window("Welcome", id: "onboarding")`: OnboardingView, contentSize resizability

No `MenuBarExtra` — the status item is managed by StatusItemController via NSStatusItem.

Init creates AppState and AppCoordinator, calls `coordinator.start()` on main actor.

- [ ] **Step 4: Build and verify**

```bash
xcodebuild -project ClipNotch.xcodeproj -scheme ClipNotch build
```

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: wire all layers with NSStatusItem and AppCoordinator"
```

---

## Task 17: Build and Smoke Test

- [ ] **Step 1: Build the app bundle**

```bash
xcodebuild -project ClipNotch.xcodeproj -scheme ClipNotch -configuration Debug build
```

Expected: Build succeeds with a .app bundle.

- [ ] **Step 2: Run the app**

Open the built .app from the build products directory. Verify:
- Menu bar icon appears
- No Dock icon
- LSUIElement behavior is correct

- [ ] **Step 3: Test clipboard ingestion**

Copy some text in another app. Open drawer (Cmd+J or left-click menu bar). Verify copied text appears in the list.

- [ ] **Step 4: Test full-permission interaction**

With Accessibility granted: Hold Cmd, press J. Drawer drops from notch area. J/K moves highlight. Release Cmd. Selected item pastes into previous app. Drawer retracts.

- [ ] **Step 5: Test degraded interaction**

Without Accessibility: Cmd+J opens drawer. J/K navigates. Enter pastes. Escape dismisses.

- [ ] **Step 6: Test multi-file copy**

Copy multiple files from Finder. Open drawer. Verify the item shows a reasonable preview. Paste it back.

- [ ] **Step 7: Test Settings**

Right-click menu bar icon -> Preferences. Verify retention controls, launch at login toggle, permission status.

- [ ] **Step 8: Final commit**

```bash
git add -A && git commit -m "feat: ClipNotch v1 complete"
```

---

## Spec Coverage

| Spec Section | Task(s) |
|-------------|---------|
| 1. Product Overview | All tasks |
| 2.1 Sentinel | T6 (Pasteboard + Ingester), T10 (EventTap) |
| 2.2 Storage | T3 (DatabaseActor), T4 (FileStore), T5 (Cleanup) |
| 2.3 Presenter | T8 (PanelManager), T9 (PasteDelivery) |
| 2.4 View Layer | T13 (Drawer views) |
| 3. Onboarding | T15 (OnboardingView with Settings link + prompt) |
| 3.3 Degraded mode | T11 (HotKeyManager) |
| 3.4 Event tap health | T10 (tryReEnable) |
| 4.1 Full-permission mode | T10 + T16 (correct paste ordering) |
| 4.2 Degraded mode | T11 + T16 |
| 4.3 Paste delivery | T9 (writeObjects for files) |
| 5. Drawer UI | T7 (Screen), T8 (Panel), T13 (Views) |
| 6. Storage schema | T2 (Models), T3 (DatabaseActor + file_references table) |
| 6.3 Content handling | T6 (background ingestion) |
| 6.4 Dedup | T6 (hash check) |
| 6.5 Retention | T5 (Cleanup) |
| 7.1 Menu bar | T16 (NSStatusItem, not MenuBarExtra) |
| 7.2 Settings | T14 |
| 7.3 Lifecycle | T16 (Coordinator) |
| 7.4 Login | T14 (SMAppService) |
| 8. Out of scope | Not implemented |

## Key Implementation Notes

1. **App bundle required.** Do not treat `swift run` as the final test path. Use `xcodebuild` for builds and run the .app bundle for smoke tests.
2. **Database is an actor.** All sqlite3 access is serialized. No shared connection across threads.
3. **Content ingestion is off-main.** Snapshot pasteboard data on main, process everything else in background.
4. **Multi-file copies use a separate table.** `clipboard_file_references` with item_id FK.
5. **File URLs use writeObjects.** Apple documents this as the correct way to write URLs to NSPasteboard.
6. **NSStatusItem, not MenuBarExtra.** Required for separate left-click/right-click behavior.
7. **Event tap callback is tiny.** Inspect, decide, enqueue, return. No real work.
8. **Full-mode paste ordering matters.** Write pasteboard -> start closing -> post Cmd+V after modifier release propagates.
9. **Onboarding opens Settings pane.** Both the system prompt (AXIsProcessTrustedWithOptions) and a direct link to the Accessibility settings pane.
10. **Representation wording is narrow.** Restore supported v1 representations only: plain text, RTF, HTML, image, file URLs.
