import Foundation
import Observation

struct AutofillCategory: Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let synonyms: [String]

    static let builtInSynonyms = [
        "email": ["Email address", "E-mail", "E-mail address", "Your email", "Your email address"],
        "phone": ["Phone number", "Mobile", "Mobile number", "Telephone", "Telephone number", "Contact number"]
    ]
}

enum FormFieldMatcher {
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func isSensitive(_ labels: [String]) -> Bool {
        let terms = ["password", "passcode", "verification", "one time", "otp", "captcha", "security code", "authentication code"]
        return labels.contains { label in
            let padded = " " + normalize(label) + " "
            return terms.contains { padded.contains(" " + $0 + " ") }
        }
    }

    static func match(labels: [String], categories: [AutofillCategory]) -> String? {
        guard !isSensitive(labels) else { return nil }
        let names = Set(labels.flatMap { label -> [String] in
            let name = normalize(label)
            // Google Forms includes the required marker in the accessible question name.
            let requiredMarker = " required question"
            guard name.hasSuffix(requiredMarker) else { return [name] }
            return [name, String(name.dropLast(requiredMarker.count))]
        }.filter { !$0.isEmpty })
        let matches = categories.filter { category in
            let aliases = [category.label] + category.synonyms
                + (AutofillCategory.builtInSynonyms[category.id] ?? [])
            return aliases.contains { names.contains(normalize($0)) }
        }
        return matches.count == 1 ? matches[0].id : nil
    }
}

enum AutofillProfileResolver {
    static func candidates(for categoryID: String, preferredProfileID: UUID?, profiles: [DataPaletteProfile]) -> [DataPaletteValue] {
        let values = profiles.flatMap { profile in
            profile.fields.filter {
                DataPaletteType.identifier(for: $0.label) == categoryID
                    && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.map { DataPaletteValue(profileID: profile.id, profileName: profile.name, field: $0) }
        }
        let preferred = values.filter { $0.profileID == preferredProfileID }
        return preferred.isEmpty ? values : preferred
    }

    static func eligibleProfiles(for categoryIDs: Set<String>, profiles: [DataPaletteProfile]) -> [DataPaletteProfile] {
        profiles.filter { profile in
            profile.fields.contains {
                categoryIDs.contains(DataPaletteType.identifier(for: $0.label))
                    && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }
}

struct AutofillVisitPolicy: Equatable {
    private(set) var visitID: UUID?
    private(set) var isDismissed = false

    mutating func enter(_ id: UUID) {
        guard visitID != id else { return }
        visitID = id
        isDismissed = false
    }

    mutating func dismiss() { isDismissed = true }

    func permits(host: String, excludedHosts: [String]) -> Bool {
        !isDismissed && !excludedHosts.contains(host.lowercased())
    }
}

@Observable
@MainActor
final class AutofillSettings {
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: "autofillEnabled") }
    }
    private(set) var excludedHosts: [String] {
        didSet { defaults.set(excludedHosts, forKey: "autofillExcludedHosts") }
    }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: "autofillEnabled") as? Bool ?? true
        excludedHosts = defaults.stringArray(forKey: "autofillExcludedHosts") ?? []
    }

    func exclude(_ host: String) {
        excludedHosts = Array(Set(excludedHosts + [host.lowercased()])).sorted()
    }

    func allow(_ host: String) { excludedHosts.removeAll { $0 == host } }
}
