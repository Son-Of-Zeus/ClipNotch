import AppKit
import ApplicationServices

struct NavigationShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt16

    static let previous = NavigationShortcut(keyCode: 0x26)
    static let next = NavigationShortcut(keyCode: 0x28)

    var displayKeys: [String] { [KeyDisplay.label(for: keyCode)] }

    var isValid: Bool {
        ![0x24, 0x30, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x4C].contains(keyCode)
    }
}

enum DrawerInteractionMode: String, Codable, CaseIterable, Sendable {
    case holdToPaste
    case toggle

    var title: String {
        switch self {
        case .holdToPaste: "Hold to paste"
        case .toggle: "Toggle drawer"
        }
    }
}

struct ShortcutConfiguration: Codable, Equatable, Sendable {
    var previousItem: NavigationShortcut = .previous
    var nextItem: NavigationShortcut = .next
    var interactionMode: DrawerInteractionMode = .holdToPaste

    static let `default` = ShortcutConfiguration()

    var hasDuplicateNavigationKeys: Bool { previousItem.keyCode == nextItem.keyCode }
    var isValid: Bool { previousItem.isValid && nextItem.isValid && !hasDuplicateNavigationKeys }

    func displayKeys(for shortcut: NavigationShortcut, palette: Bool = false) -> [String] {
        (palette ? ["⌘", "⇧"] : ["⌘"]) + shortcut.displayKeys
    }

}

enum ShortcutMatcher {
    static func openingPage(
        keyCode: UInt16,
        flags: CGEventFlags,
        configuration: ShortcutConfiguration
    ) -> DrawerSession.Page? {
        guard configuration.isValid,
              keyCode == configuration.previousItem.keyCode || keyCode == configuration.nextItem.keyCode else {
            return nil
        }
        let modifiers = flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
        if modifiers == .maskCommand { return .clipboard }
        if modifiers == [.maskCommand, .maskShift] { return .dataTypes }
        return nil
    }
}

enum KeyDisplay {
    static func label(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0x00: "A"; case 0x01: "S"; case 0x02: "D"; case 0x03: "F"
        case 0x04: "H"; case 0x05: "G"; case 0x06: "Z"; case 0x07: "X"
        case 0x08: "C"; case 0x09: "V"; case 0x0B: "B"; case 0x0C: "Q"
        case 0x0D: "W"; case 0x0E: "E"; case 0x0F: "R"; case 0x10: "Y"
        case 0x11: "T"; case 0x12: "1"; case 0x13: "2"; case 0x14: "3"
        case 0x15: "4"; case 0x16: "6"; case 0x17: "5"; case 0x18: "="
        case 0x19: "9"; case 0x1A: "7"; case 0x1B: "-"; case 0x1C: "8"
        case 0x1D: "0"; case 0x1F: "O"; case 0x20: "U"; case 0x22: "I"
        case 0x23: "P"; case 0x25: "L"; case 0x26: "J"; case 0x28: "K"
        case 0x2D: "N"; case 0x2E: "M"; case 0x2F: "."; case 0x2B: ","
        case 0x24: "↩"
        case 0x30: "⇥"
        case 0x31: "Space"
        case 0x35: "⎋"
        case 0x7B: "←"
        case 0x7C: "→"
        case 0x7D: "↓"
        case 0x7E: "↑"
        default: "Key \(keyCode)"
        }
    }
}
