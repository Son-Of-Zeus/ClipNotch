import AppKit
import Carbon.HIToolbox

enum PasteDelivery {
    
    static func deliver(
        _ item: ClipboardItem,
        fileRefs: [FileReference],
        fileStore: FileStore,
        completion: (() -> Void)? = nil
    ) {
        writeToPasteboard(item, fileRefs: fileRefs, fileStore: fileStore)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            postSyntheticPaste()
            completion?()
        }
    }
    
    static func writeToPasteboard(
        _ item: ClipboardItem,
        fileRefs: [FileReference],
        fileStore: FileStore
    ) {
        let pb = NSPasteboard.general
        pb.clearContents()
        
        switch item.contentType {
        case .fileURL:
            let urls = fileRefs.compactMap { ref -> NSURL? in
                NSURL(fileURLWithPath: ref.originalPath)
            }
            if !urls.isEmpty {
                pb.writeObjects(urls)
            }
            if let text = item.plainTextPreview {
                pb.setString(text, forType: .string)
            }
            
        case .image:
            if let imgPath = item.imagePath,
               let data = fileStore.loadData(at: imgPath) {
                let type: NSPasteboard.PasteboardType = imgPath.hasSuffix(".png") ? .png : .tiff
                pb.setData(data, forType: type)
            }
            if let text = item.plainTextPreview {
                pb.setString(text, forType: .string)
            }
            
        case .rtf:
            if let rtfPath = item.rtfPath,
               let rtfData = fileStore.loadData(at: rtfPath) {
                pb.setData(rtfData, forType: .rtf)
            }
            if let htmlPath = item.htmlPath,
               let htmlData = fileStore.loadData(at: htmlPath) {
                pb.setData(htmlData, forType: .html)
            }
            if let textPath = item.fullTextPath,
               let textData = fileStore.loadData(at: textPath),
               let text = String(data: textData, encoding: .utf8) {
                pb.setString(text, forType: .string)
            } else if let preview = item.plainTextPreview {
                pb.setString(preview, forType: .string)
            }
            
        case .html:
            if let htmlPath = item.htmlPath,
               let htmlData = fileStore.loadData(at: htmlPath) {
                pb.setData(htmlData, forType: .html)
            }
            if let textPath = item.fullTextPath,
               let textData = fileStore.loadData(at: textPath),
               let text = String(data: textData, encoding: .utf8) {
                pb.setString(text, forType: .string)
            } else if let preview = item.plainTextPreview {
                pb.setString(preview, forType: .string)
            }
            
        case .plainText:
            if let textPath = item.fullTextPath,
               let textData = fileStore.loadData(at: textPath),
               let text = String(data: textData, encoding: .utf8) {
                pb.setString(text, forType: .string)
            } else if let preview = item.plainTextPreview {
                pb.setString(preview, forType: .string)
            }
            
        case .unknown:
            if let preview = item.plainTextPreview {
                pb.setString(preview, forType: .string)
            }
        }
    }
    
    static func postSyntheticPaste() {
        let vKeyCode: CGKeyCode = 0x09
        
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
            return
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
