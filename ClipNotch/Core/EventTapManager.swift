import AppKit
import Carbon.HIToolbox

@MainActor
final class EventTapManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Accessed from the event-tap callback thread.
    nonisolated(unsafe) var drawerIsOpen: Bool = false
    nonisolated(unsafe) var shortcutConfiguration: ShortcutConfiguration = .default

    var onOpenDrawer: (() -> Void)?
    var onToggleDrawer: (() -> Void)?
    var onPreviousItem: (() -> Void)?
    var onNextItem: (() -> Void)?
    var onPaste: (() -> Void)?
    var onEscape: (() -> Void)?
    var onClickOutside: ((NSPoint) -> Void)?
    var onPossiblePasteboardChange: (() -> Void)?

    private static let kEscape: CGKeyCode = 0x35
    private static let kReturn: CGKeyCode = 0x24
    private static let kC: CGKeyCode = 0x08
    private static let kX: CGKeyCode = 0x07

    func start() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: EventTapManager.tapCallback,
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }

    func tryReEnable() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Static callback (runs on the event-tap thread, not MainActor)

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak manager] in manager?.tryReEnable() }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let configuration = manager.shortcutConfiguration
        let drawerOpen = manager.drawerIsOpen
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        switch type {
        case .keyDown:
            if !isAutoRepeat,
               event.flags.contains(.maskCommand),
               keyCode == kC || keyCode == kX {
                DispatchQueue.main.async { manager.onPossiblePasteboardChange?() }
            }

            if ShortcutMatcher.shouldHandleOpenShortcut(
                keyCode: keyCode,
                flags: event.flags,
                isAutoRepeat: isAutoRepeat,
                drawerIsOpen: drawerOpen,
                shortcut: configuration.openDrawer,
                mode: configuration.interactionMode
            ) {
                if drawerOpen {
                    DispatchQueue.main.async { manager.onToggleDrawer?() }
                } else {
                    DispatchQueue.main.async { manager.onOpenDrawer?() }
                }
                return nil
            }

            guard drawerOpen else { break }

            if keyCode == configuration.previousItem.keyCode && !isAutoRepeat {
                DispatchQueue.main.async { manager.onPreviousItem?() }
                return nil
            }

            if keyCode == configuration.nextItem.keyCode && !isAutoRepeat {
                DispatchQueue.main.async { manager.onNextItem?() }
                return nil
            }

            // In hold-to-paste mode, consume an opener that is not also a navigation key.
            // If it is the previous/next key, the branches above have already handled it.
            if !isAutoRepeat, ShortcutMatcher.matchesGlobalShortcut(
                keyCode: keyCode,
                flags: event.flags,
                shortcut: configuration.openDrawer
            ) {
                return nil
            }

            if keyCode == kReturn && configuration.interactionMode == .toggle {
                DispatchQueue.main.async { manager.onPaste?() }
                return nil
            }

            if keyCode == kEscape {
                DispatchQueue.main.async { manager.onEscape?() }
                return nil
            }

        case .flagsChanged:
            if drawerOpen, ShortcutMatcher.shouldPasteAfterModifierChange(
                flags: event.flags,
                opener: configuration.openDrawer,
                mode: configuration.interactionMode
            ) {
                DispatchQueue.main.async { manager.onPaste?() }
            }

        case .leftMouseDown:
            if drawerOpen {
                let location = event.location
                DispatchQueue.main.async { manager.onClickOutside?(NSPoint(x: location.x, y: location.y)) }
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }
}
