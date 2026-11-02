import AppKit

enum PasteDelivery {
    static func writeToPasteboard(_ payload: ClipboardPayload, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()

        switch payload {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .richText(let text, let rtf, let html):
            if let rtf {
                pasteboard.setData(rtf, forType: .rtf)
            }
            if let html {
                pasteboard.setData(html, forType: .html)
            }
            pasteboard.setString(text, forType: .string)
        case .image(let data, let type):
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
        case .files(let references):
            let urls = references.map { NSURL(fileURLWithPath: $0.originalPath) }
            if !urls.isEmpty {
                pasteboard.writeObjects(urls)
            }
            pasteboard.setString(
                references.map(\.originalPath).joined(separator: "\n"),
                forType: .string
            )
        }
    }

    static func postSyntheticPaste(to processID: pid_t? = nil) {
        let pasteKeyCode: CGKeyCode = 0x09
        guard let keyDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: pasteKeyCode,
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: pasteKeyCode,
            keyDown: false
        ) else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        if let processID {
            keyDown.postToPid(processID)
            keyUp.postToPid(processID)
        } else {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
