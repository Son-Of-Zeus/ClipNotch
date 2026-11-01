import ApplicationServices

// The event tap and mouse controls both use this session on the main run loop.
struct DrawerSession {
    enum Page: Hashable {
        case clipboard
        case profiles
        case fields

        var isPalette: Bool { self != .clipboard }
    }

    enum Action: Equatable {
        case open
        case close
        case previous
        case next
        case confirm
        case showProfiles
        case showClipboard
    }

    private(set) var isOpen = false
    private(set) var page: Page = .clipboard
    private(set) var releaseArmed = false
    private var previousFlags: CGEventFlags = []
    private var switchedDuringHold = false

    mutating func open(_ page: Page, flags: CGEventFlags = [], mode: DrawerInteractionMode = .holdToPaste) {
        isOpen = true
        self.page = page
        previousFlags = flags
        releaseArmed = mode == .holdToPaste && flags.contains(.maskCommand)
        switchedDuringHold = false
    }

    mutating func keyDown(
        _ keyCode: UInt16,
        flags: CGEventFlags,
        isRepeat: Bool,
        configuration: ShortcutConfiguration
    ) -> Action? {
        let target = ShortcutMatcher.openingPage(keyCode: keyCode, flags: flags, configuration: configuration)
        if !isOpen {
            guard let target, !isRepeat else { return nil }
            open(target, flags: flags, mode: configuration.interactionMode)
            return .open
        }
        if let target, !isRepeat, configuration.interactionMode == .toggle, !switchedDuringHold {
            if target.isPalette == page.isPalette {
                return .close
            }
            page = target
            return target == .clipboard ? .showClipboard : .showProfiles
        }
        if keyCode == 0x35, !isRepeat {
            if page == .fields {
                page = .profiles
                releaseArmed = false
                return .showProfiles
            }
            return .close
        }
        if keyCode == 0x24, !isRepeat { return .confirm }
        guard !isRepeat, !flags.contains(.maskAlternate), !flags.contains(.maskControl) else { return nil }
        if keyCode == configuration.previousItem.keyCode { return .previous }
        if keyCode == configuration.nextItem.keyCode { return .next }
        return nil
    }

    mutating func flagsChanged(_ flags: CGEventFlags, mode: DrawerInteractionMode) -> Action? {
        let wasCommandHeld = previousFlags.contains(.maskCommand)
        let wasShiftHeld = previousFlags.contains(.maskShift)
        previousFlags = flags
        guard isOpen else { return nil }
        let commandHeld = flags.contains(.maskCommand)
        let shiftHeld = flags.contains(.maskShift)

        if !commandHeld { switchedDuringHold = false }
        if commandHeld && !wasCommandHeld && mode == .holdToPaste { releaseArmed = true }
        if wasCommandHeld && !commandHeld && mode == .holdToPaste && releaseArmed {
            releaseArmed = false
            return page == .profiles ? .close : .confirm
        }
        if commandHeld && shiftHeld && !wasShiftHeld && page != .profiles {
            page = .profiles
            switchedDuringHold = true
            return .showProfiles
        }
        if mode == .holdToPaste && commandHeld && wasShiftHeld && !shiftHeld
            && page == .profiles && releaseArmed {
            return .confirm
        }
        return nil
    }

    mutating func show(_ page: Page, fromMouse: Bool = false) {
        self.page = page
        if fromMouse { releaseArmed = false }
    }

    mutating func close() {
        isOpen = false
        releaseArmed = false
        switchedDuringHold = false
    }
}
