import Foundation

struct ClipboardItem: Identifiable, Equatable {
    let id: String
    let createdAt: Date
    let primaryType: String
    let sourceBundleID: String?
    let appName: String?
    let displayTitle: String?
    let plainTextPreview: String?
    let fullTextPath: String?
    let imagePath: String?
    let thumbnailPath: String?
    let rtfPath: String?
    let htmlPath: String?
    let byteSize: Int
    let contentHash: String
    var isFavorite: Bool
    var lastAccessedAt: Date?

    enum ContentType: String {
        case plainText, rtf, html, image, fileURL, unknown

        var badge: String {
            switch self {
            case .plainText: "Text"
            case .rtf: "RTF"
            case .html: "HTML"
            case .image: "Image"
            case .fileURL: "File"
            case .unknown: "?"
            }
        }

        var iconName: String {
            switch self {
            case .plainText: "doc.text"
            case .rtf: "doc.richtext"
            case .html: "globe"
            case .image: "photo"
            case .fileURL: "folder"
            case .unknown: "questionmark.square"
            }
        }
    }

    var contentType: ContentType {
        switch primaryType {
        case let t where t.contains("public.file-url"): .fileURL
        case let t where t.contains("public.image") || t.contains("public.tiff") || t.contains("public.png"): .image
        case let t where t.contains("public.rtf"): .rtf
        case let t where t.contains("public.html"): .html
        case let t where t.contains("public.utf8-plain-text") || t.contains("public.plain-text"): .plainText
        default: .unknown
        }
    }

    var preview: String {
        if let text = plainTextPreview, !text.isEmpty {
            return String(text.prefix(200))
        }
        if let title = displayTitle, !title.isEmpty {
            return title
        }
        return contentType.badge
    }

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
