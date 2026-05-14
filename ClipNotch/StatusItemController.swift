import AppKit

@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    
    var onOpenClipboard: (() -> Void)?
    var onPreferences: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onQuit: (() -> Void)?
    
    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipNotch")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Clipboard", action: #selector(openClipboardClicked), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences...", action: #selector(preferencesClicked), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear History", action: #selector(clearHistoryClicked), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClipNotch", action: #selector(quitClicked), keyEquivalent: "q")
        
        for menuItem in menu.items where !menuItem.isSeparatorItem {
            menuItem.target = self
        }
        
        self.statusItem = item
        self.menu = menu
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        showMenu()
    }
    
    func showMenu() {
        guard let menu, let button = statusItem?.button else { return }
        // Pop up without temporarily assigning `statusItem.menu`. That pattern can drop
        // menu item actions (e.g. Preferences) when the menu is cleared synchronously.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
    
    @objc private func openClipboardClicked() {
        onOpenClipboard?()
    }
    
    @objc private func preferencesClicked() {
        onPreferences?()
    }
    
    @objc private func clearHistoryClicked() {
        onClearHistory?()
    }
    
    @objc private func quitClicked() {
        onQuit?()
    }
}
