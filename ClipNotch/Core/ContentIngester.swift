import AppKit
import UniformTypeIdentifiers

struct PasteboardSnapshot: Sendable {
    let types: [String]
    let plainText: String?
    let rtfData: Data?
    let htmlData: Data?
    let imageData: Data?
    let fileURLs: [URL]
    let sourceBundleID: String?
    let appName: String?

    @MainActor
    static func capture() -> PasteboardSnapshot {
        let pb = NSPasteboard.general
        let types = pb.types?.map(\.rawValue) ?? []

        let plainText = pb.string(forType: .string)
        let rtfData = pb.data(forType: .rtf)
        let htmlData = pb.data(forType: .html)

        var imageData: Data? = nil
        if let tiffData = pb.data(forType: .tiff) {
            imageData = tiffData
        } else if let pngData = pb.data(forType: .png) {
            imageData = pngData
        }

        let fileURLs: [URL]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] {
            fileURLs = urls
        } else {
            fileURLs = []
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        let sourceBundleID = frontApp?.bundleIdentifier
        let appName = frontApp?.localizedName

        return PasteboardSnapshot(
            types: types,
            plainText: plainText,
            rtfData: rtfData,
            htmlData: htmlData,
            imageData: imageData,
            fileURLs: fileURLs,
            sourceBundleID: sourceBundleID,
            appName: appName
        )
    }
}

final class ContentIngester: Sendable {
    let database: DatabaseActor
    let fileStore: FileStore
    let cleanupManager: CleanupManager

    init(database: DatabaseActor, fileStore: FileStore, cleanupManager: CleanupManager) {
        self.database = database
        self.fileStore = fileStore
        self.cleanupManager = cleanupManager
    }

    func ingest(snapshot: PasteboardSnapshot) async {
        let itemID = UUID().uuidString

        let primaryType: String
        var plainTextPreview: String? = nil
        var fullTextPath: String? = nil
        var imagePath: String? = nil
        var thumbnailPath: String? = nil
        var rtfPath: String? = nil
        var htmlPath: String? = nil
        var byteSize = 0
        var contentHash: String
        var displayTitle: String? = nil
        var fileRefs: [FileReference] = []

        if !snapshot.fileURLs.isEmpty {
            primaryType = UTType.fileURL.identifier

            let names = snapshot.fileURLs.map { $0.lastPathComponent }
            displayTitle = names.count == 1 ? names[0] : "\(names.count) items"
            plainTextPreview = names.joined(separator: ", ")

            let pathsString = snapshot.fileURLs.map(\.path).sorted().joined(separator: "\n")
            contentHash = fileStore.canonicalTextHash(pathsString)

            for (index, url) in snapshot.fileURLs.enumerated() {
                let ref = FileReference(
                    id: UUID().uuidString,
                    itemID: itemID,
                    bookmarkPath: nil,
                    originalPath: url.path,
                    displayName: url.lastPathComponent,
                    typeIdentifier: UTType(filenameExtension: url.pathExtension)?.identifier,
                    iconCachePath: nil,
                    sortOrder: index
                )
                fileRefs.append(ref)
            }

            byteSize = pathsString.utf8.count

        } else if let imgData = snapshot.imageData {
            guard imgData.count <= 50 * 1024 * 1024 else { return }

            primaryType = UTType.image.identifier
            contentHash = fileStore.canonicalHash(for: imgData)

            if let image = NSImage(data: imgData) {
                let hasAlpha = imgData.count > 0 && snapshot.types.contains(NSPasteboard.PasteboardType.png.rawValue)
                if let paths = fileStore.saveImage(image, id: itemID, hasAlpha: hasAlpha) {
                    imagePath = paths.imagePath
                    thumbnailPath = paths.thumbnailPath
                    byteSize = imgData.count
                }
            }
            displayTitle = "Image"
            plainTextPreview = "Image"

        } else if let rtfData = snapshot.rtfData {
            primaryType = UTType.rtf.identifier
            contentHash = fileStore.canonicalHash(for: rtfData)

            if let path = fileStore.saveData(rtfData, id: itemID, ext: "rtf") {
                rtfPath = path
                byteSize += rtfData.count
            }

            if let text = snapshot.plainText {
                let preview = String(text.prefix(200))
                plainTextPreview = preview
                if text.count > 200 {
                    fullTextPath = fileStore.saveText(text, id: itemID)
                    byteSize += text.utf8.count
                }
            }

            if let htmlData = snapshot.htmlData {
                htmlPath = fileStore.saveData(htmlData, id: itemID, ext: "html")
                byteSize += htmlData.count
            }

        } else if let htmlData = snapshot.htmlData {
            primaryType = UTType.html.identifier
            contentHash = fileStore.canonicalHash(for: htmlData)

            htmlPath = fileStore.saveData(htmlData, id: itemID, ext: "html")
            byteSize += htmlData.count

            if let text = snapshot.plainText {
                let preview = String(text.prefix(200))
                plainTextPreview = preview
                if text.count > 200 {
                    fullTextPath = fileStore.saveText(text, id: itemID)
                    byteSize += text.utf8.count
                }
            }

        } else if let text = snapshot.plainText {
            primaryType = UTType.utf8PlainText.identifier
            contentHash = fileStore.canonicalTextHash(text)

            let preview = String(text.prefix(200))
            plainTextPreview = preview

            if text.count > 200 {
                fullTextPath = fileStore.saveText(text, id: itemID)
            }
            byteSize = text.utf8.count

        } else {
            return
        }

        if await database.existsWithHash(contentHash) {
            let writtenPaths = [fullTextPath, imagePath, thumbnailPath, rtfPath, htmlPath].compactMap { $0 }
            fileStore.deleteFiles(writtenPaths)
            return
        }

        let item = ClipboardItem(
            id: itemID,
            createdAt: Date(),
            primaryType: primaryType,
            sourceBundleID: snapshot.sourceBundleID,
            appName: snapshot.appName,
            displayTitle: displayTitle,
            plainTextPreview: plainTextPreview,
            fullTextPath: fullTextPath,
            imagePath: imagePath,
            thumbnailPath: thumbnailPath,
            rtfPath: rtfPath,
            htmlPath: htmlPath,
            byteSize: byteSize,
            contentHash: contentHash,
            isFavorite: false,
            lastAccessedAt: nil
        )

        do {
            try await database.insert(item)
            if !fileRefs.isEmpty {
                try await database.insertFileReferences(fileRefs)
            }
        } catch {
            let writtenPaths = [fullTextPath, imagePath, thumbnailPath, rtfPath, htmlPath].compactMap { $0 }
            fileStore.deleteFiles(writtenPaths)
        }
    }
}
