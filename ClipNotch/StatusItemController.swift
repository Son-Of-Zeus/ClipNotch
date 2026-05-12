import AppKit

@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    
    var onLeftClick: (() -> Void)?
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
        menu.addItem(withTitle: "Preferences...", action: #selector(preferencesClicked), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear History", action: #selector(clearHistoryClicked), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClipNotch", action: #selector(quitClicked), keyEquivalent: "q")
        
        for menuItem in menu.items {
            menuItem.target = self
        }
        
        self.statusItem = item
        self.menu = menu
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            onLeftClick?()
        }
    }
    
    func showMenu() {
        guard let menu, let statusItem else { return }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
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
