# Repository Guidelines

## Project Structure & Module Organization

ClipNotch is a macOS 14+ SwiftUI menu-bar clipboard manager. The Xcode project is `ClipNotch.xcodeproj`; open it in Xcode for normal development.

- `ClipNotch/ClipNotchApp.swift` and `AppCoordinator.swift` bootstrap the app and lifecycle.
- `Core/` monitors the pasteboard, handles event taps, and ingests content.
- `Presenter/` owns panel presentation and paste delivery.
- `Storage/` contains the SQLite actor, file store, and cleanup logic.
- `Models/` defines persisted and UI-facing data types.
- `Views/` contains SwiftUI screens and reusable rows; `Utilities/` holds shared design and screen helpers.
- `docs/superpowers/` preserves the product design and implementation plan.

Keep new code in the layer that owns the responsibility. For example, add clipboard capture logic to `Core/`, not a SwiftUI view.

## Build, Test, and Development Commands

Use Xcode’s **ClipNotch** scheme to run and debug locally. From the repository root, the equivalent command-line build is:

```sh
xcodebuild -project ClipNotch.xcodeproj -scheme ClipNotch -configuration Debug build
```

Use `xcodebuild ... clean build` only when a normal build appears to use stale artifacts. There is currently no test target; add XCTest coverage alongside any new target or significant logic change, then run it with `xcodebuild test`.

## Coding Style & Naming Conventions

Follow the existing Swift style: four-space indentation, one declaration per line, `PascalCase` for types, and `camelCase` for methods, properties, and enum cases. Prefer focused `final` classes and `@MainActor` for UI-bound state. Keep AppKit lifecycle/panel work explicit and isolate storage access behind `DatabaseActor`. Use descriptive names such as `PasteboardMonitor` and `ClipboardItemRow`; avoid abbreviations outside conventional Apple APIs.

No formatter or linter is configured. Format code with Xcode and keep imports minimal and ordered consistently with neighboring files.

## Testing Guidelines

When tests are added, name test methods after behavior, for example `testRefreshItemsResetsSelection()`. Cover boundary cases around retention, item limits, pasteboard deduplication, and accessibility-dependent behavior. Manually verify menu-bar launch, drawer positioning, clipboard capture, settings persistence, and paste delivery before submitting UI changes.

## Commit & Pull Request Guidelines

Recent commits use concise imperative subjects, often with a prefix such as `fix:`; follow that pattern (for example, `fix: persist drawer selection`). Keep commits scoped to one behavior. Pull requests should explain the user-visible change, note manual verification, link the issue when applicable, and include screenshots or a short recording for SwiftUI or panel-layout changes. Do not commit Xcode user data, build products, or local app state.
