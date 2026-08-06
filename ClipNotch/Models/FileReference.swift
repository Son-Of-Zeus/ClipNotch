import Foundation

struct FileReference: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let itemID: String
    let originalPath: String
    let displayName: String
    let typeIdentifier: String?
    let sortOrder: Int

    var estimatedByteSize: Int {
        originalPath.utf8.count
            + displayName.utf8.count
            + (typeIdentifier?.utf8.count ?? 0)
    }
}
