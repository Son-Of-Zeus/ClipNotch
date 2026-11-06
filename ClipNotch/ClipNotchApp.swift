import AppKit
import SwiftUI

/// Owns the single `AppState` and `AppCoordinator` so both SwiftUI and `AppDelegate` share one graph.
@MainActor
final class AppBootstrap: ObservableObject {
    static let shared = AppBootstrap()

    let appState = AppState()
    private(set) var coordinator: AppCoordinator?
    private var preferencesWindow: NSWindow?

    func ensureStarted() {
        #if DEBUG
        guard NSClassFromString("XCTestCase") == nil else { return }
        #endif
        guard coordinator == nil else { return }
        let c = AppCoordinator(appState: appState)
        coordinator = c
        c.start()
    }

    func activateSettingsWindow() {
        if preferencesWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = "ClipNotch"
            window.contentMinSize = NSSize(width: 700, height: 520)
            ClipNotchWindowChrome.apply(to: window)
            window.contentView = NSHostingView(rootView: ClipNotchSettingsView(appState: appState))
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
}

@main
struct ClipNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Preferences…") {
                    Task { @MainActor in
                        AppBootstrap.shared.activateSettingsWindow()
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
                Divider()
                Button("Open Clipboard") { AppBootstrap.shared.coordinator?.showDrawer(.clipboard) }
                Button("Open Data Palette") { AppBootstrap.shared.coordinator?.showDrawer(.dataTypes) }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                    .keyboardShortcut("x", modifiers: .command)
                Button("Copy") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                    .keyboardShortcut("c", modifiers: .command)
                Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                    .keyboardShortcut("v", modifiers: .command)
                Divider()
                Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                    .keyboardShortcut("a", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isPreparingTermination = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AppBootstrap.shared.ensureStarted()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppBootstrap.shared.coordinator?.shutdown()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isPreparingTermination { return .terminateLater }
        guard let coordinator = AppBootstrap.shared.coordinator else { return .terminateNow }
        isPreparingTermination = true
        Task { @MainActor in
            await coordinator.prepareToTerminate()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            AppBootstrap.shared.coordinator?.refreshAccessibilityAndEventTap()
        }
    }

}
