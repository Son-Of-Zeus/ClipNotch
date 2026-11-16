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

    func testMemoryWarningFlushesThenUnloadsPersistedPayload() async throws {
        let persistence = RecordingPersistence()
        let store = ClipboardHistoryStore(
            persistence: persistence,
            limits: limits(maxMemoryBytes: 200)
        )
        let value = String(repeating: "a", count: 80)
        await store.insert(entry(id: "image-sized", text: value, hash: "large"))

        await store.handleMemoryPressure(critical: false)

        let statistics = await store.statistics()
        let reloaded = try await store.payload(for: "image-sized")
        XCTAssertEqual(statistics.itemCount, 1)
        XCTAssertEqual(statistics.dirtyCount, 0)
        XCTAssertEqual(statistics.residentBytes, 0)
        XCTAssertEqual(reloaded, .text(value))
    }

    func testContentAddressedImageIsRemovedAfterDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipNotchTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = try ClipboardPersistence(directory: directory, encryption: testEncryption)
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
        let loaded = try await persistence.loadPayload(for: "image")
        let payloadDirectory = directory.appendingPathComponent("payloads")
        XCTAssertEqual(loaded, image.payload)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: payloadDirectory.path).count, 1)

        try await persistence.persist(entries: [], deleting: ["image"], limits: limits())
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: payloadDirectory.path).isEmpty)
    }

    func testPersistencePrunesExpiredEntriesInBatch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipNotchTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = try ClipboardPersistence(directory: directory, encryption: testEncryption)
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
        let summaries = try await persistence.loadSummaries(
            limit: 10,
            cutoff: Date().addingTimeInterval(-3600)
        )
        XCTAssertEqual(summaries.map(\.id), ["current"])
    }

    func testRetentionKeepsCutoffAndExpiresSummariesOnRead() async {
        let clock = TestClock()
        let store = ClipboardHistoryStore(persistence: RecordingPersistence(), limits: limits(), now: { clock.now() })
        await store.insert(entry(id: "old", text: "old", hash: "old", createdAt: clock.now()))
        clock.advance(by: 1)
        await store.insert(entry(id: "new", text: "new", hash: "new", createdAt: clock.now()))
        clock.advance(by: 3599)

        let atCutoff = await store.summaries(limit: 10)
        XCTAssertEqual(atCutoff.map(\.id), ["new", "old"])

        clock.advance(by: 1)
        let afterCutoff = await store.summaries(limit: 10)
        let statistics = await store.statistics()
        XCTAssertEqual(afterCutoff.map(\.id), ["new"])
        XCTAssertEqual(statistics.residentBytes, ClipboardPayload.text("new").estimatedByteSize)
        await store.shutdown()
    }

    func testCachedPayloadExpiresOnRead() async throws {
        let clock = TestClock()
        let store = ClipboardHistoryStore(persistence: RecordingPersistence(), limits: limits(), now: { clock.now() })
        let item = entry(id: "cached", text: "value", hash: "cached", createdAt: clock.now())
        await store.insert(item)
        clock.advance(by: 3600)
        let atCutoff = try await store.payload(for: item.summary.id)
        XCTAssertEqual(atCutoff, item.payload)

        clock.advance(by: 1)
        let expired = try await store.payload(for: item.summary.id)
        let statistics = await store.statistics()
        XCTAssertNil(expired)
        XCTAssertEqual(statistics, ClipboardHistoryStatistics(itemCount: 0, dirtyCount: 0, residentBytes: 0))
        await store.shutdown()
    }

    func testRecopyOfExpiredContentCreatesFreshEntry() async {
        let clock = TestClock()
        let persistence = RecordingPersistence()
        let store = ClipboardHistoryStore(persistence: persistence, limits: limits(), now: { clock.now() })
        await store.insert(entry(id: "old", text: "same", hash: "same", createdAt: clock.now()))
        await store.flush()
        clock.advance(by: 3601)

        let inserted = await store.insert(entry(id: "fresh", text: "same", hash: "same", createdAt: clock.now()))
        let summaries = await store.summaries(limit: 10)
        await store.flush()
        let snapshot = await persistence.snapshot()
        XCTAssertTrue(inserted)
        XCTAssertEqual(summaries.map(\.id), ["fresh"])
        XCTAssertEqual(snapshot.entryIDs, ["fresh"])
        XCTAssertEqual(snapshot.deletedIDs, ["old"])
    }

    func testExpiredReadQueuesPersistentDeletion() async throws {
        let clock = TestClock()
        let item = entry(id: "persisted", text: "value", hash: "persisted", createdAt: clock.now())
        let persistence = RecordingPersistence(entries: [item])
        let store = ClipboardHistoryStore(persistence: persistence, limits: limits(), now: { clock.now() })
        try await store.start()
        clock.advance(by: 3601)

        let summaries = await store.summaries(limit: 10)
        let payload = try await store.payload(for: item.summary.id)
        let beforeFlush = await persistence.snapshot()
        XCTAssertTrue(summaries.isEmpty)
        XCTAssertNil(payload)
        XCTAssertEqual(beforeFlush.entryIDs, [item.summary.id])
        XCTAssertEqual(beforeFlush.persistCalls, 0)

        await store.flush()
        let afterFlush = await persistence.snapshot()
        XCTAssertTrue(afterFlush.entryIDs.isEmpty)
        XCTAssertEqual(afterFlush.deletedIDs, [item.summary.id])
        XCTAssertEqual(afterFlush.persistCalls, 1)
    }

    func testExpiredReadSchedulesDeletionBatch() async throws {
        let clock = TestClock()
        let deleted = expectation(description: "Scheduled expiration deletion")
        let item = entry(id: "persisted", text: "value", hash: "persisted", createdAt: clock.now())
        let persistence = RecordingPersistence(entries: [item], onPersist: { deleted.fulfill() })
        let store = ClipboardHistoryStore(
            persistence: persistence,
            limits: limits(),
            batchPolicy: ClipboardBatchPolicy(idleDelay: 0),
            now: { clock.now() }
        )
        try await store.start()
        clock.advance(by: 3601)
        _ = await store.summaries(limit: 10)

        await fulfillment(of: [deleted], timeout: 2)
        let snapshot = await persistence.snapshot()
        XCTAssertEqual(snapshot.deletedIDs, [item.summary.id])
        XCTAssertTrue(snapshot.entryIDs.isEmpty)
        await store.shutdown()
    }

    func testStartupRemovesItemsThatExpiredDuringLoading() async throws {
        let clock = TestClock()
        let item = entry(id: "persisted", text: "value", hash: "persisted", createdAt: clock.now())
        let persistence = RecordingPersistence(entries: [item], onLoadSummaries: { clock.advance(by: 3601) })
        let store = ClipboardHistoryStore(persistence: persistence, limits: limits(), now: { clock.now() })

        try await store.start()
        let statistics = await store.statistics()
        XCTAssertEqual(statistics.itemCount, 0)
        await store.flush()
        let snapshot = await persistence.snapshot()
        XCTAssertEqual(snapshot.deletedIDs, [item.summary.id])
    }

    func testConcurrentPayloadLoadsCountMemoryOnceAndEvictAccurately() async throws {
        let clock = TestClock()
        let old = entry(id: "old", text: "aaaa", hash: "old", createdAt: clock.now())
        let new = entry(id: "new", text: "bbbb", hash: "new", createdAt: clock.now().addingTimeInterval(1))
        let persistence = RecordingPersistence(entries: [old, new], suspendPayloadLoads: true)
        let store = ClipboardHistoryStore(
            persistence: persistence,
            limits: limits(maxMemoryBytes: old.payload.estimatedByteSize + new.payload.estimatedByteSize),
            now: { clock.now() }
        )
        try await store.start()
        let reads = (0..<3).map { _ in Task { try await store.payload(for: old.summary.id) } }
        await persistence.waitForPayloadLoads(3)
        await persistence.releasePayloadLoads()
        for read in reads {
            let payload = try await read.value
            XCTAssertEqual(payload, old.payload)
        }
        let afterConcurrentLoads = await store.statistics()
        XCTAssertEqual(afterConcurrentLoads.residentBytes, old.payload.estimatedByteSize)

        let newPayload = try await store.payload(for: new.summary.id)
        XCTAssertEqual(newPayload, new.payload)
        let beforeEviction = await store.statistics()
        XCTAssertEqual(beforeEviction.residentBytes, old.payload.estimatedByteSize + new.payload.estimatedByteSize)
        await store.updateLimits(limits(maxMemoryBytes: new.payload.estimatedByteSize))
        let afterEviction = await store.statistics()
        let cachedNewPayload = try await store.payload(for: new.summary.id)
        let snapshot = await persistence.snapshot()
        XCTAssertEqual(afterEviction.residentBytes, new.payload.estimatedByteSize)
        XCTAssertEqual(afterEviction.itemCount, 2)
        XCTAssertEqual(cachedNewPayload, new.payload)
        XCTAssertEqual(snapshot.payloadLoadCalls, 4)
        await store.shutdown()
    }

    func testClearDeallocatesResidentImageBuffer() async throws {
        let released = expectation(description: "Image buffer released")
        let persistence = RecordingPersistence()
        let store = ClipboardHistoryStore(persistence: persistence, limits: limits())
        await store.insert(imageEntry(releasing: released))
        let beforeClear = await store.statistics()
        XCTAssertEqual(beforeClear.residentBytes, 512 * 1024)

        await store.clear()

        let afterClear = await store.statistics()
        let payload = try await store.payload(for: "image")
        XCTAssertEqual(afterClear, ClipboardHistoryStatistics(itemCount: 0, dirtyCount: 0, residentBytes: 0))
        XCTAssertNil(payload)
        await fulfillment(of: [released], timeout: 1)
    }

    func testClearDuringPayloadLoadDoesNotRestoreItem() async throws {
        let item = entry(id: "persisted", text: "value", hash: "persisted")
        let persistence = RecordingPersistence(entries: [item], suspendPayloadLoads: true)
        let store = ClipboardHistoryStore(persistence: persistence, limits: limits())
        try await store.start()
        let read = Task { try await store.payload(for: item.summary.id) }
        await persistence.waitForPayloadLoads(1)
        await store.clear()
        await persistence.releasePayloadLoads()

        let payload = try await read.value
        let statistics = await store.statistics()
        XCTAssertNil(payload)
        XCTAssertEqual(statistics, ClipboardHistoryStatistics(itemCount: 0, dirtyCount: 0, residentBytes: 0))
    }

    func testExpirationDuringPayloadLoadDoesNotRestoreItem() async throws {
        let clock = TestClock()
        let item = entry(id: "persisted", text: "value", hash: "persisted", createdAt: clock.now())
        let persistence = RecordingPersistence(entries: [item], suspendPayloadLoads: true)
        let store = ClipboardHistoryStore(persistence: persistence, limits: limits(), now: { clock.now() })
        try await store.start()
        let read = Task { try await store.payload(for: item.summary.id) }
        await persistence.waitForPayloadLoads(1)
        clock.advance(by: 3601)
        await persistence.releasePayloadLoads()

        let payload = try await read.value
        let statistics = await store.statistics()
        XCTAssertNil(payload)
        XCTAssertEqual(statistics, ClipboardHistoryStatistics(itemCount: 0, dirtyCount: 0, residentBytes: 0))
        await store.flush()
        let snapshot = await persistence.snapshot()
        XCTAssertEqual(snapshot.deletedIDs, [item.summary.id])
    }

    func testPayloadLoadFindsRecordAfterIndexChanges() async throws {
        let item = entry(id: "persisted", text: "value", hash: "persisted")
        let persistence = RecordingPersistence(entries: [item], suspendPayloadLoads: true)
        let store = ClipboardHistoryStore(persistence: persistence, limits: limits())
        try await store.start()
        let read = Task { try await store.payload(for: item.summary.id) }
        await persistence.waitForPayloadLoads(1)
        let new = entry(id: "new", text: "new", hash: "new")
        await store.insert(new)
        await persistence.releasePayloadLoads()

        let payload = try await read.value
        let newPayload = try await store.payload(for: new.summary.id)
        let statistics = await store.statistics()
        XCTAssertEqual(payload, item.payload)
        XCTAssertEqual(newPayload, new.payload)
        XCTAssertEqual(statistics.residentBytes, item.payload.estimatedByteSize + new.payload.estimatedByteSize)
        await store.shutdown()
    }

    private func imageEntry(releasing expectation: XCTestExpectation) -> ClipboardEntry {
        let size = 512 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 1)
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        let data = Data(bytesNoCopy: buffer, count: size, deallocator: .custom { buffer, _ in
            buffer.deallocate()
            expectation.fulfill()
        })
        return ClipboardEntry(
            summary: ClipboardSummary(
                id: "image",
                createdAt: Date(),
                kind: .image,
                sourceBundleID: nil,
                appName: nil,
                displayTitle: "Image",
                preview: "Image",
                byteSize: size,
                contentHash: "image"
            ),
            payload: .image(data: data, pasteboardType: "public.png")
        )
    }

    private func entry(id: String, text: String, hash: String, createdAt: Date = Date()) -> ClipboardEntry {
        let payload = ClipboardPayload.text(text)
        return ClipboardEntry(
            summary: ClipboardSummary(
                id: id,
                createdAt: createdAt,
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
        let deletedIDs: Set<String>
        let payloadLoadCalls: Int
    }

    private var entries: [String: ClipboardEntry] = [:]
    private var persistCalls = 0
    private var shouldFail: Bool
    private var deletedIDs = Set<String>()
    private var payloadLoadCalls = 0
    private var suspendPayloadLoads: Bool
    private var pendingLoads: [(ClipboardPayload?, CheckedContinuation<ClipboardPayload?, Never>)] = []
    private var loadWaiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?
    private let onLoadSummaries: @Sendable () -> Void
    private let onPersist: @Sendable () -> Void

    init(
        shouldFail: Bool = false,
        entries: [ClipboardEntry] = [],
        suspendPayloadLoads: Bool = false,
        onLoadSummaries: @escaping @Sendable () -> Void = {},
        onPersist: @escaping @Sendable () -> Void = {}
    ) {
        self.shouldFail = shouldFail
        self.entries = Dictionary(uniqueKeysWithValues: entries.map { ($0.summary.id, $0) })
        self.suspendPayloadLoads = suspendPayloadLoads
        self.onLoadSummaries = onLoadSummaries
        self.onPersist = onPersist
    }

    func loadSummaries(limit: Int, cutoff: Date) -> [ClipboardSummary] {
        defer { onLoadSummaries() }
        return entries.values
            .map(\.summary)
            .filter { $0.createdAt >= cutoff }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    func loadPayload(for id: String) async -> ClipboardPayload? {
        payloadLoadCalls += 1
        let payload = entries[id]?.payload
        guard suspendPayloadLoads else { return payload }
        return await withCheckedContinuation { continuation in
            pendingLoads.append((payload, continuation))
            if let waiter = loadWaiter, pendingLoads.count >= waiter.count {
                loadWaiter = nil
                waiter.continuation.resume()
            }
        }
    }

    func waitForPayloadLoads(_ count: Int) async {
        guard pendingLoads.count < count else { return }
        await withCheckedContinuation { loadWaiter = (count, $0) }
    }

    func releasePayloadLoads() {
        suspendPayloadLoads = false
        let loads = pendingLoads
        pendingLoads.removeAll()
        for (payload, continuation) in loads {
            continuation.resume(returning: payload)
        }
    }

    func persist(
        entries newEntries: [ClipboardEntry],
        deleting ids: Set<String>,
        limits: ClipboardLimits
    ) throws {
        persistCalls += 1
        if shouldFail { throw TestError.expected }
        ids.forEach { entries.removeValue(forKey: $0) }
        deletedIDs.formUnion(ids)
        newEntries.forEach { entries[$0.summary.id] = $0 }
        onPersist()
    }

    func clear() {
        entries.removeAll()
    }

    func runMaintenance(limits: ClipboardLimits) {}

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func snapshot() -> Snapshot {
        Snapshot(
            persistCalls: persistCalls,
            entryIDs: Set(entries.keys),
            deletedIDs: deletedIDs,
            payloadLoadCalls: payloadLoadCalls
        )
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_000_000)

    func now() -> Date {
        lock.withLock { date }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { date.addTimeInterval(interval) }
    }
}

private enum TestError: Error {
    case expected
}
