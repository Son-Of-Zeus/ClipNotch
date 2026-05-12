import Foundation

struct FileReference: Identifiable, Equatable {
    let id: String
    let itemID: String
    let bookmarkPath: String?
    let originalPath: String
    let displayName: String
    let typeIdentifier: String?
    let iconCachePath: String?
    let sortOrder: Int
}
