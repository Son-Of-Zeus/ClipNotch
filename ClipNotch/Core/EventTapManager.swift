import AppKit

@MainActor
final class EventTapManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onKeyDown: ((UInt16, CGEventFlags, Bool) -> Bool)?
    var onFlagsChanged: ((CGEventFlags) -> Void)?
    var onPointer: ((NSPoint, Bool) -> Void)?
    var onPossiblePasteboardChange: (() -> Void)?

    func start() -> Bool {
        let eventTypes: [CGEventType] = [
            .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .mouseMoved, .scrollWheel
        ]
        let eventMask = eventTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.tapCallback,
            userInfo: refcon
        ) else { return false }

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

    private func handle(_ type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        switch type {
        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !isRepeat, event.flags.contains(.maskCommand), keyCode == 0x08 || keyCode == 0x07 {
                onPossiblePasteboardChange?()
            }
            return onKeyDown?(keyCode, event.flags, isRepeat) ?? false
        case .flagsChanged:
            onFlagsChanged?(event.flags)
        case .leftMouseDown, .rightMouseDown, .mouseMoved, .scrollWheel:
            onPointer?(event.location, type == .leftMouseDown || type == .rightMouseDown)
        default:
            break
        }
        return false
    }

    // The tap source is installed exclusively on the main run loop.
    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        return MainActor.assumeIsolated {
            let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handle(type, event: event) ? nil : Unmanaged.passUnretained(event)
        }
    }
}
