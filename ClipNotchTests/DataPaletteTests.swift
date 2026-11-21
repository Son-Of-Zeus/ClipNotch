import AppKit
import SwiftUI
import XCTest
@testable import ClipNotch

final class DataPaletteTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ClipNotchPaletteTests-\(UUID())")
    }

    @MainActor
    func testEditorScrollsToEachNewRow() throws {
        let draft = ScrollTestDraft()
        let host = NSHostingView(rootView: ScrollTestEditor(draft: draft))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 160),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(findScrollView(in: host))
        let document = try XCTUnwrap(scrollView.documentView)
        func distanceFromBottom() -> CGFloat {
            let visibleRect = scrollView.documentVisibleRect
            return document.isFlipped ? document.bounds.maxY - visibleRect.maxY : visibleRect.minY - document.bounds.minY
        }

        XCTAssertGreaterThan(distanceFromBottom(), 100, "Existing rows should start at the top")
        for _ in 0..<2 {
            let previousHeight = document.bounds.height
            let field = DataPaletteField(label: "")
            draft.rows.append(field)
            draft.addedRowID = field.id
            let reachedBottom = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                document.bounds.height > previousHeight && distanceFromBottom() <= 4
            }, object: nil)
            wait(for: [reachedBottom], timeout: 3)
        }
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        return view.subviews.lazy.compactMap(findScrollView(in:)).first
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
    func testTypeFirstSelectionFindsWorkOnlyPhoneWithValuePreview() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = DataPalettePersistence(directory: directory)
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
        let persistence = DataPalettePersistence(directory: directory)
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
        let persistence = DataPalettePersistence(directory: directory)
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
        let palette = DataPalettePersistence(directory: directory)
        let document = try await palette.load()
        let clipboard = try ClipboardPersistence(baseDirectory: directory, removeLegacyData: false)
        try await clipboard.clear()
        try await clipboard.runMaintenance(limits: ClipboardLimits(maxAge: 1, maxCount: 1, maxMemoryBytes: 1024, maxDiskBytes: 1024))
        let reloaded = try await palette.load()
        XCTAssertEqual(reloaded, document)
    }
}

private final class ScrollTestDraft: ObservableObject {
    @Published var rows = (1...12).map { DataPaletteField(label: "Field \($0)") }
    @Published var addedRowID: UUID?
}

private struct ScrollTestEditor: View {
    @ObservedObject var draft: ScrollTestDraft

    var body: some View {
        PaletteEditorScrollView(addedRowID: draft.addedRowID) {
            ForEach(draft.rows) { row in
                Text(row.label).frame(height: 40).id(row.id)
            }
        }
    }
}

private actor FailingPalettePersistence: DataPalettePersisting {
    func load() -> DataPaletteDocument { .initial }
    func save(_ document: DataPaletteDocument) throws { throw CocoaError(.fileWriteNoPermission) }
}
