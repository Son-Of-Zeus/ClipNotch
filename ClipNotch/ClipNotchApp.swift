import AppKit
import SwiftUI

/// Owns the single `AppState` and `AppCoordinator` so both SwiftUI and `AppDelegate` share one graph.
@MainActor
final class AppBootstrap: ObservableObject {
    static let shared = AppBootstrap()

    let appState = AppState()
    private(set) var coordinator: AppCoordinator?
    private var preferencesOpener: (() -> Void)?

    func ensureStarted() {
        guard coordinator == nil else { return }
        let c = AppCoordinator(appState: appState)
        coordinator = c
        c.start()
    }

    func activateSettingsWindow() {
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey && !$0.title.contains("Welcome") }) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        preferencesOpener?()
    }

    func configurePreferencesOpener(_ opener: @escaping () -> Void) {
        preferencesOpener = opener
    }
}

@main
struct ClipNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "preferences") {
            ClipNotchSettingsView(appState: AppBootstrap.shared.appState)
                .onAppear {
                    Task { @MainActor in
                        AppBootstrap.shared.ensureStarted()
                        AppBootstrap.shared.configurePreferencesOpener {
                            openWindow(id: "preferences")
                        }
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 640, height: 472)
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
