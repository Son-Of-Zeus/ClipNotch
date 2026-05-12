import Foundation
import AppKit
import CryptoKit

final class FileStore: Sendable {
    let itemsDirectory: URL

    init() throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("ClipNotch", isDirectory: true)
            .appendingPathComponent("items", isDirectory: true)

        try FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )
        self.itemsDirectory = appSupport
    }

    func saveText(_ text: String, id: String) -> String? {
        let path = itemsDirectory.appendingPathComponent("\(id).txt")
        do {
            try text.write(to: path, atomically: true, encoding: .utf8)
            return path.path
        } catch {
            return nil
        }
    }

    func saveImage(_ image: NSImage, id: String, hasAlpha: Bool) -> (imagePath: String, thumbnailPath: String)? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }

        let ext: String
        let imageData: Data?
        if hasAlpha {
            ext = "png"
            imageData = bitmap.representation(using: .png, properties: [:])
        } else {
            ext = "jpg"
            imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        }

        guard let data = imageData else { return nil }

        let imagePath = itemsDirectory.appendingPathComponent("\(id).\(ext)")
        let thumbPath = itemsDirectory.appendingPathComponent("\(id)_thumb.jpg")

        do {
            try data.write(to: imagePath, options: .atomic)
        } catch {
            return nil
        }

        let thumbSize = NSSize(width: 64, height: 64)
        let thumbImage = NSImage(size: thumbSize)
        thumbImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        thumbImage.unlockFocus()

        if let thumbTiff = thumbImage.tiffRepresentation,
           let thumbBitmap = NSBitmapImageRep(data: thumbTiff),
           let thumbData = thumbBitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
            try? thumbData.write(to: thumbPath, options: .atomic)
        }

        return (imagePath.path, thumbPath.path)
    }

    func saveData(_ data: Data, id: String, ext: String) -> String? {
        let path = itemsDirectory.appendingPathComponent("\(id).\(ext)")
        do {
            try data.write(to: path, options: .atomic)
            return path.path
        } catch {
            return nil
        }
    }

    func loadData(at path: String) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    func deleteFiles(_ paths: [String]) {
        let fm = FileManager.default
        for path in paths where !path.isEmpty {
            try? fm.removeItem(atPath: path)
        }
    }

    func orphanSweep(knownIDs: Set<String>) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: itemsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in contents {
            let name = url.deletingPathExtension().lastPathComponent
            let baseID = name.replacingOccurrences(of: "_thumb", with: "")
            if !knownIDs.contains(baseID) {
                try? fm.removeItem(at: url)
            }
        }
    }

    func canonicalHash(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func canonicalTextHash(_ text: String) -> String {
        let normalized = text.precomposedStringWithCanonicalMapping
        let data = Data(normalized.utf8)
        return canonicalHash(for: data)
    }
}
