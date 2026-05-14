import AppKit
import SwiftUI

enum PanelMode {
    case fullPermission
    case degraded
}

private class DrawerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelManager {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private(set) var previousApp: NSRunningApplication?
    
    var isOpen: Bool { panel != nil }
    
    func open<Content: View>(mode: PanelMode, position: NSPoint, height: CGFloat, content: Content) {
        close()
        
        if mode == .degraded {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        
        let clampedHeight = max(min(height, 500), 42)
        let panelRect = NSRect(
            x: position.x,
            y: position.y - clampedHeight,
            width: 340,
            height: clampedHeight
        )
        
        let panel: DrawerPanel
        switch mode {
        case .fullPermission:
            panel = DrawerPanel(
                contentRect: panelRect,
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .popUpMenu
            panel.isFloatingPanel = true
            
        case .degraded:
            panel = DrawerPanel(
                contentRect: panelRect,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .popUpMenu
        }
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        
        let hosting = NSHostingView(rootView: AnyView(content))
        panel.contentView = hosting
        
        self.panel = panel
        self.hostingView = hosting
        
        panel.orderFront(nil)
        
        if mode == .degraded {
            panel.makeKey()
        }
    }
    
    func updateHeight(_ height: CGFloat) {
        guard let panel else { return }
        var frame = panel.frame
        let maxHeight: CGFloat = 420
        let clampedHeight = min(height, maxHeight)
        
        let topY = frame.maxY
        frame.size.height = clampedHeight
        frame.origin.y = topY - clampedHeight
        
        panel.setFrame(frame, display: true)
    }
    
    func close() {
        panel?.orderOut(nil)
        hostingView = nil
        panel = nil
    }
    
    func restorePreviousApp() {
        guard let app = previousApp else { return }
        app.activate()
        previousApp = nil
    }
}
