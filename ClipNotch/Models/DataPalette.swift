import Foundation

struct DataPaletteField: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var label: String
    var value: String = ""
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

    static let initial = DataPaletteDocument(profiles: [
        DataPaletteProfile(name: "Personal"),
        DataPaletteProfile(name: "Work")
    ])
}
