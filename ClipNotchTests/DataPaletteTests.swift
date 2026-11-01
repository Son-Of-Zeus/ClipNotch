import Foundation
import XCTest
@testable import ClipNotch

final class DataPaletteTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ClipNotchPaletteTests-\(UUID())")
    }

    func testDefaultsSeedOnceAndDeletingAllProfilesSurvivesRestart() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = DataPalettePersistence(directory: directory)
        let initial = try await persistence.load()
        XCTAssertEqual(initial.profiles.map(\.name), ["Personal", "Work"])
        XCTAssertEqual(initial.profiles[0].fields.map(\.label), ["Email", "Phone"])
        try await persistence.save(DataPaletteDocument(profiles: []))

        let reloaded = try await DataPalettePersistence(directory: directory).load()
        XCTAssertTrue(reloaded.profiles.isEmpty)
    }

    func testSavedProfileKeepsIDsAndExactMultilineValue() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = DataPaletteProfile(name: "Office", fields: [DataPaletteField(label: "Address", value: "  Line one\nLine two\n")])
        let document = DataPaletteDocument(profiles: [profile])
        try await DataPalettePersistence(directory: directory).save(document)
        let reloaded = try await DataPalettePersistence(directory: directory).load()
        XCTAssertEqual(reloaded, document)
    }

    func testCorruptFileIsNotReplacedByDefaults() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("data-palette.json")
        let corrupt = Data("invalid JSON".utf8)
        try corrupt.write(to: file)
        do {
            _ = try await DataPalettePersistence(directory: directory).load()
            XCTFail("Loading corrupt data must fail")
        } catch {
            XCTAssertEqual(try Data(contentsOf: file), corrupt)
        }
    }

    @MainActor
    func testProfileSelectionFiltersEmptyValuesAndClampsNavigation() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = DataPalettePersistence(directory: directory)
        let profile = DataPaletteProfile(name: "Work", fields: [
            DataPaletteField(label: "Email", value: "work@example.com"),
            DataPaletteField(label: "Phone"),
            DataPaletteField(label: "Note", value: "\n")
        ])
        try await persistence.save(DataPaletteDocument(profiles: [profile]))
        let store = DataPaletteStore(persistence: persistence)
        await store.load()
        XCTAssertTrue(store.openSelectedProfile())
        XCTAssertEqual(store.fields.map(\.label), ["Email", "Note"])
        store.moveSelection(by: 10, inProfiles: false)
        XCTAssertEqual(store.selectedField?.value, "\n")
        store.moveSelection(by: -10, inProfiles: false)
        XCTAssertEqual(store.selectedField?.value, "work@example.com")
        let deleted = await store.delete(profile)
        XCTAssertTrue(deleted)
        XCTAssertFalse(store.openSelectedProfile())
        XCTAssertNil(store.selectedField)
    }

    @MainActor
    func testFailedSaveRetainsOriginalProfile() async {
        let store = DataPaletteStore(persistence: FailingPalettePersistence())
        await store.load()
        let original = store.profiles
        var changed = original[0]
        changed.name = "Changed"
        let saved = await store.save(changed)
        XCTAssertFalse(saved)
        XCTAssertEqual(store.profiles, original)
        XCTAssertNotNil(store.errorMessage)
    }

    func testClipboardCleanupDoesNotRemovePaletteData() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let palette = DataPalettePersistence(directory: directory)
        let document = try await palette.load()
        let clipboard = try ClipboardPersistence(baseDirectory: directory, removeLegacyData: false)
        try await clipboard.clear()
        try await clipboard.runMaintenance(limits: ClipboardLimits(maxAge: 1, maxCount: 1, maxMemoryBytes: 1024, maxDiskBytes: 1024))
        let reloaded = try await palette.load()
        XCTAssertEqual(reloaded, document)
    }
}

private actor FailingPalettePersistence: DataPalettePersisting {
    func load() -> DataPaletteDocument { .initial }
    func save(_ document: DataPaletteDocument) throws { throw CocoaError(.fileWriteNoPermission) }
}
