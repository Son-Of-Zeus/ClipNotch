import Foundation
import SQLCipher

protocol ClipboardPersisting: Actor {
    func loadSummaries(limit: Int, cutoff: Date) throws -> [ClipboardSummary]
    func loadPayload(for id: String) async throws -> ClipboardPayload?
    func persist(entries: [ClipboardEntry], deleting ids: Set<String>, limits: ClipboardLimits) throws
    func clear() throws
    func runMaintenance(limits: ClipboardLimits) throws
}

actor ClipboardPersistence: ClipboardPersisting {
    private let db: OpaquePointer
    private let payloadDirectory: URL
    private let encryption: StorageEncryption

    init(directory: URL, encryption: StorageEncryption) throws {
        let payloadDirectory = directory.appendingPathComponent("payloads", isDirectory: true)

        try StorageEncryption.createDirectory(payloadDirectory)

        let databaseURL = directory.appendingPathComponent("clipboard.sqlite")
        var pointer: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &pointer) == SQLITE_OK, let pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw PersistenceError.cannotOpen
        }

        do {
            let key = encryption.key(for: .database)
            let result = key.withUnsafeBytes { bytes in
                sqlite3_key(pointer, bytes.baseAddress, Int32(bytes.count))
            }
            guard result == SQLITE_OK else { throw PersistenceError.cannotOpen }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(pointer, "PRAGMA cipher_version", -1, &statement, nil) == SQLITE_OK else {
                throw PersistenceError.encryptionUnavailable
            }
            let hasCipher = sqlite3_step(statement) == SQLITE_ROW && Self.text(statement, 0)?.isEmpty == false
            sqlite3_finalize(statement)
            guard hasCipher else { throw PersistenceError.encryptionUnavailable }
            _ = try Self.scalarInt(pointer, sql: "SELECT COUNT(*) FROM sqlite_master")
            try Self.configure(pointer)
            try Self.createTables(pointer)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
        } catch {
            sqlite3_close(pointer)
            throw error
        }

        db = pointer
        self.payloadDirectory = payloadDirectory
        self.encryption = encryption
    }

    deinit {
        sqlite3_close(db)
    }

    func loadSummaries(limit: Int, cutoff: Date) throws -> [ClipboardSummary] {
        let sql = """
        SELECT id, created_at, kind, source_bundle_id, app_name, display_title,
               preview, byte_size, content_hash
        FROM clipboard_entries
        WHERE created_at >= ?
        ORDER BY created_at DESC LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PersistenceError.statementFailed("load summaries")
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var summaries: [ClipboardSummary] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let id = Self.text(statement, 0),
                  let kindValue = Self.text(statement, 2),
                  let kind = ClipboardContentKind(rawValue: kindValue),
                  let hash = Self.text(statement, 8) else { throw PersistenceError.invalidData }
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
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw PersistenceError.statementFailed("load summaries") }
        return summaries
    }

    func loadPayload(for id: String) throws -> ClipboardPayload? {
        let sql = """
        SELECT kind, text_payload, rtf_payload, html_payload, image_hash, image_type
        FROM clipboard_entries WHERE id = ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PersistenceError.statementFailed("load payload")
        }
        defer { sqlite3_finalize(statement) }
        Self.bind(id, to: statement, at: 1)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw PersistenceError.statementFailed("load payload") }
        guard let kindValue = Self.text(statement, 0),
              let kind = ClipboardContentKind(rawValue: kindValue) else { throw PersistenceError.invalidData }

        switch kind {
        case .text:
            guard let data = Self.data(statement, 1),
                  let text = String(data: data, encoding: .utf8) else { throw PersistenceError.invalidData }
            return .text(text)
        case .richText:
            guard let textData = Self.data(statement, 1),
                  let text = String(data: textData, encoding: .utf8) else { throw PersistenceError.invalidData }
            return .richText(
                plainText: text,
                rtf: Self.data(statement, 2),
                html: Self.data(statement, 3)
            )
        case .image:
            guard let hash = Self.text(statement, 4),
                  let type = Self.text(statement, 5) else { throw PersistenceError.invalidData }
            let url = imageURL(hash: hash, pasteboardType: type)
            let data = try encryption.read(from: url, purpose: .images, context: url.lastPathComponent)
            return .image(data: data, pasteboardType: type)
        case .files:
            return .files(try loadFileReferences(for: id))
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

        let countBefore = try rowCount()
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

        if try !ids.isEmpty || rowCount() < countBefore + entries.count {
            try removeOrphanImages()
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
        try removeOrphanImages()
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
        try removeOrphanImages()
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

    private func loadFileReferences(for itemID: String) throws -> [FileReference] {
        let sql = """
        SELECT id, original_path, display_name, type_identifier, sort_order
        FROM clipboard_file_references WHERE item_id = ? ORDER BY sort_order
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PersistenceError.statementFailed("load file references")
        }
        defer { sqlite3_finalize(statement) }
        Self.bind(itemID, to: statement, at: 1)

        var references: [FileReference] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let id = Self.text(statement, 0),
                  let path = Self.text(statement, 1),
                  let name = Self.text(statement, 2) else { throw PersistenceError.invalidData }
            references.append(FileReference(
                id: id,
                itemID: itemID,
                originalPath: path,
                displayName: name,
                typeIdentifier: Self.text(statement, 3),
                sortOrder: Int(sqlite3_column_int(statement, 4))
            ))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw PersistenceError.statementFailed("load file references") }
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

        while try totalPayloadBytes() > limits.maxDiskBytes {
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

    private func totalPayloadBytes() throws -> Int {
        try Self.scalarInt(db, sql: "SELECT COALESCE(SUM(byte_size), 0) FROM clipboard_entries")
    }

    private func rowCount() throws -> Int {
        try Self.scalarInt(db, sql: "SELECT COUNT(*) FROM clipboard_entries")
    }

    private func writeImage(_ data: Data, hash: String, pasteboardType: String) throws {
        let url = imageURL(hash: hash, pasteboardType: pasteboardType)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try encryption.read(from: url, purpose: .images, context: url.lastPathComponent)
            return
        }
        try encryption.write(data, to: url, purpose: .images, context: url.lastPathComponent)
    }

    private func imageURL(hash: String, pasteboardType: String) -> URL {
        payloadDirectory.appendingPathComponent(encryption.imageName(hash: hash, type: pasteboardType))
    }

    private func removeOrphanImages() throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT image_hash, image_type FROM clipboard_entries WHERE image_hash IS NOT NULL", -1, &statement, nil) == SQLITE_OK else {
            throw PersistenceError.statementFailed("load image references")
        }
        defer { sqlite3_finalize(statement) }

        var retained = Set<String>()
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            if let hash = Self.text(statement, 0), let type = Self.text(statement, 1) {
                retained.insert(imageURL(hash: hash, pasteboardType: type).lastPathComponent)
            }
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw PersistenceError.statementFailed("load image references") }

        let files = try FileManager.default.contentsOfDirectory(
            at: payloadDirectory,
            includingPropertiesForKeys: nil
        )
        for file in files where !retained.contains(file.lastPathComponent) {
            try FileManager.default.removeItem(at: file)
        }
    }

    private static func configure(_ db: OpaquePointer) throws {
        try execute(db, "PRAGMA temp_store=MEMORY")
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
            sqlite3_free(error)
            throw PersistenceError.statementFailed(String(cString: sqlite3_errstr(sqlite3_errcode(db))))
        }
    }

    private static func scalarInt(_ db: OpaquePointer, sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PersistenceError.statementFailed("prepare scalar query")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw PersistenceError.statementFailed("read scalar query") }
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
        if value.isEmpty {
            sqlite3_bind_zeroblob(statement, index, 0)
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
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        if sqlite3_column_bytes(statement, column) == 0 { return Data() }
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }

}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum PersistenceError: LocalizedError {
    case cannotOpen
    case statementFailed(String)
    case invalidData
    case encryptionUnavailable

    var errorDescription: String? {
        switch self {
        case .cannotOpen: "The encrypted clipboard database could not be opened."
        case .statementFailed(let operation): "Clipboard storage failed (\(operation))."
        case .invalidData: "The stored clipboard data is invalid."
        case .encryptionUnavailable: "Database encryption is unavailable."
        }
    }
}
