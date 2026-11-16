import Foundation
import XCTest
@testable import ClipNotch

let testEncryption = try! StorageEncryption(keyData: Data(repeating: 0x42, count: 32))

extension XCTestCase {
    func makeStorageDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipNotchTests-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    @MainActor
    func makePreferences() throws -> PreferencesStore {
        try PreferencesStore(directory: makeStorageDirectory(), encryption: testEncryption)
    }

    @MainActor
    func makeAppState() throws -> AppState {
        AppState(
            preferences: try makePreferences(),
            dataPalette: DataPaletteStore(persistence: DataPalettePersistence(
                directory: makeStorageDirectory(), encryption: testEncryption
            ))
        )
    }
}
