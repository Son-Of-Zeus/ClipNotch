import Foundation

protocol DataPalettePersisting: Actor {
    func load() throws -> DataPaletteDocument
    func save(_ document: DataPaletteDocument) throws
}

actor DataPalettePersistence: DataPalettePersisting {
    private let fileURL: URL

    init(directory: URL = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first!.appendingPathComponent("ClipNotch", isDirectory: true)) {
        fileURL = directory.appendingPathComponent("data-palette.json")
    }

    func load() throws -> DataPaletteDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let document = DataPaletteDocument.initial
            try save(document)
            return document
        }
        return try JSONDecoder().decode(DataPaletteDocument.self, from: Data(contentsOf: fileURL))
    }

    func save(_ document: DataPaletteDocument) throws {
        let data = try JSONEncoder().encode(document)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
