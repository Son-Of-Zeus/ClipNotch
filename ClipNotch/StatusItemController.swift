import AppKit

@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?

    var onPreferences: (() -> Void)?
    var onOpenClipboard: (() -> Void)?
    var onOpenDataPalette: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onQuit: (() -> Void)?

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipNotch")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Clipboard", action: #selector(openClipboard), keyEquivalent: "")
        menu.addItem(withTitle: "Open Data Palette", action: #selector(openDataPalette), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences...", action: #selector(preferencesClicked), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear History", action: #selector(clearHistoryClicked), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClipNotch", action: #selector(quitClicked), keyEquivalent: "q")

        for menuItem in menu.items where !menuItem.isSeparatorItem {
            menuItem.target = self
        }

        item.menu = menu
        self.statusItem = item
    }

    @objc private func preferencesClicked() {
        onPreferences?()
    }

    @objc private func openClipboard() { onOpenClipboard?() }

    @objc private func openDataPalette() { onOpenDataPalette?() }

    @objc private func clearHistoryClicked() {
        onClearHistory?()
    }

    @objc private func quitClicked() {
        onQuit?()
    }
}
