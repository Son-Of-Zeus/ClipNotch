import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppCoordinator {
    let appState: AppState
    let accessibilityGuide = AccessibilityGuideController()

    private var history: ClipboardHistoryStore!
    private var contentIngester: ContentIngester!
    private var pasteboardMonitor: PasteboardMonitor!
    private var eventTapManager: EventTapManager?
    private var panelManager: PanelManager!
    private var autofillController: FormAutofillController?
    private var statusItemController: StatusItemController!
    private var onboardingWindow: NSWindow?
    private var restoreSettingsWindow: (() -> Void)?
    private var historyStartupTask: Task<Void, Never>?
    private var windowCloseObserver: Any?
    private var maintenanceScheduler: NSBackgroundActivityScheduler?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var drawerMetrics: NotchMetrics?
    private var drawerRequestID: UUID?
    private var drawerLoadTask: Task<Void, Never>?
    private var isLoadingClipboard = false
    private var pendingClipboardPaste = false
    private var isPasting = false
    private var onboardingSampleHash: String?
    private var reportedStorageError: String?

    init(appState: AppState, history: ClipboardHistoryStore? = nil, panelManager: PanelManager? = nil) {
        self.appState = appState
        self.history = history
        self.panelManager = panelManager ?? PanelManager()
    }

    func start(persistence: ClipboardPersistence) {
        appState.onStorageError = { [weak self] error in self?.presentStorageError(error) }
        appState.preferences.onError = { [weak self] error in self?.presentStorageError(error) }
        appState.launchAtLogin = SMAppService.mainApp.status == .enabled
        accessibilityGuide.onGranted = { [weak self] in
            guard let self else { return }
            self.refreshAccessibilityAndEventTap()
            if self.onboardingWindow?.isVisible == true {
                self.appState.onboarding.reconcilePermission(self.appState.hasAccessibilityPermission, shortcutsReady: self.appState.areShortcutsReady)
                NSApp.activate(ignoringOtherApps: true)
                self.onboardingWindow?.makeKeyAndOrderFront(nil)
            }
        }
        let history = ClipboardHistoryStore(persistence: persistence, limits: storageLimits, onError: { [weak appState] error in
            await appState?.reportStorageError(error)
        })
        self.history = history
        contentIngester = ContentIngester(history: history)
        appState.configurePayloadLoader { [weak history] id in
            try await history?.payload(for: id)
        }

        pasteboardMonitor = PasteboardMonitor()
        pasteboardMonitor.onNewContent = { [weak self] in
            self?.handleNewPasteboardContent()
        }

        autofillController = FormAutofillController(appState: appState, panel: panelManager, pasteboardMonitor: pasteboardMonitor)
        autofillController?.onPermissionChange = { [weak self] in self?.refreshAccessibilityAndEventTap() }
        setupStatusItem()
        refreshAccessibilityAndEventTap()
        startMaintenanceScheduler()
        startMemoryPressureMonitoring()

        historyStartupTask = Task { [weak self] in
            do {
                try await history.start()
            } catch {
                AppBootstrap.presentStartupFailure(error)
                return
            }
            await self?.appState.dataPalette.load()
            guard let self else { return }
            self.pasteboardMonitor.start()
            self.autofillController?.start()
        }

        showOnboardingIfNeeded()
    }

    func prepareToTerminate() async {
        await history?.shutdown()
    }

    func shutdown() {
        accessibilityGuide.stop()
        autofillController?.stop()
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
        appState.areShortcutsReady = false
        panelManager?.close()
    }

    func refreshAccessibilityAndEventTap() {
        appState.hasAccessibilityPermission = AXIsProcessTrusted()
        autofillController?.refresh()
        guard appState.hasAccessibilityPermission else {
            eventTapManager?.stop()
            eventTapManager = nil
            appState.areShortcutsReady = false
            return
        }
        if let eventTapManager, !eventTapManager.isRunning {
            eventTapManager.stop()
            self.eventTapManager = nil
        }
        if eventTapManager == nil { startEventTap() }
        appState.areShortcutsReady = eventTapManager?.isRunning == true
    }

    func openPreferences() {
        AppBootstrap.shared.activateSettingsWindow()
    }

    func showOnboarding(in window: NSWindow? = nil) {
        accessibilityGuide.stop()
        closeDrawer()
        onboardingSampleHash = nil
        appState.onboarding.move(to: .welcome)
        presentOnboardingWindow(in: window)
    }

    func showOnboardingIfNeeded() {
        guard !appState.hasCompletedOnboarding else { return }
        presentOnboardingWindow()
    }

    func refreshAutofill() { autofillController?.refresh() }

    func showDrawer(_ page: DrawerSession.Page) {
        refreshAccessibilityAndEventTap()
        guard appState.hasAccessibilityPermission && appState.areShortcutsReady else {
            appState.onboarding.move(to: .permission)
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
        statusItemController.onOpenDataPalette = { [weak self] in self?.showDrawer(.dataTypes) }
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
            if keyCode == 0x35, self.autofillController?.dismissWithEscape() == true { return true }
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

        guard manager.start() else { return }
        eventTapManager = manager
    }

    private func handleNewPasteboardContent() {
        guard let entry = ClipboardCapture.capture() else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.historyStartupTask?.value
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
        case .showDataTypes, .showClipboard:
            updateMouseInteraction(at: NSEvent.mouseLocation)
        }
    }

    private func moveSelection(by offset: Int) {
        if appState.drawer.page == .clipboard {
            if offset < 0 { appState.moveSelectionUp() } else { appState.moveSelectionDown() }
        } else {
            appState.dataPalette.moveSelection(by: offset, inDataTypes: appState.drawer.page == .dataTypes)
        }
    }

    func openDrawer() {
        autofillController?.drawerWillOpen()
        let requestID = UUID()
        drawerRequestID = requestID
        appState.selectedIndex = 0
        appState.dataPalette.resetSelection()
        isLoadingClipboard = true
        drawerLoadTask?.cancel()
        drawerLoadTask = Task { [weak self] in
            guard let self else { return }
            await self.historyStartupTask?.value
            let items = await self.history.summaries(limit: self.appState.maxItemCount)
            guard !Task.isCancelled, self.drawerRequestID == requestID else { return }
            self.appState.items = items
            self.appState.selectedIndex = min(self.appState.selectedIndex, max(items.count - 1, 0))
            if self.onboardingWindow?.isVisible == true, self.appState.onboarding.step == .practice,
               let hash = self.onboardingSampleHash,
               let index = items.firstIndex(where: { $0.contentHash == hash }) {
                self.appState.selectedIndex = index
            }
            let metrics = ScreenUtilities.notchMetrics(bodyHeight: ScreenUtilities.maxBodyHeight)
            self.drawerMetrics = metrics
            self.panelManager.open(
                frame: metrics.windowFrame,
                content: DrawerView(
                    appState: self.appState,
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
        case .dataTypes:
            guard appState.dataPalette.openSelectedType() else { return }
            appState.drawer.show(.profileValues, fromMouse: fromMouse)
            updateMouseInteraction(at: NSEvent.mouseLocation)
        case .profileValues:
            guard let value = appState.dataPalette.selectedValue else {
                closeDrawer()
                return
            }
            deliver(.text(value.field.value))
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
                let payload: ClipboardPayload?
                do {
                    payload = try await self.history.payload(for: item.id)
                } catch {
                    self.isPasting = false
                    self.closeDrawer()
                    self.presentStorageError(error)
                    return
                }
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
        if !appState.isDrawerOpen {
            autofillController?.handlePointer(quartzPoint, isClick: isClick)
        }
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

    func closeDrawer() {
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
        Task { [weak self] in
            guard let self else { return }
            await self.history.clear()
            self.appState.clearLoadedItems()
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

    private func presentStorageError(_ error: Error) {
        let message = error.localizedDescription
        guard reportedStorageError != message else { return }
        reportedStorageError = message
        let alert = NSAlert()
        alert.messageText = "ClipNotch storage failed"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentOnboardingWindow(in settingsWindow: NSWindow? = nil) {
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        onboardingWindow?.contentViewController = nil
        onboardingWindow = nil

        let hosting = NSHostingController(rootView: OnboardingView(
            appState: appState,
            guide: accessibilityGuide,
            onPermissionChange: { [weak self] in
                guard let self else { return }
                self.refreshAccessibilityAndEventTap()
                if self.appState.hasAccessibilityPermission {
                    NSApp.activate(ignoringOtherApps: true)
                    self.onboardingWindow?.makeKeyAndOrderFront(nil)
                }
            },
            onCopySample: { [weak self] in
                guard let self else { return false }
                self.refreshAccessibilityAndEventTap()
                guard self.appState.hasAccessibilityPermission && self.appState.areShortcutsReady else {
                    self.appState.onboarding.move(to: .permission)
                    return false
                }
                PasteDelivery.writeToPasteboard(.text(OnboardingView.sample))
                self.pasteboardMonitor.skipCurrentChange()
                guard let entry = ClipboardCapture.capture() else { return false }
                await self.historyStartupTask?.value
                await self.contentIngester.ingest(entry)
                self.onboardingSampleHash = entry.summary.contentHash
                return true
            },
            onFinish: { [weak self] in
                guard let self else { return }
                self.refreshAccessibilityAndEventTap()
                guard self.appState.hasAccessibilityPermission && self.appState.areShortcutsReady else { return }
                self.appState.hasCompletedOnboarding = true
                self.autofillController?.refresh()
                self.finishOnboarding()
            }
        ))
        let window = settingsWindow ?? NSWindow()
        if settingsWindow != nil {
            let settingsContent = window.contentView
            let settingsFrame = window.frame
            let settingsStyle = window.styleMask
            restoreSettingsWindow = { [weak window] in
                guard let window else { return }
                window.contentViewController = nil
                window.contentView = settingsContent
                window.styleMask = settingsStyle
                window.title = "ClipNotch"
                window.setFrame(settingsFrame, display: true)
            }
        }
        window.contentViewController = hosting
        window.title = "Welcome to ClipNotch"
        window.styleMask = [.titled, .closable]
        ClipNotchWindowChrome.apply(to: window)
        window.setContentSize(OnboardingView.windowSize)
        if settingsWindow == nil { window.center() }
        window.isReleasedWhenClosed = false
        onboardingWindow = window

        observeWindowClose(window) { [weak self] in
            self?.accessibilityGuide.stop()
            self?.onboardingSampleHash = nil
            self?.closeDrawer()
            if let restore = self?.restoreSettingsWindow {
                self?.restoreSettingsWindow = nil
                restore()
            } else {
                self?.onboardingWindow?.contentViewController = nil
            }
            self?.onboardingWindow = nil
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func finishOnboarding() {
        guard let restore = restoreSettingsWindow else {
            onboardingWindow?.close()
            return
        }
        accessibilityGuide.stop()
        onboardingSampleHash = nil
        closeDrawer()
        restoreSettingsWindow = nil
        onboardingWindow = nil
        if let observer = windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            windowCloseObserver = nil
        }
        restore()
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
