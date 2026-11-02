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
    private var drawerMetrics: NotchMetrics?
    private var drawerRequestID: UUID?
    private var drawerLoadTask: Task<Void, Never>?
    private var isLoadingClipboard = false
    private var pendingClipboardPaste = false
    private var isPasting = false

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
            await self?.appState.dataPalette.load()
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

    func showDrawer(_ page: DrawerSession.Page) {
        refreshAccessibilityAndEventTap()
        guard appState.hasAccessibilityPermission else {
            presentOnboardingWindow()
            return
        }
        if appState.isDrawerOpen {
            appState.drawer.show(page, fromMouse: true)
        } else {
            appState.drawer.open(page)
            openDrawer()
        }
    }

    func shortcutConfigurationDidChange() {
        if appState.isDrawerOpen { closeDrawer() }
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
        statusItemController.onOpenClipboard = { [weak self] in self?.showDrawer(.clipboard) }
        statusItemController.onOpenDataPalette = { [weak self] in self?.showDrawer(.profiles) }
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
        manager.onKeyDown = { [weak self] keyCode, flags, isRepeat in
            guard let self, !self.appState.isRecordingShortcut else { return false }
            let wasOpen = self.appState.isDrawerOpen
            let configuration = self.appState.shortcutConfiguration
            let action = self.appState.drawer.keyDown(keyCode, flags: flags, isRepeat: isRepeat, configuration: configuration)
            if let action { self.performDrawerAction(action) }
            let isNavigationKey = keyCode == configuration.previousItem.keyCode || keyCode == configuration.nextItem.keyCode
            return action != nil || (wasOpen && isNavigationKey && !flags.contains(.maskAlternate) && !flags.contains(.maskControl))
        }
        manager.onFlagsChanged = { [weak self] flags in
            guard let self else { return }
            let action = self.appState.drawer.flagsChanged(flags, mode: self.appState.shortcutConfiguration.interactionMode)
            if let action { self.performDrawerAction(action) }
        }
        manager.onPointer = { [weak self] point, isClick in
            self?.handlePointer(point, isClick: isClick)
        }
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

    private func performDrawerAction(_ action: DrawerSession.Action) {
        switch action {
        case .open:
            guard appState.hasAccessibilityPermission else {
                appState.drawer.close()
                return
            }
            openDrawer()
        case .close: closeDrawer()
        case .previous: moveSelection(by: -1)
        case .next: moveSelection(by: 1)
        case .confirm: confirmSelection()
        case .showProfiles, .showClipboard:
            updateMouseInteraction(at: NSEvent.mouseLocation)
        }
    }

    private func moveSelection(by offset: Int) {
        if appState.drawer.page == .clipboard {
            if offset < 0 { appState.moveSelectionUp() } else { appState.moveSelectionDown() }
        } else {
            appState.dataPalette.moveSelection(by: offset, inProfiles: appState.drawer.page == .profiles)
        }
    }

    private func openDrawer() {
        let requestID = UUID()
        drawerRequestID = requestID
        appState.selectedIndex = 0
        appState.dataPalette.resetSelection()
        let metrics = ScreenUtilities.notchMetrics(bodyHeight: ScreenUtilities.maxBodyHeight)
        drawerMetrics = metrics
        panelManager.open(
            frame: metrics.windowFrame,
            content: DrawerView(
                appState: appState,
                metrics: metrics,
                onSelectPage: { [weak self] page in
                    self?.appState.drawer.show(page, fromMouse: true)
                    self?.updateMouseInteraction(at: NSEvent.mouseLocation)
                },
                onConfirm: { [weak self] in self?.confirmSelection(fromMouse: true) },
                onOpenPreferences: { [weak self] in
                    guard let self else { return }
                    self.closeDrawer()
                    self.appState.showsDataPalettePreferences = true
                    self.openPreferences()
                }
            )
        )
        updateMouseInteraction(at: NSEvent.mouseLocation)
        isLoadingClipboard = true
        drawerLoadTask?.cancel()
        drawerLoadTask = Task { [weak self] in
            guard let self else { return }
            let items = await self.history.summaries(limit: self.appState.maxItemCount)
            guard !Task.isCancelled, self.drawerRequestID == requestID else { return }
            self.appState.items = items
            self.appState.selectedIndex = min(self.appState.selectedIndex, max(items.count - 1, 0))
            self.isLoadingClipboard = false
            self.updateMouseInteraction(at: NSEvent.mouseLocation)
            if self.pendingClipboardPaste {
                self.pendingClipboardPaste = false
                self.confirmSelection()
            }
        }
    }

    private func confirmSelection(fromMouse: Bool = false) {
        guard appState.isDrawerOpen, !isPasting else { return }
        switch appState.drawer.page {
        case .profiles:
            guard appState.dataPalette.openSelectedProfile() else { return }
            appState.drawer.show(.fields, fromMouse: fromMouse)
            updateMouseInteraction(at: NSEvent.mouseLocation)
        case .fields:
            guard let field = appState.dataPalette.selectedField else {
                closeDrawer()
                return
            }
            deliver(.text(field.value))
        case .clipboard:
            if isLoadingClipboard {
                pendingClipboardPaste = true
                return
            }
            guard let item = appState.selectedItem else {
                closeDrawer()
                return
            }
            isPasting = true
            let requestID = drawerRequestID
            Task { [weak self] in
                guard let self else { return }
                let payload = await self.history.payload(for: item.id)
                guard self.drawerRequestID == requestID, self.appState.isDrawerOpen else { return }
                self.isPasting = false
                guard let payload else { self.closeDrawer(); return }
                self.deliver(payload)
            }
        }
    }

    private func deliver(_ payload: ClipboardPayload) {
        PasteDelivery.writeToPasteboard(payload)
        pasteboardMonitor.skipCurrentChange()
        closeDrawer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            PasteDelivery.postSyntheticPaste()
        }
    }

    private func handlePointer(_ quartzPoint: NSPoint, isClick: Bool) {
        guard appState.isDrawerOpen else { return }
        let point = ScreenUtilities.appKitPoint(fromQuartzPoint: quartzPoint)
        let inside = updateMouseInteraction(at: point)
        if isClick && !inside { closeDrawer() }
    }

    @discardableResult
    private func updateMouseInteraction(at point: NSPoint) -> Bool {
        guard let metrics = drawerMetrics, appState.isDrawerOpen else { return false }
        let height = metrics.notchHeight + appState.drawerBodyHeight
        let origin = NSPoint(x: metrics.screen.frame.midX - metrics.bodyWidth / 2, y: metrics.screen.frame.maxY)
        let local = CGPoint(x: point.x - origin.x, y: origin.y - point.y)
        let inside = NotchShape().path(in: CGRect(x: 0, y: 0, width: metrics.bodyWidth, height: height)).contains(local)
        panelManager.setMouseInteraction(enabled: inside)
        return inside
    }

    private func closeDrawer() {
        appState.drawer.close()
        drawerRequestID = nil
        drawerLoadTask?.cancel()
        drawerLoadTask = nil
        pendingClipboardPaste = false
        isLoadingClipboard = false
        isPasting = false
        panelManager?.setMouseInteraction(enabled: false)
        panelManager?.close(after: 0.18)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.appState.isDrawerOpen else { return }
            self.appState.clearLoadedItems()
        }
    }

    private func clearHistory() {
        appState.clearLoadedItems()
        Task { [weak self] in
            guard let self else { return }
            await self.history.clear()
            if self.appState.isDrawerOpen {
                await self.appState.refreshItems(from: self.history)
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

        let hosting = NSHostingController(rootView: OnboardingView(
            appState: appState,
            onPermissionChange: { [weak self] in
                self?.refreshAccessibilityAndEventTap()
            },
            onFinish: { [weak self] in
                guard let self else { return }
                self.refreshAccessibilityAndEventTap()
                guard self.appState.hasAccessibilityPermission else { return }
                self.appState.hasCompletedOnboarding = true
                self.onboardingWindow?.close()
            }
        ))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to ClipNotch"
        window.styleMask = [.titled, .closable]
        window.titlebarAppearsTransparent = true
        window.setContentSize(OnboardingView.windowSize)
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
