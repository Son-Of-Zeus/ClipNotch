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
    private(set) var selectedTypeID: String?
    var typeIndex = 0
    var valueIndex = 0

    @ObservationIgnored private let persistence: any DataPalettePersisting

    init(persistence: any DataPalettePersisting = DataPalettePersistence()) {
        self.persistence = persistence
    }

    var dataTypes: [DataPaletteType] {
        var seen = Set<String>()
        return profiles.flatMap(\.filledFields).compactMap { field in
            let type = DataPaletteType(label: field.label.trimmingCharacters(in: .whitespacesAndNewlines))
            return seen.insert(type.id).inserted ? type : nil
        }
    }

    var selectedType: DataPaletteType? {
        dataTypes.first { $0.id == selectedTypeID }
    }

    var profileValues: [DataPaletteValue] {
        guard let selectedType else { return [] }
        return values(for: selectedType)
    }

    var selectedValue: DataPaletteValue? {
        profileValues.indices.contains(valueIndex) ? profileValues[valueIndex] : nil
    }

    func values(for type: DataPaletteType) -> [DataPaletteValue] {
        profiles.flatMap { profile in
            profile.filledFields
                .filter { DataPaletteType.identifier(for: $0.label) == type.id }
                .map { DataPaletteValue(profileID: profile.id, profileName: profile.name, field: $0) }
        }
    }

    func profileCount(for type: DataPaletteType) -> Int {
        Set(values(for: type).map(\.profileID)).count
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
            typeIndex = min(typeIndex, max(dataTypes.count - 1, 0))
            valueIndex = min(valueIndex, max(profileValues.count - 1, 0))
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Could not save Data Palette: \(error.localizedDescription)"
            return false
        }
    }

    func openSelectedType() -> Bool {
        guard dataTypes.indices.contains(typeIndex) else { return false }
        selectedTypeID = dataTypes[typeIndex].id
        valueIndex = 0
        return true
    }

    func moveSelection(by offset: Int, inDataTypes: Bool) {
        if inDataTypes {
            typeIndex = min(max(typeIndex + offset, 0), max(dataTypes.count - 1, 0))
        } else {
            valueIndex = min(max(valueIndex + offset, 0), max(profileValues.count - 1, 0))
        }
    }

    func resetSelection() {
        typeIndex = 0
        valueIndex = 0
        selectedTypeID = nil
    }
}
