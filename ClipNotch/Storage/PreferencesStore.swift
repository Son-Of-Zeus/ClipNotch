import Foundation
import Observation

struct AppPreferences: Codable, Equatable {
    var hasCompletedOnboarding = false
    var onboardingStep = OnboardingStep.welcome.rawValue
    var retentionHours = 24.0
    var maxItemCount = 10
    var maxDiskMB = 100
    var maxMemoryMB = 128
    var launchAtLogin = false
    var shortcutConfiguration = ShortcutConfiguration.default
    var autofillEnabled = true
    var autofillExcludedHosts: [String] = []
}

@Observable
@MainActor
final class PreferencesStore {
    private(set) var values: AppPreferences
    private(set) var errorMessage: String?
    var onError: ((Error) -> Void)?
    private let fileURL: URL
    private let encryption: StorageEncryption

    init(directory: URL, encryption: StorageEncryption) throws {
        fileURL = directory.appendingPathComponent("preferences.enc")
        self.encryption = encryption
        if FileManager.default.fileExists(atPath: fileURL.path) {
            values = try JSONDecoder().decode(
                AppPreferences.self, from: encryption.read(from: fileURL, purpose: .preferences)
            )
        } else {
            values = AppPreferences()
            try encryption.write(JSONEncoder().encode(values), to: fileURL, purpose: .preferences)
        }
    }

    func set<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value>, to value: Value) {
        var updated = values
        updated[keyPath: keyPath] = value
        do {
            try encryption.write(JSONEncoder().encode(updated), to: fileURL, purpose: .preferences)
            values = updated
            errorMessage = nil
        } catch {
            errorMessage = "Could not save preferences: \(error.localizedDescription)"
            onError?(error)
        }
    }
}
