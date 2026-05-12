import AppKit

struct DrawerPosition {
    let screen: NSScreen
    let topCenter: NSPoint
    let isNotched: Bool
}

enum ScreenUtilities {
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

    static func drawerPosition(width: CGFloat = 340) -> DrawerPosition {
        let screen = targetScreen()
        let frame = screen.frame
        let safeArea = screen.safeAreaInsets
        let isNotched = safeArea.top > 0

        let topY = frame.maxY - safeArea.top
        let centerX = frame.midX - width / 2

        return DrawerPosition(
            screen: screen,
            topCenter: NSPoint(x: centerX, y: topY),
            isNotched: isNotched
        )
    }
}
