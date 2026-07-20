import AppKit
import SwiftUI

extension Notification.Name {
    /// Bring the SwiftUI settings `WindowGroup` forward (menu bar Preferences / Cmd+,).
    static let clipNotchActivateSettingsWindow = Notification.Name("clipNotchActivateSettingsWindow")
}

/// Owns the single `AppState` and `AppCoordinator` so both SwiftUI and `AppDelegate` share one graph.
@MainActor
final class AppBootstrap: ObservableObject {
    static let shared = AppBootstrap()

    let appState = AppState()
    private(set) var coordinator: AppCoordinator?

    func ensureStarted() {
        guard coordinator == nil else { return }
        let c = AppCoordinator(appState: appState)
        coordinator = c
        c.start()
    }

    func activateSettingsWindow() {
        NotificationCenter.default.post(name: .clipNotchActivateSettingsWindow, object: nil)
    }
}

@main
struct ClipNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ClipNotchSettingsView(appState: AppBootstrap.shared.appState)
                .onAppear {
                    Task { @MainActor in
                        AppBootstrap.shared.ensureStarted()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .clipNotchActivateSettingsWindow)) { _ in
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows where window.isVisible && window.canBecomeKey {
                        if window.title.contains("Welcome") { continue }
                        window.makeKeyAndOrderFront(nil)
                        return
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 456, height: 360)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Preferences…") {
                    Task { @MainActor in
                        AppBootstrap.shared.activateSettingsWindow()
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

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
