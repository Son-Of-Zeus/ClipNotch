import SwiftUI

/// ClipNotch Professional palette — stitch design system.
enum ClipNotchDesign {
    // MARK: Surfaces

    static let surface = Color(hex: 0x131313)
    static let surfaceDim = Color(hex: 0x131313)
    static let surfaceContainer = Color(hex: 0x202020)
    static let surfaceContainerHigh = Color(hex: 0x2A2A2A)
    static let surfaceVariant = Color(hex: 0x353534)

    // MARK: Paper panel (stitch mock content area)

    static let paper = Color(hex: 0xFDF6E3)
    static let paperText = Color(hex: 0x131313)
    static let paperTextMuted = Color(hex: 0x353534)

    // MARK: On-surface text

    static let onSurface = Color(hex: 0xE5E2E1)
    static let onSurfaceVariant = Color(hex: 0xC4C6D0)

    // MARK: Primary / highlight

    static let primary = Color(hex: 0xD8E2FF)
    static let primaryContainer = Color(hex: 0xADC6FF)
    static let onPrimary = Color(hex: 0x122F5F)
    static let surfaceTint = Color(hex: 0xADC6FF)

    /// Selection & active-state fill — shared by notch drawer rows and prefs accents.
    static let highlight = primaryContainer

    // MARK: Secondary (status)

    static let secondary = Color(hex: 0x42E355)
    static let secondaryContainer = Color(hex: 0x04C339)
    static let onSecondaryContainer = Color(hex: 0x00480F)

    // MARK: Outlines & controls

    static let outline = Color(hex: 0x8E909A)
    static let outlineVariant = Color(hex: 0x414755)
    static let shortcutBg = Color(hex: 0x444444)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
}
