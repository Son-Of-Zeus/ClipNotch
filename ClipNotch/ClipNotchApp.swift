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
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 472),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
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
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isPreparingTermination = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMinimalMainMenu()
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

    @objc func openPreferences(_ sender: Any?) {
        Task { @MainActor in
            AppBootstrap.shared.activateSettingsWindow()
        }
    }

    private func installMinimalMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "ClipNotch"
        let appMenu = NSMenu(title: appName)
        appMenuItem.submenu = appMenu

        let prefs = NSMenuItem(
            title: "Preferences…",
            action: #selector(openPreferences(_:)),
            keyEquivalent: ","
        )
        prefs.keyEquivalentModifierMask = .command
        prefs.target = self
        appMenu.addItem(prefs)

        NSApp.mainMenu = mainMenu
    }
}
