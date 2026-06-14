import AppKit
import SwiftUI

/// Panel recipe ported from DynamicNotchKit — this exact combination is what lets the window paint
/// over the menu bar / notch region. Deviating (e.g. overriding `constrainFrameRect` or adding
/// `.fullScreenAuxiliary` to the collection behavior) causes macOS to pin the content below the
/// menu bar, which is the bug we hit before.
private final class DrawerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelManager {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    var isOpen: Bool { panel != nil }

    func open<Content: View>(frame: NSRect, content: Content) {
        close()

        let panel = DrawerPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        // Purely visual overlay — clicks pass through; dismissal is handled by the global event tap.
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: AnyView(content))
        panel.contentView = hosting

        panel.setFrame(frame, display: false)
        panel.layoutIfNeeded()
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hosting
    }

    func close() {
        panel?.orderOut(nil)
        hostingView = nil
        panel = nil
    }
}
