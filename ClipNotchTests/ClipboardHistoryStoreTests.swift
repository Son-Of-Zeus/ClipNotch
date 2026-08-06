import Foundation
import XCTest
@testable import ClipNotch

final class ClipboardHistoryStoreTests: XCTestCase {
    func testInsertDeduplicatesBeforePersistence() async throws {
        let persistence = RecordingPersistence()
        let store = ClipboardHistoryStore(persistence: persistence, limits: limits())
        let first = entry(id: "first", text: "same", hash: "duplicate")
        let second = entry(id: "second", text: "same", hash: "duplicate")

        let insertedFirst = await store.insert(first)
        let insertedSecond = await store.insert(second)
        let statistics = await store.statistics()
        let persistenceSnapshot = await persistence.snapshot()

        XCTAssertTrue(insertedFirst)
        XCTAssertFalse(insertedSecond)
        XCTAssertEqual(statistics.itemCount, 1)
        XCTAssertEqual(statistics.dirtyCount, 1)
        XCTAssertEqual(persistenceSnapshot.persistCalls, 0)
    }

    func testMemoryBudgetEvictsOldestDirtyEntry() async {
        let persistence = RecordingPersistence()
        let store = ClipboardHistoryStore(
            persistence: persistence,
            limits: limits(maxMemoryBytes: 10)
        )

        await store.insert(entry(id: "old", text: "aaaa", hash: "old"))
        await store.insert(entry(id: "new", text: "bbbb", hash: "new"))

        let summaries = await store.summaries(limit: 10)
        let statistics = await store.statistics()
        XCTAssertEqual(summaries.map(\.id), ["new"])
        XCTAssertEqual(statistics.residentBytes, 8)
    }

    func testIdleDelayPersistsOneBatch() async throws {
        let persistence = RecordingPersistence()
        let policy = ClipboardBatchPolicy(
            idleDelay: 0.02,
            hardDelay: 1,
            itemThreshold: 100,
            byteThreshold: .max
        )
        let store = ClipboardHistoryStore(
            persistence: persistence,
            limits: limits(),
            batchPolicy: policy
        )

        await store.insert(entry(id: "one", text: "1", hash: "one"))
        await store.insert(entry(id: "two", text: "2", hash: "two"))
        try await Task.sleep(nanoseconds: 100_000_000)

        let snapshot = await persistence.snapshot()
        let statistics = await store.statistics()
        XCTAssertEqual(snapshot.persistCalls, 1)
        XCTAssertEqual(snapshot.entryIDs, ["one", "two"])
        XCTAssertEqual(statistics.dirtyCount, 0)
    }

    func testFailedBatchRemainsDirty() async {
        let persistence = RecordingPersistence(shouldFail: true)
        let policy = ClipboardBatchPolicy(
            idleDelay: 60,
            hardDelay: 300,
            itemThreshold: 100,
            byteThreshold: .max
        )
        let store = ClipboardHistoryStore(
            persistence: persistence,
            limits: limits(),
            batchPolicy: policy
        )

        await store.insert(entry(id: "dirty", text: "value", hash: "dirty"))
        await store.flush()

        let statistics = await store.statistics()
        let snapshot = await persistence.snapshot()
        XCTAssertEqual(statistics.dirtyCount, 1)
        XCTAssertEqual(snapshot.persistCalls, 1)
        XCTAssertTrue(snapshot.entryIDs.isEmpty)

        await persistence.setShouldFail(false)
        await store.flush()
        let retriedStatistics = await store.statistics()
        let retriedSnapshot = await persistence.snapshot()
        XCTAssertEqual(retriedStatistics.dirtyCount, 0)
        XCTAssertEqual(retriedSnapshot.persistCalls, 2)
        XCTAssertEqual(retriedSnapshot.entryIDs, ["dirty"])
    }

    func testMemoryWarningFlushesThenUnloadsPersistedPayload() async {
        let persistence = RecordingPersistence()
        let store = ClipboardHistoryStore(
            persistence: persistence,
            limits: limits(maxMemoryBytes: 200)
        )
        let value = String(repeating: "a", count: 80)
        await store.insert(entry(id: "image-sized", text: value, hash: "large"))

        await store.handleMemoryPressure(critical: false)

        let statistics = await store.statistics()
        let reloaded = await store.payload(for: "image-sized")
        XCTAssertEqual(statistics.itemCount, 1)
        XCTAssertEqual(statistics.dirtyCount, 0)
        XCTAssertEqual(statistics.residentBytes, 0)
        XCTAssertEqual(reloaded, .text(value))
    }

    func testContentAddressedImageIsRemovedAfterDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipNotchTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = try ClipboardPersistence(baseDirectory: directory, removeLegacyData: false)
        let imageData = Data([0, 1, 2, 3])
        let image = ClipboardEntry(
            summary: ClipboardSummary(
                id: "image",
                createdAt: Date(),
                kind: .image,
                sourceBundleID: nil,
                appName: nil,
                displayTitle: "Image",
                preview: "Image",
                byteSize: imageData.count,
                contentHash: "content-hash"
            ),
            payload: .image(data: imageData, pasteboardType: "public.png")
        )

        try await persistence.persist(entries: [image], deleting: [], limits: limits())
        let loaded = await persistence.loadPayload(for: "image")
        let payloadDirectory = directory.appendingPathComponent("payloads-v2")
        XCTAssertEqual(loaded, image.payload)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: payloadDirectory.path).count, 1)

        try await persistence.persist(entries: [], deleting: ["image"], limits: limits())
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: payloadDirectory.path).isEmpty)
    }

    func testPersistencePrunesExpiredEntriesInBatch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipNotchTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = try ClipboardPersistence(baseDirectory: directory, removeLegacyData: false)
        let old = entry(id: "old", text: "old", hash: "old")
        let currentPayload = ClipboardPayload.text("current")
        let current = ClipboardEntry(
            summary: ClipboardSummary(
                id: "current",
                createdAt: Date(),
                kind: .text,
                sourceBundleID: nil,
                appName: nil,
                displayTitle: nil,
                preview: "current",
                byteSize: currentPayload.estimatedByteSize,
                contentHash: "current"
            ),
            payload: currentPayload
        )
        let expired = ClipboardEntry(
            summary: ClipboardSummary(
                id: old.summary.id,
                createdAt: Date().addingTimeInterval(-7200),
                kind: old.summary.kind,
                sourceBundleID: nil,
                appName: nil,
                displayTitle: nil,
                preview: old.summary.preview,
                byteSize: old.summary.byteSize,
                contentHash: old.summary.contentHash
            ),
            payload: old.payload
        )

        try await persistence.persist(entries: [expired, current], deleting: [], limits: limits())
        let summaries = await persistence.loadSummaries(
            limit: 10,
            cutoff: Date().addingTimeInterval(-3600)
        )
        XCTAssertEqual(summaries.map(\.id), ["current"])
    }

    private func entry(id: String, text: String, hash: String) -> ClipboardEntry {
        let payload = ClipboardPayload.text(text)
        return ClipboardEntry(
            summary: ClipboardSummary(
                id: id,
                createdAt: Date(),
                kind: .text,
                sourceBundleID: nil,
                appName: nil,
                displayTitle: nil,
                preview: text,
                byteSize: payload.estimatedByteSize,
                contentHash: hash
            ),
            payload: payload
        )
    }

    private func limits(maxMemoryBytes: Int = 1024 * 1024) -> ClipboardLimits {
        ClipboardLimits(
            maxAge: 3600,
            maxCount: 100,
            maxMemoryBytes: maxMemoryBytes,
            maxDiskBytes: 1024 * 1024
        )
    }
}

private actor RecordingPersistence: ClipboardPersisting {
    struct Snapshot: Sendable {
        let persistCalls: Int
        let entryIDs: Set<String>
    }

    private var entries: [String: ClipboardEntry] = [:]
    private var persistCalls = 0
    private var shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func loadSummaries(limit: Int, cutoff: Date) -> [ClipboardSummary] {
        entries.values
            .map(\.summary)
            .filter { $0.createdAt >= cutoff }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    func loadPayload(for id: String) -> ClipboardPayload? {
        entries[id]?.payload
    }

    func persist(
        entries newEntries: [ClipboardEntry],
        deleting ids: Set<String>,
        limits: ClipboardLimits
    ) throws {
        persistCalls += 1
        if shouldFail { throw TestError.expected }
        ids.forEach { entries.removeValue(forKey: $0) }
        newEntries.forEach { entries[$0.summary.id] = $0 }
    }

    func clear() {
        entries.removeAll()
    }

    func runMaintenance(limits: ClipboardLimits) {}

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func snapshot() -> Snapshot {
        Snapshot(persistCalls: persistCalls, entryIDs: Set(entries.keys))
    }
}

private enum TestError: Error {
    case expected
}
