import AppKit
import Carbon.HIToolbox

@MainActor
final class EventTapManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Accessed from event tap callback thread — must be atomic-safe
    nonisolated(unsafe) var drawerIsOpen: Bool = false

    var onCmdJDown: (() -> Void)?
    var onJDown: (() -> Void)?
    var onKDown: (() -> Void)?
    var onCmdReleased: (() -> Void)?
    var onEscape: (() -> Void)?
    var onClickOutside: ((NSPoint) -> Void)?

    private static let kJ: CGKeyCode = 0x26
    private static let kK: CGKeyCode = 0x28
    private static let kEscape: CGKeyCode = 0x35

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

        self.eventTap = tap
        self.runLoopSource = source
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

    // MARK: - Static callback (runs on event tap thread, NOT MainActor)

    private static let tapCallback: CGEventTapCallBack = { proxy, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak manager] in
                manager?.tryReEnable()
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let cmdHeld = flags.contains(.maskCommand)
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let drawerOpen = manager.drawerIsOpen

        switch type {
        case .keyDown:
            if keyCode == kJ && cmdHeld && !drawerOpen && !isAutoRepeat {
                DispatchQueue.main.async { manager.onCmdJDown?() }
                return nil // consume
            }

            if keyCode == kJ && cmdHeld && drawerOpen && isAutoRepeat {
                return nil // consume
            }

            if keyCode == kJ && cmdHeld && drawerOpen {
                DispatchQueue.main.async { manager.onJDown?() }
                return nil // consume
            }

            if keyCode == kK && cmdHeld && drawerOpen {
                DispatchQueue.main.async { manager.onKDown?() }
                return nil // consume
            }

            if keyCode == kEscape && drawerOpen {
                DispatchQueue.main.async { manager.onEscape?() }
                return nil // consume
            }

        case .flagsChanged:
            if !cmdHeld && drawerOpen {
                DispatchQueue.main.async { manager.onCmdReleased?() }
                return Unmanaged.passUnretained(event)
            }

        case .leftMouseDown:
            if drawerOpen {
                let location = event.location
                DispatchQueue.main.async {
                    manager.onClickOutside?(NSPoint(x: location.x, y: location.y))
                }
                return Unmanaged.passUnretained(event)
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }
}
