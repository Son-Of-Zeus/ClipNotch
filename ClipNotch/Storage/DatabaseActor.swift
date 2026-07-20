import Foundation
import SQLite3

actor DatabaseActor {
    private let db: OpaquePointer

    init() throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("ClipNotch", isDirectory: true)

        try FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )

        let dbPath = appSupport.appendingPathComponent("clipnotch.db").path
        var dbPointer: OpaquePointer?
        guard sqlite3_open(dbPath, &dbPointer) == SQLITE_OK, let dbPointer else {
            throw DatabaseError.cannotOpen
        }
        self.db = dbPointer

        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA foreign_keys=ON")
        // The clipboard history is deliberately small; retain only a tiny SQLite page cache while idle.
        try execute("PRAGMA cache_size=-128")
        try execute("PRAGMA mmap_size=0")
        try createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let msg = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw DatabaseError.statementFailed(msg)
        }
    }

    private func createTables() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            created_at REAL NOT NULL,
            primary_type TEXT NOT NULL,
            source_bundle_id TEXT,
            app_name TEXT,
            display_title TEXT,
            plain_text_preview TEXT,
            full_text_path TEXT,
            image_path TEXT,
            thumbnail_path TEXT,
            rtf_path TEXT,
            html_path TEXT,
            byte_size INTEGER NOT NULL DEFAULT 0,
            content_hash TEXT NOT NULL,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            last_accessed_at REAL
        )
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_items_created_at ON clipboard_items(created_at DESC)")
        try execute("CREATE INDEX IF NOT EXISTS idx_items_content_hash ON clipboard_items(content_hash)")

        try execute("""
        CREATE TABLE IF NOT EXISTS clipboard_file_references (
            id TEXT PRIMARY KEY,
            item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
            bookmark_path TEXT,
            original_path TEXT NOT NULL,
            display_name TEXT NOT NULL,
            type_identifier TEXT,
            icon_cache_path TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0
        )
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_file_refs_item_id ON clipboard_file_references(item_id)")
    }

    // MARK: - CRUD Methods

    func insert(_ item: ClipboardItem) throws {
        let sql = """
        INSERT OR REPLACE INTO clipboard_items (
            id, created_at, primary_type, source_bundle_id, app_name,
            display_title, plain_text_preview, full_text_path, image_path,
            thumbnail_path, rtf_path, html_path,
            byte_size, content_hash, is_favorite, last_accessed_at
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.statementFailed("prepare insert")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (item.id as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 2, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, (item.primaryType as NSString).utf8String, -1, nil)
        bindOptionalText(stmt, 4, item.sourceBundleID)
        bindOptionalText(stmt, 5, item.appName)
        bindOptionalText(stmt, 6, item.displayTitle)
        bindOptionalText(stmt, 7, item.plainTextPreview)
        bindOptionalText(stmt, 8, item.fullTextPath)
        bindOptionalText(stmt, 9, item.imagePath)
        bindOptionalText(stmt, 10, item.thumbnailPath)
        bindOptionalText(stmt, 11, item.rtfPath)
        bindOptionalText(stmt, 12, item.htmlPath)
        sqlite3_bind_int(stmt, 13, Int32(item.byteSize))
        sqlite3_bind_text(stmt, 14, (item.contentHash as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 15, item.isFavorite ? 1 : 0)
        if let accessed = item.lastAccessedAt {
            sqlite3_bind_double(stmt, 16, accessed.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 16)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.statementFailed("execute insert")
        }
    }

    func insertFileReferences(_ refs: [FileReference]) throws {
        let sql = """
        INSERT OR REPLACE INTO clipboard_file_references (
            id, item_id, bookmark_path, original_path, display_name, type_identifier, icon_cache_path, sort_order
        ) VALUES (?,?,?,?,?,?,?,?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.statementFailed("prepare insert file ref")
        }
        defer { sqlite3_finalize(stmt) }

        for ref in refs {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)

            sqlite3_bind_text(stmt, 1, (ref.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (ref.itemID as NSString).utf8String, -1, nil)
            bindOptionalText(stmt, 3, ref.bookmarkPath)
            sqlite3_bind_text(stmt, 4, (ref.originalPath as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (ref.displayName as NSString).utf8String, -1, nil)
            bindOptionalText(stmt, 6, ref.typeIdentifier)
            bindOptionalText(stmt, 7, ref.iconCachePath)
            sqlite3_bind_int(stmt, 8, Int32(ref.sortOrder))

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.statementFailed("execute insert file ref")
            }
        }
    }

    func fetchRecent(limit: Int = 20) -> [ClipboardItem] {
        let sql = """
        SELECT id, created_at, primary_type, source_bundle_id, app_name,
               display_title, plain_text_preview, full_text_path, image_path,
               thumbnail_path, rtf_path, html_path,
               byte_size, content_hash, is_favorite, last_accessed_at
        FROM clipboard_items ORDER BY created_at DESC LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var items: [ClipboardItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            items.append(itemFromRow(stmt))
        }
        return items
    }

    func fetchFileReferences(for itemID: String) -> [FileReference] {
        let sql = """
        SELECT id, item_id, bookmark_path, original_path, display_name, type_identifier, icon_cache_path, sort_order
        FROM clipboard_file_references WHERE item_id = ? ORDER BY sort_order ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (itemID as NSString).utf8String, -1, nil)

        var refs: [FileReference] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            refs.append(fileReferenceFromRow(stmt))
        }
        return refs
    }

    func mostRecentHash() -> String? {
        let sql = "SELECT content_hash FROM clipboard_items ORDER BY created_at DESC LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return columnText(stmt, 0)
    }

    func existsWithHash(_ hash: String) -> Bool {
        let sql = "SELECT 1 FROM clipboard_items WHERE content_hash = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (hash as NSString).utf8String, -1, nil)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    func deleteItems(olderThan date: Date) throws -> [String] {
        var paths: [String] = []
        let cutoff = date.timeIntervalSince1970
        let collectSQL = """
        SELECT T1.full_text_path, T1.image_path, T1.thumbnail_path, T1.rtf_path, T1.html_path,
               T2.bookmark_path, T2.icon_cache_path
        FROM clipboard_items AS T1 LEFT JOIN clipboard_file_references AS T2 ON T1.id = T2.item_id
        WHERE T1.created_at < ?
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, collectSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, cutoff)
            while sqlite3_step(stmt) == SQLITE_ROW {
                for col in 0..<7 {
                    if let path = columnText(stmt, Int32(col)) {
                        paths.append(path)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        let deleteSQL = "DELETE FROM clipboard_items WHERE created_at < ?"
        var deleteStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK else {
            throw DatabaseError.statementFailed("prepare delete old")
        }
        defer { sqlite3_finalize(deleteStmt) }
        sqlite3_bind_double(deleteStmt, 1, cutoff)
        guard sqlite3_step(deleteStmt) == SQLITE_DONE else {
            throw DatabaseError.statementFailed("execute delete old")
        }

        return paths
    }

    func deleteExcessItems(keepCount: Int) throws -> [String] {
        var paths: [String] = []
        let collectSQL = """
        SELECT T1.full_text_path, T1.image_path, T1.thumbnail_path, T1.rtf_path, T1.html_path,
               T2.bookmark_path, T2.icon_cache_path
        FROM clipboard_items AS T1 LEFT JOIN clipboard_file_references AS T2 ON T1.id = T2.item_id
        ORDER BY T1.created_at DESC LIMIT -1 OFFSET ?
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, collectSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(keepCount))
            while sqlite3_step(stmt) == SQLITE_ROW {
                for col in 0..<7 {
                    if let path = columnText(stmt, Int32(col)) {
                        paths.append(path)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        let deleteSQL = """
        DELETE FROM clipboard_items WHERE id NOT IN (
            SELECT id FROM clipboard_items ORDER BY created_at DESC LIMIT ?
        )
        """
        var deleteStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK else {
            throw DatabaseError.statementFailed("prepare delete excess")
        }
        defer { sqlite3_finalize(deleteStmt) }
        sqlite3_bind_int(deleteStmt, 1, Int32(keepCount))
        guard sqlite3_step(deleteStmt) == SQLITE_DONE else {
            throw DatabaseError.statementFailed("execute delete excess")
        }

        return paths
    }

    func totalDiskUsage() -> Int {
        let sql = "SELECT COALESCE(SUM(byte_size), 0) FROM clipboard_items"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func itemCount() -> Int {
        let sql = "SELECT COUNT(*) FROM clipboard_items"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    func releaseCachedMemory() {
        sqlite3_db_release_memory(db)
    }

    func allItemIDs() -> Set<String> {
        let sql = "SELECT id FROM clipboard_items"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var ids = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let id = columnText(stmt, 0) {
                ids.insert(id)
            }
        }
        return ids
    }

    // MARK: - Helpers

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: ptr)
    }

    private func itemFromRow(_ stmt: OpaquePointer?) -> ClipboardItem {
        ClipboardItem(
            id: columnText(stmt, 0) ?? UUID().uuidString,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
            primaryType: columnText(stmt, 2) ?? "unknown",
            sourceBundleID: columnText(stmt, 3),
            appName: columnText(stmt, 4),
            displayTitle: columnText(stmt, 5),
            plainTextPreview: columnText(stmt, 6),
            fullTextPath: columnText(stmt, 7),
            imagePath: columnText(stmt, 8),
            thumbnailPath: columnText(stmt, 9),
            rtfPath: columnText(stmt, 10),
            htmlPath: columnText(stmt, 11),
            byteSize: Int(sqlite3_column_int(stmt, 12)),
            contentHash: columnText(stmt, 13) ?? "",
            isFavorite: sqlite3_column_int(stmt, 14) != 0,
            lastAccessedAt: sqlite3_column_type(stmt, 15) != SQLITE_NULL
                ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 15))
                : nil
        )
    }

    private func fileReferenceFromRow(_ stmt: OpaquePointer?) -> FileReference {
        FileReference(
            id: columnText(stmt, 0) ?? UUID().uuidString,
            itemID: columnText(stmt, 1) ?? "",
            bookmarkPath: columnText(stmt, 2),
            originalPath: columnText(stmt, 3) ?? "",
            displayName: columnText(stmt, 4) ?? "",
            typeIdentifier: columnText(stmt, 5),
            iconCachePath: columnText(stmt, 6),
            sortOrder: Int(sqlite3_column_int(stmt, 7))
        )
    }
}

enum DatabaseError: Error {
    case cannotOpen
    case statementFailed(String)
}
