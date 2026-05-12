import AppKit
import SwiftUI

@MainActor
final class AppCoordinator {
    let appState: AppState
    
    private var database: DatabaseActor!
    private var fileStore: FileStore!
    private var cleanupManager: CleanupManager!
    private var pasteboardMonitor: PasteboardMonitor!
    private var contentIngester: ContentIngester!
    private var eventTapManager: EventTapManager!
    private var hotKeyManager: HotKeyManager!
    private var panelManager: PanelManager!
    private var statusItemController: StatusItemController!
    private var onboardingWindow: NSWindow?
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func start() {
        do {
            database = try DatabaseActor()
            fileStore = try FileStore()
        } catch {
            print("ClipNotch: Failed to initialize storage: \(error)")
            return
        }
        
        cleanupManager = CleanupManager(database: database, fileStore: fileStore)
        
        Task.detached { [cleanupManager] in
            await cleanupManager!.runOrphanSweep()
        }
        
        contentIngester = ContentIngester(
            database: database,
            fileStore: fileStore,
            cleanupManager: cleanupManager
        )
        
        pasteboardMonitor = PasteboardMonitor()
        pasteboardMonitor.onNewContent = { [weak self] in
            self?.handleNewPasteboardContent()
        }
        pasteboardMonitor.start()
        
        panelManager = PanelManager()
        
        statusItemController = StatusItemController()
        statusItemController.onLeftClick = { [weak self] in
            self?.openDrawerDegraded()
        }
        statusItemController.onPreferences = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        statusItemController.onClearHistory = { [weak self] in
            self?.clearHistory()
        }
        statusItemController.onQuit = {
            NSApplication.shared.terminate(nil)
        }
        statusItemController.setup()
        
        appState.hasAccessibilityPermission = AXIsProcessTrusted()
        
        if appState.hasAccessibilityPermission {
            startEventTap()
        } else {
            startHotKey()
        }
        
        Task { [weak self] in
            await self?.appState.refreshItems(from: self!.database)
        }
        
        if !appState.hasCompletedOnboarding {
            showOnboarding()
        }
    }
    
    func shutdown() {
        onboardingWindow?.close()
        onboardingWindow = nil
        pasteboardMonitor?.stop()
        eventTapManager?.stop()
        hotKeyManager?.unregister()
        panelManager?.close()
    }
    
    // MARK: - Event Handling Setup
    
    private func startEventTap() {
        eventTapManager = EventTapManager()
        eventTapManager.onCmdJDown = { [weak self] in
            self?.openDrawerFullPermission()
        }
        eventTapManager.onJDown = { [weak self] in
            self?.appState.moveSelectionDown()
        }
        eventTapManager.onKDown = { [weak self] in
            self?.appState.moveSelectionUp()
        }
        eventTapManager.onCmdReleased = { [weak self] in
            self?.pasteSelectedFullMode()
        }
        eventTapManager.onEscape = { [weak self] in
            self?.closeDrawer()
        }
        eventTapManager.onClickOutside = { [weak self] _ in
            self?.closeDrawer()
        }
        
        if !eventTapManager.start() {
            print("ClipNotch: Event tap failed, falling back to HotKey")
            startHotKey()
        }
    }
    
    private func startHotKey() {
        hotKeyManager = HotKeyManager()
        hotKeyManager.onHotKey = { [weak self] in
            guard let self else { return }
            if self.appState.isDrawerOpen {
                self.closeDrawer()
            } else {
                self.openDrawerDegraded()
            }
        }
        hotKeyManager.register()
    }
    
    // MARK: - Pasteboard
    
    private func handleNewPasteboardContent() {
        let snapshot = PasteboardSnapshot.capture()
        Task.detached { [contentIngester] in
            await contentIngester!.ingest(snapshot: snapshot)
        }
        
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(500))
            await self.appState.refreshItems(from: self.database)
        }
    }
    
    // MARK: - Drawer Operations
    
    private func openDrawerFullPermission() {
        guard !appState.isDrawerOpen else { return }
        
        Task { [weak self] in
            guard let self else { return }
            await self.appState.refreshItems(from: self.database)
            
            let position = ScreenUtilities.drawerPosition()
            appState.isDrawerOpen = true
            eventTapManager?.drawerIsOpen = true
            appState.selectedIndex = 0
            
            let drawerContent = DrawerView(
                appState: appState,
                isDegraded: false
            )
            
            let height = min(CGFloat(max(appState.items.count, 1)) * 42 + 16, 420)
            panelManager.open(
                mode: .fullPermission,
                position: position.topCenter,
                height: height,
                content: drawerContent
            )
        }
    }
    
    private func openDrawerDegraded() {
        guard !appState.isDrawerOpen else {
            closeDrawer()
            return
        }
        
        Task { [weak self] in
            guard let self else { return }
            await self.appState.refreshItems(from: self.database)
            
            let position = ScreenUtilities.drawerPosition()
            appState.isDrawerOpen = true
            appState.selectedIndex = 0
            
            let drawerContent = DrawerView(
                appState: appState,
                isDegraded: !appState.hasAccessibilityPermission
            )
            
            let height = min(CGFloat(max(appState.items.count, 1)) * 42 + 16, 420)
            panelManager.open(
                mode: .degraded,
                position: position.topCenter,
                height: height,
                content: drawerContent
            )
        }
    }
    
    private func pasteSelectedFullMode() {
        guard appState.isDrawerOpen, let item = appState.selectedItem else {
            closeDrawer()
            return
        }
        
        Task { [weak self] in
            guard let self else { return }
            let fileRefs = await self.database.fetchFileReferences(for: item.id)
            
            PasteDelivery.writeToPasteboard(item, fileRefs: fileRefs, fileStore: self.fileStore)
            
            self.closeDrawer()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                PasteDelivery.postSyntheticPaste()
            }
        }
    }
    
    func pasteSelectedDegraded() {
        guard appState.isDrawerOpen, let item = appState.selectedItem else {
            closeDrawer()
            return
        }
        
        Task { [weak self] in
            guard let self else { return }
            let fileRefs = await self.database.fetchFileReferences(for: item.id)
            
            PasteDelivery.writeToPasteboard(item, fileRefs: fileRefs, fileStore: self.fileStore)
            
            self.closeDrawer()
            
            self.panelManager.restorePreviousApp()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                PasteDelivery.postSyntheticPaste()
            }
        }
    }
    
    private func closeDrawer() {
        appState.isDrawerOpen = false
        eventTapManager?.drawerIsOpen = false
        panelManager?.close()
    }
    
    private func clearHistory() {
        Task { [weak self] in
            guard let self else { return }
            let cutoff = Date.distantFuture
            let paths = try? await self.database.deleteItems(olderThan: cutoff)
            if let paths {
                self.fileStore.deleteFiles(paths)
            }
            await self.appState.refreshItems(from: self.database)
        }
    }
    
    // MARK: - Onboarding
    
    private func showOnboarding() {
        let onboardingView = OnboardingView(appState: appState)
        let hosting = NSHostingController(rootView: onboardingView)
        
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to ClipNotch"
        window.setContentSize(NSSize(width: 440, height: 380))
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        
        self.onboardingWindow = window
        
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
