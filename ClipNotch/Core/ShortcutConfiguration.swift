import AppKit
import ApplicationServices

struct ShortcutModifiers: OptionSet, Codable, Equatable, Sendable {
    let rawValue: UInt

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let control = ShortcutModifiers(rawValue: 1 << 2)
    static let shift = ShortcutModifiers(rawValue: 1 << 3)

    static let all: ShortcutModifiers = [.command, .option, .control, .shift]

    init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        var modifiers: ShortcutModifiers = []
        if eventFlags.contains(.command) { modifiers.insert(.command) }
        if eventFlags.contains(.option) { modifiers.insert(.option) }
        if eventFlags.contains(.control) { modifiers.insert(.control) }
        if eventFlags.contains(.shift) { modifiers.insert(.shift) }
        self = modifiers
    }

    init(cgEventFlags: CGEventFlags) {
        var modifiers: ShortcutModifiers = []
        if cgEventFlags.contains(.maskCommand) { modifiers.insert(.command) }
        if cgEventFlags.contains(.maskAlternate) { modifiers.insert(.option) }
        if cgEventFlags.contains(.maskControl) { modifiers.insert(.control) }
        if cgEventFlags.contains(.maskShift) { modifiers.insert(.shift) }
        self = modifiers
    }

    var glyphs: [String] {
        var result: [String] = []
        if contains(.control) { result.append("⌃") }
        if contains(.option) { result.append("⌥") }
        if contains(.shift) { result.append("⇧") }
        if contains(.command) { result.append("⌘") }
        return result
    }
}

struct GlobalShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt16
    var modifiers: ShortcutModifiers

    static let `default` = GlobalShortcut(keyCode: 0x26, modifiers: [.command])

    var isValid: Bool { !modifiers.isEmpty }

    var displayKeys: [String] {
        modifiers.glyphs + [KeyDisplay.label(for: keyCode)]
    }
}

struct NavigationShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt16

    static let previous = NavigationShortcut(keyCode: 0x26)
    static let next = NavigationShortcut(keyCode: 0x28)

    var displayKeys: [String] { [KeyDisplay.label(for: keyCode)] }
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
    var openDrawer: GlobalShortcut = .default
    var previousItem: NavigationShortcut = .previous
    var nextItem: NavigationShortcut = .next
    var interactionMode: DrawerInteractionMode = .holdToPaste

    static let `default` = ShortcutConfiguration()

    var hasDuplicateNavigationKeys: Bool {
        previousItem.keyCode == nextItem.keyCode
    }
}

enum ShortcutMatcher {
    static func matchesGlobalShortcut(
        keyCode: UInt16,
        flags: CGEventFlags,
        shortcut: GlobalShortcut
    ) -> Bool {
        keyCode == shortcut.keyCode
            && ShortcutModifiers(cgEventFlags: flags) == shortcut.modifiers
    }

    /// The opener should only win over navigation while the drawer is open in toggle mode.
    /// In hold-to-paste mode, the opener key may intentionally be the previous/next key.
    static func shouldHandleOpenShortcut(
        keyCode: UInt16,
        flags: CGEventFlags,
        isAutoRepeat: Bool,
        drawerIsOpen: Bool,
        shortcut: GlobalShortcut,
        mode: DrawerInteractionMode
    ) -> Bool {
        !isAutoRepeat
            && matchesGlobalShortcut(keyCode: keyCode, flags: flags, shortcut: shortcut)
            && (!drawerIsOpen || mode == .toggle)
    }

    static func shouldPasteAfterModifierChange(
        flags: CGEventFlags,
        opener: GlobalShortcut,
        mode: DrawerInteractionMode
    ) -> Bool {
        mode == .holdToPaste
            && ShortcutModifiers(cgEventFlags: flags).intersection(opener.modifiers).isEmpty
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
