import Foundation

final class CleanupManager: Sendable {
    let database: DatabaseActor
    let fileStore: FileStore

    init(database: DatabaseActor, fileStore: FileStore) {
        self.database = database
        self.fileStore = fileStore
    }

    func runCleanup(
        maxAge: TimeInterval = 24 * 3600,
        maxCount: Int = 500,
        maxDiskBytes: Int = 500 * 1024 * 1024
    ) async {
        // Time-based cleanup
        let cutoffDate = Date().addingTimeInterval(-maxAge)
        if let paths = try? await database.deleteItems(olderThan: cutoffDate) {
            fileStore.deleteFiles(paths)
        }

        // Count-based cleanup
        if let paths = try? await database.deleteExcessItems(keepCount: maxCount) {
            fileStore.deleteFiles(paths)
        }

        // Disk-based cleanup (iterative)
        var usage = await database.totalDiskUsage()
        while usage > maxDiskBytes {
            let currentCount = await database.itemCount()
            let targetCount = max(1, currentCount - 10)
            if let paths = try? await database.deleteExcessItems(keepCount: targetCount) {
                fileStore.deleteFiles(paths)
            }
            let newUsage = await database.totalDiskUsage()
            if newUsage >= usage { break }
            usage = newUsage
        }
    }

    func runOrphanSweep() async {
        let knownIDs = await database.allItemIDs()
        fileStore.orphanSweep(knownIDs: knownIDs)
    }
}
