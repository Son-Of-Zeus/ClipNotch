# Repository Guidelines

## Project Structure & Module Organization

ClipNotch is a macOS 14+ SwiftUI menu-bar clipboard manager that can also fill web forms. The Xcode project is `ClipNotch.xcodeproj`; open it in Xcode for normal development.

- `ClipNotch/ClipNotchApp.swift`, `AppCoordinator.swift` and `AppState.swift` bootstrap the app, its lifecycle and its shared state. `StatusItemController.swift` owns the menu bar item.
- `Core/` monitors the pasteboard, ingests content, keeps the clipboard history (`ClipboardHistoryStore`), handles event taps and shortcuts, and reads browser forms for autofill (`BrowserFormMonitor`, `DataPaletteStore`).
- `Presenter/` owns panel presentation, paste delivery, form-fill delivery and the Accessibility permission guide.
- `Storage/` persists the clipboard history and the Data Palette in SQLite through the `ClipboardPersistence` and `DataPalettePersistence` actors.
- `Models/` defines persisted and UI-facing data types.
- `Views/` contains SwiftUI screens and reusable rows; `Utilities/` holds shared design and screen helpers.
- `ClipNotchTests/` contains the XCTest target.
- `docs/superpowers/` preserves the original product design and implementation plan.

Keep new code in the layer that owns the responsibility. For example, add clipboard capture logic to `Core/`, not a SwiftUI view.

## Build, Test, and Development Commands

Use Xcode’s **ClipNotch** scheme to run and debug locally. From the repository root, the equivalent command-line build is:

```sh
xcodebuild -project ClipNotch.xcodeproj -scheme ClipNotch -configuration Debug build
```

Use `xcodebuild ... clean build` only when a normal build appears to use stale artifacts.

`ClipNotchTests` uses the app as its test host (`TEST_HOST` is `ClipNotch.app`), and `ClipNotch/Info.plist` sets `LSMultipleInstancesProhibited`. Quit any running ClipNotch first, or macOS refuses to launch the test host and the run fails with "Could not launch ClipNotchTests". Then run the tests:

```sh
xcodebuild -project ClipNotch.xcodeproj -scheme ClipNotch test
```

Add XCTest coverage alongside significant logic changes.

## Coding Style & Naming Conventions

Follow the existing Swift style: four-space indentation, one declaration per line, `PascalCase` for types, and `camelCase` for methods, properties, and enum cases. Prefer focused `final` classes and `@MainActor` for UI-bound state. Keep AppKit lifecycle/panel work explicit and isolate storage access behind the persistence actors in `Storage/`. Use descriptive names such as `PasteboardMonitor` and `ClipboardItemRow`; avoid abbreviations outside conventional Apple APIs.

No formatter or linter is configured. Format code with Xcode and keep imports minimal and ordered consistently with neighboring files.

## Testing Guidelines

Name test methods after behavior, for example `testRefreshItemsResetsSelection()`. Cover boundary cases around retention, item limits, pasteboard deduplication, and accessibility-dependent behavior. Manually verify menu-bar launch, drawer positioning, clipboard capture, settings persistence, and paste delivery before submitting UI changes.

## Releasing

The website installs ClipNotch with `curl -fsSL https://clipnotch.pranavvijay.me/install.sh | sh`. The script downloads the first asset of the latest GitHub release and checks it against the SHA-256 digest that GitHub publishes. Every release must therefore have the app zip as its first and only asset.

1. In `ClipNotch/Info.plist`, set `CFBundleShortVersionString` to the new version and raise `CFBundleVersion` by one. The version is not in the build settings.
2. Do not change the signing settings. Release builds are signed to run locally (ad-hoc, no team) with the hardened runtime, and the app is not notarized.
3. In Xcode, select Product > Archive with the **ClipNotch** scheme (Archive uses the Release configuration). In the Organizer, select Distribute App, then Custom, then Copy App, and export the app.
4. Check the exported app. `codesign -dv --verbose=2 ClipNotch.app` must show `Signature=adhoc` and `flags=0x10002(adhoc,runtime)`. `lipo -archs ClipNotch.app/Contents/MacOS/ClipNotch` must show `x86_64 arm64`.
5. Zip the app: `ditto -c -k --keepParent ClipNotch.app ClipNotch-<version>.zip`. The zip contains only `ClipNotch.app`.
6. Commit the version change as `chore: bump ClipNotch to <version>` and push it to `main`.
7. Write the release notes in the same form as v1.0.1: a short list of changes; "Requires macOS 14 or later. Universal (Apple silicon and Intel)."; the note that a zip downloaded in a browser needs Open Anyway in System Settings > Privacy & Security; and `SHA-256: <checksum>` from `shasum -a 256 ClipNotch-<version>.zip`.
8. Publish: `gh release create v<version> --repo Son-Of-Zeus/ClipNotch --target main --title "ClipNotch <version>" --notes-file notes.md ClipNotch-<version>.zip`.
9. Check the release: `curl -fsSL https://api.github.com/repos/Son-Of-Zeus/ClipNotch/releases/latest` must show the new `tag_name`, and `assets[0].digest` must equal `sha256:` plus the checksum from step 7.

Each build gets a new ad-hoc signature, so macOS can ask users to grant Accessibility again after an update. The install script tells them how.

## Commit & Pull Request Guidelines

Recent commits use concise imperative subjects, often with a prefix such as `fix:`; follow that pattern (for example, `fix: persist drawer selection`). Keep commits scoped to one behavior. Pull requests should explain the user-visible change, note manual verification, link the issue when applicable, and include screenshots or a short recording for SwiftUI or panel-layout changes. Do not commit Xcode user data, build products, or local app state.

## General Agent Guidelines

- Don't rely on this computer's global Python. Use uv for everything.
- Don't read `.env` files; you will be blocked. Instead, assume necessary keys are set and load them in scripts with `dotenv`.
- Avoid writing `README.md` documents or other explanatory Markdown documents unless explicitly told to. Avoid including emojis in code, comments, or logs.
- Code with conciseness and simplicity.
- Avoid excessive tests; only create tests for what is highly important and likely to undergo change in the future.
- Prioritize clear and low-verbosity code.
- Minimize the diff created by PRs.
- Do not use the question tool; instead, ask the user questions in plain text.
- Avoid backwards compatibility in favor of complete removal of the old in favor of the new.
- Avoid adding excessive catches, exceptions, and special-case handling without good reason.
- Fallback cases make it unclear what path code takes; avoid them.
- Code following Rob Pike's Go principles:
  - Clear is better than clever
  - Delete code; don't comment it out or leave it
  - A little repetition is better than a little dependency
  - First make it work, then make it work right, then make it work fast
- State intention and estimated duration before executing long-running tool calls.
