import AppKit
import SwiftUI

@main
struct ClipNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        Settings {
            Text("Use the menu bar icon to access ClipNotch settings.")
                .frame(width: 300, height: 100)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var coordinator: AppCoordinator?
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let c = AppCoordinator(appState: appState)
        coordinator = c
        c.start()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        coordinator?.refreshAccessibilityAndEventTap()
    }
}
