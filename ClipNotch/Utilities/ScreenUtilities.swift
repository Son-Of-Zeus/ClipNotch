import AppKit

/// Geometry for the notch tray, following the DynamicNotchKit approach: a large, top-anchored,
/// transparent window centered over the notch. The tray itself is a *solid black* shape drawn
/// top-aligned inside that window, so the physical camera notch is absorbed into the black and the
/// tray appears to drop straight out of the notch.
struct NotchMetrics {
    let screen: NSScreen
    let windowFrame: NSRect
    let notchHeight: CGFloat
    let bodyWidth: CGFloat
    let bodyHeight: CGFloat

    var isNotched: Bool { screen.safeAreaInsets.top > 0 }
}

enum ScreenUtilities {
    static let drawerWidth: CGFloat = 340
    static let rowHeight: CGFloat = 42
    static let listVerticalPadding: CGFloat = 16
    static let maxBodyHeight: CGFloat = 420
    static let minBodyHeight: CGFloat = 42

    static func bodyHeight(forItemCount count: Int) -> CGFloat {
        let raw = CGFloat(max(count, 1)) * rowHeight + listVerticalPadding
        return min(max(raw, minBodyHeight), maxBodyHeight)
    }

    static func targetScreen() -> NSScreen {
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for window in windows {
                guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                      ownerPID == frontApp.processIdentifier,
                      let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                      let x = bounds["X"], let y = bounds["Y"] else { continue }

                let point = NSPoint(x: x + 1, y: y + 1)
                for screen in NSScreen.screens {
                    if screen.frame.contains(point) {
                        return screen
                    }
                }
            }
        }

        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                return screen
            }
        }

        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    static func notchMetrics(bodyHeight: CGFloat) -> NotchMetrics {
        let screen = targetScreen()
        let frame = screen.frame
        let safeTop = screen.safeAreaInsets.top
        let menubarHeight = frame.maxY - screen.visibleFrame.maxY
        // On notched Macs this is the notch height; otherwise fall back to the menu-bar height so the
        // tray still tucks under the top edge.
        let notchHeight = safeTop > 0 ? safeTop : (menubarHeight > 0 ? menubarHeight : 32)

        // A generous top-anchored, horizontally-centered window (à la DynamicNotchKit). The tray is
        // drawn top-aligned inside it; the surrounding area is transparent and click-through.
        let windowWidth = max(frame.width / 2, drawerWidth + 80)
        let windowHeight = max(frame.height / 2, notchHeight + bodyHeight + 60)
        let windowFrame = NSRect(
            x: frame.midX - windowWidth / 2,
            y: frame.maxY - windowHeight,
            width: windowWidth,
            height: windowHeight
        )

        return NotchMetrics(
            screen: screen,
            windowFrame: windowFrame,
            notchHeight: notchHeight,
            bodyWidth: drawerWidth,
            bodyHeight: bodyHeight
        )
    }
}
