import AppKit
import SwiftUI
import Observation

@Observable
@MainActor
final class AppState {
    var drawer = DrawerSession()
    let dataPalette = DataPaletteStore()
    let autofillSettings = AutofillSettings()
    var isRecordingShortcut = false
    var showsDataPalettePreferences = false

    var isDrawerOpen: Bool { drawer.isOpen }
    var selectedIndex: Int = 0
    var items: [ClipboardSummary] = []
    var hasAccessibilityPermission: Bool = false
    var isFirstLaunch: Bool = true

    @ObservationIgnored private var persistTimers: [String: DispatchWorkItem] = [:]
    @ObservationIgnored private let thumbnailCache = NSCache<NSString, NSImage>()
    @ObservationIgnored private var payloadLoader: (@Sendable (String) async -> ClipboardPayload?)?

    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet { debouncePersist("hasCompletedOnboarding") { UserDefaults.standard.set(self.hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }
    }

    var retentionHours: Double = {
        let v = UserDefaults.standard.double(forKey: "retentionHours"); return v > 0 ? v : 24
    }() {
        didSet { debouncePersist("retentionHours") { UserDefaults.standard.set(self.retentionHours, forKey: "retentionHours") } }
    }

    var maxItemCount: Int = {
        let v = UserDefaults.standard.integer(forKey: "maxItemCount"); return v > 0 ? v : 10
    }() {
        didSet { debouncePersist("maxItemCount") { UserDefaults.standard.set(self.maxItemCount, forKey: "maxItemCount") } }
    }

    var maxDiskMB: Int = {
        let v = UserDefaults.standard.integer(forKey: "maxDiskMB"); return v > 0 ? v : 100
    }() {
        didSet { debouncePersist("maxDiskMB") { UserDefaults.standard.set(self.maxDiskMB, forKey: "maxDiskMB") } }
    }

    var maxMemoryMB: Int = {
        let value = UserDefaults.standard.integer(forKey: "maxMemoryMB")
        return value > 0 ? value : 128
    }() {
        didSet { debouncePersist("maxMemoryMB") { UserDefaults.standard.set(self.maxMemoryMB, forKey: "maxMemoryMB") } }
    }

    var launchAtLogin: Bool = UserDefaults.standard.bool(forKey: "launchAtLogin") {
        didSet { debouncePersist("launchAtLogin") { UserDefaults.standard.set(self.launchAtLogin, forKey: "launchAtLogin") } }
    }

    var shortcutConfiguration: ShortcutConfiguration = ShortcutConfiguration.load() {
        didSet {
            debouncePersist("shortcutConfiguration") {
                self.shortcutConfiguration.save()
            }
        }
    }

    private func debouncePersist(_ key: String, action: @escaping () -> Void) {
        persistTimers[key]?.cancel()
        let item = DispatchWorkItem { action() }
        persistTimers[key] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
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

    func configurePayloadLoader(_ loader: @escaping @Sendable (String) async -> ClipboardPayload?) {
        payloadLoader = loader
    }

    func thumbnail(for id: String) async -> NSImage? {
        if let cached = thumbnailCache.object(forKey: id as NSString) {
            return cached
        }
        guard let payload = await payloadLoader?(id),
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
