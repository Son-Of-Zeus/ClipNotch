import Foundation

struct DataPaletteField: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var label: String
    var value: String = ""
}

struct DataPaletteType: Equatable, Identifiable, Sendable {
    let label: String

    var id: String { Self.identifier(for: label) }

    static func identifier(for label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct DataPaletteValue: Equatable, Identifiable, Sendable {
    let profileID: UUID
    let profileName: String
    let field: DataPaletteField

    var id: UUID { field.id }
}

struct DataPaletteProfile: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var fields: [DataPaletteField] = [
        DataPaletteField(label: "Email"),
        DataPaletteField(label: "Phone")
    ]

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && fields.allSatisfy { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var filledFields: [DataPaletteField] { fields.filter { !$0.value.isEmpty } }
}

struct DataPaletteDocument: Codable, Equatable, Sendable {
    var profiles: [DataPaletteProfile]
    var synonyms: [String: [String]] = [:]

    init(profiles: [DataPaletteProfile], synonyms: [String: [String]] = [:]) {
        self.profiles = profiles
        self.synonyms = synonyms
    }

    private enum CodingKeys: String, CodingKey { case profiles, synonyms }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try container.decode([DataPaletteProfile].self, forKey: .profiles)
        synonyms = try container.decodeIfPresent([String: [String]].self, forKey: .synonyms) ?? [:]
    }

    static let initial = DataPaletteDocument(profiles: [
        DataPaletteProfile(name: "Personal"),
        DataPaletteProfile(name: "Work")
    ])
}
