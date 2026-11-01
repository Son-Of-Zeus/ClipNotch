import Foundation
import Observation

@Observable
@MainActor
final class DataPaletteStore {
    private(set) var profiles: [DataPaletteProfile] = []
    private(set) var isLoaded = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    var selectedProfileID: UUID?
    var profileIndex = 0
    var fieldIndex = 0

    @ObservationIgnored private let persistence: any DataPalettePersisting

    init(persistence: any DataPalettePersisting = DataPalettePersistence()) {
        self.persistence = persistence
    }

    var selectedProfile: DataPaletteProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    var fields: [DataPaletteField] { selectedProfile?.filledFields ?? [] }

    var selectedField: DataPaletteField? {
        fields.indices.contains(fieldIndex) ? fields[fieldIndex] : nil
    }

    func load() async {
        guard !isLoaded, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            profiles = try await persistence.load().profiles
            isLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = "Could not load Data Palette: \(error.localizedDescription)"
        }
    }

    func save(_ profile: DataPaletteProfile) async -> Bool {
        guard isLoaded, !isSaving, profile.isValid else { return false }
        var updated = profiles
        if let index = updated.firstIndex(where: { $0.id == profile.id }) {
            updated[index] = profile
        } else {
            updated.append(profile)
        }
        return await persist(updated)
    }

    func delete(_ profile: DataPaletteProfile) async -> Bool {
        guard isLoaded, !isSaving else { return false }
        return await persist(profiles.filter { $0.id != profile.id })
    }

    private func persist(_ updated: [DataPaletteProfile]) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            try await persistence.save(DataPaletteDocument(profiles: updated))
            profiles = updated
            profileIndex = min(profileIndex, max(profiles.count - 1, 0))
            fieldIndex = min(fieldIndex, max(fields.count - 1, 0))
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Could not save Data Palette: \(error.localizedDescription)"
            return false
        }
    }

    func openSelectedProfile() -> Bool {
        guard profiles.indices.contains(profileIndex) else { return false }
        selectedProfileID = profiles[profileIndex].id
        fieldIndex = 0
        return true
    }

    func selectProfile(_ id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profileIndex = index
        _ = openSelectedProfile()
    }

    func moveSelection(by offset: Int, inProfiles: Bool) {
        if inProfiles {
            profileIndex = min(max(profileIndex + offset, 0), max(profiles.count - 1, 0))
        } else {
            fieldIndex = min(max(fieldIndex + offset, 0), max(fields.count - 1, 0))
        }
    }

    func resetSelection() {
        profileIndex = 0
        fieldIndex = 0
        selectedProfileID = nil
    }
}
