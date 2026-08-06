import AppKit
import SwiftUI

@MainActor
final class AppCoordinator {
    let appState: AppState

    private var history: ClipboardHistoryStore!
    private var contentIngester: ContentIngester!
    private var pasteboardMonitor: PasteboardMonitor!
    private var eventTapManager: EventTapManager?
    private var panelManager: PanelManager!
    private var statusItemController: StatusItemController!
    private var onboardingWindow: NSWindow?
    private var windowCloseObserver: Any?
    private var maintenanceScheduler: NSBackgroundActivityScheduler?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        let persistence: ClipboardPersistence
        do {
            persistence = try ClipboardPersistence()
        } catch {
            presentStorageFailure(error)
            return
        }

        let history = ClipboardHistoryStore(persistence: persistence, limits: storageLimits)
        self.history = history
        contentIngester = ContentIngester(history: history)
        appState.configurePayloadLoader { [weak history] id in
            await history?.payload(for: id)
        }

        pasteboardMonitor = PasteboardMonitor()
        pasteboardMonitor.onNewContent = { [weak self] in
            self?.handleNewPasteboardContent()
        }

        panelManager = PanelManager()
        setupStatusItem()
        refreshAccessibilityAndEventTap()
        startMaintenanceScheduler()
        startMemoryPressureMonitoring()

        Task { [weak self] in
            await history.start()
            guard let self else { return }
            self.pasteboardMonitor.start()
        }

        if !appState.hasCompletedOnboarding || appState.showOnboardingOnLaunch {
            presentOnboardingWindow()
        }
    }

    func prepareToTerminate() async {
        await history?.shutdown()
    }

    func shutdown() {
        if let observer = windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        windowCloseObserver = nil
        maintenanceScheduler?.invalidate()
        maintenanceScheduler = nil
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        onboardingWindow?.contentViewController = nil
        onboardingWindow?.close()
        onboardingWindow = nil
        pasteboardMonitor?.stop()
        eventTapManager?.stop()
        eventTapManager = nil
        panelManager?.close()
    }

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

    func openPreferences() {
        AppBootstrap.shared.activateSettingsWindow()
    }

    func applyShortcutConfiguration(_ configuration: ShortcutConfiguration) {
        eventTapManager?.shortcutConfiguration = configuration
    }

    func applyStorageConfiguration() {
        let limits = storageLimits
        Task { [weak history] in
            await history?.updateLimits(limits)
        }
    }

    private var storageLimits: ClipboardLimits {
        ClipboardLimits(
            maxAge: appState.retentionHours * 3600,
            maxCount: appState.maxItemCount,
            maxMemoryBytes: appState.maxMemoryMB * 1024 * 1024,
            maxDiskBytes: appState.maxDiskMB * 1024 * 1024
        )
    }

    private func setupStatusItem() {
        statusItemController = StatusItemController()
        statusItemController.onPreferences = { [weak self] in
            self?.openPreferences()
        }
        statusItemController.onClearHistory = { [weak self] in
            self?.clearHistory()
        }
        statusItemController.onQuit = {
            NSApplication.shared.terminate(nil)
        }
        statusItemController.setup()
    }

    private func startEventTap() {
        let manager = EventTapManager()
        manager.shortcutConfiguration = appState.shortcutConfiguration
        manager.onOpenDrawer = { [weak self] in self?.openDrawer() }
        manager.onToggleDrawer = { [weak self] in self?.closeDrawer() }
        manager.onPreviousItem = { [weak self] in self?.appState.moveSelectionUp() }
        manager.onNextItem = { [weak self] in self?.appState.moveSelectionDown() }
        manager.onPaste = { [weak self] in self?.pasteSelected() }
        manager.onEscape = { [weak self] in self?.closeDrawer() }
        manager.onClickOutside = { [weak self] _ in self?.closeDrawer() }
        manager.onPossiblePasteboardChange = { [weak self] in
            self?.pasteboardMonitor?.hintAtPossibleChange()
        }

        guard manager.start() else {
            print("ClipNotch: Event tap failed to start")
            return
        }
        eventTapManager = manager
    }

    private func handleNewPasteboardContent() {
        guard let entry = ClipboardCapture.capture() else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.contentIngester.ingest(entry)
            if self.appState.isDrawerOpen {
                await self.appState.refreshItems(from: self.history)
            }
        }
    }

    private func openDrawer() {
        guard appState.hasAccessibilityPermission, !appState.isDrawerOpen else { return }

        Task { [weak self] in
            guard let self else { return }
            await self.appState.refreshItems(from: self.history)

            let bodyHeight = ScreenUtilities.bodyHeight(forItemCount: appState.items.count)
            let metrics = ScreenUtilities.notchMetrics(bodyHeight: bodyHeight)
            appState.isDrawerOpen = true
            eventTapManager?.drawerIsOpen = true
            appState.selectedIndex = 0

            panelManager.open(
                frame: metrics.windowFrame,
                content: DrawerView(appState: appState, metrics: metrics)
            )
        }
    }

    private func pasteSelected() {
        guard appState.isDrawerOpen, let item = appState.selectedItem else {
            closeDrawer()
            return
        }

        Task { [weak self] in
            guard let self, let payload = await self.history.payload(for: item.id) else {
                self?.closeDrawer()
                return
            }
            PasteDelivery.writeToPasteboard(payload)
            self.pasteboardMonitor.skipCurrentChange()
            self.closeDrawer()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                PasteDelivery.postSyntheticPaste()
            }
        }
    }

    private func closeDrawer() {
        appState.isDrawerOpen = false
        eventTapManager?.drawerIsOpen = false
        panelManager?.close(after: 0.18)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.appState.isDrawerOpen else { return }
            self.appState.clearLoadedItems()
        }
    }

    private func clearHistory() {
        Task { [weak self] in
            guard let self else { return }
            await self.history.clear()
            if self.appState.isDrawerOpen {
                await self.appState.refreshItems(from: self.history)
            } else {
                self.appState.clearLoadedItems()
            }
        }
    }

    private func startMaintenanceScheduler() {
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.clipnotch.history-maintenance")
        scheduler.repeats = true
        scheduler.interval = 6 * 3600
        scheduler.tolerance = 2 * 3600
        scheduler.qualityOfService = .background
        scheduler.schedule { [weak self] completion in
            Task { [weak self] in
                guard let self else {
                    completion(.finished)
                    return
                }
                await self.history.runMaintenance()
                completion(.finished)
            }
        }
        maintenanceScheduler = scheduler
    }

    private func startMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let critical = self.memoryPressureSource?.data.contains(.critical) == true
            self.appState.clearThumbnailCache()
            Task { [weak history] in
                await history?.handleMemoryPressure(critical: critical)
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func presentStorageFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "ClipNotch could not start"
        alert.informativeText = "Storage failed to open (\(error.localizedDescription))."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func presentOnboardingWindow() {
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        onboardingWindow?.contentViewController = nil
        onboardingWindow = nil

        let hosting = NSHostingController(rootView: OnboardingView(appState: appState))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to ClipNotch"
        window.setContentSize(NSSize(width: 440, height: 340))
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        onboardingWindow = window

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
