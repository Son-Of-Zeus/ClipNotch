import Foundation
import SQLite3

protocol ClipboardPersisting: Actor {
    func loadSummaries(limit: Int, cutoff: Date) -> [ClipboardSummary]
    func loadPayload(for id: String) -> ClipboardPayload?
    func persist(entries: [ClipboardEntry], deleting ids: Set<String>, limits: ClipboardLimits) throws
    func clear() throws
    func runMaintenance(limits: ClipboardLimits) throws
}

actor ClipboardPersistence: ClipboardPersisting {
    private let db: OpaquePointer
    private let payloadDirectory: URL

    init(baseDirectory: URL? = nil, removeLegacyData: Bool = true) throws {
        let appSupport = baseDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("ClipNotch", isDirectory: true)
        let payloadDirectory = appSupport.appendingPathComponent("payloads-v2", isDirectory: true)

        try FileManager.default.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)

        let databaseURL = appSupport.appendingPathComponent("clipnotch-v2.sqlite")
        var pointer: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &pointer) == SQLITE_OK, let pointer else {
            throw PersistenceError.cannotOpen
        }

        do {
            try Self.configure(pointer)
            try Self.createTables(pointer)
        } catch {
            sqlite3_close(pointer)
            throw error
        }

        db = pointer
        self.payloadDirectory = payloadDirectory
        if removeLegacyData {
            Self.removeLegacyStore(from: appSupport)
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func loadSummaries(limit: Int, cutoff: Date) -> [ClipboardSummary] {
        let sql = """
        SELECT id, created_at, kind, source_bundle_id, app_name, display_title,
               preview, byte_size, content_hash
        FROM clipboard_entries
        WHERE created_at >= ?
        ORDER BY created_at DESC LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var summaries: [ClipboardSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = Self.text(statement, 0),
                  let kindValue = Self.text(statement, 2),
                  let kind = ClipboardContentKind(rawValue: kindValue),
                  let hash = Self.text(statement, 8) else { continue }
            summaries.append(ClipboardSummary(
                id: id,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                kind: kind,
                sourceBundleID: Self.text(statement, 3),
                appName: Self.text(statement, 4),
                displayTitle: Self.text(statement, 5),
                preview: Self.text(statement, 6) ?? kind.badge,
                byteSize: Int(sqlite3_column_int64(statement, 7)),
                contentHash: hash
            ))
        }
        return summaries
    }

    func loadPayload(for id: String) -> ClipboardPayload? {
        let sql = """
        SELECT kind, text_payload, rtf_payload, html_payload, image_hash, image_type
        FROM clipboard_entries WHERE id = ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        Self.bind(id, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let kindValue = Self.text(statement, 0),
              let kind = ClipboardContentKind(rawValue: kindValue) else { return nil }

        switch kind {
        case .text:
            guard let data = Self.data(statement, 1),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return .text(text)
        case .richText:
            guard let textData = Self.data(statement, 1),
                  let text = String(data: textData, encoding: .utf8) else { return nil }
            return .richText(
                plainText: text,
                rtf: Self.data(statement, 2),
                html: Self.data(statement, 3)
            )
        case .image:
            guard let hash = Self.text(statement, 4),
                  let type = Self.text(statement, 5),
                  let data = try? Data(contentsOf: imageURL(hash: hash, pasteboardType: type)) else { return nil }
            return .image(data: data, pasteboardType: type)
        case .files:
            return .files(loadFileReferences(for: id))
        }
    }

    func persist(
        entries: [ClipboardEntry],
        deleting ids: Set<String>,
        limits: ClipboardLimits
    ) throws {
        for entry in entries {
            if case .image(let data, let type) = entry.payload {
                try writeImage(data, hash: entry.summary.contentHash, pasteboardType: type)
            }
        }

        let countBefore = rowCount()
        try Self.execute(db, "BEGIN IMMEDIATE")
        do {
            for id in ids {
                try delete(id: id)
            }
            for entry in entries {
                try insert(entry)
            }
            try prune(limits: limits)
            try Self.execute(db, "COMMIT")
        } catch {
            try? Self.execute(db, "ROLLBACK")
            throw error
        }

        if !ids.isEmpty || rowCount() < countBefore + entries.count {
            removeOrphanImages()
        }
    }

    func clear() throws {
        try Self.execute(db, "BEGIN IMMEDIATE")
        do {
            try Self.execute(db, "DELETE FROM clipboard_entries")
            try Self.execute(db, "COMMIT")
        } catch {
            try? Self.execute(db, "ROLLBACK")
            throw error
        }
        removeOrphanImages()
    }

    func runMaintenance(limits: ClipboardLimits) throws {
        try Self.execute(db, "BEGIN IMMEDIATE")
        do {
            try prune(limits: limits)
            try Self.execute(db, "COMMIT")
        } catch {
            try? Self.execute(db, "ROLLBACK")
            throw error
        }
        removeOrphanImages()
        try Self.execute(db, "PRAGMA incremental_vacuum(256)")
        try Self.execute(db, "PRAGMA wal_checkpoint(PASSIVE)")
    }

    private func insert(_ entry: ClipboardEntry) throws {
        let sql = """
        INSERT OR REPLACE INTO clipboard_entries (
            id, created_at, kind, source_bundle_id, app_name, display_title,
            preview, byte_size, content_hash, text_payload, rtf_payload,
            html_payload, image_hash, image_type
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PersistenceError.statementFailed("prepare entry insert")
        }
        defer { sqlite3_finalize(statement) }

        let summary = entry.summary
        Self.bind(summary.id, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, summary.createdAt.timeIntervalSince1970)
        Self.bind(summary.kind.rawValue, to: statement, at: 3)
        Self.bind(summary.sourceBundleID, to: statement, at: 4)
        Self.bind(summary.appName, to: statement, at: 5)
        Self.bind(summary.displayTitle, to: statement, at: 6)
        Self.bind(summary.preview, to: statement, at: 7)
        sqlite3_bind_int64(statement, 8, sqlite3_int64(summary.byteSize))
        Self.bind(summary.contentHash, to: statement, at: 9)

        switch entry.payload {
        case .text(let text):
            Self.bind(Data(text.utf8), to: statement, at: 10)
        case .richText(let text, let rtf, let html):
            Self.bind(Data(text.utf8), to: statement, at: 10)
            Self.bind(rtf, to: statement, at: 11)
            Self.bind(html, to: statement, at: 12)
        case .image(_, let type):
            Self.bind(summary.contentHash, to: statement, at: 13)
            Self.bind(type, to: statement, at: 14)
        case .files:
            break
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw PersistenceError.statementFailed("insert entry")
        }

        if case .files(let references) = entry.payload {
            try insertFileReferences(references, itemID: summary.id)
        }
    }

    private func insertFileReferences(_ references: [FileReference], itemID: String) throws {
        var statement: OpaquePointer?
        let sql = """
        INSERT INTO clipboard_file_references (
            id, item_id, original_path, display_name, type_identifier, sort_order
        ) VALUES (?,?,?,?,?,?)
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PersistenceError.statementFailed("prepare file references")
        }
        defer { sqlite3_finalize(statement) }

        for reference in references {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            Self.bind(reference.id, to: statement, at: 1)
            Self.bind(itemID, to: statement, at: 2)
            Self.bind(reference.originalPath, to: statement, at: 3)
            Self.bind(reference.displayName, to: statement, at: 4)
            Self.bind(reference.typeIdentifier, to: statement, at: 5)
            sqlite3_bind_int(statement, 6, Int32(reference.sortOrder))
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw PersistenceError.statementFailed("insert file reference")
            }
        }
    }

    private func loadFileReferences(for itemID: String) -> [FileReference] {
        let sql = """
        SELECT id, original_path, display_name, type_identifier, sort_order
        FROM clipboard_file_references WHERE item_id = ? ORDER BY sort_order
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        Self.bind(itemID, to: statement, at: 1)

        var references: [FileReference] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = Self.text(statement, 0),
                  let path = Self.text(statement, 1),
                  let name = Self.text(statement, 2) else { continue }
            references.append(FileReference(
                id: id,
                itemID: itemID,
                originalPath: path,
                displayName: name,
                typeIdentifier: Self.text(statement, 3),
                sortOrder: Int(sqlite3_column_int(statement, 4))
            ))
        }
        return references
    }

    private func delete(id: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM clipboard_entries WHERE id = ?", -1, &statement, nil) == SQLITE_OK else {
            throw PersistenceError.statementFailed("prepare entry delete")
        }
        defer { sqlite3_finalize(statement) }
        Self.bind(id, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw PersistenceError.statementFailed("delete entry")
        }
    }

    private func prune(limits: ClipboardLimits) throws {
        let cutoff = Date().addingTimeInterval(-limits.maxAge).timeIntervalSince1970
        try run("DELETE FROM clipboard_entries WHERE created_at < ?") { statement in
            sqlite3_bind_double(statement, 1, cutoff)
        }
        try run("""
        DELETE FROM clipboard_entries WHERE id NOT IN (
            SELECT id FROM clipboard_entries ORDER BY created_at DESC LIMIT ?
        )
        """) { statement in
            sqlite3_bind_int(statement, 1, Int32(limits.maxCount))
        }

        while totalPayloadBytes() > limits.maxDiskBytes {
            try Self.execute(db, """
            DELETE FROM clipboard_entries WHERE id = (
                SELECT id FROM clipboard_entries ORDER BY created_at ASC LIMIT 1
            )
            """)
        }
    }

    private func run(_ sql: String, bindings: (OpaquePointer?) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PersistenceError.statementFailed("prepare prune")
        }
        defer { sqlite3_finalize(statement) }
        bindings(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw PersistenceError.statementFailed("execute prune")
        }
    }

    private func totalPayloadBytes() -> Int {
        Self.scalarInt(db, sql: "SELECT COALESCE(SUM(byte_size), 0) FROM clipboard_entries")
    }

    private func rowCount() -> Int {
        Self.scalarInt(db, sql: "SELECT COUNT(*) FROM clipboard_entries")
    }

    private func writeImage(_ data: Data, hash: String, pasteboardType: String) throws {
        let url = imageURL(hash: hash, pasteboardType: pasteboardType)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try data.write(to: url, options: .atomic)
    }

    private func imageURL(hash: String, pasteboardType: String) -> URL {
        payloadDirectory.appendingPathComponent("\(hash).\(Self.imageExtension(for: pasteboardType))")
    }

    private func removeOrphanImages() {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT image_hash, image_type FROM clipboard_entries WHERE image_hash IS NOT NULL", -1, &statement, nil) == SQLITE_OK else {
            return
        }

        var retained = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let hash = Self.text(statement, 0), let type = Self.text(statement, 1) {
                retained.insert(imageURL(hash: hash, pasteboardType: type).lastPathComponent)
            }
        }
        sqlite3_finalize(statement)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: payloadDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where !retained.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func configure(_ db: OpaquePointer) throws {
        try execute(db, "PRAGMA auto_vacuum=INCREMENTAL")
        try execute(db, "PRAGMA journal_mode=WAL")
        try execute(db, "PRAGMA synchronous=NORMAL")
        try execute(db, "PRAGMA foreign_keys=ON")
        try execute(db, "PRAGMA cache_size=-256")
        try execute(db, "PRAGMA mmap_size=0")
        try execute(db, "PRAGMA wal_autocheckpoint=4096")
        try execute(db, "PRAGMA journal_size_limit=16777216")
    }

    private static func createTables(_ db: OpaquePointer) throws {
        try execute(db, """
        CREATE TABLE IF NOT EXISTS clipboard_entries (
            id TEXT PRIMARY KEY,
            created_at REAL NOT NULL,
            kind TEXT NOT NULL,
            source_bundle_id TEXT,
            app_name TEXT,
            display_title TEXT,
            preview TEXT NOT NULL,
            byte_size INTEGER NOT NULL,
            content_hash TEXT NOT NULL UNIQUE,
            text_payload BLOB,
            rtf_payload BLOB,
            html_payload BLOB,
            image_hash TEXT,
            image_type TEXT
        )
        """)
        try execute(db, "CREATE INDEX IF NOT EXISTS idx_entries_created_at ON clipboard_entries(created_at DESC)")
        try execute(db, """
        CREATE TABLE IF NOT EXISTS clipboard_file_references (
            id TEXT PRIMARY KEY,
            item_id TEXT NOT NULL REFERENCES clipboard_entries(id) ON DELETE CASCADE,
            original_path TEXT NOT NULL,
            display_name TEXT NOT NULL,
            type_identifier TEXT,
            sort_order INTEGER NOT NULL
        )
        """)
        try execute(db, "CREATE INDEX IF NOT EXISTS idx_file_item ON clipboard_file_references(item_id)")
    }

    private static func execute(_ db: OpaquePointer, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw PersistenceError.statementFailed(message)
        }
    }

    private static func scalarInt(_ db: OpaquePointer, sql: String) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func bind(_ value: String?, to statement: OpaquePointer?, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, sqliteTransient)
    }

    private static func bind(_ value: Data?, to statement: OpaquePointer?, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
        }
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    private static func data(_ statement: OpaquePointer?, _ column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }

    private static func imageExtension(for type: String) -> String {
        switch type {
        case "public.png": "png"
        case "public.jpeg": "jpg"
        case "public.heic": "heic"
        default: "tiff"
        }
    }

    private static func removeLegacyStore(from appSupport: URL) {
        let manager = FileManager.default
        let legacyPaths = [
            appSupport.appendingPathComponent("clipnotch.db"),
            appSupport.appendingPathComponent("clipnotch.db-wal"),
            appSupport.appendingPathComponent("clipnotch.db-shm"),
            appSupport.appendingPathComponent("items", isDirectory: true)
        ]
        for path in legacyPaths {
            try? manager.removeItem(at: path)
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum PersistenceError: Error {
    case cannotOpen
    case statementFailed(String)
}
