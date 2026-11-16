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
        let persistence = DataPalettePersistence(directory: directory, encryption: testEncryption)
        let initial = try await persistence.load()
        XCTAssertEqual(initial.profiles.map(\.name), ["Personal", "Work"])
        XCTAssertEqual(initial.profiles[0].fields.map(\.label), ["Email", "Phone"])
        try await persistence.save(DataPaletteDocument(profiles: []))

        let reloaded = try await DataPalettePersistence(directory: directory, encryption: testEncryption).load()
        XCTAssertTrue(reloaded.profiles.isEmpty)
    }

    func testSavedProfileKeepsIDsAndExactMultilineValue() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = DataPaletteProfile(name: "Office", fields: [DataPaletteField(label: "Address", value: "  Line one\nLine two\n")])
        let document = DataPaletteDocument(profiles: [profile])
        try await DataPalettePersistence(directory: directory, encryption: testEncryption).save(document)
        let reloaded = try await DataPalettePersistence(directory: directory, encryption: testEncryption).load()
        XCTAssertEqual(reloaded, document)
    }

    func testCorruptFileIsNotReplacedByDefaults() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("data-palette.enc")
        let corrupt = Data("invalid JSON".utf8)
        try corrupt.write(to: file)
        do {
            _ = try await DataPalettePersistence(directory: directory, encryption: testEncryption).load()
            XCTFail("Loading corrupt data must fail")
        } catch {
            XCTAssertEqual(try Data(contentsOf: file), corrupt)
        }
    }

    @MainActor
    func testTypeFirstSelectionFindsWorkOnlyPhoneWithValuePreview() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = DataPalettePersistence(directory: directory, encryption: testEncryption)
        let personal = DataPaletteProfile(name: "Personal", fields: [
            DataPaletteField(label: "Email", value: "personal@example.com"),
            DataPaletteField(label: "Phone")
        ])
        let work = DataPaletteProfile(name: "Work", fields: [
            DataPaletteField(label: "Email", value: "work@example.com"),
            DataPaletteField(label: "Phone", value: " +44 123 456 "),
            DataPaletteField(label: "Unused")
        ])
        try await persistence.save(DataPaletteDocument(profiles: [personal, work]))
        let store = DataPaletteStore(persistence: persistence)
        await store.load()

        XCTAssertEqual(store.dataTypes.map(\.label), ["Email", "Phone"])
        store.typeIndex = 1
        XCTAssertTrue(store.openSelectedType())
        XCTAssertEqual(store.profileValues.map(\.profileName), ["Work"])
        XCTAssertEqual(store.selectedValue?.field.value, " +44 123 456 ")
        XCTAssertEqual(store.selectedValue?.profileID, work.id)
    }

    @MainActor
    func testCustomTypesGroupLabelsAndPreserveEveryMatchingValue() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = DataPalettePersistence(directory: directory, encryption: testEncryption)
        let first = DataPaletteProfile(name: "Personal", fields: [
            DataPaletteField(label: "Office code", value: "First"),
            DataPaletteField(label: "Office code", value: "Second")
        ])
        let second = DataPaletteProfile(name: "Work", fields: [
            DataPaletteField(label: " office CODE ", value: "  Third\nline  ")
        ])
        try await persistence.save(DataPaletteDocument(profiles: [first, second]))
        let store = DataPaletteStore(persistence: persistence)
        await store.load()

        XCTAssertEqual(store.dataTypes.map(\.label), ["Office code"])
        XCTAssertEqual(store.profileCount(for: try XCTUnwrap(store.dataTypes.first)), 2)
        XCTAssertTrue(store.openSelectedType())
        XCTAssertEqual(store.profileValues.map(\.field.id), first.fields.map(\.id) + second.fields.map(\.id))
        store.moveSelection(by: 10, inDataTypes: false)
        XCTAssertEqual(store.selectedValue?.field.value, "  Third\nline  ")
        store.moveSelection(by: -10, inDataTypes: false)
        XCTAssertEqual(store.selectedValue?.field.value, "First")
    }

    @MainActor
    func testRemovingSelectedTypeClearsValuesWithoutReselectingAnotherType() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = DataPalettePersistence(directory: directory, encryption: testEncryption)
        let profile = DataPaletteProfile(name: "Work", fields: [DataPaletteField(label: "Phone", value: "123")])
        try await persistence.save(DataPaletteDocument(profiles: [profile]))
        let store = DataPaletteStore(persistence: persistence)
        await store.load()
        XCTAssertTrue(store.openSelectedType())

        let deleted = await store.delete(profile)

        XCTAssertTrue(deleted)
        XCTAssertTrue(store.dataTypes.isEmpty)
        XCTAssertTrue(store.profileValues.isEmpty)
        XCTAssertNil(store.selectedValue)
        XCTAssertFalse(store.openSelectedType())
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
        let palette = DataPalettePersistence(directory: directory, encryption: testEncryption)
        let document = try await palette.load()
        let clipboard = try ClipboardPersistence(directory: directory, encryption: testEncryption)
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
