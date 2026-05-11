# ClipNotch v1 Design Spec

Menu-bar-only macOS clipboard manager that drops a drawer from the MacBook notch. Hold Cmd+J, navigate with J/K, release Cmd to paste. Designed for minimal idle footprint and smooth animations.

**macOS target:** 14.0 (Sonoma) minimum

---

## 1. Product Overview

ClipNotch is a lightweight clipboard history manager for macOS. It monitors the system pasteboard, stores clipboard items locally, and presents them in a drawer panel that animates from the MacBook notch. The core interaction is hold-to-select: hold Cmd, press J to open, J/K to navigate, release Cmd to paste.

### Core Principles

- **Zero idle cost.** No drawer panel, no drawer SwiftUI view, no clipboard list view when the drawer is closed. The idle process is a pasteboard polling timer and a CGEvent tap.
- **Rich content.** Handles plain text, rich text (RTF), HTML, images, file references, and any other standard pasteboard type.
- **Privacy-friendly.** 24-hour default retention. All data is local. No network, no analytics, no telemetry.
- **Graceful degradation.** Works without Accessibility permission in a reduced mode.

---

## 2. Architecture

Four layers with clear boundaries:

### 2.1 Sentinel (always running)

The bare-bones process core that exists when the drawer is closed.

- **CGEvent tap** (active filter, not passive observer): monitors global key events. Intercepts and consumes Cmd+J to open the drawer, J/K while Cmd is held to navigate, Escape to dismiss. All other events pass through unmodified.
- **Pasteboard polling:** `NSPasteboard.changeCount` checked on a 1-second `DispatchSourceTimer`. Returns immediately if unchanged.
- **Content ingestion:** When a change is detected, serialize metadata to SQLite, write rich payloads (images, RTF, HTML) to disk, compute canonical content hash for dedup.

### 2.2 Storage (always available, lazy-loaded)

- **SQLite** via raw `sqlite3` C API. Configured with:
  ```sql
  PRAGMA journal_mode=WAL;
  PRAGMA synchronous=NORMAL;
  PRAGMA foreign_keys=ON;
  ```
- Writes on a **serial background `DispatchQueue`**. UI reads concurrently without blocking ingestion.
- **Rich payloads** stored as files in `~/Library/Application Support/ClipNotch/items/` with UUID filenames.
- **Finder file copies** stored as security-scoped bookmarks + metadata. Never copy actual file bytes.
- **Thumbnails** generated at ingest time (64x64) for images, stored alongside the full image.

### 2.3 Presenter (created on invoke, destroyed on dismiss)

Two panel variants, never mutated:

**Full-permission panel** (Accessibility granted):
- `NSPanel`, borderless, `.nonactivatingPanel` style mask, `.floating` window level
- Does not steal focus from the foreground app
- Destroyed completely on dismiss (panel closed, `NSHostingView` nilled)

**Degraded/menu-bar panel** (no Accessibility, or invoked via menu bar):
- `NSPanel`, borderless, activating, becomes key window
- Before opening: remember `NSWorkspace.shared.frontmostApplication`
- On paste: close drawer, reactivate previous app, then fire synthetic Cmd+V after a short dispatch delay

Both panels contain a single `NSHostingView` with the drawer SwiftUI view.

### 2.4 View Layer (SwiftUI, lives inside Presenter)

- Vertical list of clipboard items, flat chronological order (most recent first)
- Shadow Drop visual style (see Section 5)
- Fetches last ~20 items from SQLite on creation
- Highlight state tracks J/K navigation
- Type badges, text previews, relative timestamps per row

---

## 3. Onboarding & Permissions

### 3.1 First Launch

Single-screen welcome window (no wizard). Content:

> ClipNotch needs Accessibility permission to detect your global shortcut and modifier release. Clipboard history is stored locally and never leaves your Mac.

- Call `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt` once during onboarding to trigger the system prompt.
- Show a button that opens `System Settings > Privacy & Security > Accessibility` as a convenience.
- Below the button: manual instructions ("Open System Settings, go to Privacy & Security > Accessibility, and enable ClipNotch") in case the deep link breaks.
- `NSApp.activate(ignoringOtherApps: true)` before showing the onboarding window so it appears in front.

### 3.2 Permission Polling

After the user navigates to System Settings, poll `AXIsProcessTrusted()` every 2 seconds. Auto-detect when granted, transition to "ready" state, dismiss onboarding.

### 3.3 Graceful Degradation

If Accessibility is denied or revoked:
- Global summon via `RegisterEventHotKey` (Carbon hot key API) for Cmd+J. This works without Accessibility for a single key combo registration.
- Once the drawer is open and the activating panel is key window, `NSEvent.addLocalMonitorForEvents` handles J/K/Enter/Escape locally.
- Interaction changes: J/K to navigate, **Enter to paste** (no hold-to-release). Escape to dismiss.
- Drawer shows a subtle one-line hint: "Enable Accessibility for hold-to-paste mode"

### 3.4 Event Tap Health

If the CGEvent tap stops delivering events or is disabled by the system, the app attempts to re-enable it via `CGEventTapEnable`. If re-enable fails, fall back to degraded mode until tap health returns. No crash, no error dialog -- silent recovery.

---

## 4. Interaction Model

### 4.1 Full-Permission Mode

| State | Input | Action |
|-------|-------|--------|
| Closed | Cmd down + J down | Create non-activating panel, animate drawer open, highlight first item. **Consume event.** |
| Open | J down (Cmd held) | Move highlight down. Scroll if at edge. **Consume event.** |
| Open | K down (Cmd held) | Move highlight up. Scroll if at edge. **Consume event.** |
| Open | Cmd released | Write selected item to `NSPasteboard` (all valid representations), fire synthetic Cmd+V via `CGEvent`, animate drawer closed, destroy panel. **Consume event.** |
| Open | Escape | Animate drawer closed, destroy panel. No paste. **Consume event.** |
| Open | Click outside panel | Same as Escape. Detected via the same CGEvent tap (monitor `kCGEventLeftMouseDown` and check if click location is outside the panel frame). |
| Any | All other events | Pass through unmodified. |

### 4.2 Degraded / Menu-Bar Mode

| State | Input | Action |
|-------|-------|--------|
| Closed | Cmd+J (via RegisterEventHotKey) or menu bar left-click | Remember frontmost app. Create activating panel, animate drawer open, highlight first item. |
| Open | J | Move highlight down. |
| Open | K | Move highlight up. |
| Open | Enter | Write selected item to `NSPasteboard`, close drawer, reactivate previous frontmost app, fire synthetic Cmd+V after next runloop tick. |
| Open | Escape | Close drawer, reactivate previous frontmost app. No paste. |
| Open | Panel deactivated / click away | Same as Escape. Detected via resign/deactivate notifications. |

### 4.3 Paste Delivery

Representations written to `NSPasteboard` based on content type:

| Item Type | Pasteboard Representations |
|-----------|---------------------------|
| Plain text | `public.utf8-plain-text` |
| Rich text | RTF + HTML + plain text fallback |
| Image | TIFF/PNG/JPEG as originally captured |
| File reference | File URLs (resolved from bookmarks, not raw bookmark data) |

Then post synthetic Cmd+V via `CGEvent` to the frontmost app.

---

## 5. Drawer UI & Animation

### 5.1 Screen Targeting

Choose target screen for the drawer:
1. Screen containing the frontmost app's focused window, if available
2. Screen containing the mouse cursor
3. `NSScreen.main`
4. `NSScreen.screens.first`

### 5.2 Notch Awareness

Use `NSScreen.safeAreaInsets`:
- `safeAreaInsets.top > 0`: notched/camera-housing display. Anchor drawer at top center, below the unsafe region.
- `safeAreaInsets.top == 0`: external or older display. Anchor drawer at top center.

### 5.3 Panel Specs

- Width: 320-360pt
- Max visible height: ~420pt (10-12 items)
- Background: `#1c1c1e`
- Corner radius: 16pt
- Shadow: dramatic drop shadow, equivalent to `0 20px 60px rgba(0,0,0,0.8)` via `NSShadow`

### 5.4 Animation

**Open:**
- Panel starts at 0 height at the notch/top-center position
- Expands downward with gravity-style ease-out (~`(0.22, 1, 0.36, 1)` control points or `.easeOut(duration: 0.28)`)
- Items fade in with staggered 8-12ms delay per row, capped at first 6 rows. Remaining rows appear immediately.

**Close:**
- Panel height shrinks upward toward the notch with faster ease-in (~0.2s)
- Items fade out simultaneously (no stagger -- snappy dismiss)

**Highlight movement:**
- Selected item background crossfades, 0.1s ease. No spring or bounce -- just responsive.

### 5.5 Item Row Layout

- **Left:** Type badge (small rounded rect icon) -- `T` for text, camera for image, folder for file, `<>` for code/HTML
- **Center:** `plain_text_preview` or `display_title` or `file_display_name`. Single line, truncated. For images: thumbnail + filename.
- **Right:** Relative timestamp ("2m ago", "1h ago")
- **Row height:** 40pt
- **Highlighted row:** `#2c2c2e` background + thin accent-color left border

---

## 6. Storage Schema

### 6.1 Database

SQLite database at `~/Library/Application Support/ClipNotch/clipnotch.db`.

### 6.2 Table: `clipboard_items`

| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PRIMARY KEY | UUID |
| `created_at` | REAL NOT NULL | Unix timestamp |
| `primary_type` | TEXT NOT NULL | UTType identifier string |
| `source_bundle_id` | TEXT | Bundle ID of the app that produced the content |
| `app_name` | TEXT | Display name of the source app |
| `display_title` | TEXT | Human-readable title for the item |
| `plain_text_preview` | TEXT | First ~200 chars for drawer display. For short text items, this is also the full payload. |
| `full_text_path` | TEXT | Path to full text file on disk (only if > 200 chars) |
| `image_path` | TEXT | Path to compressed image (JPEG for opaque, PNG for alpha) |
| `thumbnail_path` | TEXT | Path to 64x64 thumbnail |
| `file_bookmark_path` | TEXT | Security-scoped bookmark data path |
| `file_original_path` | TEXT | Original file path at time of copy |
| `file_display_name` | TEXT | Filename for display |
| `file_icon_cache_path` | TEXT | Cached file type icon |
| `rtf_path` | TEXT | Path to RTF data |
| `html_path` | TEXT | Path to HTML data |
| `byte_size` | INTEGER NOT NULL | Total content size in bytes |
| `content_hash` | TEXT NOT NULL | Canonical SHA-256 for dedup |
| `is_favorite` | INTEGER NOT NULL DEFAULT 0 | Reserved for future use |
| `last_accessed_at` | REAL | Reserved for future use |

### 6.3 Content Handling Rules

**Plain text:** Store in `plain_text_preview` if <= 200 chars (doubles as full payload in SQLite). Write to `full_text_path` only for longer text.

**Images:** JPEG (quality 0.8) for opaque bitmap images. PNG for alpha or lossless-sensitive content (screenshots with text). Generate 64x64 thumbnail at ingest. Skip images > 50MB.

**Files from Finder:** Store security-scoped bookmark, original path, display name, UTType, and cached icon. Never copy actual file bytes. Track existence on access.

**Rich text / HTML:** Store both RTF and HTML blobs to disk when both are available and size is reasonable. Extract plain text preview regardless. For browser copies, HTML is the richer representation. For native macOS app copies, RTF may be richer.

**Multi-representation priority for `primary_type`:**
1. File URLs
2. Image
3. RTF
4. HTML
5. Plain text

Store both HTML and RTF when available, but select one `primary_type`.

### 6.4 Dedup

Compute canonical hash based on content type:
- Plain text: normalized UTF-8 text
- Image: encoded canonical image bytes
- File: resolved file URL + modification date
- HTML/RTF: raw blob hash + extracted text hash

If the hash matches the most recent item, skip ingestion.

### 6.5 Retention & Cleanup

Default limits (configurable):
- **Time:** 24 hours
- **Count:** 500 items max
- **Disk:** 500 MB max

Cleanup runs on each new item insert. Deletes expired rows and their associated files from disk. Whichever limit is hit first triggers cleanup.

---

## 7. Preferences & App Lifecycle

### 7.1 Menu Bar Presence

- `LSUIElement = true` in Info.plist (no Dock icon)
- Menu bar icon: small clipboard glyph or notch-shaped icon
- **Left-click:** Opens drawer in degraded/menu-bar mode (remember frontmost app, Enter to paste)
- **Right-click:** Context menu with "Preferences...", "Clear History", "Quit"

### 7.2 Settings Window

Standard SwiftUI `Settings` scene. `NSApp.activate(ignoringOtherApps: true)` before presenting so it appears in front.

- **Retention policy:**
  - Time-based: default 24 hours, range 1 hour to 30 days
  - Max item count: default 500
  - Max disk usage: default 500 MB
- **Hotkey:** Display current hotkey (Cmd+J). Hardcoded for v1.
- **Launch at login:** Toggle via `SMAppService.mainApp.register()` / `.unregister()`
- **Status:**
  - Current item count and disk usage
  - Accessibility permission status indicator
  - Event tap health status

### 7.3 App Lifecycle

| State | What Exists |
|-------|-------------|
| **Idle** | `NSApplication`, CGEvent tap, pasteboard polling timer, menu bar item. No drawer panel, no drawer `NSHostingView`, no clipboard list SwiftUI view. Settings UI only created when opened. |
| **Invoke** | Create appropriate panel variant, load SwiftUI drawer view into `NSHostingView`, fetch last ~20 items from SQLite, animate open. |
| **Active** | Panel visible, SwiftUI view hierarchy alive, event tap filtering J/K/Escape. |
| **Dismiss** | Animate closed, destroy panel, nil `NSHostingView`, release all drawer SwiftUI references. Back to idle. |
| **Quit** | Disable event tap, invalidate timer, close SQLite connection. |

### 7.4 Launch at Login

```swift
try SMAppService.mainApp.register()   // enable
try SMAppService.mainApp.unregister() // disable
```

---

## 8. Out of Scope for v1

- Search / filtering within the drawer
- Pinned / favorite items (schema columns reserved)
- Configurable hotkey
- Sync across devices
- Snippet expansion
- Categories or smart grouping
- Secure content auto-detection
