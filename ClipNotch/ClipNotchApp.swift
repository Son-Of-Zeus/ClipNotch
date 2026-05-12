import SwiftUI

@main
struct ClipNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        Window("Hidden", id: "hidden") {
            EmptyView().frame(width: 0, height: 0)
        }
        .defaultSize(width: 0, height: 0)
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
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }
}
