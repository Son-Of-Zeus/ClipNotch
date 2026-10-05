import Foundation

struct ClipboardBatchPolicy: Sendable {
    var idleDelay: TimeInterval = 60
    var hardDelay: TimeInterval = 5 * 60
    var itemThreshold: Int = 25
    var byteThreshold: Int = 32 * 1024 * 1024
}

struct ClipboardHistoryStatistics: Equatable, Sendable {
    let itemCount: Int
    let dirtyCount: Int
    let residentBytes: Int
}

actor ClipboardHistoryStore {
    private struct Record: Sendable {
        let summary: ClipboardSummary
        var payload: ClipboardPayload?
        var isPersisted: Bool
        var isDirty: Bool
    }

    private let persistence: any ClipboardPersisting
    private let batchPolicy: ClipboardBatchPolicy
    private let now: @Sendable () -> Date
    private var limits: ClipboardLimits
    private var records: [Record] = []
    private var knownHashes = Set<String>()
    private var pendingDeletionIDs = Set<String>()
    private var residentBytes = 0
    private var idleFlushTask: Task<Void, Never>?
    private var hardFlushTask: Task<Void, Never>?

    init(
        persistence: any ClipboardPersisting,
        limits: ClipboardLimits,
        batchPolicy: ClipboardBatchPolicy = ClipboardBatchPolicy(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.persistence = persistence
        self.limits = limits
        self.batchPolicy = batchPolicy
        self.now = now
    }

    func start() async {
        let cutoff = now().addingTimeInterval(-limits.maxAge)
        let summaries = await persistence.loadSummaries(limit: limits.maxCount, cutoff: cutoff)
        records = summaries.map { Record(summary: $0, payload: nil, isPersisted: true, isDirty: false) }
        knownHashes = Set(summaries.map(\.contentHash))
        removeExpiredRecords()
    }

    @discardableResult
    func insert(_ entry: ClipboardEntry) async -> Bool {
        removeExpiredRecords()
        guard !knownHashes.contains(entry.summary.contentHash) else { return false }

        knownHashes.insert(entry.summary.contentHash)
        records.insert(Record(
            summary: entry.summary,
            payload: entry.payload,
            isPersisted: false,
            isDirty: true
        ), at: 0)
        residentBytes += entry.payload.estimatedByteSize
        enforceLimits()

        if dirtyCount >= batchPolicy.itemThreshold || dirtyBytes >= batchPolicy.byteThreshold {
            Task { await flush() }
        } else {
            scheduleFlush()
        }
        return true
    }

    func summaries(limit: Int) -> [ClipboardSummary] {
        removeExpiredRecords()
        return Array(records.prefix(limit).map(\.summary))
    }

    func payload(for id: String) async -> ClipboardPayload? {
        removeExpiredRecords()
        guard let index = records.firstIndex(where: { $0.summary.id == id }) else { return nil }
        if let payload = records[index].payload {
            return payload
        }

        let loadedPayload = await persistence.loadPayload(for: id)
        removeExpiredRecords()
        guard let currentIndex = records.firstIndex(where: { $0.summary.id == id }) else { return nil }
        if let payload = records[currentIndex].payload {
            return payload
        }
        guard let payload = loadedPayload else { return nil }
        records[currentIndex].payload = payload
        residentBytes += payload.estimatedByteSize
        enforceMemoryLimit()
        return payload
    }

    func updateLimits(_ newLimits: ClipboardLimits) {
        limits = newLimits
        enforceLimits()
        if !pendingDeletionIDs.isEmpty {
            scheduleFlush()
        }
    }

    func clear() async {
        cancelScheduledFlushes()
        records.removeAll(keepingCapacity: false)
        knownHashes.removeAll(keepingCapacity: false)
        pendingDeletionIDs.removeAll(keepingCapacity: false)
        residentBytes = 0
        try? await persistence.clear()
    }

    func flush() async {
        idleFlushTask?.cancel()
        idleFlushTask = nil
        hardFlushTask?.cancel()
        hardFlushTask = nil

        let dirtyEntries = records.compactMap { record -> ClipboardEntry? in
            guard record.isDirty, let payload = record.payload else { return nil }
            return ClipboardEntry(summary: record.summary, payload: payload)
        }
        let deletionIDs = pendingDeletionIDs
        guard !dirtyEntries.isEmpty || !deletionIDs.isEmpty else { return }

        do {
            try await persistence.persist(entries: dirtyEntries, deleting: deletionIDs, limits: limits)
            let persistedIDs = Set(dirtyEntries.map(\.summary.id))
            for index in records.indices where persistedIDs.contains(records[index].summary.id) {
                records[index].isDirty = false
                records[index].isPersisted = true
            }
            pendingDeletionIDs.subtract(deletionIDs)
        } catch {
            scheduleFlush()
        }
    }

    func runMaintenance() async {
        enforceLimits()
        await flush()
        try? await persistence.runMaintenance(limits: limits)
    }

    func handleMemoryPressure(critical: Bool) async {
        if !critical {
            await flush()
        }
        let fraction = critical ? 0.25 : 0.75
        evictResidentPayloads(to: Int(Double(limits.maxMemoryBytes) * fraction))
    }

    func shutdown() async {
        cancelScheduledFlushes()
        await flush()
    }

    func statistics() -> ClipboardHistoryStatistics {
        ClipboardHistoryStatistics(
            itemCount: records.count,
            dirtyCount: dirtyCount,
            residentBytes: residentBytes
        )
    }

    private var dirtyCount: Int {
        records.lazy.filter(\.isDirty).count
    }

    private var dirtyBytes: Int {
        records.lazy.filter(\.isDirty).compactMap(\.payload).reduce(0) { $0 + $1.estimatedByteSize }
    }

    private func enforceLimits() {
        removeExpiredRecords()
        while !records.isEmpty, records.count > limits.maxCount {
            removeRecord(at: records.count - 1)
        }
        var historyBytes = records.reduce(0) { $0 + $1.summary.byteSize }
        while historyBytes > limits.maxDiskBytes, let oldest = records.last {
            historyBytes -= oldest.summary.byteSize
            removeRecord(at: records.count - 1)
        }
        enforceMemoryLimit()
    }

    private func removeExpiredRecords() {
        let cutoff = now().addingTimeInterval(-limits.maxAge)
        let deletionCount = pendingDeletionIDs.count
        for index in records.indices.reversed() where records[index].summary.createdAt < cutoff {
            removeRecord(at: index)
        }
        if pendingDeletionIDs.count > deletionCount {
            scheduleFlush()
        }
    }

    private func enforceMemoryLimit() {
        evictResidentPayloads(to: limits.maxMemoryBytes)
    }

    private func evictResidentPayloads(to targetBytes: Int) {
        var index = records.count - 1
        while residentBytes > targetBytes, index >= 0, !records.isEmpty {
            guard let payload = records[index].payload else {
                index -= 1
                continue
            }

            residentBytes -= payload.estimatedByteSize
            if records[index].isPersisted {
                records[index].payload = nil
                index -= 1
            } else {
                removeRecord(at: index, subtractPayload: false)
                index = min(index - 1, records.count - 1)
            }
        }
    }

    private func removeRecord(at index: Int, subtractPayload: Bool = true) {
        let record = records.remove(at: index)
        if subtractPayload, let payload = record.payload {
            residentBytes -= payload.estimatedByteSize
        }
        if record.isPersisted {
            pendingDeletionIDs.insert(record.summary.id)
        }
        knownHashes.remove(record.summary.contentHash)
    }

    private func scheduleFlush() {
        guard dirtyCount > 0 || !pendingDeletionIDs.isEmpty else { return }

        idleFlushTask?.cancel()
        let idleNanoseconds = UInt64(batchPolicy.idleDelay * 1_000_000_000)
        idleFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: idleNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }

        guard hardFlushTask == nil else { return }
        let hardNanoseconds = UInt64(batchPolicy.hardDelay * 1_000_000_000)
        hardFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: hardNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func cancelScheduledFlushes() {
        idleFlushTask?.cancel()
        idleFlushTask = nil
        hardFlushTask?.cancel()
        hardFlushTask = nil
    }
}
