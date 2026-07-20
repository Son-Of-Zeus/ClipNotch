import AppKit
import SwiftUI

/// Semantic colors shared by the app. AppKit supplies their light/dark variants.
enum ClipNotchDesign {
    // MARK: macOS settings surfaces

    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let groupedBackground = Color(nsColor: .underPageBackgroundColor)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let label = Color(nsColor: .labelColor)
    static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
    static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)

    // MARK: Neutral app-owned emphasis

    static let graphite = Color(nsColor: .darkGray)
    static let graphiteSelection = Color.white.opacity(0.14)
    static let graphiteSelectionStrong = Color.white.opacity(0.20)
    static let graphiteStroke = Color.white.opacity(0.12)

    // MARK: Drawer

    static let drawerBackground = Color.black
    static let drawerText = Color.white.opacity(0.92)
    static let drawerSecondaryText = Color.white.opacity(0.52)
    static let drawerTertiaryText = Color.white.opacity(0.30)
    static let drawerControl = Color.white.opacity(0.07)
    static let drawerSelection = Color.white.opacity(0.13)
    static let drawerSelectionIcon = Color.white.opacity(0.20)
}

/// Short, consistent motion that respects the system Reduce Motion preference.
enum ClipNotchMotion {
    static func standard(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .easeInOut(duration: 0.22)
    }

    static func emphasis(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(duration: 0.32, bounce: 0.10)
    }

    static func drawer(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(duration: 0.34, bounce: 0.12)
    }
}
