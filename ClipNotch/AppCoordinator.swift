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
    private var eventTapManager: EventTapManager?
    private var panelManager: PanelManager!
    private var statusItemController: StatusItemController!
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var cleanupTimer: DispatchSourceTimer?
    private var windowCloseObserver: Any?
    
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
        statusItemController.onOpenClipboard = { [weak self] in
            self?.handleOpenClipboardFromMenu()
        }
        statusItemController.onPreferences = { [weak self] in
            self?.showSettings()
        }
        statusItemController.onClearHistory = { [weak self] in
            self?.clearHistory()
        }
        statusItemController.onQuit = {
            NSApplication.shared.terminate(nil)
        }
        statusItemController.setup()
        
        refreshAccessibilityAndEventTap()
        
        Task { [weak self] in
            await self?.appState.refreshItems(from: self!.database)
        }
        
        startCleanupTimer()

        if !appState.hasCompletedOnboarding {
            presentOnboardingWindow()
        }
    }

    /// Re-check trust after returning from System Settings and attach the event tap when newly allowed.
    func refreshAccessibilityAndEventTap() {
        appState.hasAccessibilityPermission = AXIsProcessTrusted()
        guard appState.hasAccessibilityPermission else {
            eventTapManager?.stop()
            eventTapManager = nil
            return
        }
        guard eventTapManager == nil else { return }
        startEventTap()
    }

    private func startCleanupTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 300, repeating: 300)
        timer.setEventHandler { [weak self] in
            Task { [weak self] in
                guard let self else { return }
                await self.runCleanupWithUserSettings()
                await self.appState.refreshItems(from: self.database)
            }
        }
        timer.resume()
        cleanupTimer = timer
    }
    
    func shutdown() {
        cleanupTimer?.cancel()
        cleanupTimer = nil
        if let obs = windowCloseObserver { NotificationCenter.default.removeObserver(obs) }
        windowCloseObserver = nil
        settingsWindow?.contentViewController = nil
        settingsWindow = nil
        onboardingWindow?.contentViewController = nil
        onboardingWindow?.close()
        onboardingWindow = nil
        pasteboardMonitor?.stop()
        eventTapManager?.stop()
        eventTapManager = nil
        panelManager?.close()
    }
    
    // MARK: - Event Handling Setup
    
    private func startEventTap() {
        let manager = EventTapManager()
        manager.onCmdJDown = { [weak self] in
            self?.openDrawer()
        }
        manager.onJDown = { [weak self] in
            self?.appState.moveSelectionUp()
        }
        manager.onKDown = { [weak self] in
            self?.appState.moveSelectionDown()
        }
        manager.onCmdReleased = { [weak self] in
            self?.pasteSelected()
        }
        manager.onEscape = { [weak self] in
            self?.closeDrawer()
        }
        manager.onClickOutside = { [weak self] _ in
            self?.closeDrawer()
        }
        
        guard manager.start() else {
            print("ClipNotch: Event tap failed to start")
            return
        }
        eventTapManager = manager
    }
    
    // MARK: - Pasteboard
    
    private func handleNewPasteboardContent() {
        let snapshot = PasteboardSnapshot.capture()
        Task { [weak self] in
            guard let self else { return }
            await self.contentIngester.ingest(snapshot: snapshot)
            await self.runCleanupWithUserSettings()
            await self.appState.refreshItems(from: self.database)
        }
    }

    private func runCleanupWithUserSettings() async {
        let maxAge = appState.retentionHours * 3600
        let maxCount = appState.maxItemCount
        let maxDiskBytes = appState.maxDiskMB * 1024 * 1024
        await cleanupManager.runCleanup(
            maxAge: maxAge,
            maxCount: maxCount,
            maxDiskBytes: maxDiskBytes
        )
    }
    
    // MARK: - Drawer Operations
    
    private func handleOpenClipboardFromMenu() {
        guard appState.hasAccessibilityPermission else {
            presentOnboardingWindow()
            return
        }
        if appState.isDrawerOpen {
            closeDrawer()
        } else {
            openDrawer()
        }
    }
    
    private func openDrawer() {
        guard appState.hasAccessibilityPermission else { return }
        guard !appState.isDrawerOpen else { return }
        
        Task { [weak self] in
            guard let self else { return }
            await self.appState.refreshItems(from: self.database)
            
            let position = ScreenUtilities.drawerPosition()
            appState.isDrawerOpen = true
            eventTapManager?.drawerIsOpen = true
            appState.selectedIndex = 0
            
            let contentHeight = min(CGFloat(max(appState.items.count, 1)) * 42 + 16, 420)
            let totalHeight = contentHeight + position.safeAreaTop

            let drawerContent = DrawerView(
                appState: appState,
                notchInset: position.safeAreaTop
            )
            
            panelManager.open(
                position: position.topCenter,
                width: ScreenUtilities.drawerWidth,
                height: totalHeight,
                content: drawerContent
            )
        }
    }
    
    private func pasteSelected() {
        guard appState.isDrawerOpen, let item = appState.selectedItem else {
            closeDrawer()
            return
        }
        
        Task { [weak self] in
            guard let self else { return }
            let fileRefs = await self.database.fetchFileReferences(for: item.id)
            
            PasteDelivery.writeToPasteboard(item, fileRefs: fileRefs, fileStore: self.fileStore)
            self.pasteboardMonitor?.skipCurrentChange()
            
            self.closeDrawer()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
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
    
    // MARK: - Settings
    
    private func showSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        settingsWindow?.contentViewController = nil
        settingsWindow = nil
        
        let settingsView = SettingsView(appState: appState)
        let hosting = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(contentViewController: hosting)
        window.title = "ClipNotch Settings"
        window.setContentSize(NSSize(width: 420, height: 320))
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        
        self.settingsWindow = window
        observeWindowClose(window) { [weak self] in
            self?.settingsWindow?.contentViewController = nil
            self?.settingsWindow = nil
        }
        
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    
    // MARK: - Onboarding
    
    private func presentOnboardingWindow() {
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        onboardingWindow?.contentViewController = nil
        onboardingWindow = nil
        
        let onboardingView = OnboardingView(appState: appState)
        let hosting = NSHostingController(rootView: onboardingView)
        
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to ClipNotch"
        window.setContentSize(NSSize(width: 440, height: 340))
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        
        self.onboardingWindow = window
        observeWindowClose(window) { [weak self] in
            self?.onboardingWindow?.contentViewController = nil
            self?.onboardingWindow = nil
        }
        
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func observeWindowClose(_ window: NSWindow, handler: @escaping () -> Void) {
        if let existing = windowCloseObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in handler() }
    }
}
