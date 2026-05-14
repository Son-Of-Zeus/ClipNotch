import AppKit
import SwiftUI

private class DrawerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that does not inherit the screen’s top safe-area inset; SwiftUI already lays out
/// the camera housing via `notchInset`, and the system inset was creating a visible gap above the island.
private final class DrawerRootHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets {
        var edge = super.safeAreaInsets
        edge.top = 0
        return edge
    }
}

@MainActor
final class PanelManager {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    
    var isOpen: Bool { panel != nil }
    
    func open<Content: View>(position: NSPoint, width: CGFloat, height: CGFloat, content: Content) {
        close()

        let clampedHeight = max(min(height, 500), 42)
        let clampedWidth = max(320, min(width, 1200))
        let panelRect = NSRect(
            x: position.x,
            y: position.y - clampedHeight,
            width: clampedWidth,
            height: clampedHeight
        )

        // “Dynamic Island” style: float above other apps’ document windows without switching the
        // active app. See Window Levels: https://developer.apple.com/documentation/appkit/nswindow/level
        // — `.popUpMenu` sits above `.normal` / `.floating` so we paint over the workspace; the
        // `.nonactivatingPanel` style keeps the user’s frontmost app logically active (like an overlay).
        let panel = DrawerPanel(
            contentRect: panelRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let hosting = DrawerRootHostingView(rootView: AnyView(content))
        panel.contentView = hosting

        self.panel = panel
        self.hostingView = hosting

        // Above peer panels at the same level; still respects `.popUpMenu` ordering vs document windows.
        panel.orderFrontRegardless()
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
}
