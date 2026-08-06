import SwiftUI
import Observation

@Observable
@MainActor
final class AppState {
    var isDrawerOpen: Bool = false
    var selectedIndex: Int = 0
    var items: [ClipboardItem] = []
    var hasAccessibilityPermission: Bool = false
    var isFirstLaunch: Bool = true

    @ObservationIgnored private var persistTimers: [String: DispatchWorkItem] = [:]

    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet { debouncePersist("hasCompletedOnboarding") { UserDefaults.standard.set(self.hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }
    }

    var showOnboardingOnLaunch: Bool = UserDefaults.standard.bool(forKey: "showOnboardingOnLaunch") {
        didSet { debouncePersist("showOnboardingOnLaunch") { UserDefaults.standard.set(self.showOnboardingOnLaunch, forKey: "showOnboardingOnLaunch") } }
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

    func moveSelectionDown() {
        guard !items.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, items.count - 1)
    }

    func moveSelectionUp() {
        selectedIndex = max(selectedIndex - 1, 0)
    }

    var selectedItem: ClipboardItem? {
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    func refreshItems(from database: DatabaseActor) async {
        let fetched = await database.fetchRecent(limit: maxItemCount)
        items = fetched
        selectedIndex = 0
    }

    func clearLoadedItems() {
        items.removeAll(keepingCapacity: false)
        selectedIndex = 0
    }
}

private extension ShortcutConfiguration {
    static let storageKey = "shortcutConfiguration"

    static func load() -> ShortcutConfiguration {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let configuration = try? JSONDecoder().decode(ShortcutConfiguration.self, from: data) else {
            return .default
        }
        return configuration
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
