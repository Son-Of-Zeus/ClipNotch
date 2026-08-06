import Foundation

enum ClipboardContentKind: String, Sendable {
    case text
    case richText
    case image
    case files

    var badge: String {
        switch self {
        case .text: "Text"
        case .richText: "Rich"
        case .image: "Image"
        case .files: "File"
        }
    }

    var iconName: String {
        switch self {
        case .text: "doc.text"
        case .richText: "doc.richtext"
        case .image: "photo"
        case .files: "folder"
        }
    }
}

struct ClipboardSummary: Identifiable, Equatable, Sendable {
    let id: String
    let createdAt: Date
    let kind: ClipboardContentKind
    let sourceBundleID: String?
    let appName: String?
    let displayTitle: String?
    let preview: String
    let byteSize: Int
    let contentHash: String

    var relativeTimestamp: String {
        let interval = Date().timeIntervalSince(createdAt)
        switch interval {
        case ..<60: return "now"
        case ..<3600: return "\(Int(interval / 60))m ago"
        case ..<86400: return "\(Int(interval / 3600))h ago"
        default: return "\(Int(interval / 86400))d ago"
        }
    }
}

enum ClipboardPayload: Equatable, Sendable {
    case text(String)
    case richText(plainText: String, rtf: Data?, html: Data?)
    case image(data: Data, pasteboardType: String)
    case files([FileReference])

    var estimatedByteSize: Int {
        switch self {
        case .text(let text):
            Self.textByteSize(text)
        case .richText(let text, let rtf, let html):
            Self.textByteSize(text) + (rtf?.count ?? 0) + (html?.count ?? 0)
        case .image(let data, _):
            data.count
        case .files(let references):
            references.reduce(0) { $0 + $1.estimatedByteSize }
        }
    }

    static func textByteSize(_ text: String) -> Int {
        max(text.utf8.count, text.utf16.count * 2)
    }
}

struct ClipboardEntry: Equatable, Sendable {
    let summary: ClipboardSummary
    let payload: ClipboardPayload
}

struct ClipboardLimits: Equatable, Sendable {
    static let defaultMemoryBytes = 128 * 1024 * 1024

    var maxAge: TimeInterval
    var maxCount: Int
    var maxMemoryBytes: Int
    var maxDiskBytes: Int
}
