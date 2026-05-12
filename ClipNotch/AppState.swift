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

    @ObservationIgnored
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false

    @ObservationIgnored
    @AppStorage("retentionHours") var retentionHours: Double = 24

    @ObservationIgnored
    @AppStorage("maxItemCount") var maxItemCount: Int = 500

    @ObservationIgnored
    @AppStorage("maxDiskMB") var maxDiskMB: Int = 500

    @ObservationIgnored
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false

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
        let fetched = await database.fetchRecent(limit: 20)
        items = fetched
        selectedIndex = 0
    }
}
