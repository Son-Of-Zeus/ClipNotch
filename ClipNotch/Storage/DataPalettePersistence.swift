import Foundation

protocol DataPalettePersisting: Actor {
    func load() throws -> DataPaletteDocument
    func save(_ document: DataPaletteDocument) throws
}

actor DataPalettePersistence: DataPalettePersisting {
    private let fileURL: URL
    private let encryption: StorageEncryption

    init(directory: URL, encryption: StorageEncryption) {
        fileURL = directory.appendingPathComponent("data-palette.enc")
        self.encryption = encryption
    }

    func load() throws -> DataPaletteDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let document = DataPaletteDocument.initial
            try save(document)
            return document
        }
        return try JSONDecoder().decode(
            DataPaletteDocument.self, from: encryption.read(from: fileURL, purpose: .palette)
        )
    }

    func save(_ document: DataPaletteDocument) throws {
        let data = try JSONEncoder().encode(document)
        try encryption.write(data, to: fileURL, purpose: .palette)
    }
}
