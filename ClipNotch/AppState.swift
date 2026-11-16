import AppKit
import SwiftUI
import Observation
import ServiceManagement

@Observable
@MainActor
final class AppState {
    var drawer = DrawerSession()
    let dataPalette: DataPaletteStore
    let autofillSettings: AutofillSettings
    var isRecordingShortcut = false
    var showsDataPalettePreferences = false
    let onboarding: OnboardingProgress
    let preferences: PreferencesStore
    var onStorageError: ((Error) -> Void)?
    var loginError: String?

    var isDrawerOpen: Bool { drawer.isOpen }
    var selectedIndex: Int = 0
    var items: [ClipboardSummary] = []
    var hasAccessibilityPermission: Bool = false
    var areShortcutsReady = false
    var isFirstLaunch: Bool = true

    @ObservationIgnored private let thumbnailCache = NSCache<NSString, NSImage>()
    @ObservationIgnored private var payloadLoader: (@Sendable (String) async throws -> ClipboardPayload?)?

    init(preferences: PreferencesStore, dataPalette: DataPaletteStore) {
        self.preferences = preferences
        self.dataPalette = dataPalette
        autofillSettings = AutofillSettings(preferences: preferences)
        onboarding = OnboardingProgress(preferences: preferences)
    }

    var hasCompletedOnboarding: Bool {
        get { preferences.values.hasCompletedOnboarding }
        set { preferences.set(\.hasCompletedOnboarding, to: newValue) }
    }

    var retentionHours: Double {
        get { preferences.values.retentionHours }
        set { preferences.set(\.retentionHours, to: newValue) }
    }

    var maxItemCount: Int {
        get { preferences.values.maxItemCount }
        set { preferences.set(\.maxItemCount, to: newValue) }
    }

    var maxDiskMB: Int {
        get { preferences.values.maxDiskMB }
        set { preferences.set(\.maxDiskMB, to: newValue) }
    }

    var maxMemoryMB: Int {
        get { preferences.values.maxMemoryMB }
        set { preferences.set(\.maxMemoryMB, to: newValue) }
    }

    var launchAtLogin: Bool {
        get { preferences.values.launchAtLogin }
        set { preferences.set(\.launchAtLogin, to: newValue) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
            loginError = nil
        } catch {
            loginError = "Could not change login settings: \(error.localizedDescription)"
        }
    }

    var shortcutConfiguration: ShortcutConfiguration {
        get { preferences.values.shortcutConfiguration }
        set { preferences.set(\.shortcutConfiguration, to: newValue) }
    }

    func reportStorageError(_ error: Error) {
        onStorageError?(error)
    }

    var drawerBodyHeight: CGFloat {
        let count: Int
        switch drawer.page {
        case .clipboard: count = items.count
        case .dataTypes: count = dataPalette.dataTypes.count
        case .profileValues: count = dataPalette.profileValues.count
        }
        let listHeight = count == 0 ? 130 : CGFloat(count) * 43 + 16
        return min(listHeight + 44 + 24 + (drawer.page.isPalette ? 32 : 0), ScreenUtilities.maxBodyHeight)
    }

    func moveSelectionDown() {
        guard !items.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, items.count - 1)
    }

    func moveSelectionUp() {
        selectedIndex = max(selectedIndex - 1, 0)
    }

    var selectedItem: ClipboardSummary? {
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    func refreshItems(from history: ClipboardHistoryStore) async {
        items = await history.summaries(limit: maxItemCount)
        selectedIndex = 0
    }

    func configurePayloadLoader(_ loader: @escaping @Sendable (String) async throws -> ClipboardPayload?) {
        payloadLoader = loader
    }

    func thumbnail(for id: String) async -> NSImage? {
        if let cached = thumbnailCache.object(forKey: id as NSString) {
            return cached
        }
        let payload: ClipboardPayload?
        do {
            payload = try await payloadLoader?(id)
        } catch {
            reportStorageError(error)
            return nil
        }
        guard let payload,
              case .image(let data, _) = payload,
              let image = NSImage(data: data) else { return nil }

        let size = NSSize(width: 64, height: 64)
        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        thumbnail.unlockFocus()
        thumbnailCache.setObject(thumbnail, forKey: id as NSString)
        return thumbnail
    }

    func clearThumbnailCache() {
        thumbnailCache.removeAllObjects()
    }

    func clearLoadedItems() {
        items.removeAll(keepingCapacity: false)
        selectedIndex = 0
        clearThumbnailCache()
    }
}
