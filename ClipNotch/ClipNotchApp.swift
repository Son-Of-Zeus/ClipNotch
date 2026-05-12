import SwiftUI

@main
struct ClipNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        Settings {
            SettingsView(appState: delegate.appState)
        }
        
        Window("Welcome to ClipNotch", id: "onboarding") {
            OnboardingView(appState: delegate.appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 440, height: 380)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var coordinator: AppCoordinator?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let c = AppCoordinator(appState: appState)
        coordinator = c
        c.start()
        
        if !appState.hasCompletedOnboarding {
            if let url = URL(string: "clipnotch://onboarding") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }
}
